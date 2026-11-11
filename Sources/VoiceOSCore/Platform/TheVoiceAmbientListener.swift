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
        
        // Request authorization if needed
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in }
        }
        if #available(macOS 10.14, *) {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            }
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
        } catch {
            NSLog("[The Voice] Failed to start ambient audio engine: %@", error.localizedDescription)
            return
        }
        
        startRecognitionTask()
        NSLog("[The Voice] Ambient hands-free wake word listening active ('Voice ...').")
    }
    
    private func startRecognitionTask() {
        guard let request = recognitionRequest else { return }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                self.evaluateWakeWord(in: text)
            }
            
            if error != nil {
                // Restart cycle gracefully when Apple speech task times out
                if self.isListening && !self.isPausedForActiveSession {
                    self.restartTask()
                }
            }
        }
    }
    
    /// Pure helper for extracting an actionable command after a configurable wake phrase (English, Hindi & Hinglish).
    public static func extractCommand(from transcript: String, wakePhrase: String) -> String? {
        let clean = transcript.replacingOccurrences(of: "[,.!?।]", with: " ", options: .regularExpression)
                              .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = clean.lowercased()
        guard !lower.isEmpty else { return nil }

        let targetPhrase = wakePhrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates = Array(Set([targetPhrase.isEmpty ? "jarvis" : targetPhrase, "voice"]))

        for phrase in candidates {
            let escaped = NSRegularExpression.escapedPattern(for: phrase)
            let pattern = #"\b(?:hey\s+|hi\s+|ok\s+|okay\s+|hello\s+|the\s+|arey\s+)?\#(escaped)\b"#
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

    /// Checks live stream for configured wake-word + instruction and triggers barge-in immediately.
    private func evaluateWakeWord(in transcript: String) {
        if let afterWake = Self.extractCommand(from: transcript, wakePhrase: wakePhrase) {
            // Cooldown check (prevent multiple firings within 1.5 seconds)
            guard Date().timeIntervalSince(lastTriggerTime) > 1.5 else { return }
            lastTriggerTime = Date()
            
            NSLog("[WakeWord] Triggered ('%@'). Payload: '%@'", wakePhrase, afterWake)
            SpeechPipelineEngine.shared.bargeIn()
            EventBus.shared.publish(VoiceEvent(
                kind: .custom("wake_word_triggered"),
                source: "TheVoiceAmbientListener",
                severity: .info,
                payload: ["wake_phrase": wakePhrase, "has_command": afterWake.isEmpty ? "false" : "true"]
            ))
            
            restartTask()
            DispatchQueue.main.async { [weak self] in
                self?.onWakeWordTriggered?(afterWake)
            }
            return
        }
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

