// Ported from islandcn, MIT License, Copyright (c) 2026 Leo. Modified for Swift.
// Active microphone, dictation, and speech recognition privacy activity bridge.

import Foundation

@MainActor
public final class RecordingActivityBridge: ObservableObject {
    public static let shared = RecordingActivityBridge()

    private let activityId = "mic-recording"
    private var startTime: Date?
    private var timer: Timer?

    private init() {}

    public func startRecording(sourceName: String = "Dictation", onStop: (@Sendable () -> Void)? = nil) {
        startTime = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncActivity(sourceName: sourceName, onStop: onStop)
            }
        }
        syncActivity(sourceName: sourceName, onStop: onStop)
    }

    public func stopRecording() {
        timer?.invalidate()
        timer = nil
        startTime = nil
        ActivityCenter.shared.end(id: activityId)
    }

    private func syncActivity(sourceName: String, onStop: (@Sendable () -> Void)?) {
        guard let start = startTime else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let timeStr = String(format: "%d:%02d", elapsed / 60, elapsed % 60)

        let leading: ActivitySlotContent = .symbol(name: "mic.fill", tint: "red")
        let trailing: ActivitySlotContent = .text(timeStr)

        let expanded = ActivityExpandedSlots(
            leading: leading,
            trailing: .symbol(name: "stop.circle.fill", tint: "red"),
            center: .text("Mic on: \(sourceName)"),
            bottom: .text("Recording (\(timeStr))")
        )

        let content = ActivityContent(
            compact: ActivityCompactSlots(leading: leading, trailing: trailing),
            minimal: leading,
            expanded: expanded
        )

        ActivityCenter.shared.start(ActivityOptions(
            id: activityId,
            label: "Microphone Active: \(sourceName)",
            priority: ActivityPriority.recording,
            alert: false,
            isSensitive: false,
            content: content,
            onPress: {
                onStop?()
            }
        ))
    }
}

