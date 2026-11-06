import Foundation
import AVFoundation
import Speech

/// "THE VOICE" Mode: Ambient Hands-Free Wake-Word Recognition Engine
/// Keeps the app in a lightweight background listening state without touching any keyboard keys.
/// Remains completely idle until the user calls it with "Voice ...", then autonomously executes the requested action.
/// Supports barge-in interruption whenever the agent is speaking or executing.
public final class TheVoiceAmbientListener: NSObject, @unchecked Sendable, SFSpeechRecognizerDelegate {
    public static let shared = TheVoiceAmbientListener()
    
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    public private(set) var isListening: Bool = false
    private var isPausedForActiveSession: Bool = false

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
        
        // Bias wake-words
        request.contextualStrings = ["voice", "the voice", "hey voice", "voice please"]
        
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
    
    /// Checks live stream for wake-word "voice [command]" or standalone "voice"
    private func evaluateWakeWord(in transcript: String) {
        let clean = transcript.replacingOccurrences(of: "[,.!?]", with: " ", options: .regularExpression)
                              .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = clean.lowercased()
        guard !lower.isEmpty else { return }
        
        // Match regex for wake-word: \b(hey\s+|the\s+|ok\s+|okay\s+)?voice\b
        if let match = lower.range(of: #"\b(hey\s+|the\s+|ok\s+|okay\s+)?voice\b"#, options: .regularExpression) {
            let afterWake = String(clean[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Cooldown check (prevent multiple firings within 1.5 seconds)
            guard Date().timeIntervalSince(lastTriggerTime) > 1.5 else { return }
            lastTriggerTime = Date()
            
            NSLog("[The Voice] Wake word matched! Instruction payload: '%@'", afterWake)
            
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
        recognitionRequest?.contextualStrings = ["voice", "the voice", "hey voice"]
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

