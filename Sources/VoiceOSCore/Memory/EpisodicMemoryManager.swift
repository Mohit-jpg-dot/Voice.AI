import Foundation

public enum TemporalWindow: String, Sendable, CaseIterable {
    case today
    case yesterday
    case pastWeek
    case pastMonth
    case anyTime
}

public struct EpisodicRecallResult: Sendable, Equatable {
    public let answer: String
    public let matchedCount: Int
    public let timeWindow: TemporalWindow
    public let matchedSessionIds: [String]
    public let matchedSessionTitles: [String]
    public let latestTurnSnippet: String?
    
    public init(
        answer: String,
        matchedCount: Int,
        timeWindow: TemporalWindow = .anyTime,
        matchedSessionIds: [String] = [],
        matchedSessionTitles: [String] = [],
        latestTurnSnippet: String? = nil
    ) {
        self.answer = answer
        self.matchedCount = matchedCount
        self.timeWindow = timeWindow
        self.matchedSessionIds = matchedSessionIds
        self.matchedSessionTitles = matchedSessionTitles
        self.latestTurnSnippet = latestTurnSnippet
    }
}

public final class EpisodicMemoryManager: @unchecked Sendable {
    public static let shared = EpisodicMemoryManager()
    
    private let lock = NSLock()
    
    private init() {}
    
    // MARK: - Smart Title Generation
    
    /// Generates a clean, descriptive session title from user prompt text.
    public func generateSessionTitle(from prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Conversation" }
        
        var clean = trimmed
        // Strip common voice conversational prefixes and command wrappers repeatedly
        let prefixesToStrip = [
            "can you please summarize the ", "can you please summarize ", "can you please ",
            "could you please summarize the ", "could you please summarize ", "could you please ",
            "please summarize the ", "please summarize ", "please ",
            "can you summarize the ", "can you summarize ", "can you ",
            "could you summarize the ", "could you summarize ", "could you ",
            "hey jarvis what is ", "hey jarvis what was ", "hey jarvis how to ", "hey jarvis ",
            "jarvis what is ", "jarvis how to ", "jarvis ",
            "hey friday what is ", "hey friday ", "friday ",
            "bro how to ", "bro what is ", "bro what was ", "bro ", "bhai ",
            "what is ", "what was ", "tell me about ", "how to ", "how do we ",
            "summarize the ", "summarize "
        ]
        
        var stripped = true
        while stripped {
            stripped = false
            let lower = clean.lowercased()
            for p in prefixesToStrip {
                if lower.hasPrefix(p) {
                    clean = String(clean.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    stripped = true
                    break
                }
            }
        }
        
        let words = clean.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else { return "Conversation" }
        
        let prefixWords = words.prefix(6).joined(separator: " ")
        let truncated = String(prefixWords.prefix(45)).trimmingCharacters(in: .punctuationCharacters)
        return truncated.capitalized
    }
    
    // MARK: - Temporal Scope Detection
    
    public func detectTemporalWindow(query: String) -> (window: TemporalWindow, cleanTopic: String) {
        let lower = query.lowercased()
        
        // Yesterday ("yesterday", "kal", "kal raat", "yesterday's")
        if lower.contains("yesterday") || lower.contains("kal ") || lower.hasSuffix(" kal") || lower.contains("kal humne") || lower.contains("kal kya") {
            let topic = extractTopic(from: query, removing: ["yesterday", "kal", "kal raat", "what did we do", "what did we talk about", "kya kiya", "kya baat hui"])
            return (.yesterday, topic)
        }
        
        // Today / Earlier today ("today", "earlier today", "aaj")
        if lower.contains("today") || lower.contains("earlier") || lower.contains("aaj ") || lower.hasSuffix(" aaj") {
            let topic = extractTopic(from: query, removing: ["earlier today", "today", "earlier", "aaj", "what did we do", "what did we talk about"])
            return (.today, topic)
        }
        
        // Past week ("last week", "this week", "past week", "pichle hafte")
        if lower.contains("last week") || lower.contains("past week") || lower.contains("this week") || lower.contains("pichle hafte") {
            let topic = extractTopic(from: query, removing: ["last week", "past week", "this week", "pichle hafte", "what did we do"])
            return (.pastWeek, topic)
        }
        
        // Past month
        if lower.contains("last month") || lower.contains("past month") || lower.contains("pichle mahine") {
            let topic = extractTopic(from: query, removing: ["last month", "past month", "pichle mahine"])
            return (.pastMonth, topic)
        }
        
        // General topic recall
        let topic = extractTopic(from: query, removing: [
            "what was that", "what was the", "what did we talk about", "what did we do with",
            "kya tha woh", "kya thi woh", "remember that", "tell me about the"
        ])
        return (.anyTime, topic)
    }
    
    private func extractTopic(from query: String, removing keywords: [String]) -> String {
        var lower = query.lowercased()
        for kw in keywords {
            lower = lower.replacingOccurrences(of: kw, with: "")
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet.whitespaces)
        let filtered = lower.unicodeScalars.filter { allowed.contains($0) }
        return String(filtered).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Episodic Past Conversation Query
    
    public func recallPastConversation(
        query: String,
        sessions: [ConversationSessionRecord]
    ) -> EpisodicRecallResult {
        let (window, cleanTopic) = detectTemporalWindow(query: query)
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        
        // Filter sessions by date range
        let filteredByDate: [ConversationSessionRecord]
        switch window {
        case .yesterday:
            let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
            filteredByDate = sessions.filter {
                $0.updatedAt >= startOfYesterday && $0.updatedAt < startOfToday
            }
        case .today:
            filteredByDate = sessions.filter {
                $0.updatedAt >= startOfToday
            }
        case .pastWeek:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
            filteredByDate = sessions.filter {
                $0.updatedAt >= weekAgo
            }
        case .pastMonth:
            let monthAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday)!
            filteredByDate = sessions.filter {
                $0.updatedAt >= monthAgo
            }
        case .anyTime:
            filteredByDate = sessions
        }
        
        // If specific topic keywords are provided, filter or rank by topic match
        let matchingSessions: [ConversationSessionRecord]
        if !cleanTopic.isEmpty && cleanTopic.count > 2 {
            let topicWords = cleanTopic.components(separatedBy: CharacterSet.whitespaces).filter { $0.count > 2 }
            matchingSessions = filteredByDate.filter { session in
                let titleMatch = topicWords.contains { session.title.localizedCaseInsensitiveContains($0) }
                if titleMatch { return true }
                let msgMatch = session.messages.contains { msg in
                    topicWords.contains { msg.content.localizedCaseInsensitiveContains($0) }
                }
                if msgMatch { return true }
                if let sum = session.rollingSummary {
                    return topicWords.contains { sum.localizedCaseInsensitiveContains($0) }
                }
                return false
            }
        } else {
            matchingSessions = filteredByDate
        }
        
        guard !matchingSessions.isEmpty else {
            let timeLabel = window == .yesterday ? "yesterday" : (window == .today ? "earlier today" : (window == .pastWeek ? "in the past week" : ""))
            let msg = timeLabel.isEmpty
                ? "I couldn't find any past conversations matching '\(cleanTopic)'."
                : "I couldn't find any conversations from \(timeLabel)."
            return EpisodicRecallResult(
                answer: msg,
                matchedCount: 0,
                timeWindow: window
            )
        }
        
        // Build natural language answer
        var lines: [String] = []
        let windowHeader: String
        switch window {
        case .yesterday: windowHeader = "Yesterday we discussed:"
        case .today: windowHeader = "Earlier today we discussed:"
        case .pastWeek: windowHeader = "In the past week we discussed:"
        case .pastMonth: windowHeader = "In the past month we discussed:"
        case .anyTime: windowHeader = "Here is what I found in past conversations:"
        }
        lines.append(windowHeader)
        
        for s in matchingSessions.prefix(3) {
            let summaryText = s.rollingSummary ?? s.messages.last?.content ?? s.title
            let cleanSum = summaryText.count > 140 ? String(summaryText.prefix(137)) + "..." : summaryText
            lines.append("• **\(s.title)**: \(cleanSum)")
        }
        
        let answer = lines.joined(separator: "\n")
        let ids = matchingSessions.map { $0.id }
        let titles = matchingSessions.map { $0.title }
        let latestSnippet = matchingSessions.first?.messages.last?.content
        
        return EpisodicRecallResult(
            answer: answer,
            matchedCount: matchingSessions.count,
            timeWindow: window,
            matchedSessionIds: ids,
            matchedSessionTitles: titles,
            latestTurnSnippet: latestSnippet
        )
    }
}
