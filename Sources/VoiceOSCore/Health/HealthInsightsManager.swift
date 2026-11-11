import Foundation

public enum HealthMetricKind: String, Codable, Sendable, CaseIterable {
    case steps = "steps"
    case heartRate = "heart_rate"
    case restingHeartRate = "resting_heart_rate"
    case sleepHours = "sleep_hours"
    case activeCalories = "active_calories"
}

public struct HealthSampleRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let metric: HealthMetricKind
    public let value: Double
    public let unit: String
    public let recordedAt: Date

    public init(
        id: String = UUID().uuidString,
        metric: HealthMetricKind,
        value: Double,
        unit: String,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.metric = metric
        self.value = value
        self.unit = unit
        self.recordedAt = recordedAt
    }
}

public struct HealthReminder: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let scheduleText: String
    public var isEnabled: Bool

    public init(id: String = UUID().uuidString, title: String, scheduleText: String, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.scheduleText = scheduleText
        self.isEnabled = isEnabled
    }
}

public struct HealthTrendWarning: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let severity: VoiceEventSeverity
}

public struct HealthDailyDigest: Sendable, Equatable {
    public let isOptedIn: Bool
    public let totalSteps: Int
    public let avgHeartRateBPM: Double?
    public let avgRestingHeartRateBPM: Double?
    public let avgSleepHours: Double?
    public let activeCalories: Int
    public let trendWarnings: [HealthTrendWarning]
    public let summaryText: String
}

public protocol HealthInsightsManaging: Sendable {
    func isOptedIn() -> Bool
    func setOptedIn(_ enabled: Bool)
    func importAppleHealthXML(_ xmlString: String) -> Int
    func importSamples(_ records: [HealthSampleRecord]) -> Int
    func addReminder(title: String, scheduleText: String) -> HealthReminder
    func allReminders() -> [HealthReminder]
    func computeDigest() -> HealthDailyDigest
}

/// Strictly opt-in, 100% on-device Apple Health & wearables analyzer supporting XML exports,
/// wellness reminders, and automated trend warnings.
public final class HealthInsightsManager: HealthInsightsManaging, @unchecked Sendable {
    public static let shared = HealthInsightsManager()

    private let lock = NSLock()
    private let optInKey = "VoiceAI_HealthOptIn_v1"
    private let storageURL: URL
    private var optedIn: Bool
    private var samples: [HealthSampleRecord] = []
    private var reminders: [HealthReminder] = []

    private struct PersistedState: Codable {
        var samples: [HealthSampleRecord]
        var reminders: [HealthReminder]
    }

    public init(storageURL: URL? = nil, loadPersisted: Bool = true) {
        if let customURL = storageURL {
            self.storageURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.storageURL = appSupport
                .appendingPathComponent("VoiceAI", isDirectory: true)
                .appendingPathComponent("health_optin_v1.json")
        }

        self.optedIn = loadPersisted ? UserDefaults.standard.bool(forKey: "VoiceAI_HealthOptIn_v1") : false
        if loadPersisted {
            loadFromDisk()
        }
    }

    public func isOptedIn() -> Bool {
        lock.withLock { optedIn }
    }

    public func setOptedIn(_ enabled: Bool) {
        lock.withLock {
            optedIn = enabled
            UserDefaults.standard.set(enabled, forKey: optInKey)
        }
    }

    public func clearAllData() {
        lock.withLock {
            samples.removeAll()
            reminders.removeAll()
            try? FileManager.default.removeItem(at: storageURL)
        }
    }

    @discardableResult
    public func importSamples(_ records: [HealthSampleRecord]) -> Int {
        guard isOptedIn() else { return 0 }
        lock.withLock {
            samples.append(contentsOf: records)
            if samples.count > 2000 {
                samples = Array(samples.suffix(2000))
            }
            saveToDiskLocked()
        }
        return records.count
    }

    @discardableResult
    public func importAppleHealthXML(_ xmlString: String) -> Int {
        guard isOptedIn(), !xmlString.isEmpty else { return 0 }
        let parsed = Self.parseAppleHealthXML(xmlString)
        guard !parsed.isEmpty else { return 0 }
        return importSamples(parsed)
    }

    public func importFromFileURL(_ fileURL: URL) -> Int {
        guard isOptedIn(), let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return 0 }
        if fileURL.pathExtension.lowercased() == "xml" {
            return importAppleHealthXML(raw)
        }
        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([HealthSampleRecord].self, from: data) {
            return importSamples(decoded)
        }
        return 0
    }

    public func addReminder(title: String, scheduleText: String) -> HealthReminder {
        let item = HealthReminder(title: title, scheduleText: scheduleText, isEnabled: true)
        lock.withLock {
            reminders.append(item)
            saveToDiskLocked()
        }
        return item
    }

    public func allReminders() -> [HealthReminder] {
        lock.withLock { reminders }
    }

    public func computeDigest() -> HealthDailyDigest {
        let (isEnabled, currentSamples) = lock.withLock { (optedIn, samples) }
        guard isEnabled else {
            return HealthDailyDigest(
                isOptedIn: false,
                totalSteps: 0,
                avgHeartRateBPM: nil,
                avgRestingHeartRateBPM: nil,
                avgSleepHours: nil,
                activeCalories: 0,
                trendWarnings: [],
                summaryText: "Apple Health insights are opt-in and currently disabled for your privacy. Enable Health Import in Settings → Proactive & Home."
            )
        }

        guard !currentSamples.isEmpty else {
            return HealthDailyDigest(
                isOptedIn: true,
                totalSteps: 0,
                avgHeartRateBPM: nil,
                avgRestingHeartRateBPM: nil,
                avgSleepHours: nil,
                activeCalories: 0,
                trendWarnings: [],
                summaryText: "Apple Health is enabled, with 0 samples imported yet. Import your export.xml file in Settings."
            )
        }

        let steps = Int(currentSamples.filter { $0.metric == .steps }.map(\.value).reduce(0, +))
        let calories = Int(currentSamples.filter { $0.metric == .activeCalories }.map(\.value).reduce(0, +))
        let hrList = currentSamples.filter { $0.metric == .heartRate }.map(\.value)
        let rhrList = currentSamples.filter { $0.metric == .restingHeartRate }.map(\.value)
        let sleepList = currentSamples.filter { $0.metric == .sleepHours }.map(\.value)

        let avgHR = hrList.isEmpty ? nil : (hrList.reduce(0, +) / Double(hrList.count))
        let avgRHR = rhrList.isEmpty ? nil : (rhrList.reduce(0, +) / Double(rhrList.count))
        let avgSleep = sleepList.isEmpty ? nil : (sleepList.reduce(0, +) / Double(sleepList.count))

        var warnings: [HealthTrendWarning] = []
        if let rhr = avgRHR, rhr >= 85 {
            warnings.append(HealthTrendWarning(
                id: "warn_rhr_elevated",
                title: "Elevated Resting Heart Rate",
                detail: "Average resting HR is \(Int(rhr)) bpm (above 85 bpm threshold). Consider rest and hydration.",
                severity: .warning
            ))
        }
        if let sleep = avgSleep, sleep < 6.0 {
            warnings.append(HealthTrendWarning(
                id: "warn_sleep_deficit",
                title: "Sleep Deficit Trend",
                detail: String(format: "Average sleep is %.1f hrs (< 6.0 hrs target).", sleep),
                severity: .notice
            ))
        }
        let stepRecords = currentSamples.filter { $0.metric == .steps }
        if stepRecords.count >= 4 {
            let earlier = stepRecords.prefix(stepRecords.count / 2).map(\.value)
            let recent = stepRecords.suffix(stepRecords.count / 2).map(\.value)
            let earlierAvg = earlier.reduce(0, +) / Double(earlier.count)
            let recentAvg = recent.reduce(0, +) / Double(recent.count)
            if earlierAvg > 0 && recentAvg < earlierAvg * 0.65 {
                let dropPct = Int(((earlierAvg - recentAvg) / earlierAvg) * 100)
                warnings.append(HealthTrendWarning(
                    id: "warn_activity_drop",
                    title: "Activity Drop Detected (-\(dropPct)%)",
                    detail: "Recent step trend dropped by \(dropPct)% compared to your earlier baseline.",
                    severity: .notice
                ))
            }
        }

        var parts = ["Steps: \(steps)"]
        if let hr = avgHR { parts.append("Avg HR: \(Int(hr)) bpm") }
        if let rhr = avgRHR { parts.append("Resting HR: \(Int(rhr)) bpm") }
        if let sleep = avgSleep { parts.append(String(format: "Sleep: %.1f hrs", sleep)) }
        if calories > 0 { parts.append("Active Energy: \(calories) kcal") }
        let warnLine = warnings.isEmpty ? "No negative trends." : "Warnings: " + warnings.map(\.title).joined(separator: ", ")

        return HealthDailyDigest(
            isOptedIn: true,
            totalSteps: steps,
            avgHeartRateBPM: avgHR,
            avgRestingHeartRateBPM: avgRHR,
            avgSleepHours: avgSleep,
            activeCalories: calories,
            trendWarnings: warnings,
            summaryText: "On-Device Health Summary — \(parts.joined(separator: " • ")). \(warnLine)"
        )
    }

    public static func parseAppleHealthXML(_ xml: String) -> [HealthSampleRecord] {
        var parsed: [HealthSampleRecord] = []
        let pattern = #"<Record[^>]*type="([^"]+)"[^>]*value="([0-9]+(?:\.[0-9]+)?)"[^>]*/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsRange = NSRange(xml.startIndex..., in: xml)

        let dateRegex = try? NSRegularExpression(pattern: #"startDate="([^"]+)""#, options: [])
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        for match in regex.matches(in: xml, options: [], range: nsRange).prefix(2000) {
            guard match.numberOfRanges >= 3,
                  let typeRange = Range(match.range(at: 1), in: xml),
                  let valRange = Range(match.range(at: 2), in: xml),
                  let val = Double(xml[valRange]) else { continue }
            let hkType = String(xml[typeRange])

            let metric: HealthMetricKind?
            let unit: String
            switch hkType {
            case "HKQuantityTypeIdentifierStepCount":
                metric = .steps; unit = "count"
            case "HKQuantityTypeIdentifierHeartRate":
                metric = .heartRate; unit = "bpm"
            case "HKQuantityTypeIdentifierRestingHeartRate":
                metric = .restingHeartRate; unit = "bpm"
            case "HKQuantityTypeIdentifierActiveEnergyBurned":
                metric = .activeCalories; unit = "kcal"
            case "HKCategoryTypeIdentifierSleepAnalysis", "HKQuantityTypeIdentifierAppleSleepingHours":
                metric = .sleepHours; unit = "hr"
            default:
                metric = nil; unit = ""
            }
            guard let resolvedMetric = metric else { continue }

            var recorded = Date()
            if let fullRange = Range(match.range(at: 0), in: xml) {
                let tagStr = String(xml[fullRange])
                if let dm = dateRegex?.firstMatch(in: tagStr, range: NSRange(tagStr.startIndex..., in: tagStr)),
                   let dr = Range(dm.range(at: 1), in: tagStr),
                   let dt = fmt.date(from: String(tagStr[dr])) {
                    recorded = dt
                }
            }
            parsed.append(HealthSampleRecord(metric: resolvedMetric, value: val, unit: unit, recordedAt: recorded))
        }
        return parsed
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        lock.withLock {
            self.samples = state.samples
            self.reminders = state.reminders
        }
    }

    private func saveToDiskLocked() {
        let dir = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(PersistedState(samples: samples, reminders: reminders)) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }
}

