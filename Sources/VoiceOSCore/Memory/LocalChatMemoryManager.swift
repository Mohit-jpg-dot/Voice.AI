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

/// Stores and manages persistent multi-turn conversational chat history locally.
/// Saved to ~/Library/Application Support/Voice.AI/chat_history.json.
public final class LocalChatMemoryManager: @unchecked Sendable {
    public static let shared = LocalChatMemoryManager()
    
    private let lock = NSLock()
    private let fileManager = FileManager.default
    private var messages: [ChatMessage] = []
    
    private var storageURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(AppBrand.appSupportFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("chat_history.json")
    }
    
    public init() {
        loadHistory()
    }
    
    public func loadHistory() {
        lock.lock()
        defer { lock.unlock() }
        
        guard fileManager.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            // Seed initial assistant greeting
            self.messages = [
                ChatMessage(
                    role: "assistant",
                    text: "Hello! I am Voice.AI, your local macOS intelligent assistant. Ask me anything, tell me to control apps, or ask about what's on your screen."
                )
            ]
            return
        }
        self.messages = decoded
    }
    
    public func allMessages() -> [ChatMessage] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
    
    public func addMessage(role: String, text: String, sourceURL: String? = nil, sourceTitle: String? = nil, isScreenContext: Bool = false) -> ChatMessage {
        lock.lock()
        let msg = ChatMessage(role: role, text: text, sourceURL: sourceURL, sourceTitle: sourceTitle, isScreenContext: isScreenContext)
        messages.append(msg)
        // Keep the latest 100 turns in active memory
        if messages.count > 100 {
            messages.removeFirst(messages.count - 100)
        }
        let snapshot = messages
        lock.unlock()
        
        saveSnapshot(snapshot)
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
        messages = [
            ChatMessage(
                role: "assistant",
                text: "Chat history cleared. How can I assist you?"
            )
        ]
        let snapshot = messages
        lock.unlock()
        saveSnapshot(snapshot)
    }
    
    private func saveSnapshot(_ list: [ChatMessage]) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            if let data = try? JSONEncoder().encode(list) {
                try? data.write(to: self.storageURL, options: .atomic)
            }
        }
    }
}
