import Foundation
import AVFoundation
import Speech

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
    private var isPausedForActiveSession: Bool = false
    private var consecutiveErrorCount: Int = 0
    private var pendingWakeWorkItem: DispatchWorkItem?
    private var lastBargeInTime: Date = .distantPast
    private let wakePhraseKey = "VoiceAI_ConfiguredWakePhrase"

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
    
    // Callback when wake-word is triggered with actionable instruction
    public var onWakeWordTriggered: ((String) -> Void)?
    
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
        guard !isListening else { return }
        guard isTheVoiceModeEnabled else { return }
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.infoDictionary?["NSSpeechRecognitionUsageDescription"] != nil else { return }
        
        if speechRecognizer == nil {
            initRecognizer()
        }
        
        // Request authorization and auto-start once granted instead of racing audioEngine startup
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        if speechStatus == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                guard status == .authorized else { return }
                DispatchQueue.main.async { self?.startAmbientListening() }
            }
            return
        }
        guard speechStatus == .authorized else { return }

        if #available(macOS 10.14, *) {
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if micStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    guard granted else { return }
                    DispatchQueue.main.async { self?.startAmbientListening() }
                }
                return
            }
            guard micStatus == .authorized else { return }
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            NSLog("[The Voice] Microphone input format not ready yet.")
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        
        // Bias configurable wake phrase + built-in aliases
        let activePhrase = wakePhrase
        request.contextualStrings = [activePhrase, "hey \(activePhrase)", "voice", "hey voice", "jarvis", "hey jarvis"]
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            consecutiveErrorCount = 0
        } catch {
            NSLog("[The Voice] Failed to start ambient audio engine: %@", error.localizedDescription)
            return
        }
        
        startRecognitionTask()
        NSLog("[The Voice] Ambient hands-free wake word listening active ('%@ ...').", activePhrase)
    }
    
    private func startRecognitionTask() {
        guard let request = recognitionRequest else { return }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.consecutiveErrorCount = 0
                let text = result.bestTranscription.formattedString
                self.evaluateWakeWord(in: text, isFinal: result.isFinal)
            }
            
            if let err = error {
                let nsErr = err as NSError
                // Ignore intentional cancellation when restarting/pausing
                if nsErr.code == 216 || nsErr.code == 301 { return }
                // Backoff gently when Apple speech task times out or hits transient error
                if self.isListening && !self.isPausedForActiveSession {
                    self.consecutiveErrorCount += 1
                    let delay = min(2.0, 0.35 * Double(self.consecutiveErrorCount))
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self = self, self.isListening && !self.isPausedForActiveSession else { return }
                        self.restartTask()
                    }
                }
            }
        }
    }
    
    /// Pure helper for extracting an actionable command after a configurable wake phrase (English, Hindi & Hinglish).
    /// Requires explicit greeting prefix for the secondary "voice" alias (unless wakePhrase itself is "voice")
    /// so self-echo / ordinary conversation mentioning "voice" does not cause false wake triggers.
    public static func extractCommand(from transcript: String, wakePhrase: String) -> String? {
        let clean = transcript.replacingOccurrences(of: "[,.!?।]", with: " ", options: .regularExpression)
                              .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = clean.lowercased()
        guard !lower.isEmpty else { return nil }

        let targetPhrase = wakePhrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let primary = targetPhrase.isEmpty ? "jarvis" : targetPhrase

        var patterns: [String] = []
        let escapedPrimary = NSRegularExpression.escapedPattern(for: primary)
        patterns.append(#"\b(?:hey\s+|hi\s+|ok\s+|okay\s+|hello\s+|the\s+|arey\s+)?\#(escapedPrimary)\b"#)
        if primary != "voice" {
            // Secondary fallback "voice" always requires a wake prefix to avoid accidental TTS self-barge-in
            patterns.append(#"\b(?:hey|hi|ok|okay|hello|the|arey)\s+voice\b"#)
        }

        for pattern in patterns {
            if let match = lower.range(of: pattern, options: .regularExpression) {
                var afterWake = String(clean[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Strip optional Hindi/English polite joiners immediately following the wake word
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

    /// Checks live stream for configured wake-word + instruction:
    /// 1) Barges in on active TTS immediately when wake phrase is heard.
    /// 2) Debounces trailing words (~0.45s) so "Hey Jarvis open Safari" isn't cut off mid-breath before triggering.
    private func evaluateWakeWord(in transcript: String, isFinal: Bool) {
        guard let afterWake = Self.extractCommand(from: transcript, wakePhrase: wakePhrase) else { return }

        // Instant TTS interruption the moment wake word lands
        if Date().timeIntervalSince(lastBargeInTime) > 0.8 {
            lastBargeInTime = Date()
            SpeechPipelineEngine.shared.bargeIn()
            ComputerUseOperator.shared.stopActiveRun()
        }

        // Prevent duplicate firings within cooldown window
        guard Date().timeIntervalSince(lastTriggerTime) > 1.5 else { return }

        let dispatchWake: (String) -> Void = { [weak self] payload in
            guard let self = self else { return }
            guard Date().timeIntervalSince(self.lastTriggerTime) > 1.5 else { return }
            self.lastTriggerTime = Date()
            self.pendingWakeWorkItem?.cancel()
            self.pendingWakeWorkItem = nil

            NSLog("[WakeWord] Triggered ('%@'). Payload: '%@'", self.wakePhrase, payload)
            SpeechPipelineEngine.shared.bargeIn()
            ComputerUseOperator.shared.stopActiveRun()
            EventBus.shared.publish(VoiceEvent(
                kind: .custom("wake_word_triggered"),
                source: "TheVoiceAmbientListener",
                severity: .info,
                payload: ["wake_phrase": self.wakePhrase, "has_command": payload.isEmpty ? "false" : "true"]
            ))

            self.restartTask()
            DispatchQueue.main.async { [weak self] in
                self?.onWakeWordTriggered?(payload)
            }
        }

        if isFinal {
            dispatchWake(afterWake)
            return
        }

        // Coalesce streaming partial words right after wake word so full command is captured
        pendingWakeWorkItem?.cancel()
        let waitInterval: TimeInterval = afterWake.isEmpty ? 0.50 : 0.45
        let work = DispatchWorkItem {
            dispatchWake(afterWake)
        }
        pendingWakeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + waitInterval, execute: work)
    }
    
    private func restartTask() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            recognitionRequest?.requiresOnDeviceRecognition = true
        }
        let activePhrase = wakePhrase
        recognitionRequest?.contextualStrings = [activePhrase, "hey \(activePhrase)", "voice", "hey voice"]
        startRecognitionTask()
    }
    
    public func pauseForRecording() {
        guard isListening else { return }
        isPausedForActiveSession = true
        isListening = false
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
        isListening = false
        isPausedForActiveSession = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        NSLog("[The Voice] Ambient listening disabled.")
    }
}

