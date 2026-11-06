import Foundation

public enum CodingAgentState: Sendable, Equatable {
    case running(currentStep: String, progress: Double)
    case waitingForInput(question: String, options: [String])
    case completed(summary: String)
    case failed(error: String)
    
    public var label: String {
        switch self {
        case .running: return "Active"
        case .waitingForInput: return "Needs Input"
        case .completed: return "Done"
        case .failed: return "Failed"
        }
    }
}

public struct CodingAgentTask: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let role: String
    public var state: CodingAgentState
    public var tasksPerformed: [String]
    public let startedAt: Date
    public var userResponse: String?
    
    public init(
        id: UUID = UUID(),
        name: String,
        role: String,
        state: CodingAgentState,
        tasksPerformed: [String] = [],
        startedAt: Date = Date(),
        userResponse: String? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.state = state
        self.tasksPerformed = tasksPerformed
        self.startedAt = startedAt
        self.userResponse = userResponse
    }
    
    public var isWaitingForInput: Bool {
        if case .waitingForInput = state { return true }
        return false
    }
    
    public var elapsedFormatted: String {
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// Central manager for active coding subagents, background workflows, and interactive user prompts.
public final class CodingAgentManager: @unchecked Sendable {
    public static let shared = CodingAgentManager()
    
    public var onAgentsChanged: (@Sendable ([CodingAgentTask]) -> Void)?
    
    private let lock = NSLock()
    private var _agents: [CodingAgentTask] = []
    
    public var activeAgents: [CodingAgentTask] {
        lock.lock()
        defer { lock.unlock() }
        return _agents
    }
    
    public var pendingInputCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _agents.filter { $0.isWaitingForInput }.count
    }
    
    public init() {
        seedInitialAgents()
    }
    
    private func seedInitialAgents() {
        let agent1 = CodingAgentTask(
            id: UUID(),
            name: "Architecture Agent",
            role: "Senior macOS Lead",
            state: .running(currentStep: "Compiling native Swift packages & optimizing layout...", progress: 0.85),
            tasksPerformed: [
                "Scanned project dependencies and SPM targets",
                "Built universal dynamic libraries for arm64",
                "Verified 84 unit test cases across all suites"
            ],
            startedAt: Date().addingTimeInterval(-180)
        )
        
        let agent2 = CodingAgentTask(
            id: UUID(),
            name: "Blender Tutor Subagent",
            role: "3D Animation Specialist",
            state: .waitingForInput(
                question: "Do you want me to automatically insert keyframes on the armature bone?",
                options: ["Approve Keyframes", "Manual Step", "Cancel"]
            ),
            tasksPerformed: [
                "Analyzed Blender viewport and identified 3D cursor position",
                "Selected Armature object in scene collection",
                "Switched viewport mode to Pose Mode"
            ],
            startedAt: Date().addingTimeInterval(-95)
        )
        
        let agent3 = CodingAgentTask(
            id: UUID(),
            name: "Refactor Subagent",
            role: "Code Quality & Cleanup",
            state: .completed(summary: "Cleaned duplicate DMG installers and consolidated test suites."),
            tasksPerformed: [
                "Removed 4 duplicate installation files",
                "Unified test runner under scripts/run-tests.sh"
            ],
            startedAt: Date().addingTimeInterval(-320)
        )
        
        self._agents = [agent1, agent2, agent3]
    }
    
    public func registerAgent(name: String, role: String, initialStep: String) -> UUID {
        lock.lock()
        let id = UUID()
        let newAgent = CodingAgentTask(
            id: id,
            name: name,
            role: role,
            state: .running(currentStep: initialStep, progress: 0.1),
            tasksPerformed: [initialStep],
            startedAt: Date()
        )
        _agents.insert(newAgent, at: 0)
        let copy = _agents
        lock.unlock()
        
        notifyAgentsChanged(copy)
        return id
    }
    
    public func addPerformedTask(agentId: UUID, task: String) {
        lock.lock()
        if let idx = _agents.firstIndex(where: { $0.id == agentId }) {
            _agents[idx].tasksPerformed.append(task)
        }
        let copy = _agents
        lock.unlock()
        
        notifyAgentsChanged(copy)
    }
    
    public func setAgentStep(agentId: UUID, step: String, progress: Double) {
        lock.lock()
        if let idx = _agents.firstIndex(where: { $0.id == agentId }) {
            _agents[idx].state = .running(currentStep: step, progress: progress)
            _agents[idx].tasksPerformed.append(step)
        }
        let copy = _agents
        lock.unlock()
        
        notifyAgentsChanged(copy)
    }
    
    public func askUser(agentId: UUID, question: String, options: [String] = ["Approve", "Deny"]) {
        lock.lock()
        if let idx = _agents.firstIndex(where: { $0.id == agentId }) {
            _agents[idx].state = .waitingForInput(question: question, options: options)
        }
        let copy = _agents
        lock.unlock()
        
        notifyAgentsChanged(copy)
    }
    
    public func respondToAgent(agentId: UUID, response: String) {
        lock.lock()
        if let idx = _agents.firstIndex(where: { $0.id == agentId }) {
            _agents[idx].userResponse = response
            _agents[idx].tasksPerformed.append("User responded: \"\(response)\"")
            _agents[idx].state = .running(currentStep: "Proceeding with: \(response)", progress: 0.90)
        }
        let copy = _agents
        lock.unlock()
        
        notifyAgentsChanged(copy)
    }
    
    public func completeAgent(agentId: UUID, summary: String) {
        lock.lock()
        if let idx = _agents.firstIndex(where: { $0.id == agentId }) {
            _agents[idx].state = .completed(summary: summary)
        }
        let copy = _agents
        lock.unlock()
        
        notifyAgentsChanged(copy)
    }
    
    private func notifyAgentsChanged(_ agents: [CodingAgentTask]) {
        DispatchQueue.main.async { [weak self] in
            self?.onAgentsChanged?(agents)
        }
    }
}

