// Ported from islandcn, MIT License, Copyright (c) 2026 Leo. Modified for Swift.
// Real battery and charging state monitor using macOS IOKit power source APIs.

import Foundation
import IOKit.ps

public struct BatteryStatus: Sendable, Equatable {
    public let level: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let isLow: Bool
    public let isFull: Bool

    public init(level: Int, isCharging: Bool, isPluggedIn: Bool) {
        self.level = max(0, min(100, level))
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.isLow = level <= 20 && !isCharging
        self.isFull = level >= 100 && isPluggedIn
    }
}

@MainActor
public final class BatteryActivityMonitor: ObservableObject {
    public static let shared = BatteryActivityMonitor()

    @Published public private(set) var currentStatus: BatteryStatus
    private var lastChargingState: Bool = false
    private var pollTimer: Timer?

    public init() {
        let initial = Self.readSystemBattery()
        self.currentStatus = initial
        self.lastChargingState = initial.isCharging
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    public func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    public func refresh() {
        let status = Self.readSystemBattery()
        let oldStatus = self.currentStatus
        self.currentStatus = status

        // Detect charging plugged-in transition
        if !oldStatus.isCharging && status.isCharging {
            triggerChargingAlert(status: status)
        } else if !oldStatus.isLow && status.isLow {
            triggerLowBatteryAlert(status: status)
        }
    }

    public func getVoiceBatterySummary() -> String {
        let status = Self.readSystemBattery()
        if status.isCharging {
            return "Your battery is at \(status.level)% and currently charging."
        } else if status.isFull {
            return "Your battery is fully charged at 100%."
        } else {
            return "Your battery is at \(status.level)%."
        }
    }

    public func triggerManualBatteryDisplay() {
        let status = Self.readSystemBattery()
        triggerChargingAlert(status: status, forceAlert: true)
    }

    private func triggerChargingAlert(status: BatteryStatus, forceAlert: Bool = true) {
        let leading: ActivitySlotContent = .symbol(name: status.isCharging ? "bolt.fill" : "battery.100", tint: "green")
        let trailing: ActivitySlotContent = .text("\(status.level)%")
        let minimal: ActivitySlotContent = .battery(level: status.level, state: status.isCharging ? "charging" : "normal")

        let expanded = ActivityExpandedSlots(
            leading: leading,
            trailing: trailing,
            center: .text(status.isCharging ? "Charging" : "Battery"),
            bottom: .text("\(status.level)% remaining")
        )

        let content = ActivityContent(
            compact: ActivityCompactSlots(leading: leading, trailing: trailing),
            minimal: minimal,
            expanded: expanded
        )

        ActivityCenter.shared.start(ActivityOptions(
            id: "battery-status",
            label: "Battery \(status.level)%",
            priority: ActivityPriority.alert,
            alert: forceAlert,
            isSensitive: false,
            content: content
        ))
    }

    private func triggerLowBatteryAlert(status: BatteryStatus) {
        let leading: ActivitySlotContent = .symbol(name: "exclamationmark.triangle.fill", tint: "red")
        let trailing: ActivitySlotContent = .text("\(status.level)%")

        let expanded = ActivityExpandedSlots(
            leading: leading,
            trailing: trailing,
            center: .text("Low Battery"),
            bottom: .text("Plug in to power (\(status.level)%)")
        )

        let content = ActivityContent(
            compact: ActivityCompactSlots(leading: leading, trailing: trailing),
            minimal: .battery(level: status.level, state: "low"),
            expanded: expanded
        )

        ActivityCenter.shared.start(ActivityOptions(
            id: "battery-status",
            label: "Low Battery",
            priority: ActivityPriority.alert,
            alert: true,
            isSensitive: false,
            content: content
        ))
    }

    public static func readSystemBattery() -> BatteryStatus {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else {
            return BatteryStatus(level: 100, isCharging: false, isPluggedIn: true)
        }

        for source in list {
            if let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
               let cap = desc[kIOPSCurrentCapacityKey as String] as? Int,
               let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int,
               maxCap > 0 {
                let pct = Int((Double(cap) / Double(maxCap)) * 100.0)
                let isCharging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
                let isPlugged = (desc[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSACPowerValue as String)
                return BatteryStatus(level: pct, isCharging: isCharging, isPluggedIn: isPlugged)
            }
        }

        return BatteryStatus(level: 100, isCharging: false, isPluggedIn: true)
    }
}

