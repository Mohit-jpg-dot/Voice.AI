import Foundation
import NaturalLanguage

public protocol LocalEmbeddingProviding: Sendable {
    func embed(_ text: String) async -> [Float]
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double
    var activeMethodName: String { get }
}

public enum EmbeddingMethod: String, Sendable, CaseIterable {
    case appleNaturalLanguage = "Apple NaturalLanguage (On-Device)"
    case localOllama = "Local Ollama (nomic-embed-text)"
    case deterministicHash = "Deterministic Feature Hash (FNV-1a)"
}

/// On-device semantic embedding generator:
/// Priority Ladder:
/// 1. Apple NaturalLanguage sentence embeddings (NLEmbedding) on-device (zero network, Apple Silicon accelerated)
/// 2. Local Ollama embedding model (nomic-embed-text) when enabled and reachable on localhost
/// 3. Deterministic 128-dim FNV-1a hash vector as the robust offline fallback.
public final class LocalEmbeddingProvider: LocalEmbeddingProviding, @unchecked Sendable {
    public static let shared = LocalEmbeddingProvider()

    public let dimensions: Int = 128
    public var allowLocalOllamaEmbeddings: Bool = false
    public var ollamaEmbeddingModel: String = "nomic-embed-text"
    
    // Cached sentence embedding model from NaturalLanguage
    private let appleSentenceEmbedding: NLEmbedding? = {
        return NLEmbedding.sentenceEmbedding(for: .english)
    }()

    public init() {}
    
    public var activeMethod: EmbeddingMethod {
        if appleSentenceEmbedding != nil {
            return .appleNaturalLanguage
        } else if allowLocalOllamaEmbeddings {
            return .localOllama
        } else {
            return .deterministicHash
        }
    }
    
    public var activeMethodName: String {
        return activeMethod.rawValue
    }

    public func embed(_ text: String) async -> [Float] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return [Float](repeating: 0, count: dimensions)
        }
        
        // 1. Apple NaturalLanguage Sentence Embedding (Primary)
        if let nl = appleSentenceEmbedding,
           let vector = nl.vector(for: clean) {
            let floatVec = vector.map { Float($0) }
            return floatVec
        }
        
        // 2. Local Ollama (Secondary fallback)
        if allowLocalOllamaEmbeddings,
           OllamaProvider.shared.hostURL.host == "localhost" || OllamaProvider.shared.hostURL.host == "127.0.0.1",
           let ollamaVec = await queryLocalOllamaEmbedding(clean) {
            return ollamaVec
        }
        
        // 3. Deterministic Feature Hash (Tertiary fallback)
        return deterministicLocalVector(for: clean)
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

            // Character trigrams provide morphological robustness
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
        req.timeoutInterval = 4.0

        let body: [String: Any] = [
            "model": ollamaEmbeddingModel,
            "prompt": text
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = data

        do {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            if let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
               let emb = json["embedding"] as? [Double] {
                return emb.map { Float($0) }
            }
        } catch {
            return nil
        }
        return nil
    }
}
