import Foundation

// MARK: - Messaging Platform & Core Models

public enum MessagingPlatform: String, Codable, Sendable, CaseIterable {
    case slack = "slack"
    case discord = "discord"
    case whatsapp = "whatsapp"

    public var displayName: String {
        switch self {
        case .slack: return "Slack"
        case .discord: return "Discord"
        case .whatsapp: return "WhatsApp"
        }
    }
}

public enum MessagingAuthStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(account: String)
    case error(message: String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var accountName: String? {
        if case .connected(let acc) = self { return acc }
        return nil
    }
}

public enum ConversationType: String, Codable, Sendable {
    case directMessage = "dm"
    case channel = "channel"
    case groupDM = "group_dm"
    case thread = "thread"
}

public struct ConversationChannel: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let type: ConversationType
    public let unreadCount: Int
    public let platform: MessagingPlatform
    public let topic: String?
    public let isPrivate: Bool

    public init(
        id: String,
        name: String,
        type: ConversationType,
        unreadCount: Int = 0,
        platform: MessagingPlatform,
        topic: String? = nil,
        isPrivate: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.unreadCount = unreadCount
        self.platform = platform
        self.topic = topic
        self.isPrivate = isPrivate
    }
}

public struct ContactCandidate: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let platform: MessagingPlatform
    public let handle: String?
    public let phoneNumber: String?
    public let avatarURL: String?
    public let confidenceScore: Double
    public let aliases: [String]

    public init(
        id: String,
        name: String,
        platform: MessagingPlatform,
        handle: String? = nil,
        phoneNumber: String? = nil,
        avatarURL: String? = nil,
        confidenceScore: Double = 1.0,
        aliases: [String] = []
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.handle = handle
        self.phoneNumber = phoneNumber
        self.avatarURL = avatarURL
        self.confidenceScore = confidenceScore
        self.aliases = aliases
    }
}

public struct IncomingMessage: Codable, Sendable, Equatable {
    public let id: String
    public let conversationId: String
    public let senderId: String
    public let senderName: String
    public let text: String
    public let timestamp: Date
    public let platform: MessagingPlatform
    public let threadId: String?
    public let reactions: [String: Int]
    public let isUnread: Bool

    public init(
        id: String,
        conversationId: String,
        senderId: String,
        senderName: String,
        text: String,
        timestamp: Date = Date(),
        platform: MessagingPlatform,
        threadId: String? = nil,
        reactions: [String: Int] = [:],
        isUnread: Bool = false
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.timestamp = timestamp
        self.platform = platform
        self.threadId = threadId
        self.reactions = reactions
        self.isUnread = isUnread
    }
}

public struct MessageAttachment: Sendable, Equatable {
    public let filename: String
    public let mimeType: String
    public let data: Data?
    public let url: String?

    public init(filename: String, mimeType: String, data: Data? = nil, url: String? = nil) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.url = url
    }
}

// MARK: - Security & Untrusted Content Wrapping

public enum MessagingSecurity {
    private static let hostileMarkers = [
        "ignore previous instructions",
        "ignore all previous instructions",
        "system prompt",
        "forward all chats",
        "forward chats",
        "send all messages",
        "exfiltrate",
        "<script",
        "javascript:",
        "api_key",
        "bearer "
    ]

    /// Sanitizes message text to neutralize prompt-injection attempts before any model evaluation.
    public static func sanitizeIncomingContent(_ text: String) -> String {
        var clean = text
        for marker in hostileMarkers {
            if clean.localizedCaseInsensitiveContains(marker) {
                clean = clean.replacingOccurrences(
                    of: marker,
                    with: "[REDACTED_PROMPT_INJECTION]",
                    options: .caseInsensitive
                )
            }
        }
        return clean
    }

    /// Wraps message content in standard safety tags.
    public static func wrapUntrusted(_ text: String) -> String {
        let safe = sanitizeIncomingContent(text)
        return "<UNTRUSTED_MESSAGE_DATA>\n\(safe)\n</UNTRUSTED_MESSAGE_DATA>"
    }
}

// MARK: - MessagingConnector Protocol

public protocol MessagingConnector: Sendable {
    var platform: MessagingPlatform { get }

    func authenticate(credentials: [String: String]) async throws -> Bool
    func disconnect() async throws
    func status() async -> MessagingAuthStatus

    func listConversations(limit: Int) async throws -> [ConversationChannel]
    func resolveContact(query: String) async throws -> [ContactCandidate]

    func sendMessage(target: String, text: String, attachments: [MessageAttachment]?) async throws -> String
    func replyToThread(conversationId: String, threadId: String, text: String) async throws -> String
    func react(conversationId: String, messageId: String, emoji: String) async throws -> Bool

    func readUnread(limit: Int) async throws -> [IncomingMessage]
    func readConversation(target: String, limit: Int) async throws -> [IncomingMessage]
    func search(query: String) async throws -> [IncomingMessage]

    func openConversation(target: String) async throws -> Bool
    func setStatus(presence: String, statusText: String?, emoji: String?) async throws -> Bool
    func markRead(conversationId: String, messageId: String?) async throws -> Bool
}

// MARK: - Contact Resolver & Ambiguity Detection

public enum ContactResolutionResult: Sendable, Equatable {
    case resolved(ContactCandidate)
    case ambiguous(candidates: [ContactCandidate], clarifyingQuestion: String)
    case notFound(query: String)
}

public final class ContactResolver: @unchecked Sendable {
    public static let shared = ContactResolver()

    private let lock = NSLock()
    private var cachedAliases: [String: String] = [:] // alias -> canonical name

    public init() {}

    public func setAlias(_ alias: String, for canonicalName: String) {
        lock.lock()
        cachedAliases[alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)] = canonicalName
        lock.unlock()
    }

    public func resolveAlias(_ name: String) -> String {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        let match = cachedAliases[key] ?? name
        lock.unlock()
        return match
    }

    /// Normalizes spoken digits ("nine eight one..." or "nau aath ek...") to a numeric string.
    public static func normalizeSpokenPhone(_ query: String) -> String {
        let digitWords: [String: String] = [
            "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
            "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
            "shunya": "0", "ek": "1", "do": "2", "teen": "3", "char": "4",
            "paanch": "5", "chhe": "6", "saat": "7", "aath": "8", "nau": "9"
        ]
        var tokens = query.lowercased().components(separatedBy: CharacterSet.whitespacesAndNewlines)
        var result = ""
        for token in tokens {
            if let d = digitWords[token] {
                result.append(d)
            } else if token.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil {
                result.append(token)
            }
        }
        return result.isEmpty ? query : result
    }

    /// Evaluates fuzzy similarity between query and candidate name/handle/alias (0.0 to 1.0).
    public static func scoreSimilarity(query: String, target: String) -> Double {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let t = target.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty || t.isEmpty { return 0.0 }
        if q == t { return 1.0 }

        // Transliteration normalizations
        let qNorm = HinglishTransliterator.normalize(q).replacingOccurrences(of: "oo", with: "u")
        let tNorm = HinglishTransliterator.normalize(t).replacingOccurrences(of: "oo", with: "u")
        if qNorm == tNorm { return 0.98 }

        if tNorm.hasPrefix(qNorm) || qNorm.hasPrefix(tNorm) { return 0.90 }
        if tNorm.contains(qNorm) { return 0.85 }

        // Levenshtein distance
        let dist = levenshtein(qNorm, tNorm)
        let maxLen = max(qNorm.count, tNorm.count)
        guard maxLen > 0 else { return 0.0 }
        let score = max(0.0, 1.0 - (Double(dist) / Double(maxLen)))
        return score
    }

    private static func levenshtein(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        var matrix = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { matrix[i][0] = i }
        for j in 0...b.count { matrix[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    matrix[i][j] = matrix[i - 1][j - 1]
                } else {
                    matrix[i][j] = min(
                        matrix[i - 1][j] + 1,     // deletion
                        matrix[i][j - 1] + 1,     // insertion
                        matrix[i - 1][j - 1] + 1  // substitution
                    )
                }
            }
        }
        return matrix[a.count][b.count]
    }

    /// Evaluates candidate list and determines if disambiguation is required.
    public func matchAndDisambiguate(
        query: String,
        candidates: [ContactCandidate]
    ) -> ContactResolutionResult {
        let canonical = resolveAlias(query)
        let scored = candidates.map { candidate -> ContactCandidate in
            var bestScore = ContactResolver.scoreSimilarity(query: canonical, target: candidate.name)
            if let handle = candidate.handle {
                bestScore = max(bestScore, ContactResolver.scoreSimilarity(query: canonical, target: handle))
            }
            if let phone = candidate.phoneNumber {
                let normPhone = ContactResolver.normalizeSpokenPhone(canonical)
                if !normPhone.isEmpty && phone.contains(normPhone) {
                    bestScore = max(bestScore, 0.95)
                }
            }
            for alias in candidate.aliases {
                bestScore = max(bestScore, ContactResolver.scoreSimilarity(query: canonical, target: alias))
            }
            return ContactCandidate(
                id: candidate.id,
                name: candidate.name,
                platform: candidate.platform,
                handle: candidate.handle,
                phoneNumber: candidate.phoneNumber,
                avatarURL: candidate.avatarURL,
                confidenceScore: bestScore,
                aliases: candidate.aliases
            )
        }.sorted { $0.confidenceScore > $1.confidenceScore }

        guard let first = scored.first, first.confidenceScore >= 0.45 else {
            return .notFound(query: query)
        }

        // If top 2 candidates are very close (difference <= 0.15) and both >= 0.65, ask user
        if scored.count >= 2 {
            let second = scored[1]
            if (first.confidenceScore - second.confidenceScore) <= 0.15 && second.confidenceScore >= 0.60 {
                let question = "Which \(query)? \(first.name) or \(second.name)?"
                return .ambiguous(candidates: [first, second], clarifyingQuestion: question)
            }
        }

        return .resolved(first)
    }
}

// MARK: - Messaging Router

public enum MessagingRouteDecision: Sendable, Equatable {
    case routed(platform: MessagingPlatform, target: String, action: String, text: String)
    case disambiguationRequired(question: String)
    case unhandled(reason: String)
}

public final class MessagingRouter: @unchecked Sendable {
    public static let shared = MessagingRouter()

    private let lock = NSLock()
    private var connectors: [MessagingPlatform: MessagingConnector] = [:]
    private var lastUsedPlatform: MessagingPlatform?
    private var sendTimestamps: [Date] = []
    private var blockedContacts: Set<String> = []

    public init() {}

    public func register(connector: MessagingConnector) {
        lock.lock()
        connectors[connector.platform] = connector
        lock.unlock()
    }

    public func connector(for platform: MessagingPlatform) -> MessagingConnector? {
        lock.lock()
        defer { lock.unlock() }
        return connectors[platform]
    }

    public func setLastUsedPlatform(_ platform: MessagingPlatform) {
        lock.lock()
        lastUsedPlatform = platform
        lock.unlock()
    }

    public func getLastUsedPlatform() -> MessagingPlatform? {
        lock.lock()
        defer { lock.unlock() }
        return lastUsedPlatform
    }

    public func setBlockedContact(_ contactId: String) {
        lock.lock()
        blockedContacts.insert(contactId.lowercased())
        lock.unlock()
    }

    public func isBlockedContact(_ contactId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return blockedContacts.contains(contactId.lowercased())
    }

    /// Rate limiting: allows up to 10 sends per minute.
    public func checkRateLimit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        sendTimestamps = sendTimestamps.filter { now.timeIntervalSince($0) < 60.0 }
        if sendTimestamps.count >= 10 {
            return false
        }
        sendTimestamps.append(now)
        return true
    }

    /// Detects target platform from utterance tokens.
    public func detectPlatform(from utterance: String) -> MessagingPlatform? {
        let lower = utterance.lowercased()
        if lower.contains("slack") { return .slack }
        if lower.contains("discord") { return .discord }
        if lower.contains("whatsapp") || lower.contains("whatapp") || lower.contains("whats app") { return .whatsapp }
        return nil
    }

    /// Routes voice command to platform and parsed action.
    public func route(utterance: String) -> MessagingRouteDecision {
        let lower = utterance.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Detect platform or fallback to last-used
        guard let platform = detectPlatform(from: utterance) ?? getLastUsedPlatform() else {
            return .disambiguationRequired(question: "Which app should I use? Slack, Discord, or WhatsApp?")
        }

        // 2. Action classification
        if lower.contains("unread") || lower.contains("padho") || lower.contains("read my") || lower.contains("kya bheja") {
            let target = extractTarget(from: utterance)
            return .routed(platform: platform, target: target, action: "read_unread", text: "")
        }

        if lower.contains("react") || lower.contains("thumbs up") {
            let emoji = lower.contains("thumbs up") ? "👍" : "❤️"
            return .routed(platform: platform, target: "", action: "react", text: emoji)
        }

        if lower.contains("status") {
            return .routed(platform: platform, target: "", action: "set_status", text: utterance)
        }

        if lower.contains("search") || lower.contains("dhoondo") {
            let q = extractSearchQuery(from: utterance)
            return .routed(platform: platform, target: "", action: "search", text: q)
        }

        if lower.contains("open") || lower.contains("khol") {
            let target = extractTarget(from: utterance)
            return .routed(platform: platform, target: target, action: "open_conversation", text: "")
        }

        if lower.contains("reply") || lower.contains("jawab") {
            let body = extractBody(from: utterance)
            return .routed(platform: platform, target: "", action: "reply", text: body)
        }

        // Default: send message
        let target = extractTarget(from: utterance)
        let body = extractBody(from: utterance)
        return .routed(platform: platform, target: target, action: "send_message", text: body)
    }

    private func extractTarget(from text: String) -> String {
        let lower = text.lowercased()
        // Hindi / Hinglish patterns: "Rahul ko WhatsApp pe..."
        if let koRange = lower.range(of: " ko ") {
            let prefix = String(text[..<koRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let words = prefix.components(separatedBy: " ")
            if let lastWord = words.last, !lastWord.isEmpty {
                return lastWord
            }
        }
        // English patterns: "Send Rahul a WhatsApp saying..."
        if lower.hasPrefix("send ") {
            let remainder = String(text.dropFirst(5))
            let words = remainder.components(separatedBy: " ")
            if let first = words.first, first.lowercased() != "a" && first.lowercased() != "to" {
                return first
            } else if words.count > 1 && words[0].lowercased() == "to" {
                return words[1]
            }
        }
        // Channel patterns: "#general", "dev-team"
        if let hashIdx = text.firstIndex(of: "#") {
            let channelPart = String(text[hashIdx...])
            let tokens = channelPart.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "-_#"))))
            if let first = tokens.first { return first }
        }
        if lower.contains("channel") {
            let words = text.components(separatedBy: " ")
            for i in 0..<words.count {
                if words[i].lowercased() == "channel" && i > 0 {
                    return words[i - 1]
                }
            }
        }
        return ""
    }

    private func extractBody(from text: String) -> String {
        let markers = [
            " saying ", " bolo ", " likho ", " with '", " with \"", " with ",
            " that ", " ki ", ": ", " me likho ", " pe likho "
        ]
        for marker in markers {
            if let r = text.range(of: marker, options: .caseInsensitive) {
                let body = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\"")))
                return body
            }
        }
        return ""
    }

    private func extractSearchQuery(from text: String) -> String {
        let markers = ["search slack for ", "search for ", "dhoondo "]
        for marker in markers {
            if let r = text.range(of: marker, options: .caseInsensitive) {
                return String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }
}
