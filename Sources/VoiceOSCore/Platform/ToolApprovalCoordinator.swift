import Foundation

/// Abstraction over UI confirmation prompts so macOS Notch Approval Card and Windows TopCenterIsland
/// can implement interactive consequential-action gates asynchronously.
public protocol ToolApprovalPresenting: AnyObject, Sendable {
    @MainActor
    func presentApprovalCard(for action: AgentAction) async -> Bool
}

/// Evaluates PermissionTier policies, RememberedPermissionsStore grants, and interactive Notch Approval Cards.
public final class ToolApprovalCoordinator: @unchecked Sendable {
    public static let shared = ToolApprovalCoordinator()

    private let lock = NSLock()
    private weak var presenter: ToolApprovalPresenting?
    private var testResponder: (@Sendable (AgentAction) async -> Bool)?

    public init() {}

    public func setPresenter(_ presenter: ToolApprovalPresenting?) {
        lock.lock()
        self.presenter = presenter
        lock.unlock()
    }

    /// Optional async responder for deterministic unit testing of approve/deny flows without GUI.
    public func setTestResponder(_ handler: (@Sendable (AgentAction) async -> Bool)?) {
        lock.lock()
        self.testResponder = handler
        lock.unlock()
    }

    public func requestAuthorizationIfNeeded(
        toolName: String,
        appName: String,
        title: String,
        subtitle: String?,
        payload: [String: String],
        tier: PermissionTier,
        customApprovalHandler: (@Sendable (AgentAction) async -> Bool)? = nil
    ) async -> (approved: Bool, action: AgentAction?) {
        switch tier {
        case .readOnly, .reversible:
            // READ_ONLY executes silently; REVERSIBLE executes with soft event notification
            return (true, nil)

        case .consequential:
            // Honor explicit remembered grants only when granted at matching `.high` risk level
            if RememberedPermissionsStore.shared.hasPermission(for: appName, capability: toolName, risk: .high) {
                return (true, nil)
            }

            var safePayload = SecretRedactor.redactDictionary(payload)
            safePayload["permission_tier"] = tier.rawValue
            safePayload["tool_name"] = toolName

            let action = AgentAction(
                appName: appName,
                appIcon: iconForToolApp(appName),
                title: title,
                subtitle: subtitle ?? "CONSEQUENTIAL action requires your approval",
                payload: safePayload,
                riskLevel: tier.agentRiskLevel,
                isApproved: false
            )

            EventBus.shared.publish(VoiceEvent(
                kind: .approvalRequested,
                source: "ToolApprovalCoordinator",
                severity: .warning,
                payload: [
                    "tool": toolName,
                    "app": appName,
                    "tier": tier.rawValue,
                    "title": title
                ]
            ))

            let approved: Bool
            if let custom = customApprovalHandler {
                approved = await custom(action)
            } else if let responder = currentTestResponder() {
                approved = await responder(action)
            } else if let currentPresenter = currentPresenter() {
                approved = await currentPresenter.presentApprovalCard(for: action)
            } else {
                // Fail closed when no approval presenter is available for a CONSEQUENTIAL action
                approved = false
            }

            EventBus.shared.publish(VoiceEvent(
                kind: .approvalResolved,
                source: "ToolApprovalCoordinator",
                severity: approved ? .notice : .warning,
                payload: [
                    "tool": toolName,
                    "app": appName,
                    "approved": approved ? "true" : "false"
                ]
            ))

            var resolvedAction = action
            resolvedAction.isApproved = approved
            return (approved, resolvedAction)
        }
    }

    private func currentPresenter() -> ToolApprovalPresenting? {
        lock.lock()
        defer { lock.unlock() }
        return presenter
    }

    private func currentTestResponder() -> (@Sendable (AgentAction) async -> Bool)? {
        lock.lock()
        defer { lock.unlock() }
        return testResponder
    }

    private func iconForToolApp(_ app: String) -> String {
        let lower = app.lowercased()
        if lower.contains("mail") || lower.contains("email") { return "envelope.fill" }
        if lower.contains("whatsapp") || lower.contains("message") { return "message.fill" }
        if lower.contains("slack") { return "number.square.fill" }
        if lower.contains("discord") { return "bubble.left.and.bubble.right.fill" }
        if lower.contains("terminal") { return "terminal.fill" }
        if lower.contains("notion") { return "doc.text.fill" }
        if lower.contains("note") { return "note.text" }
        return "bolt.shield.fill"
    }
}

