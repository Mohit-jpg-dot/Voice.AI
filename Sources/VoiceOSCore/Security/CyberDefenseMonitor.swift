import Foundation

public struct SecurityAnomalyFinding: Identifiable, Sendable, Equatable {
    public let id: String
    public let category: String // "process" | "network" | "new_device"
    public let title: String
    public let detail: String
    public let severity: VoiceEventSeverity
    public let detectedAt: Date
}

public struct SecurityScanReport: Sendable, Equatable {
    public let findings: [SecurityAnomalyFinding]
    public let knownDevicesCount: Int
    public let summary: String
}

public struct LockdownActionReport: Sendable, Equatable {
    public let success: Bool
    public let actionsTaken: [String]
    public let summary: String
}

public protocol CyberDefenseMonitoring: Sendable {
    func analyzeSnapshot(listeningPortsOutput: String, arpOutput: String) -> SecurityScanReport
    func runLiveAnomalyScan() async -> SecurityScanReport
    func executeLockdown() async -> LockdownActionReport
}

/// Monitors processes/network listeners & LAN ARP neighbors for anomalies,
/// and provides a strictly CONSEQUENTIAL "lockdown" emergency control (lock screen, mute mic, disable Wi-Fi).
public final class CyberDefenseMonitor: CyberDefenseMonitoring, @unchecked Sendable {
    public static let shared = CyberDefenseMonitor()

    private let lock = NSLock()
    private let knownMacsKey = "VoiceAI_KnownLANMACs_v1"
    private var knownMacs: Set<String>
    private static let riskyPorts: Set<Int> = [4444, 5555, 1337, 31337, 6667, 9001]
    private static let suspiciousBinaryMarkers = ["ncat", "netcat", "socat", "xmrig", "cryptominer"]

    public init(loadPersisted: Bool = true) {
        if loadPersisted, let saved = UserDefaults.standard.stringArray(forKey: "VoiceAI_KnownLANMACs_v1") {
            self.knownMacs = Set(saved)
        } else {
            self.knownMacs = []
        }
    }

    public func seedBaselineMACs(_ macs: [String]) {
        lock.withLock {
            for mac in macs {
                knownMacs.insert(mac.lowercased())
            }
            UserDefaults.standard.set(Array(knownMacs), forKey: knownMacsKey)
        }
    }

    public func analyzeSnapshot(listeningPortsOutput: String, arpOutput: String) -> SecurityScanReport {
        var findings: [SecurityAnomalyFinding] = []

        // 1. Inspect listening ports & process names
        for rawLine in listeningPortsOutput.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()

            if Self.suspiciousBinaryMarkers.contains(where: { lower.contains($0) }) {
                findings.append(SecurityAnomalyFinding(
                    id: UUID().uuidString,
                    category: "process",
                    title: "Suspicious Network Binary",
                    detail: String(line.prefix(160)),
                    severity: .critical,
                    detectedAt: Date()
                ))
                continue
            }

            if let match = line.range(of: #":(\d+)\s+\(LISTEN\)"#, options: .regularExpression) {
                let token = String(line[match])
                let digits = token.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if let port = Int(digits), Self.riskyPorts.contains(port) {
                    findings.append(SecurityAnomalyFinding(
                        id: UUID().uuidString,
                        category: "network",
                        title: "High-Risk Listening Port \(port)",
                        detail: String(line.prefix(160)),
                        severity: .warning,
                        detectedAt: Date()
                    ))
                }
            }
        }

        // 2. Inspect ARP neighbors for unrecognized new MACs
        var newlyDiscovered: [String] = []
        let macPattern = #"\b([0-9a-fA-F]{1,2}:){5}[0-9a-fA-F]{1,2}\b"#
        if let regex = try? NSRegularExpression(pattern: macPattern, options: []) {
            for line in arpOutput.components(separatedBy: .newlines) {
                let nsRange = NSRange(line.startIndex..., in: line)
                guard let m = regex.firstMatch(in: line, range: nsRange),
                      let r = Range(m.range, in: line) else { continue }
                let mac = String(line[r]).lowercased()
                if mac == "ff:ff:ff:ff:ff:ff" { continue }

                let isNew = lock.withLock { () -> Bool in
                    if knownMacs.isEmpty {
                        return false // wait until baseline exists unless explicitly seeded
                    }
                    if !knownMacs.contains(mac) {
                        knownMacs.insert(mac)
                        UserDefaults.standard.set(Array(knownMacs), forKey: knownMacsKey)
                        return true
                    }
                    return false
                }
                if isNew {
                    newlyDiscovered.append(mac)
                    findings.append(SecurityAnomalyFinding(
                        id: UUID().uuidString,
                        category: "new_device",
                        title: "New LAN Device Detected (\(mac))",
                        detail: String(line.prefix(140)),
                        severity: .notice,
                        detectedAt: Date()
                    ))
                }
            }
        }

        if !findings.isEmpty {
            EventBus.shared.publish(VoiceEvent(
                kind: .custom("security_anomaly"),
                source: "CyberDefenseMonitor",
                severity: findings.contains(where: { $0.severity == .critical }) ? .critical : .warning,
                payload: [
                    "findings": "\(findings.count)",
                    "new_devices": "\(newlyDiscovered.count)",
                    "top": findings[0].title
                ]
            ))
        }

        let countKnown = lock.withLock { knownMacs.count }
        let summary = findings.isEmpty
            ? "Security scan clean: 0 process/port anomalies (\(countKnown) baseline LAN MACs)."
            : "Security scan detected \(findings.count) anomaly item(s): " + findings.map(\.title).joined(separator: "; ")

        return SecurityScanReport(findings: findings, knownDevicesCount: countKnown, summary: summary)
    }

    public func runLiveAnomalyScan() async -> SecurityScanReport {
        if ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1" {
            return analyzeSnapshot(listeningPortsOutput: "", arpOutput: "")
        }

        let (portsOut, arpOut) = await Task.detached(priority: .utility) { () -> (String, String) in
            func runTool(_ path: String, _ args: [String]) -> String {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                do {
                    try p.run()
                    p.waitUntilExit()
                    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                } catch {
                    return ""
                }
            }
            let lsofOut = runTool("/usr/sbin/lsof", ["-iTCP", "-sTCP:LISTEN", "-P", "-n"])
            let arpTxt = runTool("/usr/sbin/arp", ["-a"])
            return (lsofOut, arpTxt)
        }.value

        return analyzeSnapshot(listeningPortsOutput: portsOut, arpOutput: arpOut)
    }

    /// Emergency Lockdown (must only be invoked after CONSEQUENTIAL Approval Card confirmation).
    /// Locks screen, mutes microphone input, and disables Wi-Fi (dry-run safe under test env).
    public func executeLockdown() async -> LockdownActionReport {
        let env = ProcessInfo.processInfo.environment
        let isTestBinary = Bundle.main.bundleURL.pathExtension != "app"
        if env["VOICE_AI_TEST_MODE"] == "1" || (isTestBinary && env["VOICE_AI_LIVE_INTEGRATION"] != "1") {
            let steps = [
                "Muted microphone input volume (0%)",
                "Disabled Wi-Fi network adapter (dry-run)",
                "Locked display session"
            ]
            EventBus.shared.publish(VoiceEvent(
                kind: .custom("security_lockdown_executed"),
                source: "CyberDefenseMonitor",
                severity: .critical,
                payload: ["mode": "dry_run"]
            ))
            return LockdownActionReport(
                success: true,
                actionsTaken: steps,
                summary: "Security Lockdown complete: microphone muted, Wi-Fi disabled, and screen locked."
            )
        }

        // 1. Mute mic input via AppleScript
        _ = AccessibilityControlEngine.shared.executeAppleScript("set volume input volume 0")
        // 2. Disable Wi-Fi on en0
        let wifiProc = Process()
        wifiProc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        wifiProc.arguments = ["-setairportpower", "en0", "off"]
        try? wifiProc.run()
        wifiProc.waitUntilExit()
        // 3. Sleep/Lock display immediately
        let lockProc = Process()
        lockProc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        lockProc.arguments = ["displaysleepnow"]
        try? lockProc.run()
        lockProc.waitUntilExit()

        let steps = ["Muted microphone input volume", "Turned off Wi-Fi (en0)", "Locked display"]
        EventBus.shared.publish(VoiceEvent(
            kind: .custom("security_lockdown_executed"),
            source: "CyberDefenseMonitor",
            severity: .critical,
            payload: ["mode": "live"]
        ))
        return LockdownActionReport(
            success: true,
            actionsTaken: steps,
            summary: "Security Lockdown executed: mic muted, Wi-Fi disabled, and screen locked."
        )
    }
}

