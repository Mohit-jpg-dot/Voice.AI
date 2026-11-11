import Foundation
import CommonCrypto
import Security

public enum MemoryScope: String, Codable, Sendable {
    case shortTerm = "short_term"
    case longTerm = "long_term"
    case userProfile = "user_profile"
}

public enum MemoryFactKind: String, Codable, Sendable {
    case turn = "turn"
    case fact = "fact"
    case preference = "preference"
    case project = "project"
    case person = "person"
    case profile = "profile"
}

public struct StructuredMemoryItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let accountId: String
    public let scope: MemoryScope
    public let kind: MemoryFactKind
    public let content: String
    public let tags: [String]
    public let embedding: [Float]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        accountId: String,
        scope: MemoryScope,
        kind: MemoryFactKind,
        content: String,
        tags: [String] = [],
        embedding: [Float] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.scope = scope
        self.kind = kind
        self.content = content
        self.tags = tags
        self.embedding = embedding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct UserMemoryProfile: Codable, Sendable, Equatable {
    public let accountId: String
    public var displayName: String
    public var preferredLanguage: String
    public var persona: String
    public var customTraits: [String: String]
    public var updatedAt: Date

    public init(
        accountId: String,
        displayName: String = "User",
        preferredLanguage: String = "en",
        persona: String = "Friday",
        customTraits: [String: String] = [:],
        updatedAt: Date = Date()
    ) {
        self.accountId = accountId
        self.displayName = displayName
        self.preferredLanguage = preferredLanguage
        self.persona = persona
        self.customTraits = customTraits
        self.updatedAt = updatedAt
    }
}

private struct EncryptedAccountMemoryPayload: Codable {
    var items: [StructuredMemoryItem]
    var profile: UserMemoryProfile
}

public protocol MemoryStoreProtocol: Sendable {
    func load(accountId: String)
    func unload()
    @discardableResult
    func remember(
        content: String,
        scope: MemoryScope,
        kind: MemoryFactKind,
        tags: [String]
    ) async -> StructuredMemoryItem
    @discardableResult
    func forget(id: String) async -> Bool
    @discardableResult
    func forget(matching query: String) async -> Int
    func searchSemantic(
        query: String,
        scope: MemoryScope?,
        limit: Int
    ) async -> [(item: StructuredMemoryItem, score: Double)]
    func shortTermContext(limit: Int) -> [StructuredMemoryItem]
    func allItems(scope: MemoryScope?) -> [StructuredMemoryItem]
    func userProfile() -> UserMemoryProfile
    func updateUserProfile(_ transform: (inout UserMemoryProfile) -> Void)
}

/// Encrypted, per-account isolated structured MemoryStore supporting short-term turns,
/// long-term facts/preferences/projects/people, and user profile with local semantic search.
public final class MemoryStore: MemoryStoreProtocol, @unchecked Sendable {
    public static let shared = MemoryStore(accountId: "local_default")

    private let lock = NSLock()
    private let embeddingProvider: LocalEmbeddingProviding
    private var activeAccountId: String = "local_default"
    private var items: [StructuredMemoryItem] = []
    private var profile: UserMemoryProfile
    private let maxShortTermTurns = 40

    public init(
        accountId: String = "local_default",
        embeddingProvider: LocalEmbeddingProviding = LocalEmbeddingProvider.shared
    ) {
        self.embeddingProvider = embeddingProvider
        self.profile = UserMemoryProfile(accountId: accountId)
        load(accountId: accountId)
    }

    public func load(accountId: String) {
        lock.lock()
        defer { lock.unlock() }

        activeAccountId = accountId
        items = []
        profile = UserMemoryProfile(accountId: accountId)

        if let plaintext = readAndDecryptLocked(for: accountId),
           let decoded = try? JSONDecoder().decode(EncryptedAccountMemoryPayload.self, from: plaintext) {
            self.items = decoded.items
            self.profile = decoded.profile
        }
    }

    public func unload() {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll()
        profile = UserMemoryProfile(accountId: activeAccountId)
    }

    @discardableResult
    public func remember(
        content: String,
        scope: MemoryScope = .longTerm,
        kind: MemoryFactKind = .fact,
        tags: [String] = []
    ) async -> StructuredMemoryItem {
        let scrubbed = SecretRedactor.redact(content).trimmingCharacters(in: .whitespacesAndNewlines)
        let vector = await embeddingProvider.embed(scrubbed)

        let entry = lock.withLock { () -> StructuredMemoryItem in
            let account = activeAccountId
            let item = StructuredMemoryItem(
                accountId: account,
                scope: scope,
                kind: kind,
                content: scrubbed,
                tags: tags.map { SecretRedactor.redact($0) },
                embedding: vector
            )
            items.insert(item, at: 0)

            if scope == .shortTerm {
                let shortCount = items.filter { $0.scope == .shortTerm }.count
                if shortCount > maxShortTermTurns {
                    var removed = 0
                    let targetRemove = shortCount - maxShortTermTurns
                    items = items.reversed().filter { existing in
                        if existing.scope == .shortTerm && removed < targetRemove {
                            removed += 1
                            return false
                        }
                        return true
                    }.reversed()
                }
            }

            persistLocked(for: account)
            return item
        }

        EventBus.shared.publish(VoiceEvent(
            kind: .memoryUpdated,
            source: "MemoryStore",
            severity: .info,
            payload: ["action": "remember", "scope": scope.rawValue, "kind": kind.rawValue]
        ))
        return entry
    }

    @discardableResult
    public func forget(id: String) async -> Bool {
        let removed = lock.withLock { () -> Bool in
            let before = items.count
            items.removeAll { $0.id == id }
            let didRemove = items.count < before
            if didRemove {
                persistLocked(for: activeAccountId)
            }
            return didRemove
        }

        if removed {
            EventBus.shared.publish(VoiceEvent(
                kind: .memoryUpdated,
                source: "MemoryStore",
                severity: .info,
                payload: ["action": "forget_id", "id": id]
            ))
        }
        return removed
    }

    @discardableResult
    public func forget(matching query: String) async -> Int {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return 0 }
        let countRemoved = lock.withLock { () -> Int in
            let before = items.count
            items.removeAll { item in
                item.content.lowercased().contains(q) ||
                item.tags.contains(where: { $0.lowercased().contains(q) })
            }
            let diff = before - items.count
            if diff > 0 {
                persistLocked(for: activeAccountId)
            }
            return diff
        }

        if countRemoved > 0 {
            EventBus.shared.publish(VoiceEvent(
                kind: .memoryUpdated,
                source: "MemoryStore",
                severity: .info,
                payload: ["action": "forget_query", "removed": "\(countRemoved)"]
            ))
        }
        return countRemoved
    }

    public func searchSemantic(
        query: String,
        scope: MemoryScope? = nil,
        limit: Int = 5
    ) async -> [(item: StructuredMemoryItem, score: Double)] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty, limit > 0 else { return [] }
        let queryVec = await embeddingProvider.embed(cleanQuery)
        let queryLower = cleanQuery.lowercased()
        let queryTokens = queryLower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        let candidates = lock.withLock {
            items.filter { scope == nil || $0.scope == scope }
        }

        var scored: [(item: StructuredMemoryItem, score: Double)] = []
        scored.reserveCapacity(candidates.count)

        for item in candidates {
            let cosine = embeddingProvider.cosineSimilarity(queryVec, item.embedding)
            let contentLower = item.content.lowercased()
            let lexicalBoost: Double
            if contentLower.contains(queryLower) {
                lexicalBoost = 0.35
            } else if !queryTokens.isEmpty {
                let hits = queryTokens.filter { contentLower.contains($0) }.count
                lexicalBoost = 0.20 * (Double(hits) / Double(queryTokens.count))
            } else {
                lexicalBoost = 0.0
            }
            let total = cosine + lexicalBoost
            if total > 0.12 {
                scored.append((item: item, score: total))
            }
        }

        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(limit))
    }

    public func shortTermContext(limit: Int = 10) -> [StructuredMemoryItem] {
        lock.lock()
        let filtered = Array(items.filter { $0.scope == .shortTerm }.prefix(max(0, limit)))
        lock.unlock()
        return filtered
    }

    public func allItems(scope: MemoryScope? = nil) -> [StructuredMemoryItem] {
        lock.lock()
        let list = items.filter { scope == nil || $0.scope == scope }
        lock.unlock()
        return list
    }

    public func userProfile() -> UserMemoryProfile {
        lock.lock()
        defer { lock.unlock() }
        return profile
    }

    public func updateUserProfile(_ transform: (inout UserMemoryProfile) -> Void) {
        lock.lock()
        transform(&profile)
        var cleanTraits: [String: String] = [:]
        for (k, v) in profile.customTraits {
            cleanTraits[k] = SecretRedactor.redact(v)
        }
        profile.customTraits = cleanTraits
        profile.updatedAt = Date()
        persistLocked(for: activeAccountId)
        lock.unlock()

        EventBus.shared.publish(VoiceEvent(
            kind: .memoryUpdated,
            source: "MemoryStore",
            severity: .info,
            payload: ["action": "profile_updated"]
        ))
    }

    public func clearAccountMemory(accountId: String? = nil) {
        lock.lock()
        let target = accountId ?? activeAccountId
        if target == activeAccountId {
            items.removeAll()
            profile = UserMemoryProfile(accountId: target)
        }
        let path = storageURL(for: target)
        try? FileManager.default.removeItem(at: path)
        lock.unlock()
    }

    // MARK: - Per-Account AES-256 Encryption at Rest (Keychain-Bound)

    private func storageURL(for accountId: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let memDir = appSupport.appendingPathComponent("Voice.AI", isDirectory: true).appendingPathComponent("Memory", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: memDir, withIntermediateDirectories: true)
            return memDir.appendingPathComponent("memory_\(sha256(accountId)).enc")
        } catch {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceAIMemory", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback.appendingPathComponent("memory_\(sha256(accountId)).enc")
        }
    }

    private func getOrCreateKey(for accountId: String) -> Data {
        let keyName = "ai.voice.app.memory.key.\(accountId)"
        if let existing = KeychainService.shared.get(keyName),
           let data = Data(base64Encoded: existing),
           data.count == 32 {
            return data
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = Data(bytes)
        KeychainService.shared.set(data.base64EncodedString(), for: keyName)
        return data
    }

    private func persistLocked(for accountId: String) {
        let payload = EncryptedAccountMemoryPayload(items: items, profile: profile)
        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        let key = getOrCreateKey(for: accountId)
        guard let cipher = aesEncrypt(data: encoded, key: key) else { return }

        let primary = storageURL(for: accountId)
        do {
            try cipher.write(to: primary, options: .atomic)
        } catch {
            let fallbackDir = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceAIMemory", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
            try? cipher.write(to: fallbackDir.appendingPathComponent("memory_\(sha256(accountId)).enc"), options: .atomic)
        }
    }

    private func readAndDecryptLocked(for accountId: String) -> Data? {
        let primary = storageURL(for: accountId)
        var cipher = try? Data(contentsOf: primary)
        if cipher == nil {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("VoiceAIMemory")
                .appendingPathComponent("memory_\(sha256(accountId)).enc")
            cipher = try? Data(contentsOf: fallback)
        }
        guard let data = cipher else { return nil }
        return aesDecrypt(data: data, key: getOrCreateKey(for: accountId))
    }

    private func aesEncrypt(data: Data, key: Data) -> Data? {
        var iv = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, iv.count, &iv)
        let ivData = Data(iv)

        var outBuffer = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        var outLength: size_t = 0
        let status = CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionPKCS7Padding),
            (key as NSData).bytes,
            kCCKeySizeAES256,
            (ivData as NSData).bytes,
            (data as NSData).bytes,
            data.count,
            &outBuffer,
            outBuffer.count,
            &outLength
        )
        guard status == kCCSuccess else { return nil }
        return ivData + Data(outBuffer.prefix(outLength))
    }

    private func aesDecrypt(data: Data, key: Data) -> Data? {
        guard data.count > 16 else { return nil }
        let ivData = Data(data.prefix(16))
        let cipherText = Data(data.suffix(from: 16))

        var outBuffer = [UInt8](repeating: 0, count: cipherText.count + kCCBlockSizeAES128)
        var outLength: size_t = 0
        let status = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionPKCS7Padding),
            (key as NSData).bytes,
            kCCKeySizeAES256,
            (ivData as NSData).bytes,
            (cipherText as NSData).bytes,
            cipherText.count,
            &outBuffer,
            outBuffer.count,
            &outLength
        )
        guard status == kCCSuccess else { return nil }
        return Data(outBuffer.prefix(outLength))
    }

    private func sha256(_ value: String) -> String {
        let data = Data(value.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

