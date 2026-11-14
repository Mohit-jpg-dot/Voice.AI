// Ported from islandcn, MIT License, Copyright (c) 2026 Leo. Modified for Swift.
// Honest communication alerts for real email/chat replies and companion device approvals.

import Foundation

public struct IncomingMessageAlert: Identifiable, Sendable {
    public let id: String
    public let senderName: String
    public let channelName: String
    public let previewSnippet: String
    public let timestamp: Date
    public let onRead: (@Sendable () -> Void)?
    public let onReply: (@Sendable () -> Void)?
    public let onDismiss: (@Sendable () -> Void)?

    public init(
        id: String = "msg_\(UUID().uuidString.prefix(8))",
        senderName: String,
        channelName: String,
        previewSnippet: String,
        timestamp: Date = Date(),
        onRead: (@Sendable () -> Void)? = nil,
        onReply: (@Sendable () -> Void)? = nil,
        onDismiss: (@Sendable () -> Void)? = nil
    ) {
        self.id = id
        self.senderName = senderName
        self.channelName = channelName
        self.previewSnippet = previewSnippet
        self.timestamp = timestamp
        self.onRead = onRead
        self.onReply = onReply
        self.onDismiss = onDismiss
    }
}

public struct CompanionApprovalAlert: Identifiable, Sendable {
    public let id: String
    public let deviceName: String
    public let actionTitle: String
    public let onApprove: (@Sendable () -> Void)?
    public let onDeny: (@Sendable () -> Void)?

    public init(
        id: String = "companion_\(UUID().uuidString.prefix(8))",
        deviceName: String,
        actionTitle: String,
        onApprove: (@Sendable () -> Void)? = nil,
        onDeny: (@Sendable () -> Void)? = nil
    ) {
        self.id = id
        self.deviceName = deviceName
        self.actionTitle = actionTitle
        self.onApprove = onApprove
        self.onDeny = onDeny
    }
}

@MainActor
public final class CommunicationActivityBridge: ObservableObject {
    public static let shared = CommunicationActivityBridge()

    private init() {}

    public func presentIncomingMessage(_ message: IncomingMessageAlert) {
        let leading: ActivitySlotContent = .symbol(name: "message.fill", tint: "blue")
        let trailing: ActivitySlotContent = .text(message.senderName)

        let expanded = ActivityExpandedSlots(
            leading: leading,
            trailing: .text(message.channelName),
            center: .text(message.senderName),
            bottom: .text(message.previewSnippet)
        )

        let content = ActivityContent(
            compact: ActivityCompactSlots(leading: leading, trailing: trailing),
            minimal: .symbol(name: "message.fill", tint: "blue"),
            expanded: expanded
        )

        ActivityCenter.shared.start(ActivityOptions(
            id: message.id,
            label: "Message from \(message.senderName)",
            priority: ActivityPriority.alert,
            alert: true,
            isSensitive: true,
            content: content
        ))
    }

    public func presentCompanionApproval(_ approval: CompanionApprovalAlert) {
        let leading: ActivitySlotContent = .symbol(name: "iphone.badge.play", tint: "yellow")
        let trailing: ActivitySlotContent = .text("Approval")

        let expanded = ActivityExpandedSlots(
            leading: leading,
            trailing: .text(approval.deviceName),
            center: .text(approval.actionTitle),
            bottom: .text("Tap to Approve or Deny")
        )

        let content = ActivityContent(
            compact: ActivityCompactSlots(leading: leading, trailing: trailing),
            minimal: .symbol(name: "exclamationmark.shield.fill", tint: "yellow"),
            expanded: expanded
        )

        ActivityCenter.shared.start(ActivityOptions(
            id: approval.id,
            label: "Approval requested from \(approval.deviceName)",
            priority: ActivityPriority.consequentialApproval,
            alert: true,
            isSensitive: false,
            content: content
        ))
    }
}

