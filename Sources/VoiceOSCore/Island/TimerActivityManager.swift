// Ported from islandcn, MIT License, Copyright (c) 2026 Leo. Modified for Swift.
// Voice-driven timer activity manager with restart persistence, named timers, and completion alerts.

import Foundation

public struct VoiceTimerItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var label: String
    public var durationSeconds: Double
    public var remainingSeconds: Double
    public var endsAt: Double
    public var isRunning: Bool
    public var createdAt: Double

    public init(
        id: String = "timer_\(UUID().uuidString.prefix(8))",
        label: String = "Timer",
        durationSeconds: Double,
        remainingSeconds: Double? = nil,
        endsAt: Double? = nil,
        isRunning: Bool = true,
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.label = label
        self.durationSeconds = durationSeconds
        let rem = remainingSeconds ?? durationSeconds
        self.remainingSeconds = rem
        self.endsAt = endsAt ?? (Date().timeIntervalSince1970 + rem)
        self.isRunning = isRunning
        self.createdAt = createdAt
    }
}

@MainActor
public final class TimerActivityManager: ObservableObject {
    public static let shared = TimerActivityManager()

    @Published public private(set) var timers: [VoiceTimerItem] = []
    private var tickTask: Task<Void, Never>?
    private let storageKey = "voiceos.island.voice_timers"

    public var onTimerCompleted: (@Sendable (VoiceTimerItem) -> Void)?

    public init() {
        restoreTimers()
        startTickLoop()
    }

    deinit {
        tickTask?.cancel()
    }

    // MARK: - Voice & API Commands

    @discardableResult
    public func createTimer(durationSeconds: Double, label: String = "Timer") -> VoiceTimerItem {
        let item = VoiceTimerItem(label: label, durationSeconds: durationSeconds)
        timers.append(item)
        syncWithActivityCenter(item: item)
        saveTimers()
        return item
    }

    public func pauseTimer(id: String? = nil) -> Bool {
        guard let idx = indexFor(id: id) else { return false }
        var item = timers[idx]
        guard item.isRunning else { return false }

        let now = Date().timeIntervalSince1970
        item.remainingSeconds = max(0, item.endsAt - now)
        item.isRunning = false
        timers[idx] = item

        syncWithActivityCenter(item: item)
        saveTimers()
        return true
    }

    public func resumeTimer(id: String? = nil) -> Bool {
        guard let idx = indexFor(id: id) else { return false }
        var item = timers[idx]
        guard !item.isRunning, item.remainingSeconds > 0 else { return false }

        let now = Date().timeIntervalSince1970
        item.endsAt = now + item.remainingSeconds
        item.isRunning = true
        timers[idx] = item

        syncWithActivityCenter(item: item)
        saveTimers()
        return true
    }

    public func cancelTimer(id: String? = nil) -> Bool {
        guard let idx = indexFor(id: id) else { return false }
        let item = timers.remove(at: idx)
        ActivityCenter.shared.end(id: item.id)
        saveTimers()
        return true
    }

    public func getRemainingTime(id: String? = nil) -> (label: String, remainingSeconds: Double)? {
        guard let idx = indexFor(id: id) else { return nil }
        let item = timers[idx]
        let rem = item.isRunning ? max(0, item.endsAt - Date().timeIntervalSince1970) : item.remainingSeconds
        return (item.label, rem)
    }

    // MARK: - Internal Tick & Synchronization

    private func indexFor(id: String?) -> Int? {
        if let id = id {
            return timers.firstIndex(where: { $0.id == id })
        }
        return timers.indices.last
    }

    private func startTickLoop() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.handleSecondTick()
            }
        }
    }

    private func handleSecondTick() {
        let now = Date().timeIntervalSince1970
        var completed: [VoiceTimerItem] = []

        for i in timers.indices {
            guard timers[i].isRunning else { continue }
            let rem = timers[i].endsAt - now
            if rem <= 0 {
                timers[i].remainingSeconds = 0
                timers[i].isRunning = false
                completed.append(timers[i])
            } else {
                timers[i].remainingSeconds = rem
            }
        }

        for item in completed {
            handleCompletion(item: item)
        }

        saveTimers()
    }

    private func handleCompletion(item: VoiceTimerItem) {
        // Trigger spoken alert and visual alert expansion in ActivityCenter
        let alertContent = ActivityContent(
            compact: ActivityCompactSlots(
                leading: .symbol(name: "timer", tint: "orange"),
                trailing: .text("0:00")
            ),
            minimal: .symbol(name: "bell.fill", tint: "orange"),
            expanded: ActivityExpandedSlots(
                leading: .symbol(name: "bell.fill", tint: "orange"),
                trailing: .text("Done"),
                center: .text(item.label),
                bottom: .text("Timer finished!")
            )
        )

        ActivityCenter.shared.start(ActivityOptions(
            id: item.id,
            label: "\(item.label) Completed",
            priority: ActivityPriority.alert,
            alert: true,
            isSensitive: false,
            content: alertContent
        ))

        onTimerCompleted?(item)

        // Remove from list
        timers.removeAll { $0.id == item.id }
        saveTimers()
    }

    private func syncWithActivityCenter(item: VoiceTimerItem) {
        let content = buildActivityContent(for: item)
        ActivityCenter.shared.start(ActivityOptions(
            id: item.id,
            label: item.label,
            priority: ActivityPriority.timer,
            alert: false,
            isSensitive: false,
            persistsAcrossRestarts: true,
            content: content
        ))
    }

    private func buildActivityContent(for item: VoiceTimerItem) -> ActivityContent {
        let leading: ActivitySlotContent = .symbol(name: "timer", tint: "orange")
        let trailing: ActivitySlotContent = item.isRunning
            ? .timeCountdown(endsAt: item.endsAt)
            : .timeCountdown(endsAt: item.endsAt, pausedRemaining: item.remainingSeconds)

        let ringShare = item.durationSeconds > 0 ? (item.remainingSeconds / item.durationSeconds) : 0
        let minimal: ActivitySlotContent = .progressRing(progress: ringShare, tint: "orange")

        let expanded = ActivityExpandedSlots(
            leading: .symbol(name: item.isRunning ? "pause.circle.fill" : "play.circle.fill", tint: "orange"),
            trailing: .symbol(name: "xmark.circle.fill", tint: "gray"),
            center: .text(item.label),
            bottom: trailing
        )

        return ActivityContent(
            compact: ActivityCompactSlots(leading: leading, trailing: trailing),
            minimal: minimal,
            expanded: expanded
        )
    }

    // MARK: - Persistence

    private func saveTimers() {
        if let data = try? JSONEncoder().encode(timers) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func restoreTimers() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([VoiceTimerItem].self, from: data) else {
            return
        }
        let now = Date().timeIntervalSince1970
        var active: [VoiceTimerItem] = []

        for var item in list {
            if item.isRunning {
                let rem = item.endsAt - now
                if rem > 0 {
                    item.remainingSeconds = rem
                    active.append(item)
                    syncWithActivityCenter(item: item)
                }
            } else if item.remainingSeconds > 0 {
                active.append(item)
                syncWithActivityCenter(item: item)
            }
        }
        self.timers = active
    }
}

