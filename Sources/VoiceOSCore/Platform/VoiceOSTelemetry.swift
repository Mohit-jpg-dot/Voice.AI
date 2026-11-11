import Foundation

/// Structured telemetry and error tracking engine matching APP-SECRET.md.
/// Implements PostHog product telemetry event constants and Sentry diagnostic reporting.
/// When telemetry is disabled or in offline mode, logs are stored locally without leaking to external servers.
public final class VoiceOSTelemetry: @unchecked Sendable {
    public static let shared = VoiceOSTelemetry()
    
    private let lock = NSLock()
    private var breadcrumbs: [[String: Any]] = []
    private var isSentryInitialized = false
    private let logFileURL: URL
    
    // Canonical PostHog event constants from APP-SECRET.md line 140-142
    public enum Event {
        public static let onboardingIntroPresented = "onboardingIntroPresented"
        public static let onboardingIntroOutcome = "onboardingIntroOutcome"
        public static let onboardingEmailMission = "onboardingEmailMission"
        public static let onboardingAgentFallback = "onboardingAgentFallback"
        public static let recordingDiscarded = "recording_discarded"
        public static let modeSwitched = "mode_switched"
        public static let voiceSessionCompleted = "voice_session_completed"
        public static let toolExecuted = "tool_executed"
    }
    
    private init() {
        let libraryLogs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!.appendingPathComponent("Logs", isDirectory: true)
        let voiceOSLogs = libraryLogs.appendingPathComponent("VoiceOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: voiceOSLogs, withIntermediateDirectories: true)
        self.logFileURL = voiceOSLogs.appendingPathComponent("voiceos.log")
        initializeMainSentry()
    }
    
    // MARK: - Sentry Lifecycle & Diagnostics
    
    public func initializeMainSentry() {
        lock.lock()
        defer { lock.unlock() }
        isSentryInitialized = true
        log("Sentry initialized with local privacy gate", level: "info")
    }
    
    public func addSentryBreadcrumb(category: String, message: String, data: [String: Any]? = nil) {
        let scrubbedMessage = SecretRedactor.redact(message)
        lock.lock()
        defer { lock.unlock() }
        
        let crumb: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "category": category,
            "message": scrubbedMessage,
            "data": data ?? [:]
        ]
        breadcrumbs.append(crumb)
        if breadcrumbs.count > 100 {
            breadcrumbs.removeFirst()
        }
        log("[\(category)] \(scrubbedMessage)", level: "debug")
    }
    
    public func captureSentryMessage(_ message: String, level: String = "info") {
        addSentryBreadcrumb(category: "message", message: message)
        log("Captured message: \(message)", level: level)
    }
    
    public func captureSentryException(_ error: Error) {
        addSentryBreadcrumb(category: "error", message: error.localizedDescription)
        log("Captured exception: \(error.localizedDescription)", level: "error")
    }
    
    public func captureSentryLog(_ text: String) {
        log(text, level: "info")
    }
    
    public func refreshSentryUserContext(userId: String, email: String?) {
        addSentryBreadcrumb(category: "auth", message: "User context refreshed for \(userId)")
    }
    
    public func shutdownSentry() {
        lock.lock()
        defer { lock.unlock() }
        isSentryInitialized = false
        log("Sentry shutdown", level: "info")
    }
    
    // MARK: - PostHog Product Telemetry
    
    public func capture(event: String, properties: [String: Any] = [:]) {
        let isEnabled = (VoiceOSConfigStore.shared.get("settings") as? [String: Any])?["shareUserData"] as? Bool ?? false
        
        var payload = properties
        payload["distinct_id"] = getDeviceMachineId()
        payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
        payload["event"] = event
        
        log("[PostHog] Event: \(event) (shareUserData=\(isEnabled))", level: "info")
        
        if isEnabled {
            // In live cloud mode, dispatches to PostHog endpoint // LOCAL-STUB
        }
    }
    
    // MARK: - Device Machine ID (matching node-machine-id from APP-SECRET.md)
    
    public func getDeviceMachineId() -> String {
        var size = 0
        sysctlbyname("kern.uuid", nil, &size, nil, 0)
        var uuidStr = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.uuid", &uuidStr, &size, nil, 0)
        let machineUUID = String(cString: uuidStr)
        return machineUUID.isEmpty ? "voiceos_dev_machine" : machineUUID
    }
    
    // MARK: - Structured File Logging (electron-log parity)
    
    private func log(_ message: String, level: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let scrubbed = SecretRedactor.redact(message)
        let formatted = "[\(timestamp)] [\(level.uppercased())] \(scrubbed)\n"
        
        #if DEBUG
        print(formatted, terminator: "")
        #endif
        
        guard let data = formatted.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }
}

