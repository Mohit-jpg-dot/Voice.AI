import Foundation
import AVFoundation
import Speech
import CoreMedia
import CoreAudio
import AppKit
import IOKit.ps
@preconcurrency import ScreenCaptureKit

public struct ComputerAudioSegment: Sendable, Equatable {
    public let text: String
    public let capturedAt: Date
    public let sourceTitle: String?

    public init(text: String, capturedAt: Date = Date(), sourceTitle: String? = nil) {
        self.text = text
        self.capturedAt = capturedAt
        self.sourceTitle = sourceTitle
    }
}

/// Captures internal macOS system audio (YouTube, browser videos, media playback) on demand via ScreenCaptureKit,
/// excluding Voice.AI's own process audio (`excludesCurrentProcessAudio = true`).
/// Off by default so Voice.AI ignores background computer audio until the user asks it to listen.
public final class ComputerAudioListenerService: NSObject, @unchecked Sendable, SCStreamDelegate, SCStreamOutput {
    public static let shared = ComputerAudioListenerService()

    private static let enabledKey = "VoiceAI_ListenComputerAudio"

    private let lock = NSLock()
    private var _segments: [ComputerAudioSegment] = []
    private var _livePartial: String = ""
    private var _lastCommittedSegmentNormalized: String = ""

    private let sampleQueue = DispatchQueue(label: "ai.voice.computerAudio.samples")
    private var activeStream: SCStream?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var activeTaskToken = UUID()
    private var rotationTimer: DispatchSourceTimer?

    public private(set) var isCapturingSystemAudio: Bool = false
    public private(set) var lastStatusNote: String = "Off (ignoring background computer & YouTube audio)"

    public var isEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
        set {
            let previous = UserDefaults.standard.bool(forKey: Self.enabledKey)
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue {
                lastStatusNote = "Starting computer audio listener..."
                startSystemAudioCaptureIfPossible()
            } else {
                stopSystemAudioCapture()
                lastStatusNote = "Off (ignoring background computer & YouTube audio)"
            }
            if previous != newValue {
                EventBus.shared.publish(VoiceEvent(
                    kind: .custom("computer_audio_listening_changed"),
                    source: "ComputerAudioListenerService",
                    severity: .info,
                    payload: ["enabled": newValue ? "true" : "false"]
                ))
            }
        }
    }

    public override init() {
        super.init()
        let preferredLocales = [Locale(identifier: "en-US"), Locale(identifier: "en-IN"), Locale.current]
        for loc in preferredLocales {
            if let r = SFSpeechRecognizer(locale: loc) {
                self.speechRecognizer = r
                break
            }
        }
        if isEnabled {
            lastStatusNote = "Starting computer audio listener..."
            startSystemAudioCaptureIfPossible()
        }
    }

    // MARK: - Natural Voice Intent Parsing

    /// Detects natural voice requests to start or stop listening to the computer's own audio output.
    /// Returns `true` to turn on, `false` to turn off, or `nil` for unrelated queries.
    public static func parseListeningToggleCommand(_ query: String) -> Bool? {
        let lower = query
            .replacingOccurrences(of: "[,.!?'\"]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }

        // Do not hijack generic "stop listening" (wake-word shutdown) or "listen to music" playback
        let disablePhrases = [
            "stop listening to my computer",
            "stop listening to the computer",
            "stop listening to computer audio",
            "stop listening to system audio",
            "stop listening to this video",
            "stop listening to the video",
            "stop listening to youtube",
            "stop listening to the things my computer",
            "stop listening to things my computer",
            "ignore computer audio",
            "ignore system audio",
            "ignore youtube audio",
            "ignore background video",
            "ignore my computer",
            "turn off computer audio",
            "turn off listening to computer",
            "disable computer audio",
            "don t listen to my computer",
            "dont listen to my computer"
        ]
        if disablePhrases.contains(where: { lower.contains($0) }) {
            return false
        }

        let enablePhrases = [
            "listen to the things my computer is making",
            "listen to things my computer is making",
            "listen to what my computer is making",
            "listen to what the computer is making",
            "listen to the sounds my computer is making",
            "listen to what my computer is saying",
            "listen to what the computer is saying",
            "listen to what my computer is playing",
            "listen to my computer audio",
            "listen to my computer",
            "listen to the computer",
            "listen to computer audio",
            "listen to system audio",
            "listen to what s playing",
            "listen to whats playing",
            "listen to this video",
            "listen to the video",
            "listen to youtube",
            "start listening to my computer",
            "start listening to computer audio",
            "start listening to this video",
            "turn on computer audio"
        ]
        if enablePhrases.contains(where: { lower.contains($0) }) {
            return true
        }

        // General pattern: "(start) listen(ing) to ... (computer / system audio / video / youtube / things ... making)"
        if (lower.contains("listen to") || lower.contains("listening to")) &&
           (lower.contains("computer") || lower.contains("system audio") || lower.contains("youtube") || lower.contains("this video") || lower.contains("whats playing") || lower.contains("what is playing")) &&
           !lower.contains("music") && !lower.contains("song") && !lower.contains("spotify") {
            let isStop = lower.contains("stop ") || lower.contains("ignore ") || lower.contains("turn off ") || lower.contains("disable ") || lower.contains("don t ") || lower.contains("dont ")
            return !isStop
        }

        return nil
    }

    /// Detects questions asking about what the computer / active video / audio playback is talking about.
    public static func isComputerAudioQuestion(_ query: String) -> Bool {
        let lower = query
            .replacingOccurrences(of: "[,.!?'\"]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return false }

        let explicitAudioQuestions = [
            "what is my computer saying",
            "whats my computer saying",
            "what is the computer saying",
            "what is my computer talking about",
            "what is my computer playing",
            "what is playing on my computer",
            "what is this video talking about",
            "what s this video talking about",
            "whats this video talking about",
            "what is this video saying",
            "what are they talking about",
            "what are they saying",
            "what did the video say",
            "what did the video just say",
            "what did it just say",
            "summarize what s playing",
            "summarize whats playing",
            "summarize what is playing",
            "summarize this video",
            "summarize the video audio",
            "explain what s playing",
            "explain what my computer is playing"
        ]
        return explicitAudioQuestions.contains(where: { lower.contains($0) })
    }

    // MARK: - Captured Transcript Context

    public func appendTranscriptSegment(_ text: String, sourceTitle: String? = nil) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let norm = clean.lowercased()
        let activeTitle = sourceTitle ?? NowPlayingMediaManager.shared.currentMedia?.title

        lock.withLock {
            if _lastCommittedSegmentNormalized == norm { return }
            _lastCommittedSegmentNormalized = norm
            _segments.append(ComputerAudioSegment(text: clean, capturedAt: Date(), sourceTitle: activeTitle))
            if _segments.count > 30 {
                _segments.removeFirst(_segments.count - 30)
            }
        }
    }

    public func clearTranscriptBuffer() {
        lock.withLock {
            _segments.removeAll()
            _livePartial = ""
            _lastCommittedSegmentNormalized = ""
        }
    }

    public func capturedContext(maxAgeSeconds: TimeInterval = 600) -> (transcript: String, nowPlaying: NowPlayingItem?, capturedAt: Date?) {
        let cutoff = Date().addingTimeInterval(-maxAgeSeconds)
        let snapshot = lock.withLock { () -> (String, Date?) in
            _segments.removeAll { $0.capturedAt < cutoff }
            var parts = _segments.map(\.text)
            let partial = _livePartial.trimmingCharacters(in: .whitespacesAndNewlines)
            if !partial.isEmpty && !parts.contains(where: { $0.caseInsensitiveCompare(partial) == .orderedSame }) {
                parts.append(partial)
            }
            return (parts.joined(separator: " "), _segments.last?.capturedAt)
        }
        return (snapshot.0, NowPlayingMediaManager.shared.currentMedia, snapshot.1)
    }

    public func recentSegments(limit: Int = 10) -> [ComputerAudioSegment] {
        lock.withLock {
            Array(_segments.suffix(limit))
        }
    }

    // MARK: - ScreenCaptureKit System Audio Capture

    public func startSystemAudioCaptureIfPossible() {
        guard Bundle.main.bundleIdentifier != nil,
              ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] != "1" else {
            lastStatusNote = "Ready (unit-test mode)"
            return
        }
        guard !isCapturingSystemAudio else { return }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            lastStatusNote = "Enable Screen & System Audio Recording permission in System Settings to transcribe internal computer audio"
            return
        }

        Task { [weak self] in
            await self?.beginSCStreamCapture()
        }
    }

    private func beginSCStreamCapture() async {
        guard isEnabled, !isCapturingSystemAudio else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
                lastStatusNote = "No active display found for ScreenCaptureKit system audio"
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.capturesAudio = true
            cfg.excludesCurrentProcessAudio = true
            cfg.sampleRate = 48000
            cfg.channelCount = 2
            cfg.width = 2
            cfg.height = 2
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let stream = SCStream(filter: filter, configuration: cfg, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)

            startRecognitionTask()
            try await stream.startCapture()

            self.activeStream = stream
            self.isCapturingSystemAudio = true
            self.lastStatusNote = "Listening to computer audio (Voice.AI own voice excluded)"
            self.startRotationTimer()
            NSLog("[ComputerAudio] ScreenCaptureKit system audio capture started (excluding self audio).")
        } catch {
            self.isCapturingSystemAudio = false
            self.activeStream = nil
            self.lastStatusNote = "System audio capture unavailable: \(error.localizedDescription)"
            NSLog("[ComputerAudio] Failed to start ScreenCaptureKit audio capture: %@", error.localizedDescription)
        }
    }

    public func stopSystemAudioCapture() {
        rotationTimer?.cancel()
        rotationTimer = nil
        activeTaskToken = UUID()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        let streamToStop = activeStream
        activeStream = nil
        isCapturingSystemAudio = false

        commitLivePartial()

        if let stream = streamToStop {
            Task {
                try? await stream.stopCapture()
            }
        }
    }

    private func startRotationTimer() {
        rotationTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 40.0, repeating: 40.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isEnabled, self.isCapturingSystemAudio else { return }
            self.commitLivePartial()
            self.restartRecognitionTask()
        }
        timer.resume()
        rotationTimer = timer
    }

    private func startRecognitionTask() {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return }
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        self.recognitionRequest = req

        let token = UUID()
        self.activeTaskToken = token

        self.recognitionTask = speechRecognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self, token == self.activeTaskToken else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    self.lock.withLock {
                        self._livePartial = text
                    }
                    if result.isFinal {
                        self.commitLivePartial()
                        if self.isEnabled && self.isCapturingSystemAudio {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                                guard let self = self, token == self.activeTaskToken, self.isEnabled else { return }
                                self.restartRecognitionTask()
                            }
                        }
                    }
                }
            }
            if let err = error {
                let code = (err as NSError).code
                if code == 216 || code == 301 { return }
                guard self.isEnabled && self.isCapturingSystemAudio else { return }
                let delay = (code == 1110) ? 0.15 : 0.60
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self, token == self.activeTaskToken, self.isEnabled, self.isCapturingSystemAudio else { return }
                    self.commitLivePartial()
                    self.restartRecognitionTask()
                }
            }
        }
    }

    private func restartRecognitionTask() {
        activeTaskToken = UUID()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        startRecognitionTask()
    }

    private func commitLivePartial() {
        let partial = lock.withLock { () -> String in
            let p = _livePartial.trimmingCharacters(in: .whitespacesAndNewlines)
            _livePartial = ""
            return p
        }
        if !partial.isEmpty {
            appendTranscriptSegment(partial)
        }
    }

    // MARK: - SCStreamOutput & SCStreamDelegate

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, isEnabled else { return }
        guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer) else { return }
        recognitionRequest?.appendAudioSampleBuffer(sampleBuffer)
    }

    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        NSLog("[ComputerAudio] SCStream stopped with error: %@", error.localizedDescription)
        isCapturingSystemAudio = false
        activeStream = nil
        lastStatusNote = "System audio capture stopped: \(error.localizedDescription)"
    }
}

/// Real-time hardware, audio, memory, battery, and AI pipeline telemetry snapshot shared across Voice Pill and Insights.
public struct LiveHostTelemetrySnapshot: Sendable, Equatable {
    public let ramUsagePercent: Int
    public let batteryPercent: Int?
    public let isCharging: Bool
    public let activeMicName: String
    public let inputSampleRateHz: Int
    public let cpuCoreCount: Int
    public let thermalLabel: String
    public let activeAIMode: String
    public let activeSTTProvider: String
    public let wakeStatusLabel: String
    public let computerAudioEnabled: Bool

    public static func capture() -> LiveHostTelemetrySnapshot {
        let ramPct = Int(ProactiveRulesEngine.sampleHostMemoryUsagePercent().rounded())

        var batteryPct: Int? = nil
        var charging = false
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                if let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                   let cap = desc[kIOPSCurrentCapacityKey as String] as? Int,
                   let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int,
                   maxCap > 0 {
                    batteryPct = Int((Double(cap) / Double(maxCap) * 100.0).rounded())
                    charging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
                    break
                }
            }
        }

        var micName = "System Microphone"
        var sampleRateHz = 0
        var defaultInputID = AudioDeviceID(0)
        var devSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var devAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &devAddr, 0, nil, &devSize, &defaultInputID) == noErr,
           defaultInputID != AudioDeviceID(0) {
            var nameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(defaultInputID, &nameAddr, 0, nil, &nameSize, &nameRef) == noErr,
               let cfName = nameRef?.takeRetainedValue() {
                micName = cfName as String
            }

            var rate: Float64 = 0
            var rateSize = UInt32(MemoryLayout<Float64>.size)
            var rateAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(defaultInputID, &rateAddr, 0, nil, &rateSize, &rate) == noErr {
                sampleRateHz = Int(rate.rounded())
            }
        }

        let thermal: String = {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: return "Nominal"
            case .fair: return "Warm"
            case .serious: return "Elevated"
            case .critical: return "Critical"
            @unknown default: return "Nominal"
            }
        }()

        let listener = TheVoiceAmbientListener.shared
        let wakeLabel: String
        if !listener.isTheVoiceModeEnabled {
            wakeLabel = "Hands-Free Off"
        } else if listener.isListening {
            wakeLabel = listener.isAlwaysOn24x7Mode ? "24/7 Active" : "Wake: \(listener.wakePhrase.capitalized)"
        } else {
            wakeLabel = "Standby"
        }

        return LiveHostTelemetrySnapshot(
            ramUsagePercent: ramPct,
            batteryPercent: batteryPct,
            isCharging: charging,
            activeMicName: micName,
            inputSampleRateHz: sampleRateHz,
            cpuCoreCount: ProcessInfo.processInfo.activeProcessorCount,
            thermalLabel: thermal,
            activeAIMode: ModelRouter.shared.currentMode.rawValue,
            activeSTTProvider: STTEngineProvider.shared.selectedKind.rawValue,
            wakeStatusLabel: wakeLabel,
            computerAudioEnabled: ComputerAudioListenerService.shared.isEnabled
        )
    }
}

