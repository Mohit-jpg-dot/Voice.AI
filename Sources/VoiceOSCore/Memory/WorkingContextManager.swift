import Foundation

public struct ContextBudgetConfig: Sendable {
    public let smallLocalTokens: Int
    public let mediumLocalTokens: Int
    public let cloudTokens: Int
    
    public init(
        smallLocalTokens: Int = 1500,
        mediumLocalTokens: Int = 2500,
        cloudTokens: Int = 5000
    ) {
        self.smallLocalTokens = smallLocalTokens
        self.mediumLocalTokens = mediumLocalTokens
        self.cloudTokens = cloudTokens
    }
}

public final class WorkingContextManager: @unchecked Sendable {
    public static let shared = WorkingContextManager()
    
    private let lock = NSLock()
    private var config = ContextBudgetConfig()
    
    private init() {}
    
    public func setConfig(_ newConfig: ContextBudgetConfig) {
        lock.lock()
        defer { lock.unlock() }
        config = newConfig
    }
    
    /// Determines token budget dynamically based on the active model identifier and provider.
    public func tokenBudget(forModelIdentifier modelId: String, provider: String = "") -> Int {
        lock.lock()
        defer { lock.unlock() }
        let lower = (modelId + " " + provider).lowercased()
        
        // Cloud models have generous context windows
        if lower.contains("claude") || lower.contains("gpt") || lower.contains("gemini") || lower.contains("anthropic") || lower.contains("openai") {
            return config.cloudTokens
        }
        
        // 7B - 9B local models
        if lower.contains("7b") || lower.contains("8b") || lower.contains("9b") || lower.contains("14b") || lower.contains("qwen3.5:9b") {
            return config.mediumLocalTokens
        }
        
        // Small 1B - 3B local models (default for edge/local)
        return config.smallLocalTokens
    }
    
    /// Estimates token count using standard ~4 characters per token heuristic.
    public static func estimateTokens(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        // Fast approximation: characters / 4 with minimum 1 token per word
        let words = trimmed.split(separator: " ").count
        let charEstimate = Int(ceil(Double(trimmed.count) / 4.0))
        return max(words, charEstimate)
    }
    
    /// Summarizes an action record into a compact string instead of a raw JSON dump.
    public static func summarizeAction(_ action: ActionRecordItem) -> String {
        let summary = action.resultSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSummary = summary.count > 120 ? String(summary.prefix(117)) + "..." : summary
        let status = action.wasApproved ? "done" : "declined"
        return "[Action: `\(action.toolName)` (\(status)) -> \(cleanSummary)]"
    }
    
    /// Formats a single message turn, summarizing any actions cleanly.
    public static func formatTurn(_ message: MessageRecordItem) -> String {
        var lines: [String] = []
        let roleName = message.role.lowercased() == "user" ? "User" : "Assistant"
        lines.append("\(roleName): \(message.content)")
        if !message.actions.isEmpty {
            for act in message.actions {
                lines.append(summarizeAction(act))
            }
        }
        return lines.joined(separator: "\n")
    }
    
    /// Packs recent messages verbatim within the token budget (newest to oldest, output in chronological order).
    public func packMessages(
        _ messages: [MessageRecordItem],
        tokenBudget: Int
    ) -> (packed: [MessageRecordItem], totalTokens: Int, droppedCount: Int) {
        guard !messages.isEmpty && tokenBudget > 0 else {
            return ([], 0, messages.count)
        }
        
        var selected: [MessageRecordItem] = []
        var consumedTokens = 0
        
        // Walk backwards from newest to oldest
        for msg in messages.reversed() {
            let turnText = Self.formatTurn(msg)
            let turnTokens = Self.estimateTokens(for: turnText)
            
            if consumedTokens + turnTokens <= tokenBudget || selected.isEmpty {
                selected.append(msg)
                consumedTokens += turnTokens
            } else {
                break
            }
        }
        
        // Restore chronological order
        selected.reverse()
        let dropped = messages.count - selected.count
        return (selected, consumedTokens, dropped)
    }
    
    /// Produces the complete prompt-ready working context block within budget.
    public func buildWorkingContextText(
        messages: [MessageRecordItem],
        modelIdentifier: String,
        provider: String = ""
    ) -> (contextText: String, tokenCount: Int, droppedTurns: Int) {
        let budget = tokenBudget(forModelIdentifier: modelIdentifier, provider: provider)
        let (packed, usedTokens, dropped) = packMessages(messages, tokenBudget: budget)
        
        let turnsText = packed.map { Self.formatTurn($0) }.joined(separator: "\n\n")
        return (turnsText, usedTokens, dropped)
    }
}
