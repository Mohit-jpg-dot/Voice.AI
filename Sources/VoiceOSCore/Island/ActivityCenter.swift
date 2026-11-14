// Ported from islandcn, MIT License, Copyright (c) 2026 Leo. Modified for Swift.
// Observable main-actor activity engine managing priority stacks, presentations, alerts, and safety lanes.

import Foundation
import Combine

public protocol IslandClockProtocol: Sendable {
    func now() -> Double
    func schedule(at delaySeconds: Double, action: @escaping @Sendable () -> Void) -> (@Sendable () -> Void)
}

public struct SystemIslandClock: IslandClockProtocol {
    public init() {}
    public func now() -> Double {
        Date().timeIntervalSince1970
    }
    public func schedule(at delaySeconds: Double, action: @escaping @Sendable () -> Void) -> (@Sendable () -> Void) {
        let task = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, delaySeconds) * 1_000_000_000))
            if !Task.isCancelled {
                action()
            }
        }
        return { task.cancel() }
    }
}

public final class MockIslandClock: IslandClockProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var currentTime: Double = 1000.0
    private var scheduledTasks: [(id: UUID, dueTime: Double, action: @Sendable () -> Void)] = []

    public init(initialTime: Double = 1000.0) {
        self.currentTime = initialTime
    }

    public func now() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return currentTime
    }

    public func advance(by seconds: Double) {
        lock.lock()
        currentTime += seconds
        let current = currentTime
        let due = scheduledTasks.filter { $0.dueTime <= current }
        scheduledTasks.removeAll { $0.dueTime <= current }
        lock.unlock()

        for task in due {
            task.action()
        }
    }

    public func schedule(at delaySeconds: Double, action: @escaping @Sendable () -> Void) -> (@Sendable () -> Void) {
        lock.lock()
        let id = UUID()
        let due = currentTime + delaySeconds
        scheduledTasks.append((id: id, dueTime: due, action: action))
        lock.unlock()

        return { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.scheduledTasks.removeAll { $0.id == id }
            self.lock.unlock()
        }
    }
}

public struct ActivityHandle: Sendable {
    public let id: String
    private let center: ActivityCenter

    @MainActor
    public init(id: String, center: ActivityCenter) {
        self.id = id
        self.center = center
    }

    @MainActor
    public func update(_ update: ActivityUpdate) {
        center.update(id: id, with: update)
    }

    @MainActor
    public func end() {
        center.end(id: id)
    }
}

@MainActor
public final class ActivityCenter: ObservableObject {
    public static let shared = ActivityCenter()

    // MARK: - Published State
    @Published public private(set) var activities: [Activity] = []
    @Published public private(set) var currentScene: IslandScene = .idle
    @Published public private(set) var isExpanded: Bool = false
    @Published public private(set) var expandedActivityId: String? = nil
    @Published public private(set) var expandReason: ExpandReason? = nil
    @Published public private(set) var frontGroups: [String: String] = [:]
    @Published public private(set) var handoffGroup: String? = nil

    // MARK: - Safety, Privacy & Quiet Lanes
    @Published public var showSensitivePreviewsInNotch: Bool = false
    @Published public var isDNDActive: Bool = false
    @Published public var isDictationActive: Bool = false
    @Published public var isApprovalCardActive: Bool = false

    // MARK: - Clock & Internal Timers
    public var clock: IslandClockProtocol
    private var nextOrder: Int = 0
    private var alertCancelActions: [(@Sendable () -> Void)] = []
    private var pendingUpdateActions: [String: (@Sendable () -> Void)] = [:]
    private let persistenceKey = "voiceos.island.persistent_activities"

    public init(clock: IslandClockProtocol = SystemIslandClock()) {
        self.clock = clock
    }

    // MARK: - Engine Operations

    @discardableResult
    public func start(_ options: ActivityOptions) -> ActivityHandle {
        if activities.contains(where: { $0.id == options.id }) {
            let update = ActivityUpdate(
                compact: options.content.compact,
                minimal: options.content.minimal,
                expanded: options.content.expanded,
                label: options.label,
                priority: options.priority,
                alert: options.alert,
                onPress: options.onPress
            )
            self.update(id: options.id, with: update)
            return ActivityHandle(id: options.id, center: self)
        }

        let isIdle = activities.isEmpty
        let activity = Activity(
            id: options.id,
            label: options.label ?? options.id,
            priority: options.priority,
            order: nextOrder,
            content: options.content,
            revision: 0,
            group: options.group,
            isSensitive: options.isSensitive,
            persistsAcrossRestarts: options.persistsAcrossRestarts,
            onPress: options.onPress
        )
        nextOrder += 1

        var updated = activities
        updated.append(activity)
        sortActivities(&updated)
        self.activities = updated

        if options.persistsAcrossRestarts {
            savePersistentActivities()
        }

        recomputeScene()

        if options.alert {
            triggerAlert(for: options.id, fromIdle: isIdle)
        }

        return ActivityHandle(id: options.id, center: self)
    }

    public func update(id: String, with update: ActivityUpdate) {
        guard let idx = activities.firstIndex(where: { $0.id == id }) else { return }
        let existing = activities[idx]

        // Consequential Safety Lane: An active approval card CANNOT have its priority degraded
        let newPriority = (existing.priority == ActivityPriority.consequentialApproval)
            ? ActivityPriority.consequentialApproval
            : (update.priority ?? existing.priority)

        let mergedContent = mergeContent(existing.content, update: update)
        let isCrossfade = update.transition == "crossfade"
        let nextRevision = isCrossfade ? existing.revision + 1 : existing.revision

        let next = Activity(
            id: existing.id,
            label: update.label ?? existing.label,
            priority: newPriority,
            order: existing.order,
            content: mergedContent,
            revision: nextRevision,
            group: existing.group,
            isSensitive: existing.isSensitive,
            persistsAcrossRestarts: existing.persistsAcrossRestarts,
            onPress: update.onPress ?? existing.onPress
        )

        activities[idx] = next
        sortActivities(&activities)

        if next.persistsAcrossRestarts {
            savePersistentActivities()
        }

        recomputeScene()

        if update.alert == true {
            triggerAlert(for: id, fromIdle: false)
        }
    }

    public func end(id: String) {
        guard let idx = activities.firstIndex(where: { $0.id == id }) else { return }
        let ending = activities[idx]

        pendingUpdateActions[id]?()
        pendingUpdateActions.removeValue(forKey: id)

        if expandedActivityId == id {
            clearAlertTimers()
            isExpanded = false
            expandedActivityId = nil
            expandReason = nil
        }

        activities.remove(at: idx)
        frontGroups.removeValue(forKey: id)

        if ending.persistsAcrossRestarts {
            savePersistentActivities()
        }

        recomputeScene()
    }

    public func expand(id: String? = nil) {
        // Consequential Safety Lane: If approval card is active, user cannot force-expand a lower activity
        if isApprovalCardActive, let appActivity = activities.first(where: { $0.priority == ActivityPriority.consequentialApproval }) {
            if id != nil && id != appActivity.id {
                return // Locked to approval card
            }
        }

        let targetId = id ?? currentShownActivities().first?.id
        guard let target = activities.first(where: { $0.id == targetId }) else { return }

        clearAlertTimers()

        if let g = target.group {
            frontGroups[g] = target.id
        }

        isExpanded = true
        expandedActivityId = target.id
        expandReason = .user
        recomputeScene()
    }

    public func collapse() {
        // Consequential Safety Lane: Approval card CANNOT be collapsed while active
        if isApprovalCardActive && expandedActivityId != nil {
            if let active = activities.first(where: { $0.id == expandedActivityId }), active.priority == ActivityPriority.consequentialApproval {
                return // Cannot dismiss or collapse approval card
            }
        }

        guard isExpanded else { return }
        clearAlertTimers()
        isExpanded = false
        expandedActivityId = nil
        expandReason = nil
        recomputeScene()
    }

    public func reset() {
        clearAlertTimers()
        pendingUpdateActions.removeAll()
        activities.removeAll()
        frontGroups.removeAll()
        handoffGroup = nil
        isExpanded = false
        expandedActivityId = nil
        expandReason = nil
        currentScene = .idle
    }

    // MARK: - Scene Derivation

    public func recomputeScene() {
        let shown = currentShownActivities()
        let expanded = isExpanded ? activities.first(where: { $0.id == expandedActivityId }) : nil

        if let exp = expanded {
            let label = exp.label
            let contentKey = "expanded:\(keyOf(exp))"
            let slots = exp.content.expanded
            let pres = IslandPresentation.expanded(
                leading: slots?.leading,
                trailing: slots?.trailing,
                center: slots?.center,
                bottom: slots?.bottom
            )
            self.currentScene = IslandScene(
                presentation: pres,
                contentKey: contentKey,
                label: label,
                primaryId: exp.id,
                detachedId: nil
            )
            return
        }

        guard let first = shown.first else {
            self.currentScene = .idle
            return
        }

        if shown.count == 1 {
            let label = first.label
            let contentKey = "compact:\(keyOf(first))"
            let slots = sanitizedCompactSlots(for: first)
            let pres = IslandPresentation.compact(
                leading: slots?.leading,
                trailing: slots?.trailing
            )
            self.currentScene = IslandScene(
                presentation: pres,
                contentKey: contentKey,
                label: label,
                primaryId: first.id,
                detachedId: nil
            )
            return
        }

        // Two activities -> split / minimal
        let second = shown[1]
        let label = "\(first.label), \(second.label)"
        let contentKey = "minimal:\(keyOf(first)):\(keyOf(second))"
        let firstCompact = sanitizedCompactSlots(for: first) ?? ActivityCompactSlots()
        let secondCompact = sanitizedCompactSlots(for: second) ?? ActivityCompactSlots()

        let minimalAttached = first.content.minimal ?? firstCompact.leading
        let minimalDetached = second.content.minimal ?? secondCompact.leading

        let pres = IslandPresentation.minimal(
            attached: minimalAttached,
            detached: minimalDetached,
            split: SplitSlots(attached: firstCompact, detached: secondCompact)
        )

        self.currentScene = IslandScene(
            presentation: pres,
            contentKey: contentKey,
            label: label,
            primaryId: first.id,
            detachedId: second.id
        )
    }

    // MARK: - Alerts & Timing

    private func triggerAlert(for id: String, fromIdle: Bool) {
        guard let activity = activities.first(where: { $0.id == id }) else { return }

        // Consequential Safety Lane: If an approval card is active, alerts NEVER expand or interrupt
        if isApprovalCardActive || (activities.contains(where: { $0.priority == ActivityPriority.consequentialApproval })) {
            return
        }

        // Quiet Rules: Alerts must not interrupt active dictation or DND
        if isDictationActive || isDNDActive {
            return
        }

        clearAlertTimers()

        if let group = activity.group {
            frontGroups[group] = activity.id
        }

        self.isExpanded = true
        self.expandedActivityId = id
        self.expandReason = .alert
        recomputeScene()

        let holdDuration = fromIdle ? IslandMotionTokens.alertHoldIdle : IslandMotionTokens.alertHold
        let cancel = clock.schedule(at: holdDuration) { [weak self] in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    if self?.expandedActivityId == id && self?.expandReason == .alert {
                        self?.isExpanded = false
                        self?.expandedActivityId = nil
                        self?.expandReason = nil
                        self?.recomputeScene()
                    }
                }
            } else {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.expandedActivityId == id && self.expandReason == .alert {
                        self.isExpanded = false
                        self.expandedActivityId = nil
                        self.expandReason = nil
                        self.recomputeScene()
                    }
                }
            }
        }
        alertCancelActions.append(cancel)
    }

    private func clearAlertTimers() {
        for cancel in alertCancelActions {
            cancel()
        }
        alertCancelActions.removeAll()
    }

    // MARK: - Helper Methods

    private func sortActivities(_ list: inout [Activity]) {
        list.sort { a, b in
            if a.priority != b.priority {
                return b.priority < a.priority
            }
            return a.order < b.order
        }
    }

    private func currentShownActivities() -> [Activity] {
        activities.filter { a in
            guard let g = a.group else { return true }
            if handoffGroup == g { return false }
            let forward = frontGroups[g]
            if let f = forward {
                return a.id == f
            }
            let firstInGroup = activities.filter { $0.group == g }.min { $0.order < $1.order }
            return firstInGroup?.id == a.id
        }
    }

    private func keyOf(_ activity: Activity) -> String {
        activity.revision > 0 ? "\(activity.id)#\(activity.revision)" : activity.id
    }

    private func sanitizedCompactSlots(for activity: Activity) -> ActivityCompactSlots? {
        guard let compact = activity.content.compact else { return nil }
        guard activity.isSensitive && !showSensitivePreviewsInNotch else { return compact }

        // Mask sensitive text with privacy placeholder
        var sanitized = compact
        if case .text = sanitized.leading {
            sanitized.leading = .text("Private")
        }
        if case .text = sanitized.trailing {
            sanitized.trailing = .text("••••")
        }
        return sanitized
    }

    private func mergeContent(_ content: ActivityContent, update: ActivityUpdate) -> ActivityContent {
        var mergedCompact = content.compact
        if let upCompact = update.compact {
            mergedCompact = ActivityCompactSlots(
                leading: upCompact.leading ?? content.compact?.leading,
                trailing: upCompact.trailing ?? content.compact?.trailing
            )
        }

        let mergedMinimal = update.minimal ?? content.minimal

        var mergedExpanded = content.expanded
        if let upExp = update.expanded {
            mergedExpanded = ActivityExpandedSlots(
                leading: upExp.leading ?? content.expanded?.leading,
                trailing: upExp.trailing ?? content.expanded?.trailing,
                center: upExp.center ?? content.expanded?.center,
                bottom: upExp.bottom ?? content.expanded?.bottom
            )
        }

        return ActivityContent(compact: mergedCompact, minimal: mergedMinimal, expanded: mergedExpanded)
    }

    // MARK: - Restart Persistence

    public func savePersistentActivities() {
        let persistent = activities.filter { $0.persistsAcrossRestarts }.map { a in
            PersistentActivityRecord(
                id: a.id,
                label: a.label,
                priority: a.priority,
                content: a.content,
                group: a.group,
                isSensitive: a.isSensitive
            )
        }
        if let data = try? JSONEncoder().encode(persistent) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    public func restorePersistentActivities() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let list = try? JSONDecoder().decode([PersistentActivityRecord].self, from: data) else {
            return
        }
        for item in list {
            self.start(ActivityOptions(
                id: item.id,
                label: item.label,
                priority: item.priority,
                group: item.group,
                isSensitive: item.isSensitive,
                persistsAcrossRestarts: true,
                content: item.content
            ))
        }
    }
}
