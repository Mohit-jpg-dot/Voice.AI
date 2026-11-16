import Foundation

public enum TaskLedgerStatus: String, Codable, Sendable, CaseIterable {
    case requested = "requested"
    case inProgress = "in_progress"
    case waitingForApproval = "waiting_for_approval"
    case succeeded = "succeeded"
    case failed = "failed"
    case cancelled = "cancelled"
}

public struct TaskLedgerEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let sessionId: String
    public let requestText: String // Original user utterance/request
    public var plan: String // Executable plan or tool intention
    public var status: TaskLedgerStatus
    public var evidence: String? // Verified execution proof (exit code, created file, message ID, verification check)
    public let createdAt: Date
    public var updatedAt: Date
    public var expiresAt: Date?
    
    public init(
        id: String = UUID().uuidString,
        sessionId: String,
        requestText: String,
        plan: String,
        status: TaskLedgerStatus = .requested,
        evidence: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        expiresAt: Date? = Date().addingTimeInterval(3600) // Default 1 hour task expiration
    ) {
        self.id = id
        self.sessionId = sessionId
        self.requestText = requestText
        self.plan = plan
        self.status = status
        self.evidence = evidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
    }
    
    public var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return Date() > exp
    }
    
    /// Returns an honest prompt-ready string separating request from verified outcome.
    public func promptDescription() -> String {
        var lines: [String] = []
        lines.append("- Task [\(status.rawValue)]: User requested: \"\(requestText)\"")
        if !plan.isEmpty {
            lines.append("  Plan: \(plan)")
        }
        switch status {
        case .succeeded:
            if let ev = evidence, !ev.isEmpty {
                lines.append("  Verified outcome: SUCCESS. Evidence: \(ev)")
            } else {
                lines.append("  Verified outcome: SUCCESS.")
            }
        case .failed:
            if let ev = evidence, !ev.isEmpty {
                lines.append("  Verified outcome: FAILED. Evidence: \(ev)")
            } else {
                lines.append("  Verified outcome: FAILED.")
            }
        case .waitingForApproval:
            lines.append("  Status: WAITING FOR USER APPROVAL. Action has NOT been executed yet.")
        case .inProgress:
            lines.append("  Status: IN PROGRESS. Action is currently executing; not verified yet.")
        case .requested:
            lines.append("  Status: REQUESTED. Action has not started.")
        case .cancelled:
            lines.append("  Status: CANCELLED by user or safety policy.")
        }
        return lines.joined(separator: "\n")
    }
}

/// Central task ledger ensuring actions are separated from claims and verified by tools.
public final class TaskLedger: @unchecked Sendable {
    public static let shared = TaskLedger()
    
    private let lock = NSLock()
    private var tasks: [TaskLedgerEntry] = []
    
    private init() {}
    
    @discardableResult
    public func recordRequested(sessionId: String, requestText: String, plan: String) -> TaskLedgerEntry {
        lock.lock()
        defer { lock.unlock() }
        let entry = TaskLedgerEntry(
            sessionId: sessionId,
            requestText: requestText.trimmingCharacters(in: .whitespacesAndNewlines),
            plan: plan.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .requested
        )
        tasks.append(entry)
        pruneExpiredLocked()
        return entry
    }
    
    public func updatePlan(taskId: String, plan: String) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[idx].plan = plan
            tasks[idx].updatedAt = Date()
        }
    }
    
    /// Written ONLY by tool executor or verification checks, never by model claims!
    @discardableResult
    public func recordStatus(taskId: String, status: TaskLedgerStatus, evidence: String? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else {
            return false
        }
        tasks[idx].status = status
        if let ev = evidence {
            tasks[idx].evidence = ev
        }
        tasks[idx].updatedAt = Date()
        // If finished, set expiration to 30 minutes from completion
        if status == .succeeded || status == .failed || status == .cancelled {
            tasks[idx].expiresAt = Date().addingTimeInterval(1800)
        }
        return true
    }
    
    public func activeTasks(forSession sessionId: String) -> [TaskLedgerEntry] {
        lock.lock()
        defer { lock.unlock() }
        pruneExpiredLocked()
        return tasks.filter {
            $0.sessionId == sessionId &&
            ($0.status == .requested || $0.status == .inProgress || $0.status == .waitingForApproval)
        }
    }
    
    public func recentTasks(forSession sessionId: String, limit: Int = 5) -> [TaskLedgerEntry] {
        lock.lock()
        defer { lock.unlock() }
        pruneExpiredLocked()
        let matching = tasks.filter { $0.sessionId == sessionId }
        return Array(matching.suffix(limit))
    }
    
    public func lastCompletedTask(forSession sessionId: String) -> TaskLedgerEntry? {
        lock.lock()
        defer { lock.unlock() }
        return tasks.last { $0.sessionId == sessionId && ($0.status == .succeeded || $0.status == .failed) }
    }
    
    public func formatLedgerForPrompt(forSession sessionId: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        pruneExpiredLocked()
        let sessionTasks = tasks.filter { $0.sessionId == sessionId }
        guard !sessionTasks.isEmpty else { return "" }
        
        let formatted = sessionTasks.suffix(4).map { $0.promptDescription() }.joined(separator: "\n")
        return """
        Active & Recent Tasks (Truthful Execution Ledger):
        \(formatted)
        Note: Model must never claim an action succeeded unless verified evidence is recorded above.
        """
    }
    
    public func clear(forSession sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        tasks.removeAll { $0.sessionId == sessionId }
    }
    
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        tasks.removeAll()
    }
    
    private func pruneExpiredLocked() {
        let now = Date()
        tasks.removeAll { task in
            if let exp = task.expiresAt, now > exp {
                return true
            }
            return false
        }
    }
}
