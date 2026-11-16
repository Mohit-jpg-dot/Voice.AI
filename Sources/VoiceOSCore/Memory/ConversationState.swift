import Foundation

public enum EntityKind: String, Codable, Sendable, CaseIterable {
    case person
    case file
    case folder
    case app
    case url
    case date
    case place
    case document
    case project
    case other
}

public struct ConversationEntity: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var kind: EntityKind
    public var salience: Double // 0.0 to 1.0, decays over turns
    public var lastMentionedAt: Date
    public var metadata: [String: String]
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: EntityKind,
        salience: Double = 1.0,
        lastMentionedAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.salience = min(1.0, max(0.0, salience))
        self.lastMentionedAt = lastMentionedAt
        self.metadata = metadata
    }
}

public struct ResultListItem: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let index: Int // 1-based index (1, 2, 3...)
    public let title: String
    public let subtitle: String?
    public let identifier: String // e.g. file path, email ID, URL
    public let kind: EntityKind
    
    public init(
        id: String = UUID().uuidString,
        index: Int,
        title: String,
        subtitle: String? = nil,
        identifier: String,
        kind: EntityKind = .file
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.subtitle = subtitle
        self.identifier = identifier
        self.kind = kind
    }
}

public struct LastActionRecord: Codable, Sendable, Equatable {
    public let toolName: String
    public let summary: String
    public let success: Bool
    public let target: String?
    public let timestamp: Date
    
    public init(
        toolName: String,
        summary: String,
        success: Bool,
        target: String? = nil,
        timestamp: Date = Date()
    ) {
        self.toolName = toolName
        self.summary = summary
        self.success = success
        self.target = target
        self.timestamp = timestamp
    }
}

public struct ConversationStateRecord: Codable, Sendable, Equatable {
    public var sessionId: String
    public var currentTopic: String?
    public var entities: [ConversationEntity]
    public var lastResultList: [ResultListItem]
    public var lastAction: LastActionRecord?
    public var pendingDrafts: [String: String] // e.g. ["email": "...", "message": "..."]
    public var frontmostApp: String?
    public var frontmostWindow: String?
    public var lastScreenSummary: String? // Short summary, never raw pixels
    public var turnCount: Int
    public var updatedAt: Date
    
    public init(
        sessionId: String,
        currentTopic: String? = nil,
        entities: [ConversationEntity] = [],
        lastResultList: [ResultListItem] = [],
        lastAction: LastActionRecord? = nil,
        pendingDrafts: [String: String] = [:],
        frontmostApp: String? = nil,
        frontmostWindow: String? = nil,
        lastScreenSummary: String? = nil,
        turnCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.currentTopic = currentTopic
        self.entities = entities
        self.lastResultList = lastResultList
        self.lastAction = lastAction
        self.pendingDrafts = pendingDrafts
        self.frontmostApp = frontmostApp
        self.frontmostWindow = frontmostWindow
        self.lastScreenSummary = lastScreenSummary
        self.turnCount = turnCount
        self.updatedAt = updatedAt
    }
    
    /// Applies salience decay to existing entities and removes those that faded below threshold.
    public mutating func decaySalience(decayFactor: Double = 0.85, pruneThreshold: Double = 0.15) {
        turnCount += 1
        for i in 0..<entities.count {
            entities[i].salience *= decayFactor
        }
        entities.removeAll { $0.salience < pruneThreshold }
        updatedAt = Date()
    }
    
    /// Mentions or refreshes an entity with peak salience (1.0).
    public mutating func mentionEntity(name: String, kind: EntityKind, metadata: [String: String] = [:]) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if let idx = entities.firstIndex(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame && $0.kind == kind }) {
            entities[idx].salience = 1.0
            entities[idx].lastMentionedAt = Date()
            for (k, v) in metadata {
                entities[idx].metadata[k] = v
            }
        } else {
            let entity = ConversationEntity(name: clean, kind: kind, salience: 1.0, lastMentionedAt: Date(), metadata: metadata)
            entities.insert(entity, at: 0)
        }
        // Keep at most 25 salient entities
        if entities.count > 25 {
            entities.removeLast(entities.count - 25)
        }
        updatedAt = Date()
    }
    
    /// Updates the active result list with 1-based indexing.
    public mutating func setResultList(_ items: [(title: String, subtitle: String?, identifier: String, kind: EntityKind)]) {
        var list: [ResultListItem] = []
        for (idx, item) in items.enumerated() {
            let entry = ResultListItem(
                index: idx + 1,
                title: item.title,
                subtitle: item.subtitle,
                identifier: item.identifier,
                kind: item.kind
            )
            list.append(entry)
            // Also register as an entity with high salience
            mentionEntity(name: item.title, kind: item.kind, metadata: ["identifier": item.identifier, "listIndex": "\(idx + 1)"])
        }
        self.lastResultList = list
        self.updatedAt = Date()
    }
    
    /// Finds a result list item by 1-based index.
    public func itemAtIndex(_ index: Int) -> ResultListItem? {
        return lastResultList.first { $0.index == index }
    }
    
    /// Finds the most salient entity matching a kind.
    public func mostSalientEntity(matching kind: EntityKind? = nil) -> ConversationEntity? {
        let sorted = entities.sorted {
            if abs($0.salience - $1.salience) > 0.05 {
                return $0.salience > $1.salience
            }
            return $0.lastMentionedAt > $1.lastMentionedAt
        }
        if let k = kind {
            return sorted.first { $0.kind == k }
        }
        return sorted.first
    }
}

/// Thread-safe manager for the active conversation state.
public final class ConversationStateManager: @unchecked Sendable {
    public static let shared = ConversationStateManager()
    
    private let lock = NSLock()
    private var states: [String: ConversationStateRecord] = [:]
    private var activeSessionId: String = "default_session"
    
    private init() {}
    
    public func setActiveSession(id: String) {
        lock.lock()
        defer { lock.unlock() }
        activeSessionId = id
        if states[id] == nil {
            states[id] = ConversationStateRecord(sessionId: id)
        }
    }
    
    public func currentState(for sessionId: String? = nil) -> ConversationStateRecord {
        lock.lock()
        defer { lock.unlock() }
        let sid = sessionId ?? activeSessionId
        if let existing = states[sid] {
            return existing
        }
        let fresh = ConversationStateRecord(sessionId: sid)
        states[sid] = fresh
        return fresh
    }
    
    public func updateState(for sessionId: String? = nil, _ transform: (inout ConversationStateRecord) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        let sid = sessionId ?? activeSessionId
        var state = states[sid] ?? ConversationStateRecord(sessionId: sid)
        transform(&state)
        states[sid] = state
    }
    
    public func recordTurnEnd(for sessionId: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let sid = sessionId ?? activeSessionId
        if var state = states[sid] {
            state.decaySalience()
            states[sid] = state
        }
    }
    
    public func clear(for sessionId: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let sid = sessionId ?? activeSessionId
        states.removeValue(forKey: sid)
    }
    
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        states.removeAll()
    }
}
