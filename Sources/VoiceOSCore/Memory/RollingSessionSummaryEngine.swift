import Foundation

public struct StructuredSessionSummary: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let conversationId: String
    public let turnStartId: String?
    public let turnEndId: String?
    public let summaryText: String
    public let keyDecisions: [String]
    public let openQuestions: [String]
    public let entitiesMentioned: [String]
    public let numbersAndDates: [String]
    public let createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        conversationId: String,
        turnStartId: String? = nil,
        turnEndId: String? = nil,
        summaryText: String,
        keyDecisions: [String] = [],
        openQuestions: [String] = [],
        entitiesMentioned: [String] = [],
        numbersAndDates: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.turnStartId = turnStartId
        self.turnEndId = turnEndId
        self.summaryText = summaryText
        self.keyDecisions = keyDecisions
        self.openQuestions = openQuestions
        self.entitiesMentioned = entitiesMentioned
        self.numbersAndDates = numbersAndDates
        self.createdAt = createdAt
    }
    
    /// Formats the summary into a concise prompt-ready block.
    public func promptFormatted() -> String {
        var lines: [String] = []
        lines.append("Session Summary: \(summaryText)")
        if !keyDecisions.isEmpty {
            lines.append("Decisions: " + keyDecisions.joined(separator: "; "))
        }
        if !openQuestions.isEmpty {
            lines.append("Open Questions: " + openQuestions.joined(separator: "; "))
        }
        if !numbersAndDates.isEmpty {
            lines.append("Numbers & Dates: " + numbersAndDates.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

public final class RollingSessionSummaryEngine: @unchecked Sendable {
    public static let shared = RollingSessionSummaryEngine()
    
    private let lock = NSLock()
    private var cachedSummaries: [String: StructuredSessionSummary] = [:]
    
    private init() {}
    
    /// Checks if a session requires an updated rolling summary.
    public func shouldSummarize(turnCount: Int, lastSummarizedTurn: Int) -> Bool {
        // Trigger summary every 5 turns when turn count exceeds 5
        return turnCount >= 5 && (turnCount - lastSummarizedTurn >= 4)
    }
    
    /// Generates a structured rolling summary, falling back deterministically when offline.
    public func generateSummary(
        for messages: [MessageRecordItem],
        conversationId: String
    ) -> StructuredSessionSummary {
        guard !messages.isEmpty else {
            return StructuredSessionSummary(
                conversationId: conversationId,
                summaryText: "Empty session."
            )
        }
        
        // Deterministic extraction pipeline
        return deterministicSummary(for: messages, conversationId: conversationId)
    }
    
    /// Deterministic fallback extractor keeping names, decisions, open questions, and numbers.
    public func deterministicSummary(
        for messages: [MessageRecordItem],
        conversationId: String
    ) -> StructuredSessionSummary {
        var decisions: [String] = []
        var questions: [String] = []
        var entities: Set<String> = []
        var numbersDates: Set<String> = []
        var topics: [String] = []
        
        let decisionKeywords = [
            "decided", "agreed", "chose", "selected", "will use", "planned to",
            "tay kiya", "faisla kiya", "finalized"
        ]
        
        let numberRegex = try? NSRegularExpression(pattern: #"(?:\$\d+(?:\.\d+)?|\b\d+(?:\.\d+)?%?|\b\d{1,2}:\d{2}\b|\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{1,2}\b)"#, options: .caseInsensitive)
        
        for msg in messages {
            let text = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let lower = text.lowercased()
            
            // Extract decisions
            for kw in decisionKeywords where lower.contains(kw) {
                let sentence = text.components(separatedBy: CharacterSet(charactersIn: ".!\n")).first {
                    $0.lowercased().contains(kw)
                }
                if let s = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    if !decisions.contains(s) && decisions.count < 4 {
                        decisions.append(s)
                    }
                }
            }
            
            // Extract open questions from user turns
            if msg.role.lowercased() == "user" {
                if text.hasSuffix("?") || lower.hasPrefix("how ") || lower.hasPrefix("what ") || lower.hasPrefix("why ") || lower.hasPrefix("kya ") || lower.hasPrefix("kaise ") {
                    if questions.count < 3 && !questions.contains(text) {
                        questions.append(text)
                    }
                } else if topics.count < 3 {
                    // Extract core topic phrases
                    let firstSentence = text.components(separatedBy: CharacterSet(charactersIn: ".?\n")).first ?? text
                    if firstSentence.count > 5 {
                        topics.append(String(firstSentence.prefix(60)))
                    }
                }
            }
            
            // Extract numbers & dates
            if let regex = numberRegex {
                let nsText = text as NSString
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
                for match in matches.prefix(5) {
                    let numStr = nsText.substring(with: match.range)
                    numbersDates.insert(numStr)
                }
            }
            
            // Extract actions executed
            for act in msg.actions {
                entities.insert(act.toolName)
            }
        }
        
        // Assemble narrative summary
        var narrativeParts: [String] = []
        if !topics.isEmpty {
            narrativeParts.append("Discussed: " + topics.prefix(3).joined(separator: ", "))
        }
        if !decisions.isEmpty {
            narrativeParts.append("Decisions: " + decisions.prefix(2).joined(separator: "; "))
        }
        if !questions.isEmpty {
            narrativeParts.append("Key Questions: " + questions.prefix(2).joined(separator: "; "))
        }
        
        let summaryText = narrativeParts.isEmpty ? "Conversation with \(messages.count) turns." : narrativeParts.joined(separator: " | ")
        
        let startId = messages.first?.id
        let endId = messages.last?.id
        
        let record = StructuredSessionSummary(
            conversationId: conversationId,
            turnStartId: startId,
            turnEndId: endId,
            summaryText: summaryText,
            keyDecisions: decisions,
            openQuestions: questions,
            entitiesMentioned: Array(entities),
            numbersAndDates: Array(numbersDates)
        )
        
        lock.lock()
        cachedSummaries[conversationId] = record
        lock.unlock()
        
        return record
    }
    
    public func getCachedSummary(for conversationId: String) -> StructuredSessionSummary? {
        lock.lock()
        defer { lock.unlock() }
        return cachedSummaries[conversationId]
    }
}
