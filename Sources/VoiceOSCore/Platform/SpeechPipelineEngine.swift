import AVFoundation
import Speech
import Foundation
import Combine

public enum SpeechEngineState: Equatable, Sendable {
    case idle
    case recording(VoiceTriggerMode)
    case transcribing
    case speaking
    case error(String)
}

/// The core real-time voice pipeline for VoiceOS.
/// Captures microphone audio, streams real-time audio power metering levels for the Notch HUD waveform,
/// performs speech-to-text transcription via on-device SpeechRecognizer,
/// and speaks back responses with AVSpeechSynthesizer.
public final class SpeechPipelineEngine: NSObject, @unchecked Sendable, SFSpeechRecognizerDelegate, AVSpeechSynthesizerDelegate {
    public static let shared = SpeechPipelineEngine()

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechSynthesizer = AVSpeechSynthesizer()

    public private(set) var currentState: SpeechEngineState = .idle
    private var currentMode: VoiceTriggerMode = .dictation
    private var accumulatedTranscript: String = ""
    private var lastTranscribedText: String = ""
    private var lastSpeechTimestamp: Date = Date()
    private var silenceWorkItem: DispatchWorkItem?
    private var isUsingLocalWhisperForSession: Bool = false
    private let whisperProvider = LocalWhisperProvider()

    // Adaptive RMS End-of-Speech VAD (essential for Whisper & fast silence auto-stop)
    private let vadLock = NSLock()
    private var hasDetectedSpeechInSession: Bool = false
    private var speechHitBuffers: Int = 0
    private var ambientNoiseFloorRMS: Float = 0.004
    private var recordingStartedAt: Date = Date()
    private var lastVoiceActivityAt: Date = Date()
    private var lastAudioUIUpdateAt: Date = .distantPast
    private var vadTimer: DispatchSourceTimer?

    // Streaming Sentence-Chunk TTS Queue & Barge-In State
    private let ttsLock = NSLock()
    private var ttsGeneration: UInt64 = 0
    private var ttsChunkQueue: [(text: String, isHinglish: Bool)] = []
    private var isProcessingTTSQueue: Bool = false
    private var ttsCompletionCallback: (@Sendable () -> Void)?

    // Callbacks to update UI / AppState
    public var onAudioLevelsUpdated: (([CGFloat]) -> Void)?
    public var onLiveTranscript: ((String) -> Void)?
    public var onTranscriptionCompleted: ((String, VoiceTriggerMode) -> Void)?
    public var onStateChanged: ((SpeechEngineState) -> Void)?

    public override init() {
        super.init()
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.infoDictionary?["NSSpeechRecognitionUsageDescription"] != nil else {
            // Running in unit test or non-bundled CLI harness without TCC entitlements
            return
        }
        // Auto-select Indian English (understands both fluent English and Hinglish/Hindi code-switching), fallback to system
        let preferredLocales = [Locale(identifier: "en-IN"), Locale.current, Locale(identifier: "en-US"), Locale(identifier: "hi-IN")]
        var selectedRecognizer: SFSpeechRecognizer?
        for loc in preferredLocales {
            let r = SFSpeechRecognizer(locale: loc)
            if r != nil && r?.isAvailable == true {
                selectedRecognizer = r
                break
            }
        }
        self.speechRecognizer = selectedRecognizer ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        self.speechRecognizer?.delegate = self
        self.speechSynthesizer.delegate = self

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in }
        }
        if #available(macOS 10.14, *) {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            }
        }
    }

    // MARK: - Voice Pipeline Controls

    public func startRecording(mode: VoiceTriggerMode) {
        TheVoiceAmbientListener.shared.pauseForRecording()
        
        // Stop any active streaming or queued TTS playback immediately (Barge-In)
        bargeIn()

        // Clean up any stale audio session before starting fresh
        if currentState != .idle {
            cancel()
        }

        self.currentMode = mode
        self.currentState = .recording(mode)
        onStateChanged?(.recording(mode))

        // Reset recognition and silence detection
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        accumulatedTranscript = ""
        lastTranscribedText = ""
        lastSpeechTimestamp = Date()
        startVADMonitor()
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Check if Local Whisper is selected and ready
        let preferWhisper = (STTEngineProvider.shared.selectedKind == .localWhisper) && LocalWhisperProvider.diagnostics().isReady
        self.isUsingLocalWhisperForSession = preferWhisper

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // If recording format is invalid (no mic permission or muted), notify safely and recover
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            self.currentState = .error("Microphone input format invalid or access denied.")
            onStateChanged?(self.currentState)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self = self else { return }
                self.currentState = .idle
                self.onStateChanged?(.idle)
                self.onTranscriptionCompleted?("", mode)
            }
            return
        }

        if preferWhisper {
            let config = STTConfiguration(
                providerKind: .localWhisper,
                localeIdentifier: "auto",
                vocabularyBiasing: VocabularyBiasManager.shared.getVocabularyBias()
            )
            whisperProvider.start(
                configuration: config,
                onPartialResult: { [weak self] partial in
                    DispatchQueue.main.async { self?.onLiveTranscript?(partial) }
                },
                onFinalResult: { [weak self] finalText, _ in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.accumulatedTranscript = finalText
                        self.currentState = .idle
                        self.onStateChanged?(.idle)
                        TheVoiceAmbientListener.shared.resumeFromRecording()
                        self.onTranscriptionCompleted?(finalText, mode)
                    }
                },
                onError: { [weak self] err in
                    NSLog("[VoiceOS Whisper] Error: %@", err.localizedDescription)
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.currentState = .idle
                        self.onStateChanged?(.idle)
                        TheVoiceAmbientListener.shared.resumeFromRecording()
                        self.onTranscriptionCompleted?(self.accumulatedTranscript, mode)
                    }
                }
            )
            
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                self.whisperProvider.appendAudioBuffer(buffer)
                self.processAudioLevels(buffer: buffer)
            }
            
            do {
                audioEngine.prepare()
                try audioEngine.start()
            } catch {
                self.whisperProvider.cancel()
                self.currentState = .error("Failed to start audio engine: \(error.localizedDescription)")
                onStateChanged?(self.currentState)
            }
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            self.currentState = .idle
            self.onStateChanged?(.idle)
            self.onTranscriptionCompleted?("", mode)
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        // Contextual vocabulary biasing: dynamic app names + Hindi command verbs
        let biasList = VocabularyBiasManager.shared.getVocabularyBias()
        recognitionRequest.contextualStrings = Array(biasList.prefix(150))

        // Allow macOS to use on-device recognition if installed or fall back to system service
        if #available(macOS 10.15, *) {
            if speechRecognizer?.supportsOnDeviceRecognition == true {
                recognitionRequest.requiresOnDeviceRecognition = false
            }
        }

        // Install audio tap for real-time metering and recognition buffer feed
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)

            // Calculate real-time RMS audio power for HUD waveform
            self.processAudioLevels(buffer: buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            NSLog("[VoiceOS Audio] Failed to start audio engine: %@", error.localizedDescription)
            self.currentState = .error("Failed to start audio engine: \(error.localizedDescription)")
            onStateChanged?(self.currentState)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self = self else { return }
                self.currentState = .idle
                self.onStateChanged?(.idle)
                self.onTranscriptionCompleted?("", mode)
            }
            return
        }

        // Start Speech Recognition Task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let rawText = result.bestTranscription.formattedString
                self.accumulatedTranscript = rawText
                DispatchQueue.main.async {
                    self.onLiveTranscript?(rawText)
                }
                
                let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    // Only restart silence timer if new speech tokens/words actually arrived
                    if trimmed != self.lastTranscribedText {
                        self.lastTranscribedText = trimmed
                        self.lastSpeechTimestamp = Date()
                        self.resetSilenceTimer()
                    }
                }
            }

            if let error = error {
                NSLog("[VoiceOS SpeechEngine] Recognition notice/error: %@", error.localizedDescription)
                if result == nil && self.currentState != .idle {
                    DispatchQueue.main.async {
                        self.stopRecording()
                    }
                }
            }
        }
    }

    private func resetSilenceTimer() {
        silenceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard case .recording = self.currentState else { return }
            let text = self.accumulatedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            
            let elapsed = Date().timeIntervalSince(self.lastSpeechTimestamp)
            if elapsed >= 1.8 {
                NSLog("[VoiceOS SpeechEngine] 2.0s silence detected. Auto-finalizing utterance: %@", text)
                DispatchQueue.main.async {
                    self.stopRecording()
                }
            }
        }
        self.silenceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    public func stopRecording() {
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        stopVADMonitor()
        let mode = self.currentMode
        let transcript = self.accumulatedTranscript

        guard case .recording = currentState else {
            // Clean up cleanly and transition to idle
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
            recognitionTask?.finish()
            recognitionTask = nil
            recognitionRequest = nil

            self.currentState = .idle
            onStateChanged?(.idle)
            onTranscriptionCompleted?(transcript, mode)
            return
        }

        self.currentState = .transcribing
        onStateChanged?(.transcribing)

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        if isUsingLocalWhisperForSession {
            isUsingLocalWhisperForSession = false
            whisperProvider.stop()
            return
        }
        
        recognitionRequest?.endAudio()

        // Short finalization window (0.25s) for Apple speech recognizer best transcription
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self else { return }
            let finalTranscript = self.accumulatedTranscript
            self.recognitionTask?.finish()
            self.recognitionTask = nil
            self.recognitionRequest = nil

            self.currentState = .idle
            self.onStateChanged?(.idle)
            TheVoiceAmbientListener.shared.resumeFromRecording()
            self.onTranscriptionCompleted?(finalTranscript, mode)
        }
    }

    public func cancel() {
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        stopVADMonitor()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        if isUsingLocalWhisperForSession {
            isUsingLocalWhisperForSession = false
            whisperProvider.cancel()
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        TheVoiceAmbientListener.shared.resumeFromRecording()

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        KokoroTTSEngine.shared.stop()

        self.currentState = .idle
        onStateChanged?(.idle)
    }

    // MARK: - Streaming Text-to-Speech & Mid-Sentence Barge-In

    /// Splits a full reply into speakable sentence/clause chunks so TTS starts immediately on sentence 1.
    public static func splitIntoSpeakableChunks(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var chunks: [String] = []
        var current = ""
        let terminators: Set<Character> = [".", "!", "?", "।", "\n"]

        for ch in trimmed {
            current.append(ch)
            if terminators.contains(ch) {
                let candidate = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.count >= 8 {
                    chunks.append(candidate)
                    current = ""
                }
            }
        }
        let remainder = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty {
            if let last = chunks.popLast(), remainder.count < 8 {
                chunks.append("\(last) \(remainder)")
            } else {
                chunks.append(remainder)
            }
        }
        return chunks.isEmpty ? [trimmed] : chunks
    }

    public func currentTTSGeneration() -> UInt64 {
        ttsLock.withLock { ttsGeneration }
    }

    /// Stops any active speech playback immediately (mid-sentence barge-in) and clears queued chunks.
    public func bargeIn() {
        ttsLock.withLock {
            ttsGeneration &+= 1
            ttsChunkQueue.removeAll()
            isProcessingTTSQueue = false
            ttsCompletionCallback = nil
        }

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        KokoroTTSEngine.shared.stop()

        if currentState == .speaking {
            self.currentState = .idle
            onStateChanged?(.idle)
        }

        EventBus.shared.publish(VoiceEvent(
            kind: .custom("tts_barge_in"),
            source: "SpeechPipelineEngine",
            severity: .info,
            payload: ["interrupted": "true"]
        ))
    }

    /// Streams an incremental sentence chunk onto the active TTS queue without clearing earlier chunks.
    public func enqueueStreamingSpeechChunk(_ chunk: String) {
        let clean = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let isHinglish = HinglishParser.isHinglishQuery(clean)

        let shouldKickoff = ttsLock.withLock { () -> (Bool, UInt64) in
            ttsChunkQueue.append((text: clean, isHinglish: isHinglish))
            if !isProcessingTTSQueue {
                isProcessingTTSQueue = true
                return (true, ttsGeneration)
            }
            return (false, ttsGeneration)
        }

        if shouldKickoff.0 {
            self.currentState = .speaking
            onStateChanged?(.speaking)
            playNextTTSChunk(generation: shouldKickoff.1)
        }
    }

    public func speakResponse(_ text: String, completion: (@Sendable () -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?()
            return
        }

        // Barge-in any previous utterance cleanly before starting fresh response
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        KokoroTTSEngine.shared.stop()

        let isHinglish = HinglishParser.isHinglishQuery(text)
        let spokenText = Self.formatMinimalisticSpokenReply(rawText: text, isHinglish: isHinglish)
        let chunks = Self.splitIntoSpeakableChunks(spokenText)

        guard !chunks.isEmpty else {
            self.currentState = .idle
            onStateChanged?(.idle)
            completion?()
            return
        }

        let gen = ttsLock.withLock { () -> UInt64 in
            ttsGeneration &+= 1
            ttsChunkQueue = chunks.map { (text: $0, isHinglish: isHinglish) }
            ttsCompletionCallback = completion
            isProcessingTTSQueue = true
            return ttsGeneration
        }

        self.currentState = .speaking
        onStateChanged?(.speaking)
        playNextTTSChunk(generation: gen)
    }

    private func playNextTTSChunk(generation: UInt64) {
        let nextItem = ttsLock.withLock { () -> (item: (text: String, isHinglish: Bool)?, finishCallback: (@Sendable () -> Void)?) in
            guard generation == ttsGeneration else { return (nil, nil) }
            if ttsChunkQueue.isEmpty {
                isProcessingTTSQueue = false
                let cb = ttsCompletionCallback
                ttsCompletionCallback = nil
                return (nil, cb)
            }
            return (ttsChunkQueue.removeFirst(), nil)
        }

        guard generation == currentTTSGeneration() else { return }

        guard let item = nextItem.item else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, generation == self.currentTTSGeneration() else { return }
                self.currentState = .idle
                self.onStateChanged?(.idle)
                nextItem.finishCallback?()
            }
            return
        }

        let hasDevanagari = item.text.unicodeScalars.contains { scalar in
            scalar.value >= 0x0900 && scalar.value <= 0x097F
        }

        if KokoroTTSEngine.shared.isPreferredForTTS && !hasDevanagari &&
            FileManager.default.fileExists(atPath: KokoroTTSEngine.weightsURL.path) {
            KokoroTTSEngine.shared.speak(text: item.text, voice: KokoroTTSEngine.shared.selectedVoiceId) { [weak self] played in
                DispatchQueue.main.async {
                    guard let self = self, generation == self.currentTTSGeneration() else { return }
                    if played {
                        self.playNextTTSChunk(generation: generation)
                    } else {
                        self.speakWithSystemSynthesizer(item.text, isHinglish: item.isHinglish)
                    }
                }
            }
            return
        }

        speakWithSystemSynthesizer(item.text, isHinglish: item.isHinglish)
    }

    private func speakWithSystemSynthesizer(_ spokenText: String, isHinglish: Bool) {
        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.rate = 0.52 // Smooth, natural conversational pace (not dragging or robotic)
        utterance.pitchMultiplier = 1.02 // Pleasant, human tonal quality
        utterance.preUtteranceDelay = 0.05

        let hasDevanagari = spokenText.unicodeScalars.contains { scalar in
            scalar.value >= 0x0900 && scalar.value <= 0x097F
        }

        if hasDevanagari {
            utterance.voice = selectBestVoice(for: "hi")
        } else if isHinglish {
            utterance.voice = selectBestVoice(for: "en-IN") ?? selectBestVoice(for: "hi")
        } else if let savedId = UserDefaults.standard.string(forKey: "voiceos.selected_voice_id"),
                  !savedId.isEmpty,
                  let savedVoice = AVSpeechSynthesisVoice(identifier: savedId) {
            utterance.voice = savedVoice
        } else {
            utterance.voice = selectBestVoice(for: "en")
        }

        speechSynthesizer.speak(utterance)
    }

    private func selectBestVoice(for languagePrefix: String) -> AVSpeechSynthesisVoice? {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let prefix = languagePrefix.lowercased()

        // 1. High quality enhanced / premium voices if available
        if let enhanced = allVoices.first(where: {
            $0.language.lowercased().hasPrefix(prefix) &&
            ($0.quality == .enhanced || $0.quality == .premium)
        }) {
            return enhanced
        }

        // 2. High-quality natural sounding macOS voice names
        let naturalVoiceNames = ["Ava", "Samantha", "Allison", "Lekha", "Rishi", "Daniel", "Serena", "Karen", "Neel"]
        if let natural = allVoices.first(where: { v in
            v.language.lowercased().hasPrefix(prefix) && naturalVoiceNames.contains(where: { v.name.contains($0) })
        }) {
            return natural
        }

        // 3. Standard voice for this language
        if let match = allVoices.first(where: { $0.language.lowercased().hasPrefix(prefix) }) {
            return match
        }

        // 4. Default fallback
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Generates minimalistic, polite spoken replies for automation tasks rather than reading long robotic URLs.
    public static func formatMinimalisticSpokenReply(rawText: String, isHinglish: Bool = false) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Never mask failures/errors with fake "i just did" replies
        if lower.hasPrefix("could not") || lower.hasPrefix("unable to") || lower.hasPrefix("failed") ||
           lower.hasPrefix("error") || lower.contains("not found") || lower.contains("cannot locate") ||
           lower.contains("permission") || lower.contains("blocked for safety") {
            return trimmed
        }

        // 0. Closing Applications (MUST check before music/spotify/safari to avoid misrouting closed apps)
        if lower.contains("closed ") || lower.contains("closed the") || lower.contains("quit ") ||
           lower.contains("terminated ") || (lower.contains("band kar") && lower.contains("app")) {
            return isHinglish ? "Aapke liye app band kar diya sir." : "i just did"
        }

        // 1. Music / Audio / Spotify / YouTube playback
        if lower.contains("playing") || lower.contains("spotify") || lower.contains("youtube") ||
           lower.contains("gaana") || lower.contains("song") || lower.contains("chalao") ||
           lower.contains("video") || lower.contains("playback") ||
           lower.contains("doraemon") || lower.contains("doreamon") {
            if lower.contains("pause") || lower.contains("paused") {
                return isHinglish ? "Gaana pause kar diya sir." : "Paused playback, sir."
            }
            if lower.contains("next") || lower.contains("agla") || lower.contains("skip") {
                return isHinglish ? "Agla gaana chala diya sir." : "Playing the next track, sir."
            }
            if lower.contains("previous") || lower.contains("pichhla") || lower.contains("pichla") {
                return isHinglish ? "Pichhla gaana chala diya sir." : "Playing previous track, sir."
            }
            return isHinglish ? "Aapke liye gaana chala diya sir." : "currently playing this song"
        }

        // 2. UI Click Actions
        if lower.contains("clicked") || lower.contains("click") {
            if lower.contains("video") || lower.contains("song") || lower.contains("play") {
                return isHinglish ? "Aapke liye gaana chala diya sir." : "currently playing this song"
            }
            return isHinglish ? "Kaam ho gaya sir." : "i just did"
        }

        // 3. Opening Applications, Browser Tabs, Pages, or Folders
        if lower.contains("opened ") || lower.contains("opening ") ||
           lower.contains("in safari") || lower.contains("in chrome") ||
           lower.contains("in browser") || lower.contains("in finder") ||
           lower.contains("chatgpt") || lower.contains("claude") {
            return isHinglish ? "Aapke liye app khol diya sir." : "opened the app for you sir"
        }

        // 4. Automation Actions: Terminal, Volume, Screenshot, Files, Notes, Reminders, Settings
        if lower.contains("ran terminal command") || lower.contains("volume set") || lower.contains("screenshot") ||
           lower.contains("created note") || lower.contains("added reminder") || lower.contains("scheduled reminder") ||
           (lower.contains("created") && lower.contains("desktop")) || lower.contains("brightness") ||
           lower.contains("executed window") || lower.contains("executed system") || lower.contains("clicked ui") ||
           lower.contains("typed:") {
            return isHinglish ? "Kaam ho gaya sir." : "i just did"
        }

        // 4. World Search / Deep Research Report
        if lower.contains("world search") || lower.contains("deep search") || lower.contains("executive summary") ||
           trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") {
            return isHinglish ? "Aapke liye poori report taiyaar kar di hai sir." : "I found the complete report for you sir."
        }

        // 5. Interactive Tutorial Steering (Blender, VS Code, Live Screen, etc.)
        if lower.contains("in blender") || lower.contains("to animate in blender") ||
           lower.contains("guiding you autonomously") || lower.contains("guiding you live") ||
           lower.contains("live on your screen") || lower.contains("live screen") {
            return isHinglish ? "Main aapko step by step guide kar raha hoon sir." : "Guiding you through the steps now, sir."
        }

        // Conversational / Direct Answer
        // Strip URLs regex so speech synthesizer never spells out "h-t-t-p-s-colon-slash-slash"
        var cleaned = trimmed
        if let urlRegex = try? NSRegularExpression(pattern: "https?://\\S+", options: .caseInsensitive) {
            cleaned = urlRegex.stringByReplacingMatches(in: cleaned, range: NSRange(location: 0, length: cleaned.utf16.count), withTemplate: "")
        }
        cleaned = cleaned.replacingOccurrences(of: "#", with: "")
        cleaned = cleaned.replacingOccurrences(of: "*", with: "")
        cleaned = cleaned.replacingOccurrences(of: "`", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            return isHinglish ? "Kaam ho gaya sir." : "i just did"
        }

        // Keep speech natural and complete: speak up to 4 complete sentences without mid-sentence truncation
        let rawSentences = cleaned.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            
        if rawSentences.count > 4 {
            let selected = rawSentences.prefix(4).joined(separator: ". ")
            return selected + "."
        } else if !rawSentences.isEmpty {
            let joined = rawSentences.joined(separator: ". ")
            return joined.hasSuffix(".") ? joined : joined + "."
        }

        return cleaned
    }

    public func stopSpeaking() {
        bargeIn()
    }

    // MARK: - Adaptive End-of-Speech VAD & Audio Level Processing

    private func startVADMonitor() {
        stopVADMonitor()
        let now = Date()
        vadLock.lock()
        hasDetectedSpeechInSession = false
        speechHitBuffers = 0
        ambientNoiseFloorRMS = 0.004
        recordingStartedAt = now
        lastVoiceActivityAt = now
        lastAudioUIUpdateAt = .distantPast
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 0.25, repeating: 0.15)
        timer.setEventHandler { [weak self] in
            self?.checkVADSilenceTimeout()
        }
        vadTimer = timer
        vadLock.unlock()
        timer.resume()
    }

    private func stopVADMonitor() {
        vadLock.lock()
        let timer = vadTimer
        vadTimer = nil
        vadLock.unlock()
        timer?.cancel()
    }

    private func checkVADSilenceTimeout() {
        guard case .recording = currentState else { return }
        // While user is physically holding the hotkey down, let key-release finalize instead of cutting off pauses
        if HotkeyManager.shared.isAnyHotkeyHeld { return }

        vadLock.lock()
        let detected = hasDetectedSpeechInSession
        let silentFor = Date().timeIntervalSince(lastVoiceActivityAt)
        let startedFor = Date().timeIntervalSince(recordingStartedAt)
        vadLock.unlock()

        // Once speech was heard, finalize automatically ~0.95s after user stops talking
        if detected && silentFor >= 0.95 {
            stopVADMonitor()
            DispatchQueue.main.async { [weak self] in
                guard let self = self, case .recording = self.currentState else { return }
                self.stopRecording()
            }
        } else if !detected && startedFor >= 6.5 {
            // If user opened mic and said nothing for 6.5s, stop cleanly instead of hanging 20s
            stopVADMonitor()
            DispatchQueue.main.async { [weak self] in
                guard let self = self, case .recording = self.currentState else { return }
                self.stopRecording()
            }
        }
    }

    private func processAudioLevels(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var sum: Float = 0.0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        let now = Date()

        // Update adaptive VAD without allocating on audio thread
        var shouldEmitUI = false
        vadLock.lock()
        let age = now.timeIntervalSince(recordingStartedAt)
        if age > 0.20 { // Ignore initial 200ms mic activation transient
            let threshold = max(0.015, ambientNoiseFloorRMS * 2.5)
            if rms > threshold {
                speechHitBuffers += 1
                if speechHitBuffers >= 3 {
                    hasDetectedSpeechInSession = true
                }
                lastVoiceActivityAt = now
            } else {
                // Track slow ambient baseline during non-speech
                let clamped = min(0.025, max(0.002, rms))
                ambientNoiseFloorRMS = ambientNoiseFloorRMS * 0.92 + clamped * 0.08
            }
        }
        if now.timeIntervalSince(lastAudioUIUpdateAt) >= 0.05 { // Cap UI updates to ~20 Hz
            lastAudioUIUpdateAt = now
            shouldEmitUI = true
        }
        vadLock.unlock()

        guard shouldEmitUI else { return }

        let normalizedLevel = CGFloat(min(1.0, max(0.08, rms * 15.0)))
        var levels: [CGFloat] = []
        levels.reserveCapacity(10)
        for i in 0..<10 {
            let variance = CGFloat.random(in: -0.12...0.12)
            let bandLevel = min(1.0, max(0.08, normalizedLevel + variance * CGFloat(abs(i - 5)) * 0.15))
            levels.append(bandLevel)
        }

        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevelsUpdated?(levels)
            VoiceOSIPCSurface.shared.send(channel: "onVolumeUpdate", args: ["levels": levels, "peak": levels.max() ?? 0.0])
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let gen = currentTTSGeneration()
        let isStillQueueing = ttsLock.withLock { isProcessingTTSQueue }
        if isStillQueueing {
            playNextTTSChunk(generation: gen)
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.currentState = .idle
            self?.onStateChanged?(.idle)
        }
    }
}
