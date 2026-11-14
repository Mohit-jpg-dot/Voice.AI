// Ported from islandcn, MIT License, Copyright (c) 2026 Leo. Modified for Swift.
// Step-progress activity for Computer Use mode and multi-step agent actions.

import Foundation

public struct ComputerUseStepState: Sendable, Equatable {
    public var currentStep: Int
    public var totalSteps: Int
    public var budgetSecondsRemaining: Double
    public var actionDescription: String
    public var isRunning: Bool

    public init(
        currentStep: Int = 1,
        totalSteps: Int = 15,
        budgetSecondsRemaining: Double = 90.0,
        actionDescription: String = "Starting task...",
        isRunning: Bool = true
    ) {
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.budgetSecondsRemaining = budgetSecondsRemaining
        self.actionDescription = actionDescription
        self.isRunning = isRunning
    }
}

@MainActor
public final class StepProgressActivityManager: ObservableObject {
    public static let shared = StepProgressActivityManager()

    @Published public private(set) var currentState: ComputerUseStepState? = nil
    public var onStopRequested: (@Sendable () -> Void)?

    public init() {}

    public func startTask(totalSteps: Int = 15, budgetSeconds: Double = 90.0, initialDescription: String = "Starting task...") {
        let state = ComputerUseStepState(
            currentStep: 1,
            totalSteps: totalSteps,
            budgetSecondsRemaining: budgetSeconds,
            actionDescription: initialDescription,
            isRunning: true
        )
        self.currentState = state
        syncWithActivityCenter()
    }

    public func updateStep(step: Int, description: String, budgetRemaining: Double? = nil) {
        guard var state = currentState else { return }
        state.currentStep = step
        state.actionDescription = description
        if let b = budgetRemaining {
            state.budgetSecondsRemaining = b
        }
        self.currentState = state
        syncWithActivityCenter()
    }

    public func stopTask() {
        guard currentState != nil else { return }
        currentState = nil
        ActivityCenter.shared.end(id: "computer-use-step")
        onStopRequested?()
    }

    private func syncWithActivityCenter() {
        guard let state = currentState else { return }

        let share = Double(state.currentStep) / Double(max(1, state.totalSteps))
        let leading: ActivitySlotContent = .symbol(name: "sparkles", tint: "cyan")
        let trailing: ActivitySlotContent = .text("Step \(state.currentStep)/\(state.totalSteps)")
        let minimal: ActivitySlotContent = .progressRing(progress: share, tint: "cyan")

        let expanded = ActivityExpandedSlots(
            leading: .symbol(name: "stop.circle.fill", tint: "red"),
            trailing: .text("\(Int(state.budgetSecondsRemaining))s left"),
            center: .text("Step \(state.currentStep) of \(state.totalSteps)"),
            bottom: .text(state.actionDescription)
        )

        let content = ActivityContent(
            compact: ActivityCompactSlots(leading: leading, trailing: trailing),
            minimal: minimal,
            expanded: expanded
        )

        ActivityCenter.shared.start(ActivityOptions(
            id: "computer-use-step",
            label: "Computer Use: Step \(state.currentStep)",
            priority: ActivityPriority.recording,
            alert: false,
            isSensitive: false,
            content: content,
            onPress: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.stopTask()
                }
            }
        ))
    }
}

