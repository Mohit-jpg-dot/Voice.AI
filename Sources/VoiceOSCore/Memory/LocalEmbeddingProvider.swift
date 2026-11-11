import Foundation

public protocol LocalEmbeddingProviding: Sendable {
    func embed(_ text: String) async -> [Float]
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double
}

/// On-device semantic embedding generator:
/// Uses deterministic local feature-hashed n-gram vectors by default (zero network, instant offline),
/// and can optionally query a local Ollama embedding endpoint when enabled and running on localhost.
public final class LocalEmbeddingProvider: LocalEmbeddingProviding, @unchecked Sendable {
    public static let shared = LocalEmbeddingProvider()

    public let dimensions: Int = 128
    public var allowLocalOllamaEmbeddings: Bool = false
    public var ollamaEmbeddingModel: String = "nomic-embed-text"

    public init() {}

    public func embed(_ text: String) async -> [Float] {
        if allowLocalOllamaEmbeddings,
           OllamaProvider.shared.hostURL.host == "localhost" || OllamaProvider.shared.hostURL.host == "127.0.0.1",
           let ollamaVec = await queryLocalOllamaEmbedding(text) {
            return ollamaVec
        }
        return deterministicLocalVector(for: text)
    }

    public func deterministicLocalVector(for text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: dimensions)
        let normalized = HinglishTransliterator.normalize(text).lowercased()
        let tokens = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return vector }

        for token in tokens {
            let h = stableHash(token)
            let idx = Int(h % UInt64(dimensions))
            let sign: Float = ((h >> 8) & 1) == 0 ? 1.0 : -1.0
            vector[idx] += sign * 2.0

            // Character trigrams provide partial / morphological robustness across typos and Hinglish stems
            let chars = Array(token)
            if chars.count >= 3 {
                for i in 0...(chars.count - 3) {
                    let trigram = String(chars[i..<(i + 3)])
                    let th = stableHash("tri:" + trigram)
                    let tIdx = Int(th % UInt64(dimensions))
                    let tSign: Float = ((th >> 8) & 1) == 0 ? 1.0 : -1.0
                    vector[tIdx] += tSign * 0.75
                }
            }
        }

        // L2 normalize so dot product == cosine similarity
        var normSq: Float = 0
        for v in vector { normSq += v * v }
        let norm = sqrt(normSq)
        if norm > 0 {
            for i in 0..<dimensions {
                vector[i] /= norm
            }
        }
        return vector
    }

    public func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        var dot: Double = 0
        var normA: Double = 0
        var normB: Double = 0
        for i in 0..<count {
            let av = Double(a[i])
            let bv = Double(b[i])
            dot += av * bv
            normA += av * av
            normB += bv * bv
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? (dot / denom) : 0
    }

    private func stableHash(_ text: String) -> UInt64 {
        // FNV-1a 64-bit hash — stable across runs & platforms (unlike Swift Hasher which seeds randomly per process)
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash
    }

    private func queryLocalOllamaEmbedding(_ text: String) async -> [Float]? {
        let url = OllamaProvider.shared.hostURL.appendingPathComponent("api/embeddings")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 2.0
        guard let body = try? JSONSerialization.data(withJSONObject: [
            "model": ollamaEmbeddingModel,
            "prompt": text
        ]) else { return nil }
        req.httpBody = body

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let floats = json["embedding"] as? [Double], !floats.isEmpty else {
            return nil
        }
        return floats.map { Float($0) }
    }
}

