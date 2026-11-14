// Ported from islandcn, MIT License, Copyright (c) 2026 Leo. Modified for Swift.
// Generic determinate and indeterminate progress activity for email/message sending and shelf copy tasks.

import Foundation

public enum ProgressTaskStatus: Sendable, Equatable {
    case inProgress(progress: Double, subtitle: String)
    case completed(title: String)
    case failed(error: String, retryAvailable: Bool)
}

public struct ProgressTaskItem: Identifiable, Sendable {
    public let id: String
    public var title: String
    public var status: ProgressTaskStatus
    public var onRetry: (@Sendable () -> Void)?
    public var onCancel: (@Sendable () -> Void)?

    public init(
        id: String = "progress_\(UUID().uuidString.prefix(8))",
        title: String,
        status: ProgressTaskStatus,
        onRetry: (@Sendable () -> Void)? = nil,
        onCancel: (@Sendable () -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.onRetry = onRetry
        self.onCancel = onCancel
    }
}

@MainActor
public final class UploadProgressActivityManager: ObservableObject {
    public static let shared = UploadProgressActivityManager()

    @Published public private(set) var activeTasks: [ProgressTaskItem] = []

    public init() {}

    @discardableResult
    public func startProgress(
        id: String,
        title: String,
        initialSubtitle: String = "Processing...",
        onCancel: (@Sendable () -> Void)? = nil
    ) -> String {
        let item = ProgressTaskItem(
            id: id,
            title: title,
            status: .inProgress(progress: 0.05, subtitle: initialSubtitle),
            onCancel: onCancel
        )
        activeTasks.removeAll { $0.id == id }
        activeTasks.append(item)
        syncWithActivityCenter(item: item)
        return id
    }

    public func updateProgress(id: String, progress: Double, subtitle: String? = nil) {
        guard let idx = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        var item = activeTasks[idx]
        let sub = subtitle ?? {
            if case .inProgress(_, let s) = item.status { return s }
            return "Processing..."
        }()
        item.status = .inProgress(progress: max(0.0, min(1.0, progress)), subtitle: sub)
        activeTasks[idx] = item
        syncWithActivityCenter(item: item)
    }

    public func complete(id: String, successTitle: String = "Sent") {
        guard let idx = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        var item = activeTasks[idx]
        item.status = .completed(title: successTitle)
        activeTasks[idx] = item
        syncWithActivityCenter(item: item)

        // Auto-dismiss completed task after brief delay
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await self?.dismiss(id: id)
        }
    }

    public func fail(id: String, error: String, onRetry: (@Sendable () -> Void)? = nil) {
        guard let idx = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        var item = activeTasks[idx]
        item.status = .failed(error: error, retryAvailable: onRetry != nil)
        item.onRetry = onRetry
        activeTasks[idx] = item
        syncWithActivityCenter(item: item)
    }

    public func dismiss(id: String) {
        activeTasks.removeAll { $0.id == id }
        ActivityCenter.shared.end(id: id)
    }

    private func syncWithActivityCenter(item: ProgressTaskItem) {
        let (leading, trailing, minimal, expanded) = buildSlots(for: item)

        let content = ActivityContent(
            compact: ActivityCompactSlots(leading: leading, trailing: trailing),
            minimal: minimal,
            expanded: expanded
        )

        let isCompletedOrFailed: Bool
        switch item.status {
        case .completed, .failed: isCompletedOrFailed = true
        default: isCompletedOrFailed = false
        }

        ActivityCenter.shared.start(ActivityOptions(
            id: item.id,
            label: item.title,
            priority: isCompletedOrFailed ? ActivityPriority.alert : ActivityPriority.standard,
            alert: isCompletedOrFailed,
            isSensitive: false,
            content: content
        ))
    }

    private func buildSlots(for item: ProgressTaskItem) -> (
        leading: ActivitySlotContent,
        trailing: ActivitySlotContent,
        minimal: ActivitySlotContent,
        expanded: ActivityExpandedSlots
    ) {
        switch item.status {
        case .inProgress(let p, let subtitle):
            let leading: ActivitySlotContent = .symbol(name: "arrow.up.circle.fill", tint: "blue")
            let trailing: ActivitySlotContent = .text("\(Int(p * 100))%")
            let minimal: ActivitySlotContent = .progressRing(progress: p, tint: "blue")
            let expanded = ActivityExpandedSlots(
                leading: leading,
                trailing: trailing,
                center: .text(item.title),
                bottom: .text(subtitle)
            )
            return (leading, trailing, minimal, expanded)

        case .completed(let title):
            let leading: ActivitySlotContent = .symbol(name: "checkmark.circle.fill", tint: "green")
            let trailing: ActivitySlotContent = .text("Done")
            let minimal: ActivitySlotContent = .symbol(name: "checkmark", tint: "green")
            let expanded = ActivityExpandedSlots(
                leading: leading,
                trailing: trailing,
                center: .text(item.title),
                bottom: .text(title)
            )
            return (leading, trailing, minimal, expanded)

        case .failed(let err, _):
            let leading: ActivitySlotContent = .symbol(name: "exclamationmark.circle.fill", tint: "red")
            let trailing: ActivitySlotContent = .text("Failed")
            let minimal: ActivitySlotContent = .symbol(name: "xmark", tint: "red")
            let expanded = ActivityExpandedSlots(
                leading: leading,
                trailing: trailing,
                center: .text(item.title),
                bottom: .text(err)
            )
            return (leading, trailing, minimal, expanded)
        }
    }
}

