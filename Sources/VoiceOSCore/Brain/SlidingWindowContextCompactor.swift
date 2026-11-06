import Foundation

public struct ExecutionTurnSummary: Sendable {
    public let timestamp: Date
    public let userIntent: String
    public let targetApplication: String
    public let completedActions: [String]
    
    public init(timestamp: Date = Date(), userIntent: String, targetApplication: String, completedActions: [String]) {
        self.timestamp = timestamp
        self.userIntent = userIntent
        self.targetApplication = targetApplication
        self.completedActions = completedActions
    }
}

/// Dynamic Context Compactor
/// Sliding-window memory manager that bounds LLM prompt tokens and prevents context drift.
/// Retains the N most recent detailed execution steps while automatically compressing prior
/// interactions into a single consolidated history string.
public final class SlidingWindowContextCompactor: @unchecked Sendable {
    public static let shared = SlidingWindowContextCompactor()
    
    public let windowSize: Int
    private let lock = NSLock()
    private var turns: [ExecutionTurnSummary] = []
    private var compactedHistorySummary: String = ""
    
    public init(windowSize: Int = 4) {
        self.windowSize = windowSize
    }
    
    // MARK: - Turn Recording & Compaction
    
    public func recordTurn(userIntent: String, targetApplication: String, actions: [String]) {
        lock.lock()
        defer { lock.unlock() }
        
        let turn = ExecutionTurnSummary(
            userIntent: userIntent,
            targetApplication: targetApplication,
            completedActions: actions
        )
        turns.append(turn)
        
        // When sliding window is exceeded, compact oldest turn into consolidated summary
        if turns.count > windowSize {
            let overflowTurn = turns.removeFirst()
            appendCompactedTurn(overflowTurn)
        }
    }
    
    // MARK: - Prompt Context Generation
    
    public func getCompactedPromptContext() -> String {
        lock.lock()
        defer { lock.unlock() }
        
        var parts: [String] = []
        if !compactedHistorySummary.isEmpty {
            parts.append("[Prior Context Summary]: \(compactedHistorySummary)")
        }
        
        if !turns.isEmpty {
            parts.append("[Recent Actions]:")
            for (idx, turn) in turns.enumerated() {
                let actionList = turn.completedActions.joined(separator: " -> ")
                parts.append("  \(idx + 1). [\(turn.targetApplication)] \"\(turn.userIntent)\": \(actionList)")
            }
        }
        
        return parts.joined(separator: "\n")
    }
    
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        turns.removeAll()
        compactedHistorySummary = ""
    }
    
    public var activeTurnsCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return turns.count
    }
    
    private func appendCompactedTurn(_ turn: ExecutionTurnSummary) {
        let actionSummary = turn.completedActions.prefix(2).joined(separator: ", ")
        let snippet = "\(turn.targetApplication) (\(turn.userIntent): \(actionSummary))"
        if compactedHistorySummary.isEmpty {
            compactedHistorySummary = snippet
        } else {
            compactedHistorySummary += " | " + snippet
        }
    }
}

