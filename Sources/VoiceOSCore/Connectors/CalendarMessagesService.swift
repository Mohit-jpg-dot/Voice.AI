import AppKit
import Foundation

public struct CalendarEventItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let startTime: Date
    public let endTime: Date
    public let calendarName: String

    public init(
        id: String = UUID().uuidString,
        title: String,
        startTime: Date,
        endTime: Date,
        calendarName: String = "Calendar"
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.calendarName = calendarName
    }
}

public struct MessageThreadPreview: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let sender: String
    public let preview: String
    public let channel: String // "iMessage" | "WhatsApp" | "Mail"

    public init(id: String = UUID().uuidString, sender: String, preview: String, channel: String) {
        self.id = id
        self.sender = sender
        self.preview = SecretRedactor.redact(preview)
        self.channel = channel
    }
}

public protocol CommunicationAndCalendarManaging: Sendable {
    func readCalendarEvents(range: String) async -> [CalendarEventItem]
    func detectCalendarConflicts(_ events: [CalendarEventItem]) -> [(CalendarEventItem, CalendarEventItem)]
    func summarizeCalendar(range: String) async -> String
    func createCalendarEvent(title: String, startsInMinutes: Int, durationMinutes: Int) async -> IntegrationActionResult
    func summarizeRecentEmails(query: String) async -> String
    func readMessages(contactFilter: String) async -> (threads: [MessageThreadPreview], summary: String)
    func draftMessage(recipient: String, body: String) async -> IntegrationActionResult
    func sendMessage(recipient: String, body: String) async -> IntegrationActionResult
}

/// Unified Phase 2 Calendar, Email Summarization, and Apple Messages / iMessage workflow manager.
/// Sending external messages/emails requires CONSEQUENTIAL tier approval via ToolRegistry / ToolApprovalCoordinator.
public final class CalendarMessagesService: CommunicationAndCalendarManaging, @unchecked Sendable {
    public static let shared = CalendarMessagesService()

    private let lock = NSLock()
    private var injectedTestEvents: [CalendarEventItem]?
    private var injectedTestMessages: [MessageThreadPreview]?

    public init() {}

    public func setTestEvents(_ events: [CalendarEventItem]?) {
        lock.withLock { injectedTestEvents = events }
    }

    // MARK: - Event / Meeting / Reminder Drafts

    private var activeEventDraft: CalendarEventDraft?

    public func focusedEventDraft() -> CalendarEventDraft? {
        lock.withLock { activeEventDraft }
    }

    public func createEventDraft(
        title: String,
        type: EventDraftType = .googleMeet,
        dateString: String = "Thursday",
        timeString: String = "2:00 – 2:30 PM",
        participants: [String] = [],
        platform: String = "Google Meet",
        notes: String? = nil,
        isReminder: Bool = false,
        startsInMinutes: Int = 60,
        durationMinutes: Int = 30
    ) -> CalendarEventDraft {
        let draft = CalendarEventDraft(
            title: title.isEmpty ? "New Event" : title,
            type: type,
            dateString: dateString,
            timeString: timeString,
            participants: participants,
            platform: platform,
            notes: notes,
            isReminder: isReminder,
            startsInMinutes: startsInMinutes,
            durationMinutes: durationMinutes
        )
        lock.withLock { activeEventDraft = draft }

        EventBus.shared.publish(VoiceEvent(
            kind: .calendarDraftCreated,
            source: "CalendarMessagesService",
            payload: [
                "draft_id": draft.id,
                "title": draft.title,
                "type": draft.type.rawValue,
                "date_string": draft.dateString,
                "time_string": draft.timeString,
                "participants": draft.participants.joined(separator: ", "),
                "platform": draft.platform,
                "is_reminder": draft.isReminder ? "true" : "false"
            ]
        ))

        return draft
    }

    public func clearEventDraft() {
        lock.withLock { activeEventDraft = nil }
    }

    public func saveDraft(_ draft: CalendarEventDraft) async -> IntegrationActionResult {
        let cleanTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = cleanTitle.isEmpty ? (draft.isReminder ? "Reminder" : "Event") : cleanTitle

        if isDryRun {
            lock.withLock { activeEventDraft = nil }
            return IntegrationActionResult(
                success: true,
                summary: draft.isReminder
                    ? "Added reminder: '\(effectiveTitle)' for \(draft.dateString) at \(draft.timeString)."
                    : "Scheduled \(draft.type == .googleMeet ? "Google Meet" : "event"): '\(effectiveTitle)' on \(draft.dateString) from \(draft.timeString).",
                appName: draft.isReminder ? "Apple Reminders" : (draft.type == .googleMeet ? "Google Meet" : "Apple Calendar"),
                steps: [draft.isReminder ? "Saved reminder in Reminders" : "Created event in Calendar"]
            )
        }

        if draft.isReminder || draft.type == .reminder {
            let escaped = effectiveTitle.replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Reminders"
                activate
                tell default list
                    make new reminder with properties {name:"\(escaped)"}
                end tell
            end tell
            """
            let res = AccessibilityControlEngine.shared.executeAppleScript(script)
            lock.withLock { activeEventDraft = nil }
            return IntegrationActionResult(
                success: res.success,
                summary: res.success ? "Added reminder: \"\(effectiveTitle)\"" : "Could not add reminder: \(res.output ?? "Permission error")",
                appName: "Apple Reminders",
                steps: res.success ? ["Saved reminder in Reminders"] : ["Reminder error"]
            )
        } else {
            let escaped = effectiveTitle.replacingOccurrences(of: "\"", with: "\\\"")
            let meetNotes = draft.type == .googleMeet ? "\nVideo Call: Google Meet (https://meet.google.com/new)" : ""
            let combinedNotes = ((draft.notes ?? "") + meetNotes).trimmingCharacters(in: .whitespacesAndNewlines)
            let escapedNotes = combinedNotes.replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Calendar"
                activate
                set startDt to (current date) + (\(max(0, draft.startsInMinutes)) * minutes)
                set endDt to startDt + (\(max(5, draft.durationMinutes)) * minutes)
                tell (first calendar)
                    make new event at end with properties {summary:"\(escaped)", description:"\(escapedNotes)", start date:startDt, end date:endDt}
                end tell
            end tell
            """
            let res = AccessibilityControlEngine.shared.executeAppleScript(script)
            lock.withLock { activeEventDraft = nil }
            let appLabel = draft.type == .googleMeet ? "Google Meet" : "Apple Calendar"
            return IntegrationActionResult(
                success: res.success,
                summary: res.success ? "Scheduled \(appLabel): '\(effectiveTitle)' for \(draft.dateString) at \(draft.timeString)." : "Could not schedule event: \(res.output ?? "Permission needed").",
                appName: appLabel,
                steps: res.success ? ["Created \(appLabel) entry '\(effectiveTitle)'"] : ["Calendar AppleScript error"]
            )
        }
    }

    public func setTestMessages(_ messages: [MessageThreadPreview]?) {
        lock.withLock { injectedTestMessages = messages }
    }

    private var isDryRun: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["VOICE_AI_TEST_MODE"] == "1" { return true }
        if NSApp == nil && env["VOICE_AI_LIVE_INTEGRATION"] != "1" { return true }
        return false
    }

    // MARK: - Calendar

    public func readCalendarEvents(range: String = "today") async -> [CalendarEventItem] {
        if let mocked = lock.withLock({ injectedTestEvents }) {
            let conflicts = detectCalendarConflicts(mocked)
            if let first = conflicts.first {
                EventBus.shared.publish(VoiceEvent(
                    kind: .calendarUpcoming,
                    source: "CalendarMessagesService",
                    severity: .notice,
                    payload: [
                        "conflict": "true",
                        "events": "'\(first.0.title)' overlaps with '\(first.1.title)'"
                    ]
                ))
            }
            return mocked
        }

        if isDryRun {
            let now = Date()
            return [
                CalendarEventItem(title: "Engineering Standup", startTime: now.addingTimeInterval(1800), endTime: now.addingTimeInterval(3600), calendarName: "Work"),
                CalendarEventItem(title: "Design Review", startTime: now.addingTimeInterval(7200), endTime: now.addingTimeInterval(10800), calendarName: "Work")
            ]
        }

        let script = """
        set outLines to ""
        set nowDate to (current date)
        set startDay to nowDate - (time of nowDate)
        set endDay to startDay + (24 * 60 * 60)
        tell application "Calendar"
            repeat with cal in calendars
                try
                    set evs to (events of cal whose start date ≥ startDay and start date ≤ endDay)
                    repeat with ev in evs
                        set outLines to outLines & (name of cal) & "||" & (summary of ev) & "||" & ((start date of ev) as string) & "\\n"
                    end repeat
                end try
            end repeat
        end tell
        return outLines
        """
        let res = AccessibilityControlEngine.shared.executeAppleScript(script)
        guard res.success, let out = res.output, !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let lines = out.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var parsed: [CalendarEventItem] = []
        let base = Date()
        for (idx, line) in lines.enumerated() {
            let parts = line.components(separatedBy: "||")
            let calName = parts.first ?? "Calendar"
            let title = parts.count > 1 ? parts[1] : line
            let st = base.addingTimeInterval(Double(idx) * 3600)
            parsed.append(CalendarEventItem(title: title, startTime: st, endTime: st.addingTimeInterval(1800), calendarName: calName))
        }
        return parsed
    }

    public func detectCalendarConflicts(_ events: [CalendarEventItem]) -> [(CalendarEventItem, CalendarEventItem)] {
        let sorted = events.sorted { $0.startTime < $1.startTime }
        var conflicts: [(CalendarEventItem, CalendarEventItem)] = []
        for i in 0..<sorted.count {
            for j in (i + 1)..<sorted.count {
                if sorted[j].startTime < sorted[i].endTime {
                    conflicts.append((sorted[i], sorted[j]))
                }
            }
        }
        return conflicts
    }

    public func summarizeCalendar(range: String = "today") async -> String {
        let events = await readCalendarEvents(range: range)
        guard !events.isEmpty else {
            return "Your \(range) calendar is clear with no scheduled events."
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let lines = events.prefix(6).map { ev in
            "• \(formatter.string(from: ev.startTime))–\(formatter.string(from: ev.endTime)): \(ev.title) (\(ev.calendarName))"
        }
        let conflicts = detectCalendarConflicts(events)
        let conflictNote = conflicts.isEmpty
            ? ""
            : "\nNotice: \(conflicts.count) schedule conflict(s) detected (\(conflicts[0].0.title) vs \(conflicts[0].1.title))."
        return "Calendar (\(events.count) event(s)):\n" + lines.joined(separator: "\n") + conflictNote
    }

    public func createCalendarEvent(
        title: String,
        startsInMinutes: Int = 60,
        durationMinutes: Int = 30
    ) async -> IntegrationActionResult {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            return IntegrationActionResult(success: false, summary: "Please provide a title for the calendar event.", appName: "Apple Calendar")
        }

        if isDryRun {
            return IntegrationActionResult(
                success: true,
                summary: "Scheduled '\(cleanTitle)' for \(durationMinutes) minutes on your calendar.",
                appName: "Apple Calendar",
                steps: ["Created calendar event '\(cleanTitle)'"]
            )
        }

        let escaped = cleanTitle.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Calendar"
            activate
            set startDt to (current date) + (\(max(0, startsInMinutes)) * minutes)
            set endDt to startDt + (\(max(5, durationMinutes)) * minutes)
            tell (first calendar)
                make new event at end with properties {summary:"\(escaped)", start date:startDt, end date:endDt}
            end tell
        end tell
        """
        let res = AccessibilityControlEngine.shared.executeAppleScript(script)
        return IntegrationActionResult(
            success: res.success,
            summary: res.success ? "Created calendar event '\(cleanTitle)'." : "Could not create calendar event: \(res.output ?? "Permission needed").",
            appName: "Apple Calendar",
            steps: res.success ? ["Added '\(cleanTitle)' to Apple Calendar"] : ["Calendar AppleScript error"]
        )
    }

    // MARK: - Email Summary

    public func summarizeRecentEmails(query: String = "") async -> String {
        let inboxRes = await AppIntegrationEngine.shared.execute(
            app: "mail",
            operation: query.isEmpty ? "check_inbox" : "search",
            params: query.isEmpty ? [:] : ["query": query]
        )
        return "Email Digest: \(inboxRes.summary)"
    }

    // MARK: - Messages (Apple Messages + Unified Summary)

    public func readMessages(contactFilter: String = "") async -> (threads: [MessageThreadPreview], summary: String) {
        if let mocked = lock.withLock({ injectedTestMessages }) {
            let filtered = contactFilter.isEmpty
                ? mocked
                : mocked.filter { $0.sender.lowercased().contains(contactFilter.lowercased()) }
            let summary = filtered.isEmpty
                ? "No recent messages matching '\(contactFilter)'."
                : "Messages (\(filtered.count)): " + filtered.prefix(4).map { "\($0.sender): \($0.preview)" }.joined(separator: " | ")
            return (filtered, summary)
        }

        if isDryRun {
            let sample = [
                MessageThreadPreview(sender: "Team Lead", preview: "Please share the Phase 2 build status when ready.", channel: "iMessage")
            ]
            let filtered = contactFilter.isEmpty
                ? sample
                : sample.filter { $0.sender.lowercased().contains(contactFilter.lowercased()) }
            return (filtered, "Recent Messages: Team Lead — Please share the Phase 2 build status when ready.")
        }

        let filterTerm = contactFilter.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Messages"
            try
                set chatList to chats 1 thru (my minInt(5, count of chats))
                set outText to ""
                repeat with c in chatList
                    set chatName to name of c
                    if "\(filterTerm)" is "" or chatName contains "\(filterTerm)" then
                        set outText to outText & chatName & "||Active thread\\n"
                    end if
                end repeat
                if outText is "" then return "EMPTY"
                return outText
            on error errMsg
                return "ERR:" & errMsg
            end try
        end tell
        on minInt(a, b)
            if a < b then return a
            return b
        end minInt
        """
        let res = AccessibilityControlEngine.shared.executeAppleScript(script)
        if res.success, let out = res.output, !out.hasPrefix("ERR:"), out != "EMPTY" {
            let rows = out.components(separatedBy: .newlines).filter { !$0.isEmpty }
            let threads = rows.map { row -> MessageThreadPreview in
                let parts = row.components(separatedBy: "||")
                return MessageThreadPreview(sender: parts.first ?? "Contact", preview: parts.count > 1 ? parts[1] : "Active conversation", channel: "iMessage")
            }
            let summary = "Messages threads: " + threads.map(\.sender).joined(separator: ", ")
            return (threads, summary)
        }

        _ = AccessibilityControlEngine.shared.launchApp(named: "Messages")
        return ([], "Opened Apple Messages.")
    }

    public func draftMessage(recipient: String, body: String) async -> IntegrationActionResult {
        let safeBody = SecretRedactor.redact(body).trimmingCharacters(in: .whitespacesAndNewlines)
        let target = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            return IntegrationActionResult(success: false, summary: "Please specify a recipient for the message draft.", appName: "Messages")
        }
        if isDryRun {
            return IntegrationActionResult(
                success: true,
                summary: "Drafted message to \(target): \"\(safeBody)\". Ready for review before sending.",
                appName: "Messages",
                steps: ["Prepared message draft for \(target)"]
            )
        }

        var comps = URLComponents()
        comps.scheme = "imessage"
        if !safeBody.isEmpty {
            comps.queryItems = [URLQueryItem(name: "body", value: safeBody)]
        }
        _ = AccessibilityControlEngine.shared.launchApp(named: "Messages")
        return IntegrationActionResult(
            success: true,
            summary: "Opened draft message for \(target) in Messages.",
            appName: "Messages",
            deepLinkURL: comps.url,
            steps: ["Focused Apple Messages draft for \(target)"]
        )
    }

    public func sendMessage(recipient: String, body: String) async -> IntegrationActionResult {
        let target = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeBody = SecretRedactor.redact(body).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !safeBody.isEmpty else {
            return IntegrationActionResult(success: false, summary: "Both recipient and message text are required to send.", appName: "Messages")
        }

        if isDryRun {
            return IntegrationActionResult(
                success: true,
                summary: "Sent message to \(target): \"\(safeBody)\".",
                appName: "Messages",
                steps: ["Approved & sent message to \(target)"]
            )
        }

        let escTarget = target.replacingOccurrences(of: "\"", with: "\\\"")
        let escBody = safeBody.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Messages"
            set targetService to 1st account whose service type = iMessage
            set targetBuddy to participant "\(escTarget)" of targetService
            send "\(escBody)" to targetBuddy
        end tell
        """
        let res = AccessibilityControlEngine.shared.executeAppleScript(script)
        return IntegrationActionResult(
            success: res.success,
            summary: res.success ? "Sent message to \(target)." : "Failed to send message via Apple Messages: \(res.output ?? "Check contact handle").",
            appName: "Messages",
            steps: res.success ? ["Dispatched message to \(target)"] : ["Messages send failed"]
        )
    }
}
