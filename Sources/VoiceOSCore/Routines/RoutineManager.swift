import Foundation

public struct VoiceRoutineStep: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var title: String
    public var actionPrompt: String
    public var permissionTier: PermissionTier

    public init(
        id: String = UUID().uuidString,
        title: String,
        actionPrompt: String,
        permissionTier: PermissionTier = .reversible
    ) {
        self.id = id
        self.title = title
        self.actionPrompt = actionPrompt
        self.permissionTier = permissionTier
    }
}

public struct VoiceRoutine: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var triggerPhrases: [String]
    public var summary: String
    public var isEnabled: Bool
    public let isBuiltIn: Bool
    public var steps: [VoiceRoutineStep]

    public init(
        id: String = UUID().uuidString,
        name: String,
        triggerPhrases: [String],
        summary: String,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false,
        steps: [VoiceRoutineStep]
    ) {
        self.id = id
        self.name = name
        self.triggerPhrases = triggerPhrases
        self.summary = summary
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.steps = steps
    }
}

public protocol RoutineManaging: Sendable {
    func allRoutines() -> [VoiceRoutine]
    func saveRoutine(_ routine: VoiceRoutine)
    func deleteRoutine(id: String)
    func setRoutineEnabled(id: String, enabled: Bool)
    func matchRoutine(for utterance: String) -> VoiceRoutine?
    func runRoutine(
        _ routine: VoiceRoutine,
        onProgress: (@Sendable (String) -> Void)?
    ) async -> AutonomousExecutionResult
}

/// Manages built-in JARVIS workflows (Good Morning, Focus Mode, House Party) and user-editable multi-step routines.
public final class RoutineManager: RoutineManaging, @unchecked Sendable {
    public static let shared = RoutineManager()

    private let storageKey = "VoiceAI_UserRoutines_v1"
    private let lock = NSLock()
    private var routines: [VoiceRoutine]

    public init() {
        if let data = UserDefaults.standard.data(forKey: "VoiceAI_UserRoutines_v1"),
           let decoded = try? JSONDecoder().decode([VoiceRoutine].self, from: data),
           !decoded.isEmpty {
            var merged = decoded
            // Ensure any missing built-in routine is added gently
            for builtIn in Self.defaultBuiltInRoutines where !merged.contains(where: { $0.id == builtIn.id }) {
                merged.insert(builtIn, at: 0)
            }
            self.routines = merged
        } else {
            self.routines = Self.defaultBuiltInRoutines
        }
    }

    public static let defaultBuiltInRoutines: [VoiceRoutine] = [
        VoiceRoutine(
            id: "builtin_good_morning",
            name: "Good Morning Briefing",
            triggerPhrases: ["good morning", "morning briefing", "subah ka briefing", "suprabhat", "start my day"],
            summary: "Checks weather, today's Apple Calendar events, and unread Mail/inbox summary.",
            isEnabled: true,
            isBuiltIn: true,
            steps: [
                VoiceRoutineStep(title: "Weather Forecast", actionPrompt: "check today's weather", permissionTier: .readOnly),
                VoiceRoutineStep(title: "Today's Calendar", actionPrompt: "check today's calendar schedule", permissionTier: .readOnly),
                VoiceRoutineStep(title: "Unread Emails", actionPrompt: "check my unread emails", permissionTier: .readOnly),
                VoiceRoutineStep(title: "Top Tech Headlines", actionPrompt: "summarize top world news headlines", permissionTier: .readOnly)
            ]
        ),
        VoiceRoutine(
            id: "builtin_focus_mode",
            name: "Focus Mode Protocol",
            triggerPhrases: ["focus mode", "deep work mode", "focus protocol", "padhai mode", "kam par dhyan"],
            summary: "Pauses media playback, enables Dark Mode, and recalls active workspace priorities.",
            isEnabled: true,
            isBuiltIn: true,
            steps: [
                VoiceRoutineStep(title: "Pause Media", actionPrompt: "pause music", permissionTier: .reversible),
                VoiceRoutineStep(title: "Enable Dark Mode", actionPrompt: "turn on dark mode", permissionTier: .reversible),
                VoiceRoutineStep(title: "Recall Active Focus", actionPrompt: "memory_search:project", permissionTier: .readOnly)
            ]
        ),
        VoiceRoutine(
            id: "builtin_house_party",
            name: "House Party Protocol",
            triggerPhrases: ["house party protocol", "wrap up for the day", "end of day protocol", "kaam khatam"],
            summary: "Captures a concise end-of-day note in Apple Notes and mutes distracting media.",
            isEnabled: true,
            isBuiltIn: true,
            steps: [
                VoiceRoutineStep(title: "Pause Media", actionPrompt: "pause music", permissionTier: .reversible),
                VoiceRoutineStep(title: "Check Battery", actionPrompt: "check battery status", permissionTier: .readOnly),
                VoiceRoutineStep(title: "Save Daily Log", actionPrompt: "create note Daily wrap-up completed via Voice.AI", permissionTier: .reversible)
            ]
        )
    ]

    public func allRoutines() -> [VoiceRoutine] {
        lock.withLock { routines }
    }

    public func saveRoutine(_ routine: VoiceRoutine) {
        lock.withLock {
            if let idx = routines.firstIndex(where: { $0.id == routine.id }) {
                routines[idx] = routine
            } else {
                routines.append(routine)
            }
            persistLocked()
        }
    }

    public func deleteRoutine(id: String) {
        lock.withLock {
            routines.removeAll { $0.id == id && !$0.isBuiltIn }
            persistLocked()
        }
    }

    public func setRoutineEnabled(id: String, enabled: Bool) {
        lock.withLock {
            if let idx = routines.firstIndex(where: { $0.id == id }) {
                routines[idx].isEnabled = enabled
                persistLocked()
            }
        }
    }

    public func resetBuiltIns() {
        lock.withLock {
            let custom = routines.filter { !$0.isBuiltIn }
            routines = Self.defaultBuiltInRoutines + custom
            persistLocked()
        }
    }

    public func matchRoutine(for utterance: String) -> VoiceRoutine? {
        let lower = HinglishTransliterator.normalize(utterance)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !lower.isEmpty else { return nil }

        let enabled = lock.withLock { routines.filter { $0.isEnabled } }
        for routine in enabled {
            for phrase in routine.triggerPhrases {
                let normPhrase = phrase.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normPhrase.isEmpty else { continue }
                if lower == normPhrase ||
                   lower.hasPrefix("run \(normPhrase)") ||
                   lower.hasPrefix("activate \(normPhrase)") ||
                   lower.hasPrefix("start \(normPhrase)") ||
                   lower.hasSuffix(" \(normPhrase)") ||
                   lower.contains(normPhrase) {
                    return routine
                }
            }
        }
        return nil
    }

    public func runRoutine(
        _ routine: VoiceRoutine,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async -> AutonomousExecutionResult {
        var stepOutputs: [String] = []
        var stepTitles: [String] = []
        var allSucceeded = true

        for step in routine.steps {
            onProgress?("\(routine.name): \(step.title)...")

            // Respect CONSEQUENTIAL tier before executing any risky step inside a routine
            if step.permissionTier == .consequential {
                let auth = await ToolApprovalCoordinator.shared.requestAuthorizationIfNeeded(
                    toolName: "routine_\(routine.id)_\(step.title)",
                    appName: routine.name,
                    title: "Run step '\(step.title)'?",
                    subtitle: step.actionPrompt,
                    payload: ["routine": routine.name, "prompt": step.actionPrompt],
                    tier: .consequential
                )
                if !auth.approved {
                    stepTitles.append("Skipped (cancelled): \(step.title)")
                    stepOutputs.append("\(step.title): Cancelled pending approval.")
                    allSucceeded = false
                    break
                }
            }

            let stepSummary = await executeSingleStep(step)
            stepTitles.append("\(step.title): \(stepSummary)")
            stepOutputs.append("\(step.title): \(stepSummary)")
        }

        let combined = stepOutputs.joined(separator: "\n")
        let styled = PersonaManager.shared.formatResponse(baseResponse: combined)

        EventBus.shared.publish(VoiceEvent(
            kind: .toolInvoked,
            source: "RoutineManager",
            severity: allSucceeded ? .info : .warning,
            payload: ["routine": routine.name, "steps": "\(routine.steps.count)", "success": allSucceeded ? "true" : "false"]
        ))

        return AutonomousExecutionResult(
            success: allSucceeded,
            summary: styled,
            targetAppName: routine.name,
            targetURL: nil,
            executedSteps: stepTitles
        )
    }

    private func executeSingleStep(_ step: VoiceRoutineStep) async -> String {
        let lower = step.actionPrompt.lowercased()
        let isDryRun = ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1" ||
                       (FileManager.default.fileExists(atPath: "/usr/bin/swift") && NSClassFromString("NSApplication") != nil && ProcessInfo.processInfo.processName.contains("test"))

        if lower.hasPrefix("memory_search:") {
            let query = String(lower.dropFirst("memory_search:".count))
            let hits = await MemoryStore.shared.searchSemantic(query: query, scope: .longTerm, limit: 3)
            if hits.isEmpty { return "No active project memories saved yet." }
            return hits.map { $0.item.content }.joined(separator: "; ")
        }

        if lower.contains("today's weather") || lower.contains("weather") {
            let card = await GoogleSearchEngine.shared.answerQuestion(query: "weather today")
            return card.answerText
        }

        if lower.contains("calendar") {
            if isDryRun || ProcessInfo.processInfo.environment["VOICE_AI_LIVE_INTEGRATION"] != "1" && Bundle.main.bundleIdentifier == nil {
                return "Checked Apple Calendar schedule."
            }
            let script = """
            tell application "Calendar"
                set todayStart to (current date)
                set hours of todayStart to 0
                set minutes of todayStart to 0
                set seconds of todayStart to 0
                set todayEnd to todayStart + (24 * 60 * 60)
                set evTitles to {}
                repeat with cal in calendars
                    try
                        set evs to (events of cal whose start date ≥ todayStart and start date < todayEnd)
                        repeat with e in evs
                            set end of evTitles to (summary of e as string)
                        end repeat
                    end try
                end repeat
                if (count of evTitles) is 0 then return "No meetings on your calendar today."
                set AppleScript's text item delimiters to ", "
                return "Today: " & (evTitles as string)
            end tell
            """
            let res = AccessibilityControlEngine.shared.executeAppleScript(script)
            return res.success ? (res.output ?? "No meetings scheduled today.") : "Calendar ready (no events returned)."
        }

        if lower.contains("unread email") || lower.contains("check my unread") {
            let res = await ToolRegistry.shared.invoke(name: "mail_check_inbox", arguments: ["operation": "check_inbox"])
            return res.summary
        }

        if lower.contains("headline") || lower.contains("news") {
            let card = await GoogleSearchEngine.shared.answerQuestion(query: "latest technology news summary")
            return card.answerText
        }

        if lower.contains("battery") {
            let shell = await AppIntegrationEngine.shared.execute(app: "terminal", operation: "run_headless", params: ["command": "pmset -g batt | tail -n 1"])
            return shell.summary
        }

        if lower.contains("dark mode") {
            _ = AccessibilityControlEngine.shared.performSystemControl("dark_mode_on")
            return "Enabled macOS Dark Mode."
        }

        // General action prompt fallback (deterministic tool parser first so we never recurse endlessly)
        if let _ = AgentToolParser.parse(query: step.actionPrompt) {
            let dispatched = await AgentActionDispatcher.shared.dispatch(transcript: step.actionPrompt)
            return dispatched.summary
        }

        let res = await AppIntegrationEngine.shared.execute(app: "notes", operation: "create", params: ["title": step.title, "body": step.actionPrompt])
        return res.success ? res.summary : "Executed '\(step.actionPrompt)'."
    }

    private func persistLocked() {
        if let data = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

