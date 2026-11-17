import Foundation

/// ElevenLabs Cloud Text-to-Speech Provider.
/// Enables ultra-realistic neural speech synthesis, custom voice clones, and emotional expression.
public final class ElevenLabsProvider: @unchecked Sendable {
    public static let shared = ElevenLabsProvider()
    
    private let baseURL = URL(string: "https://api.elevenlabs.io/v1")!
    private let session: URLSession
    private let cacheLock = NSLock()
    private var cachedRemoteVoices: [VoiceOption] = []
    
    public static let curatedVoices: [(id: String, name: String, desc: String)] = [
        ("21m00Tcm4TlvDq8ikWAM", "Rachel", "Calm & Natural Female"),
        ("pNInz6obpgDQGcFmaJgB", "Adam", "Deep & Expressive Male"),
        ("ErXwobaYiN019PkySvjV", "Antoni", "Crisp & Confident Male"),
        ("TxGEqnHWrfWFTfGW9XjX", "Josh", "Deep & Resonant Male"),
        ("VR6AewLTigWG4xSOukaG", "Arnold", "Theatrical & Commanding Male"),
        ("EXAVITQu4vr4xnSDxMaL", "Bella", "Warm & Expressive Female"),
        ("JBFqnCBsd6RMkjVDRZzb", "George", "Warm British Butler"),
        ("onwK4e9ZLuTAKqWW03F9", "Daniel", "Authoritative & Deep Male"),
        ("MF3mGyEYCl7XYWbV9V6O", "Elli", "Clear & Engaging Female")
    ]
    
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    public var apiKey: String {
        KeychainService.shared.get(.elevenLabsApiKey) ?? ""
    }
    
    public var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public func isElevenLabsVoiceId(_ identifier: String) -> Bool {
        if identifier.starts(with: "elevenlabs:") { return true }
        return Self.curatedVoices.contains { $0.id == identifier }
    }
    
    public func extractRawVoiceId(from identifier: String) -> String {
        if identifier.starts(with: "elevenlabs:") {
            return String(identifier.dropFirst("elevenlabs:".count))
        }
        return identifier
    }
    
    /// Returns cached remote voices or curated default ElevenLabs voices.
    public func cachedOrPreconfiguredVoices() -> [VoiceOption] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if !cachedRemoteVoices.isEmpty {
            return cachedRemoteVoices
        }
        return Self.curatedVoices.map { voice in
            VoiceOption(
                identifier: "elevenlabs:\(voice.id)",
                name: "\(voice.name) (ElevenLabs — \(voice.desc))",
                provider: "ElevenLabs",
                language: "multilingual",
                isNeural: true
            )
        }
    }
    
    /// Fetches all available voices from the user's ElevenLabs account (including custom clones).
    public func fetchRemoteVoices() async throws -> [VoiceOption] {
        guard isConfigured else {
            return cachedOrPreconfiguredVoices()
        }
        
        let url = baseURL.appendingPathComponent("voices")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 10.0
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return cachedOrPreconfiguredVoices()
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voicesArray = json["voices"] as? [[String: Any]] else {
            return cachedOrPreconfiguredVoices()
        }
        
        var options: [VoiceOption] = []
        for v in voicesArray {
            guard let voiceId = v["voice_id"] as? String,
                  let name = v["name"] as? String else { continue }
            let category = v["category"] as? String ?? "custom"
            let labelDesc = (category == "cloned" || category == "generated") ? "Clone" : "Neural"
            options.append(VoiceOption(
                identifier: "elevenlabs:\(voiceId)",
                name: "\(name) (ElevenLabs \(labelDesc))",
                provider: "ElevenLabs",
                language: "multilingual",
                isNeural: true
            ))
        }
        
        if options.isEmpty {
            return cachedOrPreconfiguredVoices()
        }
        
        cacheLock.lock()
        cachedRemoteVoices = options
        cacheLock.unlock()
        return options
    }
    
    /// Synthesizes spoken text into high-fidelity MP3 audio data.
    public func synthesizeSpeech(
        text: String,
        voiceId: String,
        modelId: String = "eleven_multilingual_v2"
    ) async throws -> Data {
        let key = apiKey
        guard !key.isEmpty else {
            throw BrainError.missingApiKey(provider: "ElevenLabs")
        }
        
        let rawId = extractRawVoiceId(from: voiceId)
        let endpoint = baseURL.appendingPathComponent("text-to-speech/\(rawId)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 18.0
        
        let body: [String: Any] = [
            "text": text,
            "model_id": modelId,
            "voice_settings": [
                "stability": 0.45,
                "similarity_boost": 0.75,
                "style": 0.15,
                "use_speaker_boost": true
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw BrainError.requestFailed(statusCode: code, message: "ElevenLabs TTS failed: \(errorText)")
        }
        
        return data
    }
}
