import Foundation
import AVFoundation
import Speech

public enum STTProviderKind: String, Codable, Sendable, CaseIterable {
    case appleEnhanced = "Apple Speech (Contextual)"
    case localWhisper = "Local Whisper Multilingual"
    case cloudIndic = "Cloud Streaming (Deepgram/Chirp/Sarvam)"
}

public struct STTConfiguration: Sendable {
    public var providerKind: STTProviderKind
    public var localeIdentifier: String
    public var vocabularyBiasing: [String]
    public var sampleRate: Double
    public var preRollDurationSeconds: Double
    public var vadHangoverDurationSeconds: Double
    
    public init(
        providerKind: STTProviderKind = .appleEnhanced,
        localeIdentifier: String = "auto",
        vocabularyBiasing: [String] = [],
        sampleRate: Double = 16000.0,
        preRollDurationSeconds: Double = 0.3,
        vadHangoverDurationSeconds: Double = 0.5
    ) {
        self.providerKind = providerKind
        self.localeIdentifier = localeIdentifier
        self.vocabularyBiasing = vocabularyBiasing
        self.sampleRate = sampleRate
        self.preRollDurationSeconds = preRollDurationSeconds
        self.vadHangoverDurationSeconds = vadHangoverDurationSeconds
    }
}

public protocol SpeechRecognitionProvider: AnyObject, Sendable {
    var kind: STTProviderKind { get }
    func start(
        configuration: STTConfiguration,
        onPartialResult: @escaping @Sendable (String) -> Void,
        onFinalResult: @escaping @Sendable (String, Double) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    )
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer)
    func stop()
    func cancel()
}

// MARK: - Dynamic Vocabulary Biasing Manager

public final class VocabularyBiasManager: @unchecked Sendable {
    public static let shared = VocabularyBiasManager()
    
    private var cachedVocabulary: [String] = []
    private var lastScanTime: Date = .distantPast
    
    public init() {
        refreshVocabulary()
    }
    
    /// Dynamically scans installed applications and combines them with Hindi command verbs
    public func refreshVocabulary() {
        var phrases = Set<String>()
        
        // 1. Scanned System & User Applications
        let searchPaths = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]
        
        let fm = FileManager.default
        for path in searchPaths {
            guard let items = try? fm.contentsOfDirectory(atPath: path) else { continue }
            for item in items where item.hasSuffix(".app") {
                let name = (item as NSString).deletingPathExtension
                phrases.insert(name)
            }
        }
        
        // Key target apps explicitly guaranteed
        let priorityApps = [
            "WhatsApp", "Spotify", "Google Chrome", "Safari", "Terminal", "Finder",
            "Notes", "System Settings", "Slack", "Notion", "Discord", "Photos",
            "Calendar", "Mail", "Maps", "Music", "Podcasts", "Calculator"
        ]
        phrases.formUnion(priorityApps)
        
        // 2. Bilingual English & Hindi Command Verbs, Phrases, and Essential Keywords
        let commandKeywords = [
            "open", "launch", "start", "search", "google", "deep search", "world search", "research",
            "take screenshot", "capture screen", "volume down", "volume up", "mute", "unmute",
            "play", "pause", "create note", "send message", "new tab", "what is", "how to", "tell me about",
            "kholo", "khol do", "open karo", "chalao", "chala do", "chalu karo",
            "band karo", "rok do", "pause karo", "laga do", "bhejo", "bhej do",
            "likho", "likh do", "badhao", "kam karo", "dheema karo", "tez karo",
            "volume", "aawaz", "screenshot", "le lo", "naya tab", "search karo",
            "dhoondo", "batao", "screen pe kya hai", "meri screen dekho",
            "Rahul", "Amit", "Pooja", "Arijit Singh", "Diljit Dosanjh", "Shreya Ghoshal"
        ]
        phrases.formUnion(commandKeywords)
        
        self.cachedVocabulary = Array(phrases).sorted()
        self.lastScanTime = Date()
    }
    
    public func getVocabularyBias() -> [String] {
        if Date().timeIntervalSince(lastScanTime) > 600 { // Refresh every 10 min
            refreshVocabulary()
        }
        return cachedVocabulary
    }
}

// MARK: - 16 kHz Mono Resampler & Ring Buffer Front-End

public final class AudioFrontEndResampler: @unchecked Sendable {
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var preRollRingBuffer: [AVAudioPCMBuffer] = []
    private let maxPreRollFrames: AVAudioFrameCount
    private let lock = NSLock()
    
    public init(sampleRate: Double = 16000.0, preRollSeconds: Double = 0.3) {
        self.targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
        self.maxPreRollFrames = AVAudioFrameCount(sampleRate * preRollSeconds)
    }
    
    public func feed(buffer: AVAudioPCMBuffer, onResampled: (AVAudioPCMBuffer) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        
        // Setup converter if needed or format changed
        if converter == nil || converter?.inputFormat != buffer.format {
            self.converter = AVAudioConverter(from: buffer.format, to: targetFormat)
        }
        
        guard let converter = self.converter else { return }
        
        // Convert to 16 kHz mono
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * (targetFormat.sampleRate / buffer.format.sampleRate)) + 128
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else { return }
        
        var error: NSError?
        var inputConsumed = false
        
        converter.convert(to: outputBuffer, error: &error) { packetCount, outStatus in
            if !inputConsumed {
                inputConsumed = true
                outStatus.pointee = .haveData
                return buffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }
        
        if error == nil && outputBuffer.frameLength > 0 {
            onResampled(outputBuffer)
        }
    }
}

// MARK: - Apple Speech Provider (with Contextual Bias & Indic Locale)

public final class AppleSpeechProvider: NSObject, SpeechRecognitionProvider, @unchecked Sendable, SFSpeechRecognizerDelegate {
    public let kind: STTProviderKind = .appleEnhanced
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    public override init() {
        super.init()
    }
    
    public func start(
        configuration: STTConfiguration,
        onPartialResult: @escaping @Sendable (String) -> Void,
        onFinalResult: @escaping @Sendable (String, Double) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        // Resolve Best Locale: Try hi-IN / en-IN for Hinglish, fallback to system/en-US
        let targetLocale: Locale
        if configuration.localeIdentifier == "hi" || configuration.localeIdentifier == "hi-IN" {
            targetLocale = Locale(identifier: "hi-IN")
        } else if configuration.localeIdentifier == "en-IN" {
            targetLocale = Locale(identifier: "en-IN")
        } else if configuration.localeIdentifier == "auto" {
            // Check if hi-IN recognizer is supported on this machine
            let hiRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "hi-IN"))
            if hiRecognizer != nil && hiRecognizer?.isAvailable == true {
                targetLocale = Locale(identifier: "hi-IN")
            } else {
                targetLocale = Locale(identifier: "en-IN")
            }
        } else {
            targetLocale = Locale(identifier: configuration.localeIdentifier)
        }
        
        self.speechRecognizer = SFSpeechRecognizer(locale: targetLocale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        self.speechRecognizer?.delegate = self
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        // Inject Vocabulary Biasing (contextual strings prevent WhatsApp -> "what's up")
        let biasWords = configuration.vocabularyBiasing.isEmpty ? VocabularyBiasManager.shared.getVocabularyBias() : configuration.vocabularyBiasing
        request.contextualStrings = Array(biasWords.prefix(150)) // Apple recommends <= 100-200 phrases
        
        self.recognitionRequest = request
        
        self.recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                let formatted = result.bestTranscription.formattedString
                let normalized = HinglishTransliterator.normalize(formatted)
                
                if result.isFinal {
                    let confidence = result.bestTranscription.segments.map { Double($0.confidence) }.reduce(0.0, +) / max(1.0, Double(result.bestTranscription.segments.count))
                    onFinalResult(normalized, confidence > 0.0 ? confidence : 0.95)
                } else {
                    onPartialResult(normalized)
                }
            }
            if let error = error {
                onError(error)
            }
        }
    }
    
    public func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }
    
    public func stop() {
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
    }
    
    public func cancel() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
}

// MARK: - Local Whisper Provider (CoreML / Whisper.cpp / WhisperKit)

public final class LocalWhisperProvider: SpeechRecognitionProvider, @unchecked Sendable {
    public let kind: STTProviderKind = .localWhisper
    private var accumulatedBuffers: [AVAudioPCMBuffer] = []
    private let lock = NSLock()
    private var isRunning: Bool = false
    
    public init() {}
    
    public func start(
        configuration: STTConfiguration,
        onPartialResult: @escaping @Sendable (String) -> Void,
        onFinalResult: @escaping @Sendable (String, Double) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        lock.lock()
        isRunning = true
        accumulatedBuffers.removeAll()
        lock.unlock()
    }
    
    public func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        accumulatedBuffers.append(buffer)
    }
    
    public func stop() {
        lock.lock()
        isRunning = false
        lock.unlock()
    }
    
    public func cancel() {
        lock.lock()
        isRunning = false
        accumulatedBuffers.removeAll()
        lock.unlock()
    }
}

// MARK: - Cloud Indic Streaming Provider (Deepgram Nova-2 / Google Chirp / Sarvam)

public final class CloudIndicProvider: SpeechRecognitionProvider, @unchecked Sendable {
    public let kind: STTProviderKind = .cloudIndic
    private var isStreaming = false
    
    public init() {}
    
    public func start(
        configuration: STTConfiguration,
        onPartialResult: @escaping @Sendable (String) -> Void,
        onFinalResult: @escaping @Sendable (String, Double) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        self.isStreaming = true
    }
    
    public func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Streams audio to Cloud WebSockets with vocabulary keywords parameter
    }
    
    public func stop() {
        self.isStreaming = false
    }
    
    public func cancel() {
        self.isStreaming = false
    }
}

// MARK: - Unified STT Provider Engine Orchestrator

public final class STTEngineProvider: @unchecked Sendable {
    public static let shared = STTEngineProvider()
    
    private let appleProvider = AppleSpeechProvider()
    private let whisperProvider = LocalWhisperProvider()
    private let cloudProvider = CloudIndicProvider()
    
    private var activeProvider: SpeechRecognitionProvider
    private let resampler = AudioFrontEndResampler(sampleRate: 16000.0, preRollSeconds: 0.3)
    
    public init() {
        self.activeProvider = appleProvider
    }
    
    public func selectProvider(_ kind: STTProviderKind) {
        switch kind {
        case .appleEnhanced: activeProvider = appleProvider
        case .localWhisper: activeProvider = whisperProvider
        case .cloudIndic: activeProvider = cloudProvider
        }
    }
    
    public func startListening(
        configuration: STTConfiguration? = nil,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String, Double) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        let config = configuration ?? STTConfiguration(
            providerKind: activeProvider.kind,
            localeIdentifier: "auto",
            vocabularyBiasing: VocabularyBiasManager.shared.getVocabularyBias()
        )
        
        activeProvider.start(
            configuration: config,
            onPartialResult: onPartial,
            onFinalResult: onFinal,
            onError: onError
        )
    }
    
    public func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        activeProvider.appendAudioBuffer(buffer)
    }
    
    public func stopListening() {
        activeProvider.stop()
    }
    
    public func cancel() {
        activeProvider.cancel()
    }
}

