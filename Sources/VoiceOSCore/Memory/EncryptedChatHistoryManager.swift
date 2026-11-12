import Foundation
import CommonCrypto
import Security

public struct ActionRecordItem: Codable, Identifiable, Sendable {
    public let id: String
    public let toolName: String
    public let argumentsJSON: String
    public let resultSummary: String
    public let durationSeconds: Double
    public let wasApproved: Bool
    public let executedAt: Date
    
    public init(
        id: String = UUID().uuidString,
        toolName: String,
        argumentsJSON: String,
        resultSummary: String,
        durationSeconds: Double = 0.1,
        wasApproved: Bool = true,
        executedAt: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.resultSummary = resultSummary
        self.durationSeconds = durationSeconds
        self.wasApproved = wasApproved
        self.executedAt = executedAt
    }
}

public struct MessageRecordItem: Codable, Identifiable, Sendable {
    public let id: String
    public let role: String // "user", "assistant", "system"
    public let content: String // Secrets redacted before persistence
    public let originalLanguage: String // e.g. "hi", "en", "hinglish"
    public let timestamp: Date
    public let actions: [ActionRecordItem]
    public let citedSources: [String]
    
    public init(
        id: String = UUID().uuidString,
        role: String,
        content: String,
        originalLanguage: String = "en",
        timestamp: Date = Date(),
        actions: [ActionRecordItem] = [],
        citedSources: [String] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.originalLanguage = originalLanguage
        self.timestamp = timestamp
        self.actions = actions
        self.citedSources = citedSources
    }
}

public struct ConversationSessionRecord: Codable, Identifiable, Sendable {
    public let id: String
    public let accountId: String
    public var title: String
    public let persona: String
    public var isPinned: Bool
    public let createdAt: Date
    public var updatedAt: Date
    public var messages: [MessageRecordItem]
    
    public init(
        id: String = UUID().uuidString,
        accountId: String,
        title: String = "New Conversation",
        persona: String = "Friday",
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [MessageRecordItem] = []
    ) {
        self.id = id
        self.accountId = accountId
        self.title = title
        self.persona = persona
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

public enum HistoryRetentionPolicy: String, CaseIterable, Codable, Sendable {
    case forever = "Forever"
    case days90 = "90 Days"
    case days30 = "30 Days"
    case never = "Don't Save (Incognito)"
}

/// Encrypted-at-rest, per-account isolated chat history store for Voice.AI.
/// Encrypts conversation logs with AES-256 bound to the user's account ID in Keychain.
/// Zero cross-account leakage; scrubs secrets before writing to disk.
public final class EncryptedChatHistoryManager: @unchecked Sendable {
    public static let shared = EncryptedChatHistoryManager()
    
    private let lock = NSLock()
    private var inMemorySessions: [ConversationSessionRecord] = []
    private var loadedAccountId: String? = nil
    private let retentionKey = "voiceos.history.retention_policy"
    private let incognitoKey = "voiceos.history.incognito_active"
    
    public var isIncognito: Bool {
        get { UserDefaults.standard.bool(forKey: incognitoKey) }
        set { UserDefaults.standard.set(newValue, forKey: incognitoKey) }
    }
    
    public var retentionPolicy: HistoryRetentionPolicy {
        get {
            let saved = UserDefaults.standard.string(forKey: retentionKey) ?? HistoryRetentionPolicy.forever.rawValue
            return HistoryRetentionPolicy(rawValue: saved) ?? .forever
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: retentionKey)
            applyRetentionPurge()
        }
    }
    
    private init() {}
    
    // MARK: - Account Scoping & Session Loading
    
    public func loadForAccount(accountId: String) {
        lock.lock()
        defer { lock.unlock() }
        
        if loadedAccountId == accountId { return }
        
        inMemorySessions.removeAll()
        loadedAccountId = accountId
        
        guard let decryptedData = readAndDecryptHistoryFile(for: accountId),
              let sessions = try? JSONDecoder().decode([ConversationSessionRecord].self, from: decryptedData) else {
            return
        }
        
        self.inMemorySessions = sessions
        applyRetentionPurgeLocked()
    }
    
    public func unloadCurrentAccount() {
        lock.lock()
        defer { lock.unlock() }
        inMemorySessions.removeAll()
        loadedAccountId = nil
    }
    
    // MARK: - Query & Search
    
    public func listConversations(query: String = "") -> [ConversationSessionRecord] {
        lock.lock()
        defer { lock.unlock() }
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [ConversationSessionRecord]
        if trimmed.isEmpty {
            filtered = inMemorySessions
        } else {
            filtered = inMemorySessions.filter { session in
                if session.title.lowercased().contains(trimmed) { return true }
                return session.messages.contains { $0.content.lowercased().contains(trimmed) }
            }
        }
        
        return filtered.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            return $0.updatedAt > $1.updatedAt
        }
    }
    
    public func getConversation(id: String) -> ConversationSessionRecord? {
        lock.lock()
        defer { lock.unlock() }
        return inMemorySessions.first(where: { $0.id == id })
    }
    
    // MARK: - Mutating Conversations
    
    @discardableResult
    public func recordTurn(
        conversationId: String?,
        userText: String,
        assistantText: String,
        persona: String = "Friday",
        actions: [ActionRecordItem] = [],
        sources: [String] = [],
        timestamp: Date = Date()
    ) -> ConversationSessionRecord? {
        if isIncognito || retentionPolicy == .never { return nil }
        
        let accountId = AccountAuthService.shared.currentAccount?.id ?? "local"
        
        lock.lock()
        defer { lock.unlock() }
        
        if loadedAccountId != accountId {
            lock.unlock()
            loadForAccount(accountId: accountId)
            lock.lock()
        }
        
        // Redact any leaked secrets before disk persistence
        let safeUser = redactSecrets(userText)
        let safeAssistant = redactSecrets(assistantText)
        
        let userMessage = MessageRecordItem(role: "user", content: safeUser, timestamp: timestamp)
        let assistantMessage = MessageRecordItem(
            role: "assistant",
            content: safeAssistant,
            timestamp: timestamp,
            actions: actions,
            citedSources: sources
        )
        
        let targetId = conversationId ?? UUID().uuidString
        var session: ConversationSessionRecord
        
        if let idx = inMemorySessions.firstIndex(where: { $0.id == targetId }) {
            session = inMemorySessions[idx]
            session.messages.append(userMessage)
            session.messages.append(assistantMessage)
            session.updatedAt = timestamp
            inMemorySessions[idx] = session
        } else {
            // Auto-title from first prompt
            let generatedTitle = generateTitle(from: safeUser)
            session = ConversationSessionRecord(
                id: targetId,
                accountId: accountId,
                title: generatedTitle,
                persona: persona,
                createdAt: timestamp,
                updatedAt: timestamp,
                messages: [userMessage, assistantMessage]
            )
            inMemorySessions.insert(session, at: 0)
        }
        
        persistEncryptedHistoryLocked(for: accountId)
        return session
    }
    
    public func renameConversation(id: String, newTitle: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = inMemorySessions.firstIndex(where: { $0.id == id }) else { return }
        inMemorySessions[idx].title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        inMemorySessions[idx].updatedAt = Date()
        if let accId = loadedAccountId { persistEncryptedHistoryLocked(for: accId) }
    }
    
    public func togglePin(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = inMemorySessions.firstIndex(where: { $0.id == id }) else { return }
        inMemorySessions[idx].isPinned.toggle()
        if let accId = loadedAccountId { persistEncryptedHistoryLocked(for: accId) }
    }
    
    public func deleteConversation(id: String) {
        lock.lock()
        defer { lock.unlock() }
        inMemorySessions.removeAll(where: { $0.id == id })
        if let accId = loadedAccountId { persistEncryptedHistoryLocked(for: accId) }
    }
    
    public func clearAllHistory() {
        lock.lock()
        defer { lock.unlock() }
        inMemorySessions.removeAll()
        let accId = loadedAccountId ?? (AccountAuthService.shared.currentAccount?.id ?? "local")
        loadedAccountId = accId
        persistEncryptedHistoryLocked(for: accId)
    }
    
    // MARK: - Exporting (Markdown / JSON)
    
    public func exportConversationMarkdown(id: String) -> String? {
        guard let conv = getConversation(id: id) else { return nil }
        var md = "# \(conv.title)\n\n"
        md += "*Created: \(conv.createdAt) | Persona: \(conv.persona)*\n\n---\n\n"
        
        for msg in conv.messages {
            let roleHeader = msg.role == "user" ? "### You" : "### Voice.AI (\(conv.persona))"
            md += "\(roleHeader) (\(msg.timestamp.formatted()))\n\n\(msg.content)\n\n"
            if !msg.actions.isEmpty {
                md += "**Actions Executed:**\n"
                for act in msg.actions {
                    md += "- `\(act.toolName)`: \(act.resultSummary) (\(act.durationSeconds)s)\n"
                }
                md += "\n"
            }
            if !msg.citedSources.isEmpty {
                md += "**Sources:**\n"
                for s in msg.citedSources {
                    md += "- \(s)\n"
                }
                md += "\n"
            }
        }
        return md
    }
    
    // MARK: - Redaction Engine
    
    public func redactSecrets(_ text: String) -> String {
        return SecretRedactor.redact(text)
    }
    
    private func generateTitle(from prompt: String) -> String {
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "Conversation" }
        let words = clean.components(separatedBy: .whitespaces)
        let prefix = words.prefix(6).joined(separator: " ")
        return prefix.prefix(45).capitalized
    }
    
    // MARK: - Retention Purge
    
    private func applyRetentionPurge() {
        lock.lock()
        defer { lock.unlock() }
        applyRetentionPurgeLocked()
    }
    
    private func applyRetentionPurgeLocked() {
        let now = Date()
        switch retentionPolicy {
        case .forever:
            break
        case .days90:
            let cutoff = now.addingTimeInterval(-3600 * 24 * 90)
            inMemorySessions.removeAll(where: { $0.updatedAt < cutoff })
        case .days30:
            let cutoff = now.addingTimeInterval(-3600 * 24 * 30)
            inMemorySessions.removeAll(where: { $0.updatedAt < cutoff })
        case .never:
            inMemorySessions.removeAll()
        }
        if let accId = loadedAccountId { persistEncryptedHistoryLocked(for: accId) }
    }
    
    // MARK: - AES-256 Encryption at Rest
    
    private func getHistoryFilePath(for accountId: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDir = appSupport.appendingPathComponent("Voice.AI", isDirectory: true).appendingPathComponent("History", isDirectory: true)
        let dir: URL
        do {
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            dir = baseDir
        } catch {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceAIHistory", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            dir = fallback
        }
        
        // Hash accountId for file name
        let hash = sha256(accountId)
        return dir.appendingPathComponent("history_\(hash).enc")
    }
    
    private func getOrCreateEncryptionKey(for accountId: String) -> Data {
        let keyName = "ai.voice.app.history.key.\(accountId)"
        if let existingB64 = KeychainService.shared.get(keyName), let data = Data(base64Encoded: existingB64) {
            return data
        }
        
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let keyData = Data(bytes)
        KeychainService.shared.set(keyData.base64EncodedString(), for: keyName)
        return keyData
    }
    
    private func persistEncryptedHistoryLocked(for accountId: String) {
        guard let jsonData = try? JSONEncoder().encode(inMemorySessions) else { return }
        let key = getOrCreateEncryptionKey(for: accountId)
        
        guard let encrypted = aesEncrypt(data: jsonData, key: key) else { return }
        let primaryPath = getHistoryFilePath(for: accountId)
        do {
            try encrypted.write(to: primaryPath, options: .atomic)
        } catch {
            let fallbackDir = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceAIHistory", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
            let hash = sha256(accountId)
            let fallbackPath = fallbackDir.appendingPathComponent("history_\(hash).enc")
            try? encrypted.write(to: fallbackPath, options: .atomic)
        }
    }
    
    private func readAndDecryptHistoryFile(for accountId: String) -> Data? {
        let primaryPath = getHistoryFilePath(for: accountId)
        var encrypted = try? Data(contentsOf: primaryPath)
        if encrypted == nil {
            let hash = sha256(accountId)
            let fallbackPath = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceAIHistory/history_\(hash).enc")
            encrypted = try? Data(contentsOf: fallbackPath)
        }
        guard let data = encrypted else { return nil }
        let key = getOrCreateEncryptionKey(for: accountId)
        return aesDecrypt(data: data, key: key)
    }
    
    private func aesEncrypt(data: Data, key: Data) -> Data? {
        var iv = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, iv.count, &iv)
        let ivData = Data(iv)
        
        var outBuffer = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        var numBytesEncrypted: size_t = 0
        
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
            &numBytesEncrypted
        )
        
        guard status == kCCSuccess else { return nil }
        return ivData + Data(outBuffer.prefix(numBytesEncrypted))
    }
    
    private func aesDecrypt(data: Data, key: Data) -> Data? {
        guard data.count > 16 else { return nil }
        let ivData = Data(data.prefix(16))
        let cipherTextData = Data(data.suffix(from: 16))
        
        var outBuffer = [UInt8](repeating: 0, count: cipherTextData.count + kCCBlockSizeAES128)
        var numBytesDecrypted: size_t = 0
        
        let status = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionPKCS7Padding),
            (key as NSData).bytes,
            kCCKeySizeAES256,
            (ivData as NSData).bytes,
            (cipherTextData as NSData).bytes,
            cipherTextData.count,
            &outBuffer,
            outBuffer.count,
            &numBytesDecrypted
        )
        
        guard status == kCCSuccess else { return nil }
        return Data(outBuffer.prefix(numBytesDecrypted))
    }
    
    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Hex Extension

extension Data {
    init?(hex: String) {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        var data = Data(capacity: clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2, limitedBy: clean.endIndex) ?? clean.endIndex
            guard let b = UInt8(clean[index..<nextIndex], radix: 16) else { return nil }
            data.append(b)
            index = nextIndex
        }
        self = data
    }
    
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
