import Foundation

public struct MemoryEntry: Codable, Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let category: String
    public let content: String
    public let tags: [String]
    
    public init(id: String = UUID().uuidString, timestamp: Date = Date(), content: String, category: String = "general", tags: [String] = []) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.content = content
        self.tags = tags
    }
}

/// Manages local persistent memory in Application Support/Voice.AI.
/// Stores structured memory in memory.json, human-readable markdown in memory.md,
/// and a compact summary in memory.summary.txt.
public final class LocalMemoryManager: @unchecked Sendable {
    public static let shared = LocalMemoryManager()
    
    private let queue = DispatchQueue(label: "ai.voice.memory", qos: .utility)
    private let fileManager = FileManager.default
    
    private var appSupportDir: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(AppBrand.appSupportFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    public var jsonFileURL: URL {
        appSupportDir.appendingPathComponent("memory.json")
    }
    
    public var markdownFileURL: URL {
        appSupportDir.appendingPathComponent("memory.md")
    }
    
    public var summaryFileURL: URL {
        appSupportDir.appendingPathComponent("memory.summary.txt")
    }
    
    private var inMemoryEntries: [MemoryEntry] = []
    
    public init() {
        loadEntries()
    }
    
    public func loadEntries() {
        queue.sync {
            guard fileManager.fileExists(atPath: jsonFileURL.path),
                  let data = try? Data(contentsOf: jsonFileURL),
                  let decoded = try? JSONDecoder().decode([MemoryEntry].self, from: data) else {
                inMemoryEntries = []
                return
            }
            inMemoryEntries = decoded
        }
    }
    
    public func remember(content: String, category: String = "preference", tags: [String] = []) {
        let entry = MemoryEntry(content: content, category: category, tags: tags)
        queue.async {
            self.inMemoryEntries.insert(entry, at: 0)
            self.persistAll()
        }
    }
    
    public func allEntries() -> [MemoryEntry] {
        queue.sync { inMemoryEntries }
    }
    
    public func search(query: String) -> [MemoryEntry] {
        let lower = query.lowercased()
        return queue.sync {
            inMemoryEntries.filter {
                $0.content.lowercased().contains(lower) ||
                $0.category.lowercased().contains(lower) ||
                $0.tags.contains { $0.lowercased().contains(lower) }
            }
        }
    }
    
    public func deleteEntry(id: String) {
        queue.async {
            self.inMemoryEntries.removeAll { $0.id == id }
            self.persistAll()
        }
    }
    
    public func clearAllMemory() {
        queue.async {
            self.inMemoryEntries.removeAll()
            try? self.fileManager.removeItem(at: self.jsonFileURL)
            try? self.fileManager.removeItem(at: self.markdownFileURL)
            try? self.fileManager.removeItem(at: self.summaryFileURL)
        }
    }
    
    public func generateGreeting(persona: String = "Friday", userName: String = "Boss") -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timePeriod: String
        if hour < 12 {
            timePeriod = "Good morning"
        } else if hour < 17 {
            timePeriod = "Good afternoon"
        } else {
            timePeriod = "Good evening"
        }
        
        switch persona.lowercased() {
        case "ultron":
            return "\(timePeriod), mortal. All systems primed. Tell me what mundane obstacle I am eliminating for you today."
        case "roast":
            return "Look who decided to show up. \(timePeriod), \(userName). Ready to procrastinate or actually accomplish something?"
        default: // Friday
            return "\(timePeriod), \(userName). All systems online. What are we building today?"
        }
    }
    
    private func persistAll() {
        // 1. JSON
        if let data = try? JSONEncoder().encode(inMemoryEntries) {
            try? data.write(to: jsonFileURL, options: .atomic)
        }
        
        // 2. Markdown
        var md = "# \(AppBrand.name) Persistent User Memory\n\nLast updated: \(Date())\n\n"
        for entry in inMemoryEntries {
            md += "### [\(entry.category.uppercased())] \(entry.timestamp)\n"
            md += "\(entry.content)\n\n"
            if !entry.tags.isEmpty {
                md += "*Tags: \(entry.tags.joined(separator: ", "))*\n\n"
            }
            md += "---\n\n"
        }
        try? md.write(to: markdownFileURL, atomically: true, encoding: .utf8)
        
        // 3. Compact Summary
        let summaryLines = inMemoryEntries.prefix(10).map { "- \($0.content)" }
        let summary = "User Memory Summary (\(inMemoryEntries.count) items total):\n" + summaryLines.joined(separator: "\n")
        try? summary.write(to: summaryFileURL, atomically: true, encoding: .utf8)
    }
}
