import Foundation

public struct ChatMessage: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let role: String // "user" or "assistant"
    public let text: String
    public let timestamp: Date
    public let sourceURL: String?
    public let sourceTitle: String?
    public let isScreenContext: Bool
    
    public init(
        id: String = UUID().uuidString,
        role: String,
        text: String,
        timestamp: Date = Date(),
        sourceURL: String? = nil,
        sourceTitle: String? = nil,
        isScreenContext: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.isScreenContext = isScreenContext
    }
}

public struct VoiceChatSession: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var iconName: String
    public var isPinned: Bool
    public var messages: [ChatMessage]

    public init(
        id: String = UUID().uuidString,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        iconName: String = "globe",
        isPinned: Bool = false,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.iconName = iconName
        self.isPinned = isPinned
        self.messages = messages
    }
}

/// Stores and manages persistent multi-turn conversational chat history & sessions locally.
/// Saved to ~/Library/Application Support/Voice.AI/chat_history.json and chat_sessions.json.
public final class LocalChatMemoryManager: @unchecked Sendable {
    public static let shared = LocalChatMemoryManager()
    
    private let lock = NSLock()
    private let fileManager = FileManager.default
    private var messages: [ChatMessage] = []
    private var sessions: [VoiceChatSession] = []
    private var activeSessionId: String = UUID().uuidString
    
    private var supportDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(AppBrand.appSupportFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var storageURL: URL {
        supportDirectoryURL.appendingPathComponent("chat_history.json")
    }

    private var sessionsURL: URL {
        supportDirectoryURL.appendingPathComponent("chat_sessions.json")
    }
    
    public init() {
        loadHistory()
    }
    
    public func loadHistory() {
        lock.lock()
        defer { lock.unlock() }

        if fileManager.fileExists(atPath: sessionsURL.path),
           let sData = try? Data(contentsOf: sessionsURL),
           let decodedSessions = try? JSONDecoder().decode([VoiceChatSession].self, from: sData),
           !decodedSessions.isEmpty {
            self.sessions = decodedSessions
            if let active = decodedSessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                self.activeSessionId = active.id
                self.messages = active.messages
            }
            return
        }
        
        guard fileManager.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            // Seed initial assistant greeting
            self.messages = [Self.defaultGreetingMessage()]
            return
        }
        self.messages = decoded
        if let firstUser = decoded.first(where: { $0.role == "user" }) {
            let migrated = VoiceChatSession(
                id: activeSessionId,
                title: Self.generateTitle(from: firstUser.text),
                createdAt: firstUser.timestamp,
                updatedAt: decoded.last?.timestamp ?? Date(),
                iconName: Self.inferIcon(from: firstUser.text),
                messages: decoded
            )
            self.sessions = [migrated]
        }
    }

    private static func defaultGreetingMessage() -> ChatMessage {
        ChatMessage(
            role: "assistant",
            text: "Hello! I am Voice.AI, your local macOS intelligent assistant. Ask me anything, tell me to control apps, or ask about what's on your screen."
        )
    }

    private static func generateTitle(from rawPrompt: String) -> String {
        let cleaned = rawPrompt
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !cleaned.isEmpty else { return "New Conversation" }
        let words = cleaned.split(whereSeparator: { $0.isWhitespace }).prefix(5)
        let title = words.joined(separator: " ")
        return title.count < cleaned.count ? "\(title)…" : title
    }

    private static func inferIcon(from text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("screen") || lower.contains("look") { return "display" }
        if lower.contains("weather") || lower.contains("search") || lower.contains("google") || lower.contains("tab") { return "globe" }
        if lower.contains("mail") || lower.contains("email") || lower.contains("message") || lower.contains("whatsapp") { return "envelope.fill" }
        if lower.contains("music") || lower.contains("spotify") || lower.contains("youtube") || lower.contains("song") { return "music.note" }
        if lower.contains("file") || lower.contains("folder") || lower.contains("desktop") || lower.contains("download") { return "folder.fill" }
        if lower.contains("code") || lower.contains("terminal") || lower.contains("git") || lower.contains("build") { return "terminal.fill" }
        return "globe"
    }
    
    public func allMessages() -> [ChatMessage] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }

    public func currentSessionId() -> String {
        lock.lock()
        defer { lock.unlock() }
        return activeSessionId
    }

    public func allSessions(query: String = "") -> [VoiceChatSession] {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [VoiceChatSession]
        if trimmed.isEmpty {
            filtered = sessions
        } else {
            filtered = sessions.filter { session in
                if session.title.lowercased().contains(trimmed) { return true }
                return session.messages.contains { $0.text.lowercased().contains(trimmed) }
            }
        }
        return filtered.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    @discardableResult
    public func startNewSession() -> VoiceChatSession {
        lock.lock()
        let newId = UUID().uuidString
        let greeting = Self.defaultGreetingMessage()
        self.activeSessionId = newId
        self.messages = [greeting]
        let session = VoiceChatSession(id: newId, title: "New Session", iconName: "sparkles", messages: [greeting])
        let snapshotMsgs = self.messages
        lock.unlock()
        saveSnapshot(snapshotMsgs)
        return session
    }

    @discardableResult
    public func switchToSession(id: String) -> VoiceChatSession? {
        lock.lock()
        guard let found = sessions.first(where: { $0.id == id }) else {
            lock.unlock()
            return nil
        }
        self.activeSessionId = found.id
        self.messages = found.messages
        let snapshotMsgs = self.messages
        lock.unlock()
        saveSnapshot(snapshotMsgs)
        return found
    }

    public func togglePinSession(id: String) {
        lock.lock()
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        sessions[idx].isPinned.toggle()
        let snapshot = sessions
        lock.unlock()
        saveSessionsSnapshot(snapshot)
    }

    public func deleteSession(id: String) {
        lock.lock()
        sessions.removeAll { $0.id == id }
        let wasActive = (activeSessionId == id)
        if wasActive {
            if let fallback = sessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                activeSessionId = fallback.id
                messages = fallback.messages
            } else {
                activeSessionId = UUID().uuidString
                messages = [Self.defaultGreetingMessage()]
            }
        }
        let snapshotMsgs = messages
        let snapshotSessions = sessions
        lock.unlock()
        saveSnapshot(snapshotMsgs)
        saveSessionsSnapshot(snapshotSessions)
    }
    
    public func addMessage(role: String, text: String, sourceURL: String? = nil, sourceTitle: String? = nil, isScreenContext: Bool = false) -> ChatMessage {
        lock.lock()
        let msg = ChatMessage(role: role, text: text, sourceURL: sourceURL, sourceTitle: sourceTitle, isScreenContext: isScreenContext)
        messages.append(msg)
        // Keep the latest 100 turns in active memory
        if messages.count > 100 {
            messages.removeFirst(messages.count - 100)
        }

        if let idx = sessions.firstIndex(where: { $0.id == activeSessionId }) {
            sessions[idx].messages = messages
            sessions[idx].updatedAt = Date()
            if (sessions[idx].title == "New Session" || sessions[idx].title == "New Conversation"), role == "user" {
                sessions[idx].title = Self.generateTitle(from: text)
                sessions[idx].iconName = Self.inferIcon(from: text)
            }
        } else if role == "user" || messages.contains(where: { $0.role == "user" }) {
            let firstUser = messages.first(where: { $0.role == "user" })?.text ?? text
            let created = VoiceChatSession(
                id: activeSessionId,
                title: Self.generateTitle(from: firstUser),
                createdAt: Date(),
                updatedAt: Date(),
                iconName: Self.inferIcon(from: firstUser),
                messages: messages
            )
            sessions.insert(created, at: 0)
            if sessions.count > 120 {
                sessions = Array(sessions.prefix(120))
            }
        }

        let snapshotMsgs = messages
        let snapshotSessions = sessions
        lock.unlock()
        
        saveSnapshot(snapshotMsgs)
        saveSessionsSnapshot(snapshotSessions)
        return msg
    }
    
    public func getRecentContextText(limit: Int = 8) -> String {
        lock.lock()
        defer { lock.unlock() }
        let subset = messages.suffix(limit)
        return subset.map { "\($0.role == "user" ? "User" : "Assistant"): \($0.text)" }.joined(separator: "\n")
    }
    
    public func findRelevantContext(query: String) -> String? {
        let lower = query.lowercased()
        lock.lock()
        defer { lock.unlock() }
        
        // Check for specific queries about previous conversation
        if lower.contains("previous") || lower.contains("last question") || lower.contains("earlier") || lower.contains("remember") {
            let userMsgs = messages.filter { $0.role == "user" }
            if let last = userMsgs.last {
                return "Your previous query was: \"\(last.text)\"."
            }
        }
        
        return nil
    }
    
    public func clearChat() {
        lock.lock()
        activeSessionId = UUID().uuidString
        messages = [
            ChatMessage(
                role: "assistant",
                text: "Chat history cleared. How can I assist you?"
            )
        ]
        sessions.removeAll()
        let snapshot = messages
        lock.unlock()
        saveSnapshot(snapshot)
        saveSessionsSnapshot([])
    }
    
    private func saveSnapshot(_ list: [ChatMessage]) {
        let dest = self.storageURL
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(list) {
                try? data.write(to: dest, options: .atomic)
            }
        }
    }

    private func saveSessionsSnapshot(_ list: [VoiceChatSession]) {
        let dest = self.sessionsURL
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(list) {
                try? data.write(to: dest, options: .atomic)
            }
        }
    }
}
