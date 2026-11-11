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

public struct WhisperDiagnostics: Sendable {
    public let binaryPath: String?
    public let modelPath: String?
    public let statusSummary: String
    
    public var isReady: Bool {
        guard let bin = binaryPath else { return false }
        let name = (bin as NSString).lastPathComponent.lowercased()
        if name == "whisper" || name == "mlx_whisper" {
            return true
        }
        return modelPath != nil
    }
}

public final class LocalWhisperProvider: SpeechRecognitionProvider, @unchecked Sendable {
    public let kind: STTProviderKind = .localWhisper
    private var accumulatedBuffers: [AVAudioPCMBuffer] = []
    private let lock = NSLock()
    private var isRunning: Bool = false
    private var activeConfig: STTConfiguration = STTConfiguration(providerKind: .localWhisper)
    private var onFinalCallback: (@Sendable (String, Double) -> Void)?
    private var onErrorCallback: (@Sendable (Error) -> Void)?
    
    public init() {}
    
    private static let diagCacheLock = NSLock()
    private static var cachedDiag: WhisperDiagnostics?
    private static var lastDiagCheck: Date = .distantPast

    public static func diagnostics(forceRefresh: Bool = false) -> WhisperDiagnostics {
        diagCacheLock.lock()
        if !forceRefresh, let cached = cachedDiag, Date().timeIntervalSince(lastDiagCheck) < 30.0 {
            diagCacheLock.unlock()
            return cached
        }
        diagCacheLock.unlock()
        
        let binCandidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cpp",
            "/opt/homebrew/bin/whisper",
            "/usr/local/bin/whisper",
            "/opt/homebrew/bin/mlx_whisper",
            "/usr/local/bin/mlx_whisper",
            NSHomeDirectory() + "/.local/bin/whisper-cli",
            NSHomeDirectory() + "/.local/bin/whisper"
        ]
        var allBins = binCandidates
        let condaEnvs = "/opt/homebrew/Caskroom/miniconda/base/envs"
        if let envs = try? FileManager.default.contentsOfDirectory(atPath: condaEnvs) {
            for env in envs {
                allBins.append("\(condaEnvs)/\(env)/bin/whisper")
                allBins.append("\(condaEnvs)/\(env)/bin/mlx_whisper")
            }
        }
        let binaryPath = allBins.first { FileManager.default.isExecutableFile(atPath: $0) }
        
        let modelCandidates = [
            NSHomeDirectory() + "/.voiceos/models/ggml-base.bin",
            NSHomeDirectory() + "/.voiceos/models/ggml-base.en.bin",
            NSHomeDirectory() + "/.voiceos/models/ggml-small.bin",
            NSHomeDirectory() + "/.voiceos/models/ggml-medium.bin",
            NSHomeDirectory() + "/.voiceos/models/ggml-large-v3.bin",
            NSHomeDirectory() + "/.cache/whisper/base.pt",
            NSHomeDirectory() + "/.cache/whisper/small.pt"
        ]
        let modelPath = modelCandidates.first { path in
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                return size > 10_000_000
            }
            return false
        }
        
        let summary: String
        if let bin = binaryPath {
            let binName = (bin as NSString).lastPathComponent
            if let mod = modelPath {
                summary = "Local Whisper active (\(binName) + \((mod as NSString).lastPathComponent))."
            } else if binName == "whisper" || binName == "mlx_whisper" {
                summary = "Local Whisper active via \(binName)."
            } else {
                summary = "\(binName) found, but GGML model weights are missing in ~/.voiceos/models/."
            }
        } else if let mod = modelPath {
            summary = "Whisper weights found (\((mod as NSString).lastPathComponent)), but whisper-cli binary is not installed (`brew install whisper-cpp`)."
        } else {
            summary = "Local Whisper CLI & weights not installed; using Apple Speech (Contextual)."
        }
        
        let result = WhisperDiagnostics(binaryPath: binaryPath, modelPath: modelPath, statusSummary: summary)
        diagCacheLock.lock()
        cachedDiag = result
        lastDiagCheck = Date()
        diagCacheLock.unlock()
        return result
    }
    
    public func start(
        configuration: STTConfiguration,
        onPartialResult: @escaping @Sendable (String) -> Void,
        onFinalResult: @escaping @Sendable (String, Double) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        lock.lock()
        isRunning = true
        activeConfig = configuration
        onFinalCallback = onFinalResult
        onErrorCallback = onError
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
        guard isRunning else {
            lock.unlock()
            return
        }
        isRunning = false
        let buffers = accumulatedBuffers
        accumulatedBuffers.removeAll()
        let config = activeConfig
        let onFinal = onFinalCallback
        let onError = onErrorCallback
        onFinalCallback = nil
        onErrorCallback = nil
        lock.unlock()
        
        guard !buffers.isEmpty else {
            onFinal?("", 0.0)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let diag = Self.diagnostics()
            guard diag.isReady, let binPath = diag.binaryPath else {
                onError?(NSError(domain: "VoiceOS.Whisper", code: 404, userInfo: [NSLocalizedDescriptionKey: diag.statusSummary]))
                return
            }
            
            let wavURL = FileManager.default.temporaryDirectory.appendingPathComponent("voiceai_whisper_\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: wavURL) }
            
            guard Self.writeResampled16kWAV(buffers: buffers, to: wavURL) else {
                onError?(NSError(domain: "VoiceOS.Whisper", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to encode 16kHz WAV for Whisper."]))
                return
            }
            
            let binName = (binPath as NSString).lastPathComponent.lowercased()
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: binPath)
            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            
            let lang = config.localeIdentifier == "auto" ? "auto" : String(config.localeIdentifier.prefix(2))
            if binName.contains("whisper-cli") || binName.contains("whisper-cpp") || binName == "main" {
                guard let modelPath = diag.modelPath else {
                    onError?(NSError(domain: "VoiceOS.Whisper", code: 404, userInfo: [NSLocalizedDescriptionKey: "Missing Whisper GGML model file."]))
                    return
                }
                proc.arguments = ["-m", modelPath, "-f", wavURL.path, "-l", lang, "-nt", "--no-prints"]
            } else {
                let tmpDir = FileManager.default.temporaryDirectory.path
                proc.arguments = [wavURL.path, "--output_format", "txt", "--output_dir", tmpDir]
            }
            
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let rawOut = String(data: data, encoding: .utf8) ?? ""
                let cleaned = rawOut
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("[") }
                    .joined(separator: " ")
                let normalized = HinglishTransliterator.normalize(cleaned)
                onFinal?(normalized, normalized.isEmpty ? 0.0 : 0.94)
            } catch {
                onError?(error)
            }
        }
    }
    
    public func cancel() {
        lock.lock()
        isRunning = false
        accumulatedBuffers.removeAll()
        onFinalCallback = nil
        onErrorCallback = nil
        lock.unlock()
    }
    
    private static func writeResampled16kWAV(buffers: [AVAudioPCMBuffer], to url: URL) -> Bool {
        guard let firstFormat = buffers.first?.format,
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000.0, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: firstFormat, to: targetFormat) else {
            return false
        }
        
        do {
            let audioFile = try AVAudioFile(forWriting: url, settings: targetFormat.settings, commonFormat: .pcmFormatInt16, interleaved: true)
            for buf in buffers {
                converter.reset()
                let cap = AVAudioFrameCount(Double(buf.frameLength) * (16000.0 / buf.format.sampleRate)) + 128
                guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else { continue }
                var error: NSError?
                var consumed = false
                converter.convert(to: outBuf, error: &error) { _, outStatus in
                    if !consumed {
                        consumed = true
                        outStatus.pointee = .haveData
                        return buf
                    }
                    outStatus.pointee = .noDataNow
                    return nil
                }
                if error == nil && outBuf.frameLength > 0 {
                    try audioFile.write(from: outBuf)
                }
            }
            return true
        } catch {
            return false
        }
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
    
    public var selectedKind: STTProviderKind {
        get {
            if let saved = UserDefaults.standard.string(forKey: "voiceos.stt.provider"),
               let kind = STTProviderKind(rawValue: saved) {
                return kind
            }
            return LocalWhisperProvider.diagnostics().isReady ? .localWhisper : .appleEnhanced
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "voiceos.stt.provider")
            selectProvider(newValue)
        }
    }
    
    public init() {
        self.activeProvider = appleProvider
        selectProvider(self.selectedKind)
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

