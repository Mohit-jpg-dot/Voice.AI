import Foundation
import AVFoundation
import Speech
import CoreAudio

public protocol WakeWordDetecting: Sendable {
    var wakePhrase: String { get set }
    var isTheVoiceModeEnabled: Bool { get set }
    func startAmbientListening()
    func stopAmbientListening()
}

/// On-device configurable Wake-Word Engine ("JARVIS", "Friday", "Voice", or user-defined phrase).
/// Coexists with hold-to-talk (fn/Command), forces on-device speech recognition when supported,
/// and triggers immediate TTS barge-in whenever the wake phrase is heard.
public final class TheVoiceAmbientListener: NSObject, WakeWordDetecting, @unchecked Sendable, SFSpeechRecognizerDelegate {
    public static let shared = TheVoiceAmbientListener()
    
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    public private(set) var isListening: Bool = false
    public private(set) var isCapturingHotCommand: Bool = false
    public private(set) var lastStatusNote: String = "Initializing..."
    private var isPausedForActiveSession: Bool = false
    private var activeRecognitionTaskToken = UUID()
    private var consecutiveErrorCount: Int = 0
    private var configChangeObserver: NSObjectProtocol?
    private var pendingWakeWorkItem: DispatchWorkItem?
    private var pendingWakeTranscript: String = ""
    private var pendingWakeWasEmpty: Bool = false
    private var pendingFreeTalkWorkItem: DispatchWorkItem?
    private var pendingFreeTalkTranscript: String = ""
    private var hotCaptureTranscript: String = ""
    private var hotCaptureStartedAt: Date = .distantPast
    private var hotCaptureSilenceWorkItem: DispatchWorkItem?
    private var hotCaptureTimeoutWorkItem: DispatchWorkItem?
    private var lastHotLevelUpdateAt: Date = .distantPast
    private var rotationTimer: DispatchSourceTimer?
    private var lastBargeInTime: Date = .distantPast
    private let wakePhraseKey = "VoiceAI_ConfiguredWakePhrase"
    private let alwaysOnKey = "VoiceAI_AlwaysOn24x7Mode"

    public var diagnosticSummary: String {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micStatus: AVAuthorizationStatus = {
            if #available(macOS 10.14, *) {
                return AVCaptureDevice.authorizationStatus(for: .audio)
            }
            return .authorized
        }()
        if micStatus == .denied || micStatus == .restricted {
            return "Microphone permission denied — open System Settings > Privacy & Security > Microphone"
        }
        if speechStatus == .denied || speechStatus == .restricted {
            return "Speech Recognition permission denied — open System Settings > Privacy & Security > Speech Recognition"
        }
        if !isTheVoiceModeEnabled {
            return "Hands-free listening is turned off"
        }
        if isListening && audioEngine.isRunning {
            let computerAudioSuffix = ComputerAudioListenerService.shared.isEnabled ? " • Computer Audio ON" : " • Background video audio ignored"
            return (isAlwaysOn24x7Mode
                ? "Listening 24/7 (say 'bro ...' or any command)"
                : "Listening for '\(wakePhrase)' (plus 'bro' & 'voice')") + computerAudioSuffix
        }
        return lastStatusNote
    }

    public var wakePhrase: String {
        get {
            let saved = UserDefaults.standard.string(forKey: wakePhraseKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? "jarvis" : saved.lowercased()
        }
        set {
            let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            UserDefaults.standard.set(clean.isEmpty ? "jarvis" : clean, forKey: wakePhraseKey)
            if isListening {
                restartTask()
            }
        }
    }

    public var isTheVoiceModeEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "VoiceAI_TheVoiceModeActive") == nil {
                return true // Enabled by default out of the box
            }
            return UserDefaults.standard.bool(forKey: "VoiceAI_TheVoiceModeActive")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "VoiceAI_TheVoiceModeActive")
            if newValue {
                startAmbientListening()
            } else {
                stopAmbientListening()
            }
        }
    }

    /// 24/7 continuous listening mode: responds directly to natural speech ("bro open this up", "tell me...") without needing the wake word first.
    public var isAlwaysOn24x7Mode: Bool {
        get {
            UserDefaults.standard.bool(forKey: alwaysOnKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: alwaysOnKey)
            if newValue && !isTheVoiceModeEnabled {
                isTheVoiceModeEnabled = true
            }
        }
    }
    
    // Callback when wake-word is triggered with actionable instruction
    public var onWakeWordTriggered: ((String) -> Void)?
    /// Allows direct silence phrases ("shut up") without wake prefix when Notch pill is open or TTS is speaking.
    public var canAcceptDirectSilenceCommand: (() -> Bool)?
    /// Zero-lag hot capture callbacks (avoids CoreAudio teardown/cold-start when waking up)
    public var onHotCaptureLevels: (([CGFloat]) -> Void)?
    public var onHotCapturePartial: ((String) -> Void)?
    public var onHotCaptureCompleted: ((String) -> Void)?
    
    private var lastTriggerTime: Date = .distantPast
    
    public override init() {
        super.init()
        initRecognizer()
    }
    
    private func initRecognizer() {
        let preferredLocales = [Locale(identifier: "en-US"), Locale(identifier: "en-IN"), Locale.current]
        for loc in preferredLocales {
            if let r = SFSpeechRecognizer(locale: loc) {
                self.speechRecognizer = r
                r.delegate = self
                break
            }
        }
    }
    
    public func startAmbientListening() {
        if isListening && audioEngine.isRunning && recognitionTask != nil {
            return
        }
        if isListening && !audioEngine.isRunning {
            stopAmbientListening()
        }
        guard isTheVoiceModeEnabled else {
            lastStatusNote = "Hands-free listening is turned off"
            return
        }
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.infoDictionary?["NSSpeechRecognitionUsageDescription"] != nil else {
            lastStatusNote = "Unavailable outside app bundle"
            return
        }
        
        if speechRecognizer == nil {
            initRecognizer()
        }
        
        // Request authorization and auto-start once granted instead of racing audioEngine startup
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        if speechStatus == .notDetermined {
            lastStatusNote = "Waiting for Speech Recognition permission..."
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if status == .authorized {
                        self.startAmbientListening()
                    } else {
                        self.lastStatusNote = "Speech Recognition permission denied"
                    }
                }
            }
            return
        }
        guard speechStatus == .authorized else {
            lastStatusNote = "Speech Recognition permission denied"
            return
        }

        if #available(macOS 10.14, *) {
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if micStatus == .notDetermined {
                lastStatusNote = "Waiting for Microphone permission..."
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if granted {
                            self.startAmbientListening()
                        } else {
                            self.lastStatusNote = "Microphone permission denied"
                        }
                    }
                }
                return
            }
            guard micStatus == .authorized else {
                lastStatusNote = "Microphone permission denied"
                return
            }
        }

        if let recognizer = speechRecognizer, !recognizer.isAvailable {
            lastStatusNote = "Speech recognizer warming up..."
            NSLog("[The Voice] SFSpeechRecognizer currently reports unavailable; will start when available.")
            return
        }
        
        audioEngine.stop()
        audioEngine.reset()
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            lastStatusNote = "Microphone input device not ready"
            NSLog("[The Voice] Microphone input format not ready yet.")
            return
        }
        
        recognitionRequest = makeRecognitionRequest()
        guard let _ = recognitionRequest else {
            lastStatusNote = "Unable to initialize speech request"
            return
        }
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            if self.isCapturingHotCommand {
                self.emitHotCaptureAudioLevels(from: buffer)
            }
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            consecutiveErrorCount = 0
            lastStatusNote = "Listening"
        } catch {
            lastStatusNote = "Audio engine start failed: \(error.localizedDescription)"
            NSLog("[The Voice] Failed to start ambient audio engine: %@", error.localizedDescription)
            return
        }
        
        if configChangeObserver == nil {
            configChangeObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: audioEngine,
                queue: .main
            ) { [weak self] _ in
                guard let self = self, self.isTheVoiceModeEnabled, !self.isPausedForActiveSession else { return }
                NSLog("[The Voice] Audio configuration changed — resetting ambient mic listener.")
                self.stopAmbientListening()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.startAmbientListening()
                }
            }
        }
        
        startRecognitionTask()
        startRotationWatchdog()
        NSLog("[The Voice] Ambient hands-free wake word listening active ('%@ ...', 24/7=%@).", wakePhrase, isAlwaysOn24x7Mode ? "on" : "off")
    }

    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if available && self.isTheVoiceModeEnabled && !self.isPausedForActiveSession && !self.isListening {
                self.startAmbientListening()
            } else if !available {
                self.lastStatusNote = "Speech recognizer temporarily unavailable"
            }
        }
    }

    private func makeRecognitionRequest() -> SFSpeechAudioBufferRecognitionRequest? {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = isCapturingHotCommand ? .dictation : .confirmation
        // Only force strict offline recognition if explicitly requested; otherwise allow fast low-latency streaming partials
        if UserDefaults.standard.bool(forKey: "VoiceAI_ForceOfflineWakeSTT"),
           speechRecognizer?.supportsOnDeviceRecognition == true {
            req.requiresOnDeviceRecognition = true
        }
        let activePhrase = wakePhrase
        req.contextualStrings = [
            activePhrase, "hey \(activePhrase)", "ok \(activePhrase)",
            "jarvis", "hey jarvis", "jarvis shut up", "bro", "hey bro",
            "voice", "hey voice"
        ]
        return req
    }

    private func startRotationWatchdog() {
        rotationTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // Rotate Apple SFSpeechRecognitionTask every 42s (before the ~60s silent timeout) & recover engine if stalled
        timer.schedule(deadline: .now() + 42.0, repeating: 42.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isListening, !self.isPausedForActiveSession else { return }
            guard !self.isCapturingHotCommand && self.pendingWakeWorkItem == nil && self.pendingFreeTalkWorkItem == nil else { return }
            if !self.audioEngine.isRunning {
                self.stopAmbientListening()
                self.startAmbientListening()
            } else {
                self.restartTask()
            }
        }
        timer.resume()
        rotationTimer = timer
    }
    
    private func startRecognitionTask() {
        guard let request = recognitionRequest else { return }
        let taskToken = UUID()
        activeRecognitionTaskToken = taskToken
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            // Drop late callbacks from previously cancelled/rotated recognition tasks so they never kill the active task
            guard taskToken == self.activeRecognitionTaskToken else { return }
            
            if let result = result {
                self.consecutiveErrorCount = 0
                let text = result.bestTranscription.formattedString
                self.evaluateWakeWord(in: text, isFinal: result.isFinal)
            }
            
            if let err = error {
                let nsErr = err as NSError
                // Ignore intentional cancellation when restarting/pausing
                if nsErr.code == 216 || nsErr.code == 301 { return }
                guard self.isListening && !self.isPausedForActiveSession else { return }
                
                // 1110 = normal Apple Speech quiet-room timeout; rotate quickly without punitive error backoff
                if nsErr.code == 1110 {
                    self.consecutiveErrorCount = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                        guard let self = self,
                              taskToken == self.activeRecognitionTaskToken,
                              self.isListening, !self.isPausedForActiveSession else { return }
                        if !self.audioEngine.isRunning {
                            self.stopAmbientListening()
                            self.startAmbientListening()
                        } else {
                            self.restartTask()
                        }
                    }
                    return
                }
                
                self.consecutiveErrorCount += 1
                let delay = min(2.0, 0.30 * Double(self.consecutiveErrorCount))
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self,
                          taskToken == self.activeRecognitionTaskToken,
                          self.isListening, !self.isPausedForActiveSession else { return }
                    if !self.audioEngine.isRunning || self.consecutiveErrorCount >= 3 {
                        self.stopAmbientListening()
                        self.startAmbientListening()
                    } else {
                        self.restartTask()
                    }
                }
            }
        }
    }
    
    /// Returns true when macOS default audio output hardware is actively playing sound somewhere.
    public static func isSystemAudioOutputActive() -> Bool {
        var defaultOutputID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status1 = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &defaultOutputID)
        guard status1 == noErr, defaultOutputID != AudioDeviceID(0) else { return false }

        var isRunning: UInt32 = 0
        var runSize = UInt32(MemoryLayout<UInt32>.size)
        var runAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status2 = AudioObjectGetPropertyData(defaultOutputID, &runAddr, 0, nil, &runSize, &isRunning)
        return status2 == noErr && isRunning != 0
    }

    /// Returns true when external computer media (YouTube, Spotify, Apple Music) is actively playing.
    /// Intentionally relies only on real active player telemetry rather than hardware audio-session flags,
    /// which remain asserted on macOS whenever browsers or IDEs are open and would block "bro" / 24/7 mode.
    public static func isExternalComputerMediaPlaying() -> Bool {
        return NowPlayingMediaManager.shared.currentMedia?.isPlaying == true
    }

    /// Flushes accumulated SFSpeechRecognizer transcripts right after Voice.AI finishes speaking
    /// so lingering TTS speaker words never leak into the next listening window.
    public func flushRecognitionBufferAfterTTS() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.isListening,
                  !self.isPausedForActiveSession,
                  !self.isCapturingHotCommand,
                  self.pendingWakeWorkItem == nil,
                  self.pendingFreeTalkWorkItem == nil else { return }
            self.restartTask()
        }
    }

    /// Pure helper for extracting an actionable command after a configurable wake phrase (English, Hindi & Hinglish).
    /// Includes phonetic aliases for Jarvis ("jervis", "jarves", "javis", "jarviz", "garvis", "jar vis", "hey service")
    /// and casual starter "bro <command>" / "hey bro <command>" without matching casual trailing "bro".
    /// When `allowCasualShortTriggers` is false (e.g. while a YouTube video is talking out loud), skips casual
    /// `"bro"` / `"voice"` triggers so background media hosts cannot accidentally wake Voice.AI.
    public static func extractCommand(
        from transcript: String,
        wakePhrase: String,
        allowCasualShortTriggers: Bool = true
    ) -> String? {
        let clean = transcript.replacingOccurrences(of: "[,.!?।]", with: " ", options: .regularExpression)
                              .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                              .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = clean.lowercased()
        guard !lower.isEmpty else { return nil }

        let targetPhrase = wakePhrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let primary = targetPhrase.isEmpty ? "jarvis" : targetPhrase

        var patterns: [String] = []
        let escapedPrimary = NSRegularExpression.escapedPattern(for: primary)
        patterns.append(#"\b(?:hey\s+|hi\s+|ok\s+|okay\s+|hello\s+|the\s+|arey\s+)?\#(escapedPrimary)\b"#)

        if primary == "jarvis" {
            // Fast phonetic aliases that Apple SFSpeechRecognizer commonly produces for "Jarvis"
            let jarvisPhonetics = ["jervis", "jarves", "javis", "jarviz", "garvis", "charvis", "jar vis"]
            let joined = jarvisPhonetics.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            patterns.append(#"\b(?:hey\s+|hi\s+|ok\s+|okay\s+|hello\s+|arey\s+)?(?:\#(joined))\b"#)
            patterns.append(#"\b(?:hey|hi|ok|okay|hello|arey)\s+service\b"#)
        }

        if allowCasualShortTriggers {
            if primary != "voice" {
                // Standalone "voice" or prefixed "hey voice"/"ok voice" triggers without matching mid-sentence "Your voice settings..."
                patterns.append(#"^(?:(?:hey|hi|ok|okay|hello|the|arey)\s+)?voice\b"#)
                patterns.append(#"\b(?:hey|hi|ok|okay|hello|the|arey)\s+voice\b"#)
            }

            // Casual "Hey bro <cmd>", standalone "bro" / "hey bro", or leading "bro <cmd>" without matching trailing "... bro"
            patterns.append(#"^(?:(?:hey|hi|yo|ok|okay|arey)\s+)?bro\b"#)
            patterns.append(#"\b(?:hey|hi|yo|ok|okay|arey)\s+bro\b"#)
        } else {
            // Even while YouTube/music plays, explicit "Hey bro <cmd>" still wakes Voice.AI cleanly
            patterns.append(#"\b(?:hey|hi|yo|ok|okay|arey)\s+bro\b"#)
        }

        for pattern in patterns {
            if let match = lower.range(of: pattern, options: .regularExpression) {
                var afterWake = String(clean[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                for joiner in ["ji ", "sir ", "please ", "sun ", "suno ", "bhai ", "bro "] {
                    if afterWake.lowercased().hasPrefix(joiner) {
                        afterWake = String(afterWake.dropFirst(joiner.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                return afterWake
            }
        }
        return nil
    }

    /// Checks whether a live ambient transcript during/right after TTS playback is speaker echo of Jarvis's own voice.
    public static func looksLikeOwnTTSEcho(_ transcript: String, spokenNormalized: String) -> Bool {
        let t = transcript
            .replacingOccurrences(of: "[,.!?।\"']", with: " ", options: .regularExpression)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !spokenNormalized.isEmpty else { return false }
        let sClean = spokenNormalized
            .replacingOccurrences(of: "[,.!?।\"']", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sClean.isEmpty else { return false }

        if t.count >= 4 && sClean.contains(t) { return true }

        let tList = t.split(separator: " ").map(String.init)
        let sWords = Set(sClean.split(separator: " ").map(String.init))

        // Consecutive 2-word phrase overlap catches partial STT misrecognitions from speaker reverb
        if tList.count >= 2 {
            for i in 0..<(tList.count - 1) {
                let bigram = "\(tList[i]) \(tList[i + 1])"
                if sClean.contains(bigram) {
                    return true
                }
            }
        }

        let tWords = Set(tList)
        if tWords.count >= 2 && Double(tWords.intersection(sWords).count) / Double(tWords.count) >= 0.55 {
            return true
        }
        if tWords.count == 1 && t.count >= 5 && sWords.contains(t) {
            return true
        }
        return false
    }

    /// Determines whether an explicit wake/command should be suppressed because it came from TTS self-echo.
    public static func shouldSuppressWakeAsSelfEcho(
        transcript: String,
        spokenNormalized: String,
        isTTSActiveOrCoolingDown: Bool
    ) -> Bool {
        guard isTTSActiveOrCoolingDown, !spokenNormalized.isEmpty else { return false }
        // Explicit user interrupt ("shut up", "stop talking") always works unless TTS literally spoke that exact multi-word phrase
        if AppState.isSilenceAndCollapseCommand(transcript) {
            let cleanT = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanS = spokenNormalized.lowercased()
            return cleanS.contains(cleanT) && cleanT.split(separator: " ").count >= 2
        }
        return looksLikeOwnTTSEcho(transcript, spokenNormalized: spokenNormalized)
    }

    /// Starts active command capture on the ALREADY-RUNNING AVAudioEngine (zero CoreAudio teardown delay!).
    public func beginHotFollowUpCapture() {
        guard isListening else {
            startAmbientListening()
            return
        }
        isCapturingHotCommand = true
        hotCaptureStartedAt = Date()
        hotCaptureTranscript = ""
        pendingWakeWorkItem?.cancel()
        pendingWakeWorkItem = nil
        pendingFreeTalkWorkItem?.cancel()
        pendingFreeTalkWorkItem = nil
        restartTask()

        hotCaptureTimeoutWorkItem?.cancel()
        let timeoutWork = DispatchWorkItem { [weak self] in
            self?.finalizeHotFollowUpCapture()
        }
        hotCaptureTimeoutWorkItem = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0, execute: timeoutWork)
    }

    public func cancelHotFollowUpCapture() {
        guard isCapturingHotCommand else { return }
        isCapturingHotCommand = false
        hotCaptureTranscript = ""
        hotCaptureSilenceWorkItem?.cancel()
        hotCaptureSilenceWorkItem = nil
        hotCaptureTimeoutWorkItem?.cancel()
        hotCaptureTimeoutWorkItem = nil
        restartTask()
    }

    private func finalizeHotFollowUpCapture() {
        guard isCapturingHotCommand else { return }
        isCapturingHotCommand = false
        hotCaptureSilenceWorkItem?.cancel()
        hotCaptureSilenceWorkItem = nil
        hotCaptureTimeoutWorkItem?.cancel()
        hotCaptureTimeoutWorkItem = nil
        let captured = hotCaptureTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        hotCaptureTranscript = ""
        lastTriggerTime = Date()
        restartTask()
        DispatchQueue.main.async { [weak self] in
            self?.onHotCaptureCompleted?(captured)
        }
    }

    private func emitHotCaptureAudioLevels(from buffer: AVAudioPCMBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastHotLevelUpdateAt) >= 0.05 else { return }
        lastHotLevelUpdateAt = now
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        var sum: Float = 0.0
        for i in 0..<frameCount {
            let s = channelData[i]
            sum += s * s
        }
        let rms = sqrt(sum / Float(frameCount))
        let norm = CGFloat(min(1.0, max(0.08, rms * 15.0)))
        var levels: [CGFloat] = []
        levels.reserveCapacity(10)
        for i in 0..<10 {
            let v = CGFloat.random(in: -0.10...0.10)
            levels.append(min(1.0, max(0.08, norm + v * CGFloat(abs(i - 5)) * 0.14)))
        }
        DispatchQueue.main.async { [weak self] in
            self?.onHotCaptureLevels?(levels)
        }
    }

    /// Detects trailing spoken end-of-statement markers ("dot", "full stop", "end of statement", or trailing ".")
    /// while preserving internal dots inside domains/filenames (e.g. "mohit.dev" or "wikipedia.org").
    public static func stripStatementTerminator(_ raw: String) -> (cleaned: String, terminated: Bool) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", false) }

        if let bareRange = trimmed.range(
            of: #"^(?:dot|full\s+stop|end\s+of\s+statement)[.,!?]*$"#,
            options: [.regularExpression, .caseInsensitive]
        ), bareRange.lowerBound == trimmed.startIndex {
            return ("", true)
        }

        if let suffixRange = trimmed.range(
            of: #"\s+(?:dot|full\s+stop|end\s+of\s+statement)[.,!?]*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let clean = String(trimmed[..<suffixRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (clean, true)
        }

        // Handle speech recognizers that convert spoken "dot" into trailing "." without breaking "U.S." or "..."
        if trimmed.hasSuffix(".") && !trimmed.hasSuffix("..") {
            let wordCount = trimmed.split(separator: " ").count
            let isInitial = trimmed.range(of: #"\b[A-Za-z]\.$"#, options: .regularExpression) != nil
            if !isInitial && (wordCount >= 2 || trimmed.count >= 4) {
                let withoutTrailingDot = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                return (withoutTrailingDot, true)
            }
        }

        return (trimmed, false)
    }

    /// Strips casual conversational starters like "bro ", "hey bro " for 24/7 open-mic utterances.
    public static func cleanContinuousUtterance(_ transcript: String) -> String {
        var clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        clean = clean.replacingOccurrences(of: #"^(?:hey\s+|yo\s+|ok\s+)?(?:bro|bhai|jarvis)\b[\s,:!]*"#, with: "", options: [.regularExpression, .caseInsensitive])
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Checks live stream for configured wake-word + instruction (or hot follow-up capture / 24/7 continuous utterances):
    /// 1) Handles hot follow-up capture cleanly on the already-running audio tap (~0.70s silence finalize).
    /// 2) Interrupts active TTS immediately (<5ms) on "bro", "Voice", "hey bro", "Jarvis", or non-echo human commands.
    private func evaluateWakeWord(in transcript: String, isFinal: Bool) {
        let spokenCombined = SpeechPipelineEngine.shared.recentSpokenTextCombined
        let isTTSPlaying = (SpeechPipelineEngine.shared.currentState == .speaking)
        let isTTSCoolingDown = SpeechPipelineEngine.shared.isTTSActiveOrCoolingDown

        if isCapturingHotCommand {
            let cleanLive = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanLive.isEmpty {
                // Reject residual TTS echo arriving in the first ~300ms after barge-in/TTS stop
                if (isTTSCoolingDown || Date().timeIntervalSince(hotCaptureStartedAt) < 0.35),
                   Self.shouldSuppressWakeAsSelfEcho(
                       transcript: cleanLive,
                       spokenNormalized: spokenCombined,
                       isTTSActiveOrCoolingDown: true
                   ) {
                    return
                }
                let term = Self.stripStatementTerminator(cleanLive)
                hotCaptureTranscript = term.cleaned
                hotCaptureTimeoutWorkItem?.cancel()
                DispatchQueue.main.async { [weak self] in
                    self?.onHotCapturePartial?(term.cleaned)
                }
                if term.terminated || AppState.isSilenceAndCollapseCommand(term.cleaned) {
                    finalizeHotFollowUpCapture()
                    return
                }
                hotCaptureSilenceWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    self?.finalizeHotFollowUpCapture()
                }
                hotCaptureSilenceWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
            }
            if isFinal {
                finalizeHotFollowUpCapture()
            }
            return
        }

        // First: never react to Voice.AI's own TTS speaker output or post-TTS reverb tail
        if Self.shouldSuppressWakeAsSelfEcho(
            transcript: transcript,
            spokenNormalized: spokenCombined,
            isTTSActiveOrCoolingDown: isTTSCoolingDown
        ) {
            return
        }

        let listenToComputerAudio = ComputerAudioListenerService.shared.isEnabled
        let externalMediaPlaying = Self.isExternalComputerMediaPlaying()
        let suppressBackgroundMedia = externalMediaPlaying && !listenToComputerAudio

        // Allow explicit requests to toggle computer audio listening even while media is playing
        let directComputerToggle = ComputerAudioListenerService.parseListeningToggleCommand(transcript) != nil
        let extractedWake = Self.extractCommand(
            from: transcript,
            wakePhrase: wakePhrase,
            allowCasualShortTriggers: !suppressBackgroundMedia
        )
        let directSilence = (extractedWake == nil && canAcceptDirectSilenceCommand?() == true && AppState.isSilenceAndCollapseCommand(transcript))

        guard let afterWake = extractedWake ?? ((directSilence || directComputerToggle) ? transcript : nil) else {
            // While computer media / YouTube is playing and computer audio mode is OFF, ignore ambient non-wake chatter
            if suppressBackgroundMedia {
                return
            }

            if isTTSPlaying {
                // During active TTS (and NOT self-echo), allow real non-echo human speech (>=2 words) to interrupt immediately
                let cleaned = Self.cleanContinuousUtterance(transcript)
                let wc = cleaned.split(separator: " ").count
                if wc >= 2 && !Self.looksLikeOwnTTSEcho(transcript, spokenNormalized: spokenCombined) {
                    if Date().timeIntervalSince(lastBargeInTime) > 0.5 {
                        lastBargeInTime = Date()
                        SpeechPipelineEngine.shared.bargeIn()
                        ComputerUseOperator.shared.stopActiveRun()
                    }
                    if isAlwaysOn24x7Mode && !isTTSCoolingDown {
                        handleContinuous24x7Speech(transcript, isFinal: isFinal)
                    }
                }
            } else if isAlwaysOn24x7Mode && !isTTSCoolingDown {
                handleContinuous24x7Speech(transcript, isFinal: isFinal)
            }
            return
        }

        // Wake phrase heard — cancel any free-talk debounce
        pendingFreeTalkWorkItem?.cancel()
        pendingFreeTalkWorkItem = nil

        // Instant TTS & automation interruption the moment confirmed human wake word lands
        if Date().timeIntervalSince(lastBargeInTime) > 0.4 {
            lastBargeInTime = Date()
            SpeechPipelineEngine.shared.bargeIn()
            ComputerUseOperator.shared.stopActiveRun()
        }

        // Prevent duplicate firings within cooldown window
        guard Date().timeIntervalSince(lastTriggerTime) > 0.65 else { return }

        let dispatchWake: (String) -> Void = { [weak self] payload in
            guard let self = self else { return }
            guard Date().timeIntervalSince(self.lastTriggerTime) > 0.65 else { return }
            self.lastTriggerTime = Date()
            self.pendingWakeWorkItem?.cancel()
            self.pendingWakeWorkItem = nil
            self.pendingWakeTranscript = ""
            self.pendingWakeWasEmpty = false

            NSLog("[WakeWord] Triggered ('%@'). Payload: '%@'", self.wakePhrase, payload)
            SpeechPipelineEngine.shared.bargeIn()
            ComputerUseOperator.shared.stopActiveRun()
            EventBus.shared.publish(VoiceEvent(
                kind: .custom("wake_word_triggered"),
                source: "TheVoiceAmbientListener",
                severity: .info,
                payload: ["wake_phrase": self.wakePhrase, "has_command": payload.isEmpty ? "false" : "true"]
            ))

            if !payload.isEmpty {
                self.restartTask()
            }
            DispatchQueue.main.async { [weak self] in
                self?.onWakeWordTriggered?(payload)
            }
        }

        let termAfter = Self.stripStatementTerminator(afterWake)
        if isFinal || termAfter.terminated {
            dispatchWake(termAfter.cleaned)
            return
        }

        let trimmedAfter = termAfter.cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAfter.isEmpty {
            // Bare wake / "bro" / "Voice": fire in ~0.12s (never pushed back by identical partial repeats)
            if pendingWakeWorkItem == nil {
                pendingWakeWasEmpty = true
                pendingWakeTranscript = ""
                let work = DispatchWorkItem { dispatchWake("") }
                pendingWakeWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
            }
            return
        }

        // Non-empty command is growing after the wake word: only reschedule if trailing text actually changed
        if !pendingWakeWasEmpty && pendingWakeTranscript == trimmedAfter && pendingWakeWorkItem != nil {
            return
        }
        pendingWakeWasEmpty = false
        pendingWakeTranscript = trimmedAfter
        pendingWakeWorkItem?.cancel()
        let work = DispatchWorkItem {
            dispatchWake(trimmedAfter)
        }
        pendingWakeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.85, execute: work)
    }

    private func handleContinuous24x7Speech(_ transcript: String, isFinal: Bool) {
        let stripped = Self.cleanContinuousUtterance(transcript)
        let term = Self.stripStatementTerminator(stripped)
        let cleaned = term.cleaned
        guard !cleaned.isEmpty else { return }
        let wordCount = cleaned.split(separator: " ").count
        let isActionableShort = AgentToolParser.parse(query: cleaned) != nil || AppState.isSilenceAndCollapseCommand(cleaned)
        // Dispatch promptly once >= 2 words, a valid tool, final result, or spoken 'dot' arrives
        guard wordCount >= 2 || isActionableShort || isFinal || term.terminated else { return }
        guard Date().timeIntervalSince(lastTriggerTime) > 0.65 else { return }

        if isFinal || term.terminated {
            pendingFreeTalkWorkItem?.cancel()
            pendingFreeTalkWorkItem = nil
            pendingFreeTalkTranscript = ""
            lastTriggerTime = Date()
            restartTask()
            DispatchQueue.main.async { [weak self] in
                self?.onWakeWordTriggered?(cleaned)
            }
            return
        }

        if pendingFreeTalkTranscript == cleaned && pendingFreeTalkWorkItem != nil {
            return
        }
        pendingFreeTalkTranscript = cleaned
        pendingFreeTalkWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isAlwaysOn24x7Mode else { return }
            guard !Self.shouldSuppressWakeAsSelfEcho(
                transcript: cleaned,
                spokenNormalized: SpeechPipelineEngine.shared.recentSpokenTextCombined,
                isTTSActiveOrCoolingDown: SpeechPipelineEngine.shared.isTTSActiveOrCoolingDown
            ) else { return }
            if Self.isExternalComputerMediaPlaying() && !ComputerAudioListenerService.shared.isEnabled &&
               ComputerAudioListenerService.parseListeningToggleCommand(cleaned) == nil {
                return
            }
            guard Date().timeIntervalSince(self.lastTriggerTime) > 0.65 else { return }
            self.lastTriggerTime = Date()
            self.pendingFreeTalkWorkItem = nil
            self.pendingFreeTalkTranscript = ""
            self.restartTask()
            DispatchQueue.main.async { [weak self] in
                self?.onWakeWordTriggered?(cleaned)
            }
        }
        pendingFreeTalkWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
    
    private func restartTask() {
        activeRecognitionTaskToken = UUID()
        pendingWakeWorkItem?.cancel()
        pendingWakeWorkItem = nil
        pendingWakeTranscript = ""
        pendingWakeWasEmpty = false
        pendingFreeTalkWorkItem?.cancel()
        pendingFreeTalkWorkItem = nil
        pendingFreeTalkTranscript = ""
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = makeRecognitionRequest()
        startRecognitionTask()
    }
    
    public func pauseForRecording() {
        guard isListening else { return }
        activeRecognitionTaskToken = UUID()
        isPausedForActiveSession = true
        isListening = false
        isCapturingHotCommand = false
        hotCaptureTranscript = ""
        hotCaptureSilenceWorkItem?.cancel()
        hotCaptureSilenceWorkItem = nil
        hotCaptureTimeoutWorkItem?.cancel()
        hotCaptureTimeoutWorkItem = nil
        rotationTimer?.cancel()
        rotationTimer = nil
        pendingWakeWorkItem?.cancel()
        pendingWakeWorkItem = nil
        pendingFreeTalkWorkItem?.cancel()
        pendingFreeTalkWorkItem = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }
    
    public func resumeFromRecording() {
        guard isPausedForActiveSession && isTheVoiceModeEnabled else { return }
        isPausedForActiveSession = false
        startAmbientListening()
    }
    
    public func stopAmbientListening() {
        activeRecognitionTaskToken = UUID()
        isListening = false
        isPausedForActiveSession = false
        isCapturingHotCommand = false
        hotCaptureTranscript = ""
        hotCaptureSilenceWorkItem?.cancel()
        hotCaptureSilenceWorkItem = nil
        hotCaptureTimeoutWorkItem?.cancel()
        hotCaptureTimeoutWorkItem = nil
        rotationTimer?.cancel()
        rotationTimer = nil
        pendingWakeWorkItem?.cancel()
        pendingWakeWorkItem = nil
        pendingFreeTalkWorkItem?.cancel()
        pendingFreeTalkWorkItem = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        lastStatusNote = isTheVoiceModeEnabled ? "Paused" : "Hands-free listening is turned off"
        NSLog("[The Voice] Ambient listening disabled.")
    }
}

