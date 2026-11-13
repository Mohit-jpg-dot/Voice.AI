import Foundation
import Darwin

public enum ProactiveRuleKind: String, Codable, Sendable, CaseIterable {
    case lowBattery = "low_battery"
    case highCpuMemory = "high_cpu_memory"
    case failedBuild = "failed_build"
    case calendarConflict = "calendar_conflict"
    case importantEmail = "important_email"
}

public struct ProactiveRuleConfig: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let kind: ProactiveRuleKind
    public var title: String
    public var isEnabled: Bool
    public var threshold: Double
    public var cooldownSeconds: TimeInterval

    public init(
        id: String,
        kind: ProactiveRuleKind,
        title: String,
        isEnabled: Bool = true,
        threshold: Double,
        cooldownSeconds: TimeInterval = 300
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.isEnabled = isEnabled
        self.threshold = threshold
        self.cooldownSeconds = max(1, cooldownSeconds)
    }

    public static let defaults: [ProactiveRuleConfig] = [
        ProactiveRuleConfig(id: "rule_low_battery", kind: .lowBattery, title: "Low Battery Alert (< 20%)", isEnabled: true, threshold: 20, cooldownSeconds: 600),
        ProactiveRuleConfig(id: "rule_high_cpu_memory", kind: .highCpuMemory, title: "High CPU / Memory Load (> 85%)", isEnabled: true, threshold: 85, cooldownSeconds: 300),
        ProactiveRuleConfig(id: "rule_failed_build", kind: .failedBuild, title: "Failed Build Notification", isEnabled: true, threshold: 1, cooldownSeconds: 120),
        ProactiveRuleConfig(id: "rule_calendar_conflict", kind: .calendarConflict, title: "Calendar Conflict Warning", isEnabled: true, threshold: 15, cooldownSeconds: 600),
        ProactiveRuleConfig(id: "rule_important_email", kind: .importantEmail, title: "Important Email Alert", isEnabled: true, threshold: 1, cooldownSeconds: 300)
    ]
}

public struct ProactiveAlert: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let ruleId: String
    public let kind: ProactiveRuleKind
    public let title: String
    public let message: String
    public let severity: VoiceEventSeverity
    public let suggestedPrompt: String?
    public let createdAt: Date
    public var isDismissed: Bool

    public init(
        id: String = UUID().uuidString,
        ruleId: String,
        kind: ProactiveRuleKind,
        title: String,
        message: String,
        severity: VoiceEventSeverity,
        suggestedPrompt: String? = nil,
        createdAt: Date = Date(),
        isDismissed: Bool = false
    ) {
        self.id = id
        self.ruleId = ruleId
        self.kind = kind
        self.title = SecretRedactor.redact(title)
        self.message = SecretRedactor.redact(message)
        self.severity = severity
        self.suggestedPrompt = suggestedPrompt
        self.createdAt = createdAt
        self.isDismissed = isDismissed
    }
}

public protocol ProactiveRuleManaging: Sendable {
    func allRules() -> [ProactiveRuleConfig]
    func updateRule(_ rule: ProactiveRuleConfig)
    func setRuleEnabled(id: String, enabled: Bool)
    func activeAlerts(includeDismissed: Bool) -> [ProactiveAlert]
    func dismissAlert(id: String)
    func dismissAllAlerts()
    @discardableResult
    func evaluateEvent(_ event: VoiceEvent) -> ProactiveAlert?
}

/// Rate-limited, user-configurable EventBus rules engine raising proactive alerts for
/// battery, CPU/memory pressure, failed builds, calendar conflicts, and important emails.
public final class ProactiveRulesEngine: ProactiveRuleManaging, @unchecked Sendable {
    public static let shared = ProactiveRulesEngine()

    private let rulesStorageKey = "VoiceAI_ProactiveRules_v1"
    private let lock = NSLock()
    private let eventBus: EventBus
    private let nowProvider: @Sendable () -> Date
    private var rules: [ProactiveRuleConfig]
    private var alerts: [ProactiveAlert] = []
    private var lastFiredAt: [String: Date] = [:]
    private var busSubscriptionId: UUID?
    private var monitorTimer: Timer?

    public init(
        eventBus: EventBus = .shared,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        persistRules: Bool = true
    ) {
        self.eventBus = eventBus
        self.nowProvider = nowProvider
        if persistRules,
           let data = UserDefaults.standard.data(forKey: "VoiceAI_ProactiveRules_v1"),
           let decoded = try? JSONDecoder().decode([ProactiveRuleConfig].self, from: data),
           !decoded.isEmpty {
            self.rules = decoded
        } else {
            self.rules = ProactiveRuleConfig.defaults
        }

        self.busSubscriptionId = eventBus.subscribe(matching: nil) { [weak self] event in
            self?.handleIncomingBusEvent(event)
        }
    }

    deinit {
        if let id = busSubscriptionId {
            eventBus.unsubscribe(id)
        }
        monitorTimer?.invalidate()
    }

    public func allRules() -> [ProactiveRuleConfig] {
        lock.withLock { rules }
    }

    public func updateRule(_ rule: ProactiveRuleConfig) {
        lock.withLock {
            if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
                rules[idx] = rule
            } else {
                rules.append(rule)
            }
            if let data = try? JSONEncoder().encode(rules) {
                UserDefaults.standard.set(data, forKey: rulesStorageKey)
            }
        }
    }

    public func setRuleEnabled(id: String, enabled: Bool) {
        lock.withLock {
            if let idx = rules.firstIndex(where: { $0.id == id }) {
                rules[idx].isEnabled = enabled
                if let data = try? JSONEncoder().encode(rules) {
                    UserDefaults.standard.set(data, forKey: rulesStorageKey)
                }
            }
        }
    }

    public func activeAlerts(includeDismissed: Bool = false) -> [ProactiveAlert] {
        lock.withLock {
            includeDismissed ? alerts : alerts.filter { !$0.isDismissed }
        }
    }

    public func dismissAlert(id: String) {
        lock.withLock {
            if let idx = alerts.firstIndex(where: { $0.id == id }) {
                alerts[idx].isDismissed = true
            }
        }
        eventBus.publish(VoiceEvent(
            kind: .custom("proactive_alerts_changed"),
            source: "ProactiveRulesEngine",
            payload: ["dismissed_id": id]
        ))
    }

    public func dismissAllAlerts() {
        lock.withLock {
            for i in alerts.indices {
                alerts[i].isDismissed = true
            }
        }
        eventBus.publish(VoiceEvent(
            kind: .custom("proactive_alerts_changed"),
            source: "ProactiveRulesEngine",
            payload: ["dismissed": "all"]
        ))
    }

    public func recordExternalAlert(_ alert: ProactiveAlert) {
        lock.withLock {
            alerts.insert(alert, at: 0)
            if alerts.count > 50 { alerts = Array(alerts.prefix(50)) }
        }
        eventBus.publish(VoiceEvent(
            kind: .custom("proactive_alerts_changed"),
            source: "ProactiveRulesEngine",
            severity: alert.severity,
            payload: ["alert_id": alert.id, "title": alert.title]
        ))
    }

    private func handleIncomingBusEvent(_ event: VoiceEvent) {
        // Avoid re-evaluating our own raised-alert notifications
        if case .custom(let name) = event.kind,
           name == "proactive_alert_raised" || name == "proactive_alerts_changed" {
            return
        }
        _ = evaluateEvent(event)
    }

    @discardableResult
    public func evaluateEvent(_ event: VoiceEvent) -> ProactiveAlert? {
        let candidate = buildCandidateAlert(for: event)
        guard let alert = candidate else { return nil }

        let now = nowProvider()
        let accepted = lock.withLock { () -> Bool in
            guard let rule = rules.first(where: { $0.id == alert.ruleId && $0.isEnabled }) else {
                return false
            }
            if let last = lastFiredAt[rule.id], now.timeIntervalSince(last) < rule.cooldownSeconds {
                return false
            }
            lastFiredAt[rule.id] = now
            alerts.insert(alert, at: 0)
            if alerts.count > 50 {
                alerts = Array(alerts.prefix(50))
            }
            return true
        }

        guard accepted else { return nil }

        eventBus.publish(VoiceEvent(
            kind: .custom("proactive_alert_raised"),
            source: "ProactiveRulesEngine",
            severity: alert.severity,
            payload: [
                "alert_id": alert.id,
                "rule_id": alert.ruleId,
                "kind": alert.kind.rawValue,
                "title": alert.title,
                "message": alert.message
            ]
        ))
        return alert
    }

    private func buildCandidateAlert(for event: VoiceEvent) -> ProactiveAlert? {
        let now = nowProvider()
        let activeRules = lock.withLock { rules }

        switch event.kind {
        case .batteryChanged:
            guard let rule = activeRules.first(where: { $0.kind == .lowBattery && $0.isEnabled }) else { return nil }
            let rawLevel = (event.payload["level"] ?? "")
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isCharging = (event.payload["charging"] ?? "false").lowercased() == "true"
            guard let pct = Double(rawLevel), !isCharging, pct <= rule.threshold else { return nil }
            return ProactiveAlert(
                ruleId: rule.id,
                kind: .lowBattery,
                title: "Battery at \(Int(pct))%",
                message: "Power is running low (\(Int(pct))% remaining on battery). Connect power or enable Focus Saver.",
                severity: pct <= 10 ? .critical : .warning,
                suggestedPrompt: "Check battery and reduce brightness",
                createdAt: now
            )

        case .cpuMemoryPressure:
            guard let rule = activeRules.first(where: { $0.kind == .highCpuMemory && $0.isEnabled }) else { return nil }
            let cpu = Double((event.payload["cpu"] ?? "0").replacingOccurrences(of: "%", with: "")) ?? 0
            let mem = Double((event.payload["memory"] ?? "0").replacingOccurrences(of: "%", with: "")) ?? 0
            let peak = max(cpu, mem)
            guard peak >= rule.threshold else { return nil }
            let detail = mem >= cpu ? "Memory pressure at \(Int(mem))%" : "CPU load at \(Int(cpu))%"
            return ProactiveAlert(
                ruleId: rule.id,
                kind: .highCpuMemory,
                title: "High Resource Load (\(Int(peak))%)",
                message: "\(detail) (threshold \(Int(rule.threshold))%). Consider closing heavy background apps.",
                severity: peak >= 95 ? .critical : .warning,
                suggestedPrompt: "Show top CPU and memory usage",
                createdAt: now
            )

        case .buildStatusChanged:
            guard let rule = activeRules.first(where: { $0.kind == .failedBuild && $0.isEnabled }) else { return nil }
            let status = (event.payload["status"] ?? "").lowercased()
            guard status == "failed" || status == "error" else { return nil }
            let project = event.payload["project"] ?? event.source
            let errDetail = event.payload["error"] ?? "Check compiler output for details."
            return ProactiveAlert(
                ruleId: rule.id,
                kind: .failedBuild,
                title: "Build Failed: \(project)",
                message: errDetail,
                severity: .warning,
                suggestedPrompt: "Explain what this build error means",
                createdAt: now
            )

        case .calendarUpcoming:
            guard let rule = activeRules.first(where: { $0.kind == .calendarConflict && $0.isEnabled }) else { return nil }
            let hasConflict = (event.payload["conflict"] ?? "false").lowercased() == "true"
            guard hasConflict else { return nil }
            let eventsDesc = event.payload["events"] ?? event.payload["title"] ?? "Overlapping meetings detected"
            return ProactiveAlert(
                ruleId: rule.id,
                kind: .calendarConflict,
                title: "Calendar Conflict Detected",
                message: eventsDesc,
                severity: .notice,
                suggestedPrompt: "Summarize today's calendar schedule",
                createdAt: now
            )

        case .custom(let name):
            guard name == "email_arrived" || name == "important_email",
                  let rule = activeRules.first(where: { $0.kind == .importantEmail && $0.isEnabled }) else {
                return nil
            }
            let isImportant = (event.payload["important"] ?? "false").lowercased() == "true" || name == "important_email"
            let subject = event.payload["subject"] ?? "Message"
            let sender = event.payload["sender"] ?? "Unknown sender"
            let lowerSubj = subject.lowercased()
            let urgentKeyword = ["urgent", "action required", "deadline", "security", "invoice"].contains { lowerSubj.contains($0) }
            guard isImportant || urgentKeyword else { return nil }
            return ProactiveAlert(
                ruleId: rule.id,
                kind: .importantEmail,
                title: "Important Email from \(sender)",
                message: subject,
                severity: .notice,
                suggestedPrompt: "Summarize emails from \(sender)",
                createdAt: now
            )

        default:
            return nil
        }
    }

    // MARK: - Live System Telemetry Poll

    public func startMonitoring(intervalSeconds: TimeInterval = 60) {
        DispatchQueue.main.async {
            self.monitorTimer?.invalidate()
            let interval = max(15, intervalSeconds)
            self.monitorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task {
                    await self?.pollSystemHealthOnce()
                }
            }
        }
    }

    public func stopMonitoring() {
        DispatchQueue.main.async {
            self.monitorTimer?.invalidate()
            self.monitorTimer = nil
        }
    }

    public func pollSystemHealthOnce() async {
        // 1. Sample Memory Pressure using host_statistics64 (in-process Mach call)
        let memPct = Self.sampleHostMemoryUsagePercent()
        if memPct >= 85 {
            eventBus.publish(VoiceEvent(
                kind: .cpuMemoryPressure,
                source: "SystemHealthMonitor",
                severity: .warning,
                payload: ["memory": "\(Int(memPct))"]
            ))
        }

        // 2. Skip shell pmset probe in headless unit test mode unless explicitly requested
        let env = ProcessInfo.processInfo.environment
        if env["VOICE_AI_TEST_MODE"] == "1" { return }

        let battRes = await Task.detached(priority: .utility) { () -> (Int, Bool)? in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            proc.arguments = ["-g", "batt"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let str = String(data: data, encoding: .utf8) ?? ""
                let charging = str.contains("AC Power") || str.contains("; charging")
                if let range = str.range(of: #"\d+%"#, options: .regularExpression) {
                    let numStr = String(str[range]).replacingOccurrences(of: "%", with: "")
                    if let pct = Int(numStr) {
                        return (pct, charging)
                    }
                }
            } catch {}
            return nil
        }.value

        if let (pct, charging) = battRes {
            eventBus.publish(VoiceEvent(
                kind: .batteryChanged,
                source: "PowerMonitor",
                severity: (!charging && pct <= 20) ? .warning : .info,
                payload: ["level": "\(pct)", "charging": charging ? "true" : "false"]
            ))
        }
    }

    public static func sampleHostMemoryUsagePercent() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let hostPort = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }
        return min(100.0, max(0.0, ((active + wired + compressed) / total) * 100.0))
    }
}

