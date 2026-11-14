import AppKit
import Foundation

// MARK: - Models & Persisted Settings

public struct AppIntegrationSettings: Codable, Sendable, Equatable {
    public var enabledApps: [String: Bool]
    public var emailClientMode: String // "auto" | "apple_mail" | "gmail"
    public var emailSignature: String
    public var slackWebhookURL: String
    public var discordWebhookURL: String
    public var notionToken: String
    public var notionParentPageId: String
    public var youtubePreferredBrowser: String // "Safari" | "Google Chrome"
    public var notesDefaultFolder: String
    public var terminalOpenWindowByDefault: Bool

    public static let defaultEnabledApps: [String: Bool] = [
        "mail": true,
        "whatsapp": true,
        "slack": true,
        "discord": true,
        "youtube": true,
        "notion": true,
        "notes": true,
        "terminal": true,
        "safari": true,
        "chrome": true,
        "spotify": true,
        "calendar": true,
        "reminders": true,
        "vscode": true
    ]

    public static let `default` = AppIntegrationSettings(
        enabledApps: defaultEnabledApps,
        emailClientMode: "auto",
        emailSignature: "",
        slackWebhookURL: "",
        discordWebhookURL: "",
        notionToken: "",
        notionParentPageId: "",
        youtubePreferredBrowser: "Safari",
        notesDefaultFolder: "Notes",
        terminalOpenWindowByDefault: false
    )
}

public struct IntegrationActionResult: Sendable {
    public let success: Bool
    public let summary: String
    public let appName: String
    public let deepLinkURL: URL?
    public let steps: [String]

    public init(
        success: Bool,
        summary: String,
        appName: String,
        deepLinkURL: URL? = nil,
        steps: [String] = []
    ) {
        self.success = success
        self.summary = summary
        self.appName = appName
        self.deepLinkURL = deepLinkURL
        self.steps = steps
    }
}

/// Unified execution and configuration engine for native & web macOS app integrations:
/// Email (Apple Mail + Gmail), WhatsApp, Slack, Discord, YouTube, Notion, Apple Notes, and Terminal.
public final class AppIntegrationEngine: @unchecked Sendable {
    public static let shared = AppIntegrationEngine()

    private let settingsKey = "VoiceAI_AppIntegrationSettings_v1"
    private let lock = NSLock()
    private var cachedSettings: AppIntegrationSettings

    private init() {
        if let data = UserDefaults.standard.data(forKey: "VoiceAI_AppIntegrationSettings_v1"),
           let decoded = try? JSONDecoder().decode(AppIntegrationSettings.self, from: data) {
            var merged = decoded
            for (k, v) in AppIntegrationSettings.defaultEnabledApps where merged.enabledApps[k] == nil {
                merged.enabledApps[k] = v
            }
            self.cachedSettings = merged
        } else {
            self.cachedSettings = .default
        }
    }

    private var isDryRun: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["VOICE_AI_TEST_MODE"] == "1" { return true }
        if NSApp == nil && env["VOICE_AI_LIVE_INTEGRATION"] != "1" { return true }
        return false
    }

    // MARK: - Settings & Permission Toggles

    public func currentSettings() -> AppIntegrationSettings {
        lock.lock()
        defer { lock.unlock() }
        return cachedSettings
    }

    public func updateSettings(_ transform: (inout AppIntegrationSettings) -> Void) {
        lock.lock()
        transform(&cachedSettings)
        let snapshot = cachedSettings
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    public func canonicalIntegrationId(for rawName: String) -> String {
        let lower = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("mail") || lower.contains("gmail") || lower.contains("outlook") || lower.contains("email") {
            return "mail"
        }
        if lower.contains("whatsapp") || lower.contains("whatapp") { return "whatsapp" }
        if lower.contains("slack") { return "slack" }
        if lower.contains("discord") { return "discord" }
        if lower.contains("youtube") { return "youtube" }
        if lower.contains("notion") { return "notion" }
        if lower.contains("note") { return "notes" }
        if lower.contains("terminal") || lower.contains("shell") { return "terminal" }
        if lower.contains("spotify") { return "spotify" }
        if lower.contains("safari") { return "safari" }
        if lower.contains("chrome") { return "chrome" }
        if lower.contains("calendar") { return "calendar" }
        if lower.contains("reminder") { return "reminders" }
        if lower.contains("code") || lower.contains("vscode") { return "vscode" }
        if lower.contains("timer") { return "timer" }
        if lower.contains("notch") || lower.contains("island") { return "notch" }
        return lower
    }

    public func displayName(for id: String) -> String {
        switch id {
        case "mail": return "Email (Mail / Gmail)"
        case "whatsapp": return "WhatsApp"
        case "slack": return "Slack"
        case "discord": return "Discord"
        case "youtube": return "YouTube"
        case "notion": return "Notion"
        case "notes": return "Apple Notes"
        case "terminal": return "Terminal"
        case "spotify": return "Spotify"
        case "safari": return "Safari"
        case "chrome": return "Google Chrome"
        case "calendar": return "Apple Calendar"
        case "reminders": return "Apple Reminders"
        case "vscode": return "Visual Studio Code"
        default: return id.capitalized
        }
    }

    public func isAppIntegrated(_ rawApp: String) -> Bool {
        let id = canonicalIntegrationId(for: rawApp)
        lock.lock()
        let explicit = cachedSettings.enabledApps[id]
        let settings = cachedSettings
        lock.unlock()
        if let explicit = explicit {
            return explicit
        }
        // By default, only enable 3rd party connectors if credentials exist; local macOS tools default to true
        switch id {
        case "slack":
            let token = KeychainService.shared.get(.slackUserToken) ?? ""
            return !token.isEmpty || !settings.slackWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "discord":
            let token = KeychainService.shared.get(.discordBotToken) ?? ""
            return !token.isEmpty || !settings.discordWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "notion":
            let token = KeychainService.shared.get(.notionToken) ?? ""
            return !token.isEmpty || !settings.notionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }

    public func setAppIntegrated(_ rawApp: String, enabled: Bool) {
        let id = canonicalIntegrationId(for: rawApp)
        updateSettings { settings in
            settings.enabledApps[id] = enabled
        }
    }

    // MARK: - Unified Dispatch Entry Point

    public func execute(
        app rawApp: String,
        operation rawOperation: String,
        params: [String: String] = [:]
    ) async -> IntegrationActionResult {
        let appId = canonicalIntegrationId(for: rawApp)
        let operation = rawOperation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard isAppIntegrated(appId) else {
            let name = displayName(for: appId)
            return IntegrationActionResult(
                success: false,
                summary: "\(name) integration is disabled. Enable it in Apps -> Connected Apps to control \(name) by voice.",
                appName: name,
                steps: ["Blocked: \(name) integration is disabled"]
            )
        }

        switch appId {
        case "mail":
            return await handleEmail(operation: operation, params: params)
        case "whatsapp":
            return await handleWhatsApp(operation: operation, params: params)
        case "slack":
            return await handleSlack(operation: operation, params: params)
        case "discord":
            return await handleDiscord(operation: operation, params: params)
        case "youtube":
            return await handleYouTube(operation: operation, params: params)
        case "notion":
            return await handleNotion(operation: operation, params: params)
        case "notes":
            return await handleNotes(operation: operation, params: params)
        case "terminal":
            return await handleTerminal(operation: operation, params: params)
        case "timer":
            return await handleTimer(operation: operation, params: params)
        case "notch":
            return await handleNotch(operation: operation, params: params)
        default:
            return IntegrationActionResult(
                success: false,
                summary: "Unsupported integration target '\(rawApp)'.",
                appName: rawApp.capitalized
            )
        }
    }

    // MARK: - 1. Email Integration (Apple Mail + Gmail)

    private func handleEmail(operation: String, params: [String: String]) async -> IntegrationActionResult {
        let settings = currentSettings()
        let recipientRaw = (params["recipient"] ?? params["to"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var subject = (params["subject"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var body = (params["body"] ?? params["message"] ?? params["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let query = (params["query"] ?? params["topic"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Check Inbox / Unread / Read Latest / Search
        if operation == "check_inbox" || operation == "unread" || operation == "read" || operation == "read_latest" || operation == "search" {
            if isDryRun {
                return IntegrationActionResult(
                    success: true,
                    summary: operation == "search"
                        ? "Searched inbox for '\(query.isEmpty ? recipientRaw : query)'."
                        : "Checked Apple Mail inbox.",
                    appName: "Apple Mail",
                    deepLinkURL: URL(string: "message://"),
                    steps: ["Queried Mail inbox"]
                )
            }

            if settings.emailClientMode == "gmail" {
                return await readGmailBrowserSummary(searchQuery: query.isEmpty ? recipientRaw : query)
            }

            let filterTerm = escapeAppleScript(query.isEmpty ? recipientRaw : query)
            let readScript = filterTerm.isEmpty ? """
            tell application "Mail"
                try
                    set unreadCnt to unread count of inbox
                    set msgList to messages 1 thru (my minInt(5, count of messages of inbox)) of inbox
                    set outText to "Unread: " & unreadCnt & "||"
                    repeat with m in msgList
                        set s to subject of m
                        set snd to sender of m
                        set snip to ""
                        try
                            set snip to text 1 thru (my minInt(160, length of (content of m as string))) of (content of m as string)
                        end try
                        set outText to outText & snd & " — " & s & ": " & snip & "\\n"
                    end repeat
                    return outText
                on error errMsg
                    return "ERR:" & errMsg
                end try
            end tell
            on minInt(a, b)
                if a < b then return a
                return b
            end minInt
            """ : """
            tell application "Mail"
                try
                    set matched to (messages of inbox whose subject contains "\(filterTerm)" or sender contains "\(filterTerm)")
                    if (count of matched) is 0 then return "NO_MATCH"
                    set outText to ""
                    repeat with i from 1 to (my minInt(5, count of matched))
                        set m to item i of matched
                        set outText to outText & (sender of m) & " — " & (subject of m) & "\\n"
                    end repeat
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

            let res = AccessibilityControlEngine.shared.executeAppleScript(readScript)
            if res.success, let out = res.output, !out.hasPrefix("ERR:"), !out.isEmpty {
                if out == "NO_MATCH" {
                    return IntegrationActionResult(
                        success: true,
                        summary: "No emails matching '\(filterTerm)' found in Apple Mail inbox.",
                        appName: "Apple Mail",
                        deepLinkURL: URL(string: "message://"),
                        steps: ["Searched Apple Mail inbox"]
                    )
                }
                let formatted = out.replacingOccurrences(of: "||", with: " unread. Latest:\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return IntegrationActionResult(
                    success: true,
                    summary: formatted,
                    appName: "Apple Mail",
                    deepLinkURL: URL(string: "message://"),
                    steps: ["Fetched live emails from Apple Mail"]
                )
            }

            if settings.emailClientMode == "auto", let gmailRes = await readGmailBrowserSummaryIfOpen() {
                return gmailRes
            }

            return IntegrationActionResult(
                success: false,
                summary: "Could not read Apple Mail inbox. Make sure an email account is signed in to Mail.app or open Gmail in Safari/Chrome.",
                appName: "Email",
                steps: ["Mail account unavailable or Automation permission needed"]
            )
        }

        // Reply / Reply & Send
        if operation == "reply" || operation == "reply_and_send" {
            let shouldSend = (operation == "reply_and_send")
            if body.isEmpty && !query.isEmpty {
                let composed = await composeEmailWithBrain(recipient: recipientRaw, topic: query, isReply: true)
                body = composed.body
            }
            if !settings.emailSignature.isEmpty && !body.isEmpty {
                body += "\n\n\(settings.emailSignature)"
            }

            if isDryRun {
                return IntegrationActionResult(
                    success: true,
                    summary: shouldSend ? "Sent reply email: \"\(body.prefix(80))\"" : "Drafted email reply: \"\(body.prefix(80))\"",
                    appName: "Apple Mail",
                    deepLinkURL: URL(string: "message://"),
                    steps: [shouldSend ? "Prepared and sent email reply" : "Opened email reply draft"]
                )
            }

            if settings.emailClientMode != "gmail" && hasAppleMailAccounts() {
                let senderFilter = escapeAppleScript(recipientRaw)
                let replyScript = """
                tell application "Mail"
                    activate
                    try
                        set targetMsg to missing value
                        if "\(senderFilter)" is not "" then
                            set hits to (messages of inbox whose sender contains "\(senderFilter)" or subject contains "\(senderFilter)")
                            if (count of hits) > 0 then set targetMsg to item 1 of hits
                        end if
                        if targetMsg is missing value then
                            set sel to selection
                            if (count of sel) > 0 then set targetMsg to item 1 of sel
                        end if
                        if targetMsg is missing value and (count of messages of inbox) > 0 then
                            set targetMsg to message 1 of inbox
                        end if
                        if targetMsg is missing value then return "NO_MESSAGE"
                        set replyMsg to reply targetMsg with opening window
                        return "OPENED"
                    on error errMsg
                        return "ERR:" & errMsg
                    end try
                end tell
                """
                let replyRes = AccessibilityControlEngine.shared.executeAppleScript(replyScript)
                if replyRes.success && replyRes.output == "OPENED" {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    if !body.isEmpty {
                        pasteViaClipboard(body, pressEnter: false)
                        try? await Task.sleep(nanoseconds: 150_000_000)
                    }
                    if shouldSend {
                        _ = AccessibilityControlEngine.shared.simulateKeystroke("Command+Shift+D")
                        return IntegrationActionResult(
                            success: true,
                            summary: "Replied and sent email via Apple Mail.",
                            appName: "Apple Mail",
                            deepLinkURL: URL(string: "message://"),
                            steps: ["Created reply in Apple Mail", "Inserted reply body", "Sent reply (Cmd+Shift+D)"]
                        )
                    }
                    return IntegrationActionResult(
                        success: true,
                        summary: "Opened reply draft in Apple Mail. Say 'send' or review before sending.",
                        appName: "Apple Mail",
                        deepLinkURL: URL(string: "message://"),
                        steps: ["Opened reply window in Apple Mail", "Inserted drafted reply"]
                    )
                }
            }

            // Gmail Web Reply Fallback
            let gmailReplied = await replyInOpenGmailTab(body: body, autoSend: shouldSend)
            if gmailReplied {
                return IntegrationActionResult(
                    success: true,
                    summary: shouldSend ? "Replied and sent email in Gmail." : "Drafted reply in Gmail.",
                    appName: "Gmail",
                    deepLinkURL: URL(string: "https://mail.google.com"),
                    steps: ["Triggered Reply in Gmail", "Populated reply body"]
                )
            }

            return IntegrationActionResult(
                success: false,
                summary: "Could not find an active email to reply to in Apple Mail or an open Gmail tab.",
                appName: "Email",
                steps: ["No target email found for reply"]
            )
        }

        // Compose / Draft / Send New Email
        let shouldSend = (operation == "send")
        if (body.isEmpty || subject.isEmpty) && (!query.isEmpty || !body.isEmpty) {
            let topicSeed = query.isEmpty ? body : query
            if subject.isEmpty || body.isEmpty {
                let composed = await composeEmailWithBrain(recipient: recipientRaw, topic: topicSeed, isReply: false)
                if subject.isEmpty { subject = composed.subject }
                if body.isEmpty { body = composed.body }
            }
        }
        if subject.isEmpty { subject = "Quick Note" }
        if !settings.emailSignature.isEmpty && !body.isEmpty {
            body += "\n\n\(settings.emailSignature)"
        }

        let resolvedAddress = resolveEmailAddress(for: recipientRaw)

        if isDryRun {
            return IntegrationActionResult(
                success: true,
                summary: shouldSend
                    ? "Sent email '\(subject)' to \(resolvedAddress ?? (recipientRaw.isEmpty ? "recipient" : recipientRaw))."
                    : "Drafted email '\(subject)' to \(resolvedAddress ?? (recipientRaw.isEmpty ? "draft" : recipientRaw)).",
                appName: "Apple Mail",
                deepLinkURL: URL(string: "message://"),
                steps: [shouldSend ? "Composed and sent email" : "Created email draft"]
            )
        }

        // In-Pill Email Drafting Path (No external Apple Mail or Gmail browser tabs)
        let toList: [String]
        if let addr = resolvedAddress, !addr.isEmpty {
            toList = [addr]
        } else if !recipientRaw.isEmpty {
            let fallback = recipientRaw.contains("@") ? recipientRaw : "\(recipientRaw.lowercased().replacingOccurrences(of: " ", with: "."))@company.com"
            toList = [fallback]
        } else {
            toList = []
        }

        let draft = VoiceEmailManager.shared.createDraft(
            to: toList,
            subject: subject,
            body: body
        )
        return IntegrationActionResult(
            success: true,
            summary: "Drafted email '\(subject)' in the notch pill.",
            appName: "Mail",
            deepLinkURL: nil,
            steps: ["Created in-pill email draft for \(toList.joined(separator: ", "))"]
        )
    }

    // MARK: - 2. WhatsApp Integration

    private func handleWhatsApp(operation: String, params: [String: String]) async -> IntegrationActionResult {
        let recipient = (params["recipient"] ?? params["contact"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (params["body"] ?? params["message"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let autoSend = (operation == "send")

        if operation == "read" {
            if let wa = MessagingRouter.shared.connector(for: .whatsapp) {
                let unread = (try? await wa.readUnread(limit: 5)) ?? []
                if !unread.isEmpty {
                    let formatted = unread.map { "\($0.senderName): \($0.text)" }.joined(separator: "\n")
                    return IntegrationActionResult(
                        success: true,
                        summary: "WhatsApp messages:\n\(formatted)",
                        appName: "WhatsApp",
                        steps: ["Read unread WhatsApp messages via connector"]
                    )
                }
            }
            let captured = await ScreenVisionService.shared.captureFullScreenWithImage()
            let llm = await AutonomousAgentExecutor.shared.analyzeScreenWithActiveModel(
                pngData: captured.pngData,
                ocrText: captured.analysis.fullText,
                appName: "WhatsApp",
                sourceLabel: "WhatsApp Window",
                question: "Summarize the latest WhatsApp conversation visible on screen."
            )
            return IntegrationActionResult(
                success: true,
                summary: llm?.summary ?? captured.analysis.summary,
                appName: "WhatsApp",
                steps: ["Read active WhatsApp chat"]
            )
        }

        if autoSend && !recipient.isEmpty && !body.isEmpty, let wa = MessagingRouter.shared.connector(for: .whatsapp) {
            do {
                let id = try await wa.sendMessage(target: recipient, text: body, attachments: nil)
                return IntegrationActionResult(
                    success: true,
                    summary: "Sent WhatsApp message to \(recipient): \"\(body)\" (ID: \(id)).",
                    appName: "WhatsApp",
                    steps: ["Sent WhatsApp message via connector"]
                )
            } catch {
                // fall through to deep link
            }
        }

        if isDryRun {
            return IntegrationActionResult(
                success: true,
                summary: autoSend
                    ? "Sent WhatsApp message to \(recipient.isEmpty ? "contact" : recipient): \"\(body)\"."
                    : "Drafted WhatsApp message for \(recipient.isEmpty ? "contact" : recipient): \"\(body)\".",
                appName: "WhatsApp",
                deepLinkURL: URL(string: "whatsapp://"),
                steps: [autoSend ? "Dispatched WhatsApp message" : "Prepared WhatsApp draft"]
            )
        }

        // Phone number fast deep link
        let digitsOnly = recipient.filter { $0.isNumber || $0 == "+" }
        if digitsOnly.count >= 7,
           let encodedText = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let waURL = URL(string: "whatsapp://send?phone=\(digitsOnly)&text=\(encodedText)") {
            NSWorkspace.shared.open(waURL)
            if autoSend {
                try? await Task.sleep(nanoseconds: 900_000_000)
                _ = AccessibilityControlEngine.shared.simulateKeystroke("Return")
            }
            return IntegrationActionResult(
                success: true,
                summary: autoSend ? "Sent WhatsApp message to \(recipient)." : "Opened WhatsApp draft for \(recipient).",
                appName: "WhatsApp",
                deepLinkURL: waURL,
                steps: ["Opened WhatsApp chat for \(recipient)"]
            )
        }

        // Native WhatsApp Desktop navigation + compose
        guard AccessibilityControlEngine.shared.launchApp(named: "WhatsApp") else {
            return IntegrationActionResult(
                success: false,
                summary: "WhatsApp desktop app could not be opened on this Mac.",
                appName: "WhatsApp"
            )
        }
        try? await Task.sleep(nanoseconds: 450_000_000)

        if !recipient.isEmpty && recipient.lowercased() != "contact" {
            _ = AccessibilityControlEngine.shared.simulateKeystroke("Command+F")
            try? await Task.sleep(nanoseconds: 200_000_000)
            _ = AccessibilityControlEngine.shared.simulateKeystroke("Command+A")
            pasteViaClipboard(recipient, pressEnter: false)
            try? await Task.sleep(nanoseconds: 650_000_000)
            _ = AccessibilityControlEngine.shared.simulateKeystroke("Down")
            try? await Task.sleep(nanoseconds: 120_000_000)
            _ = AccessibilityControlEngine.shared.simulateKeystroke("Return")
            try? await Task.sleep(nanoseconds: 350_000_000)
        }

        if !body.isEmpty {
            pasteViaClipboard(body, pressEnter: autoSend)
            return IntegrationActionResult(
                success: true,
                summary: autoSend
                    ? "Sent WhatsApp message to \(recipient.isEmpty ? "chat" : recipient): \"\(body)\"."
                    : "Drafted WhatsApp message for \(recipient.isEmpty ? "chat" : recipient): \"\(body)\".",
                appName: "WhatsApp",
                deepLinkURL: URL(string: "whatsapp://"),
                steps: ["Focused WhatsApp chat", autoSend ? "Pasted & sent message" : "Pasted message draft into composer"]
            )
        }

        return IntegrationActionResult(
            success: true,
            summary: recipient.isEmpty ? "Opened WhatsApp." : "Opened \(recipient)'s chat in WhatsApp.",
            appName: "WhatsApp",
            deepLinkURL: URL(string: "whatsapp://"),
            steps: ["Opened WhatsApp"]
        )
    }

    // MARK: - 3. Slack Integration

    private func handleSlack(operation: String, params: [String: String]) async -> IntegrationActionResult {
        let settings = currentSettings()
        let target = (params["recipient"] ?? params["channel"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (params["body"] ?? params["message"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let autoSend = (operation == "send")

        if operation == "read" {
            if let slack = MessagingRouter.shared.connector(for: .slack) {
                let msgs = target.isEmpty ? (try? await slack.readUnread(limit: 5)) : (try? await slack.readConversation(target: target, limit: 5))
                if let messages = msgs, !messages.isEmpty {
                    let formatted = messages.map { "\($0.senderName): \($0.text)" }.joined(separator: "\n")
                    return IntegrationActionResult(
                        success: true,
                        summary: "Slack messages:\n\(formatted)",
                        appName: "Slack",
                        steps: ["Read Slack messages via connector"]
                    )
                }
            }
            let captured = await ScreenVisionService.shared.captureFullScreenWithImage()
            let llm = await AutonomousAgentExecutor.shared.analyzeScreenWithActiveModel(
                pngData: captured.pngData,
                ocrText: captured.analysis.fullText,
                appName: "Slack",
                sourceLabel: "Slack Window",
                question: "Summarize the active Slack channel or thread visible on screen."
            )
            return IntegrationActionResult(
                success: true,
                summary: llm?.summary ?? captured.analysis.summary,
                appName: "Slack",
                steps: ["Read active Slack channel"]
            )
        }

        if autoSend && !target.isEmpty && !body.isEmpty, let slack = MessagingRouter.shared.connector(for: .slack) {
            do {
                let ts = try await slack.sendMessage(target: target, text: body, attachments: nil)
                return IntegrationActionResult(
                    success: true,
                    summary: "Sent Slack message to \(target): \"\(body)\" (ts: \(ts)).",
                    appName: "Slack",
                    steps: ["Sent message via official Slack Web API"]
                )
            } catch {
                // fall through
            }
        }

        if isDryRun {
            return IntegrationActionResult(
                success: true,
                summary: autoSend
                    ? "Sent Slack message to \(target.isEmpty ? "channel" : target): \"\(body)\"."
                    : "Drafted Slack message for \(target.isEmpty ? "channel" : target): \"\(body)\".",
                appName: "Slack",
                deepLinkURL: URL(string: "slack://"),
                steps: [autoSend ? "Dispatched Slack message" : "Prepared Slack draft"]
            )
        }

        // Optional Webhook API fast-path when sending headless channel message
        if autoSend && !settings.slackWebhookURL.isEmpty && !body.isEmpty,
           let webhookURL = URL(string: settings.slackWebhookURL) {
            let ok = await postJSONWebhook(url: webhookURL, payload: ["text": body])
            if ok {
                return IntegrationActionResult(
                    success: true,
                    summary: "Posted message to Slack via configured webhook: \"\(body)\".",
                    appName: "Slack",
                    deepLinkURL: URL(string: "slack://"),
                    steps: ["Posted message to Slack Incoming Webhook"]
                )
            }
        }

        return await driveQuickSwitcherMessenger(
            appName: "Slack",
            deepLink: "slack://",
            target: target,
            body: body,
            autoSend: autoSend
        )
    }

    // MARK: - 4. Discord Integration

    private func handleDiscord(operation: String, params: [String: String]) async -> IntegrationActionResult {
        let settings = currentSettings()
        let target = (params["recipient"] ?? params["channel"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (params["body"] ?? params["message"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let autoSend = (operation == "send")

        if operation == "read" {
            if let discord = MessagingRouter.shared.connector(for: .discord) {
                let msgs = target.isEmpty ? (try? await discord.readUnread(limit: 5)) : (try? await discord.readConversation(target: target, limit: 5))
                if let messages = msgs, !messages.isEmpty {
                    let formatted = messages.map { "\($0.senderName): \($0.text)" }.joined(separator: "\n")
                    return IntegrationActionResult(
                        success: true,
                        summary: "Discord messages:\n\(formatted)",
                        appName: "Discord",
                        steps: ["Read Discord messages via connector"]
                    )
                }
            }
            let captured = await ScreenVisionService.shared.captureFullScreenWithImage()
            let llm = await AutonomousAgentExecutor.shared.analyzeScreenWithActiveModel(
                pngData: captured.pngData,
                ocrText: captured.analysis.fullText,
                appName: "Discord",
                sourceLabel: "Discord Window",
                question: "Summarize the active Discord channel or messages on screen."
            )
            return IntegrationActionResult(
                success: true,
                summary: llm?.summary ?? captured.analysis.summary,
                appName: "Discord",
                steps: ["Read active Discord channel"]
            )
        }

        if autoSend && !target.isEmpty && !body.isEmpty, let discord = MessagingRouter.shared.connector(for: .discord) {
            do {
                let id = try await discord.sendMessage(target: target, text: body, attachments: nil)
                return IntegrationActionResult(
                    success: true,
                    summary: "Sent Discord message to \(target): \"\(body)\" (ID: \(id)).",
                    appName: "Discord",
                    steps: ["Sent Discord message via connector"]
                )
            } catch {
                // fall through
            }
        }

        if isDryRun {
            return IntegrationActionResult(
                success: true,
                summary: autoSend
                    ? "Sent Discord message to \(target.isEmpty ? "channel" : target): \"\(body)\"."
                    : "Drafted Discord message for \(target.isEmpty ? "channel" : target): \"\(body)\".",
                appName: "Discord",
                deepLinkURL: URL(string: "discord://"),
                steps: [autoSend ? "Dispatched Discord message" : "Prepared Discord draft"]
            )
        }

        if autoSend && !settings.discordWebhookURL.isEmpty && !body.isEmpty,
           let webhookURL = URL(string: settings.discordWebhookURL) {
            let ok = await postJSONWebhook(url: webhookURL, payload: ["content": body])
            if ok {
                return IntegrationActionResult(
                    success: true,
                    summary: "Posted message to Discord via configured webhook: \"\(body)\".",
                    appName: "Discord",
                    deepLinkURL: URL(string: "discord://"),
                    steps: ["Posted message to Discord Webhook"]
                )
            }
        }

        return await driveQuickSwitcherMessenger(
            appName: "Discord",
            deepLink: "discord://",
            target: target,
            body: body,
            autoSend: autoSend
        )
    }

    // MARK: - 5. YouTube Integration

    private func handleYouTube(operation: String, params: [String: String]) async -> IntegrationActionResult {
        let settings = currentSettings()
        let query = (params["query"] ?? params["body"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let browser = (params["browser"] ?? settings.youtubePreferredBrowser)

        if operation == "search" || (operation == "play" && !query.isEmpty) {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let targetURL = URL(string: query.isEmpty ? "https://www.youtube.com" : "https://www.youtube.com/results?search_query=\(encoded)")!
            if !isDryRun {
                openURL(targetURL, inBrowser: browser)
            }
            return IntegrationActionResult(
                success: true,
                summary: query.isEmpty ? "Opened YouTube in \(browser)." : "Searched YouTube for \"\(query)\" in \(browser).",
                appName: "YouTube",
                deepLinkURL: targetURL,
                steps: ["Opened YouTube in \(browser)"]
            )
        }

        if operation == "summarize" || operation == "info" {
            if isDryRun {
                return IntegrationActionResult(
                    success: true,
                    summary: "Inspected current YouTube video tab.",
                    appName: "YouTube",
                    deepLinkURL: URL(string: "https://www.youtube.com"),
                    steps: ["Read YouTube video metadata"]
                )
            }
            let infoJS = "(function(){const t=document.querySelector('h1.ytd-watch-metadata, h1 yt-formatted-string')?.innerText || document.title; const c=document.querySelector('#channel-name a, #owner-name a')?.innerText || ''; const d=document.querySelector('#description-inline-expander, #description')?.innerText?.slice(0,900) || ''; return JSON.stringify({title:t, channel:c, desc:d});})();"
            if let rawInfo = runJSOnDomain("youtube.com", js: infoJS),
               let data = rawInfo.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                let title = json["title"] ?? "YouTube Video"
                let channel = json["channel"] ?? ""
                let desc = json["desc"] ?? ""
                let chatModel = ModelRouter.shared.resolveChatModel()
                if let resp = try? await chatModel.sendMessage(
                    messages: [
                        LLMChatMessage(role: .system, content: "Summarize this YouTube video concisely in 2-3 clear sentences based only on its title, channel, and description."),
                        LLMChatMessage(role: .user, content: "Title: \(title)\nChannel: \(channel)\nDescription: \(desc)")
                    ],
                    tools: nil,
                    jsonMode: false
                ), !resp.text.isEmpty {
                    return IntegrationActionResult(
                        success: true,
                        summary: resp.text,
                        appName: "YouTube",
                        steps: ["Extracted YouTube page metadata", "Summarized via \(chatModel.modelIdentifier)"]
                    )
                }
                return IntegrationActionResult(
                    success: true,
                    summary: "Watching \"\(title)\"\(channel.isEmpty ? "" : " by \(channel)").",
                    appName: "YouTube",
                    steps: ["Extracted YouTube page title & channel"]
                )
            }
        }

        if operation == "close" || operation == "close_tab" {
            if isDryRun {
                return IntegrationActionResult(
                    success: true,
                    summary: "Closed YouTube video tab.",
                    appName: "YouTube",
                    steps: ["Closed YouTube tab"]
                )
            }
            let closed = AccessibilityControlEngine.shared.closeYouTubePlaybackTab()
            return IntegrationActionResult(
                success: closed,
                summary: closed ? "Closed YouTube video tab." : "Could not find an open YouTube tab to close.",
                appName: "YouTube",
                steps: ["Closed YouTube tab"]
            )
        }

        // Player Transport & Actions (play, pause, next, previous, mute, unmute, forward, rewind, fullscreen, like, subscribe)
        let jsAction: String?
        let description: String
        switch operation {
        case "pause", "stop":
            jsAction = "const v=document.querySelector('video'); if(v) v.pause(); 'ok';"
            description = "Paused YouTube video."
        case "play", "resume":
            jsAction = "const v=document.querySelector('video'); if(v) v.play(); 'ok';"
            description = "Resumed YouTube playback."
        case "next":
            jsAction = "const b=document.querySelector('.ytp-next-button'); if(b){b.click(); 'ok';} else 'not_found';"
            description = "Skipped to next YouTube video."
        case "previous":
            jsAction = "window.history.back(); 'ok';"
            description = "Went back to previous YouTube video."
        case "mute":
            jsAction = "const v=document.querySelector('video'); if(v){v.muted=true; 'ok';} else 'not_found';"
            description = "Muted YouTube video."
        case "unmute":
            jsAction = "const v=document.querySelector('video'); if(v){v.muted=false; 'ok';} else 'not_found';"
            description = "Unmuted YouTube video."
        case "forward", "fast_forward":
            jsAction = "const v=document.querySelector('video'); if(v){v.currentTime+=10; 'ok';} else 'not_found';"
            description = "Skipped forward 10 seconds on YouTube."
        case "rewind", "back":
            jsAction = "const v=document.querySelector('video'); if(v){v.currentTime=Math.max(0,v.currentTime-10); 'ok';} else 'not_found';"
            description = "Rewound 10 seconds on YouTube."
        case "fullscreen":
            jsAction = "const b=document.querySelector('.ytp-fullscreen-button'); if(b){b.click(); 'ok';} else 'not_found';"
            description = "Toggled YouTube fullscreen."
        case "like":
            jsAction = "const b=document.querySelector('like-button-view-model button, #segmented-like-button button, button[aria-label*=\"like this video\" i]'); if(b){b.click(); 'ok';} else 'not_found';"
            description = "Liked the current YouTube video."
        case "subscribe":
            jsAction = "const b=document.querySelector('#subscribe-button button, ytd-subscribe-button-renderer button'); if(b){b.click(); 'ok';} else 'not_found';"
            description = "Clicked Subscribe on the current YouTube channel."
        default:
            jsAction = nil
            description = "Opened YouTube in \(browser)."
        }

        if isDryRun {
            return IntegrationActionResult(
                success: true,
                summary: description,
                appName: "YouTube",
                deepLinkURL: URL(string: "https://www.youtube.com"),
                steps: [description]
            )
        }

        if let js = jsAction, let result = runJSOnDomain("youtube.com", js: js), result.contains("ok") {
            NowPlayingMediaManager.shared.pollMediaState()
            return IntegrationActionResult(
                success: true,
                summary: description,
                appName: "YouTube",
                deepLinkURL: URL(string: "https://www.youtube.com"),
                steps: ["Executed \(operation) inside YouTube tab"]
            )
        }

        if operation == "open" || jsAction == nil {
            openURL(URL(string: "https://www.youtube.com")!, inBrowser: browser)
            return IntegrationActionResult(
                success: true,
                summary: "Opened YouTube in \(browser).",
                appName: "YouTube",
                deepLinkURL: URL(string: "https://www.youtube.com"),
                steps: ["Opened YouTube"]
            )
        }

        return IntegrationActionResult(
            success: false,
            summary: "Could not control YouTube playback — open a YouTube video tab in Safari or Google Chrome first.",
            appName: "YouTube"
        )
    }

    // MARK: - 6. Notion Integration

    private func handleNotion(operation: String, params: [String: String]) async -> IntegrationActionResult {
        let settings = currentSettings()
        let title = (params["title"] ?? params["subject"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (params["body"] ?? params["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let query = (params["query"] ?? title).trimmingCharacters(in: .whitespacesAndNewlines)

        if isDryRun {
            return IntegrationActionResult(
                success: true,
                summary: operation == "search"
                    ? "Searched Notion for '\(query)'."
                    : "Created Notion page '\(title.isEmpty ? "Voice Note" : title)'.",
                appName: "Notion",
                deepLinkURL: URL(string: "notion://"),
                steps: ["Executed Notion \(operation)"]
            )
        }

        // Direct Notion API create_page if user configured Notion token + parent page ID
        if (operation == "create_page" || operation == "create") &&
           !settings.notionToken.isEmpty && !settings.notionParentPageId.isEmpty {
            if let pageURL = await createNotionPageViaAPI(
                token: settings.notionToken,
                parentId: settings.notionParentPageId,
                title: title.isEmpty ? "Voice.AI Note" : title,
                body: body
            ) {
                return IntegrationActionResult(
                    success: true,
                    summary: "Created Notion page '\(title.isEmpty ? "Voice.AI Note" : title)' via Notion API.",
                    appName: "Notion",
                    deepLinkURL: pageURL,
                    steps: ["Created Notion page via REST API"]
                )
            }
        }

        guard AccessibilityControlEngine.shared.launchApp(named: "Notion") else {
            openURL(URL(string: "https://www.notion.so")!, inBrowser: settings.youtubePreferredBrowser)
            return IntegrationActionResult(
                success: true,
                summary: "Opened Notion in \(settings.youtubePreferredBrowser).",
                appName: "Notion",
                deepLinkURL: URL(string: "https://www.notion.so"),
                steps: ["Opened Notion web workspace"]
            )
        }
        try? await Task.sleep(nanoseconds: 450_000_000)

        if operation == "search" || operation == "open_page" {
            _ = AccessibilityControlEngine.shared.simulateKeystroke("Command+P")
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !query.isEmpty {
                pasteViaClipboard(query, pressEnter: true)
            }
            return IntegrationActionResult(
                success: true,
                summary: query.isEmpty ? "Opened Notion Quick Find." : "Searched Notion for '\(query)'.",
                appName: "Notion",
                deepLinkURL: URL(string: "notion://"),
                steps: ["Opened Notion Quick Find (Cmd+P)", "Searched '\(query)'"]
            )
        }

        if operation == "append" {
            if !body.isEmpty {
                pasteViaClipboard(body, pressEnter: false)
            }
            return IntegrationActionResult(
                success: true,
                summary: "Inserted content into active Notion page.",
                appName: "Notion",
                deepLinkURL: URL(string: "notion://"),
                steps: ["Focused Notion", "Pasted content into active page"]
            )
        }

        if operation == "create_page" || operation == "create" {
            _ = AccessibilityControlEngine.shared.simulateKeystroke("Command+N")
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !title.isEmpty {
                pasteViaClipboard(title, pressEnter: true)
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
            if !body.isEmpty {
                pasteViaClipboard(body, pressEnter: false)
            }
            return IntegrationActionResult(
                success: true,
                summary: "Created Notion page '\(title.isEmpty ? "Untitled" : title)'.",
                appName: "Notion",
                deepLinkURL: URL(string: "notion://"),
                steps: ["Triggered New Page (Cmd+N)", "Populated page title & body"]
            )
        }

        return IntegrationActionResult(
            success: true,
            summary: "Opened Notion.",
            appName: "Notion",
            deepLinkURL: URL(string: "notion://"),
            steps: ["Activated Notion.app"]
        )
    }

    // MARK: - 7. Apple Notes Integration

    private func handleNotes(operation: String, params: [String: String]) async -> IntegrationActionResult {
        let settings = currentSettings()
        let folder = escapeAppleScript(settings.notesDefaultFolder.isEmpty ? "Notes" : settings.notesDefaultFolder)
        let title = (params["title"] ?? params["subject"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (params["body"] ?? params["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let query = (params["query"] ?? title).trimmingCharacters(in: .whitespacesAndNewlines)

        if isDryRun {
            return IntegrationActionResult(
                success: true,
                summary: operation == "list" || operation == "read"
                    ? "Read notes from Apple Notes."
                    : "Saved note in Apple Notes: \"\(body.isEmpty ? title : body)\".",
                appName: "Apple Notes",
                deepLinkURL: URL(string: "notes://"),
                steps: ["Executed Apple Notes \(operation)"]
            )
        }

        switch operation {
        case "list":
            let script = """
            tell application "Notes"
                set noteNames to {}
                set countLimit to 8
                repeat with n in notes
                    set end of noteNames to (name of n as string)
                    if (count of noteNames) >= countLimit then exit repeat
                end repeat
                set AppleScript's text item delimiters to ", "
                return noteNames as string
            end tell
            """
            let res = AccessibilityControlEngine.shared.executeAppleScript(script)
            let listText = res.output ?? "No notes found."
            return IntegrationActionResult(
                success: res.success,
                summary: res.success ? "Recent Apple Notes: \(listText)" : "Could not list Apple Notes.",
                appName: "Apple Notes",
                deepLinkURL: URL(string: "notes://"),
                steps: ["Listed recent Apple Notes"]
            )

        case "read":
            let escQ = escapeAppleScript(query)
            let script = escQ.isEmpty ? """
            tell application "Notes"
                if (count of notes) > 0 then
                    set n to item 1 of notes
                    return (name of n) & ": " & (plaintext of n)
                end if
                return "NO_NOTE"
            end tell
            """ : """
            tell application "Notes"
                set hits to (notes whose name contains "\(escQ)" or plaintext contains "\(escQ)")
                if (count of hits) > 0 then
                    set n to item 1 of hits
                    return (name of n) & ": " & (plaintext of n)
                end if
                return "NO_NOTE"
            end tell
            """
            let res = AccessibilityControlEngine.shared.executeAppleScript(script)
            if res.success, let out = res.output, out != "NO_NOTE" {
                return IntegrationActionResult(
                    success: true,
                    summary: String(out.prefix(600)),
                    appName: "Apple Notes",
                    deepLinkURL: URL(string: "notes://"),
                    steps: ["Read note from Apple Notes"]
                )
            }
            return IntegrationActionResult(
                success: false,
                summary: "Could not find a matching note in Apple Notes.",
                appName: "Apple Notes"
            )

        case "append":
            let escTitle = escapeAppleScript(title.isEmpty ? query : title)
            let escBody = escapeAppleScript(body.replacingOccurrences(of: "\n", with: "<br>"))
            let script = """
            tell application "Notes"
                activate
                set hits to (notes whose name contains "\(escTitle)")
                if (count of hits) > 0 then
                    set targetNote to item 1 of hits
                    set body of targetNote to (body of targetNote) & "<br>\(escBody)"
                    return "APPENDED:" & (name of targetNote)
                else
                    tell default account
                        make new note at folder "\(folder)" with properties {name:"\(escTitle)", body:"\(escBody)"}
                    end tell
                    return "CREATED:\(escTitle)"
                end if
            end tell
            """
            let res = AccessibilityControlEngine.shared.executeAppleScript(script)
            return IntegrationActionResult(
                success: res.success,
                summary: res.success ? "Updated Apple Note '\(title.isEmpty ? query : title)'." : "Failed to update Apple Note.",
                appName: "Apple Notes",
                deepLinkURL: URL(string: "notes://"),
                steps: ["Appended text to Apple Notes"]
            )

        default: // "create" or "open"
            if body.isEmpty && title.isEmpty {
                _ = AccessibilityControlEngine.shared.launchApp(named: "Notes")
                return IntegrationActionResult(
                    success: true,
                    summary: "Opened Apple Notes.",
                    appName: "Apple Notes",
                    deepLinkURL: URL(string: "notes://"),
                    steps: ["Activated Apple Notes"]
                )
            }
            let effectiveTitle = title.isEmpty ? String(body.prefix(36)) : title
            let effectiveBody = body.isEmpty ? title : body
            let escTitle = escapeAppleScript(effectiveTitle)
            let escBody = escapeAppleScript(effectiveBody.replacingOccurrences(of: "\n", with: "<br>"))
            let script = """
            tell application "Notes"
                tell default account
                    make new note at folder "\(folder)" with properties {name:"\(escTitle)", body:"\(escBody)"}
                end tell
            end tell
            """
            let res = AccessibilityControlEngine.shared.executeAppleScript(script)
            return IntegrationActionResult(
                success: res.success,
                summary: res.success ? "Created note in Apple Notes: \"\(effectiveTitle)\"." : "Could not create note in Apple Notes.",
                appName: "Apple Notes",
                deepLinkURL: URL(string: "notes://"),
                steps: ["Created note in Apple Notes via AppleScript"]
            )
        }
    }

    // MARK: - 8. Terminal Integration

    private func handleTerminal(operation: String, params: [String: String]) async -> IntegrationActionResult {
        let settings = currentSettings()
        let command = (params["command"] ?? params["query"] ?? params["body"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if operation == "read_output" || operation == "read" {
            if isDryRun {
                return IntegrationActionResult(
                    success: true,
                    summary: "Read Terminal window buffer.",
                    appName: "Terminal",
                    steps: ["Read active Terminal tab"]
                )
            }
            let script = """
            tell application "Terminal"
                if (count of windows) > 0 then
                    set txt to contents of selected tab of front window
                    return txt
                end if
                return "NO_WINDOW"
            end tell
            """
            let res = AccessibilityControlEngine.shared.executeAppleScript(script)
            if res.success, let out = res.output, out != "NO_WINDOW" {
                let tail = String(out.suffix(700)).trimmingCharacters(in: .whitespacesAndNewlines)
                return IntegrationActionResult(
                    success: true,
                    summary: tail.isEmpty ? "Terminal buffer is empty." : tail,
                    appName: "Terminal",
                    steps: ["Read front Terminal window output"]
                )
            }
            return IntegrationActionResult(success: false, summary: "No open Terminal window found.", appName: "Terminal")
        }

        if command.isEmpty || operation == "open" {
            if !isDryRun {
                _ = AccessibilityControlEngine.shared.launchApp(named: "Terminal")
            }
            return IntegrationActionResult(
                success: true,
                summary: "Opened Terminal.",
                appName: "Terminal",
                steps: ["Launched Terminal.app"]
            )
        }

        // Destructive command safety check
        let lowerCmd = command.lowercased()
        let dangerous = ["rm -rf", "rm -fr", "sudo ", "mkfs", "dd if=", "shutdown", "reboot", "halt", ":(){", "chmod -r 777 /", "diskutil erase", "> /dev/"]
        if dangerous.contains(where: { lowerCmd.contains($0) }) {
            return IntegrationActionResult(
                success: false,
                summary: "Blocked for safety: destructive shell command '\(command)' requires manual Terminal confirmation.",
                appName: "Terminal",
                steps: ["Safety guardrail blocked destructive command"]
            )
        }

        let useVisibleWindow = (operation == "run_in_window") || (operation != "run_headless" && settings.terminalOpenWindowByDefault)
        if useVisibleWindow {
            if !isDryRun {
                let esc = escapeAppleScript(command)
                let script = """
                tell application "Terminal"
                    activate
                    do script "\(esc)"
                end tell
                """
                _ = AccessibilityControlEngine.shared.executeAppleScript(script)
            }
            return IntegrationActionResult(
                success: true,
                summary: "Running `\(command)` inside Terminal window.",
                appName: "Terminal",
                steps: ["Executed `\(command)` in Terminal.app"]
            )
        }

        if isDryRun {
            return IntegrationActionResult(
                success: true,
                summary: "Ran terminal command `\(command)`.",
                appName: "Terminal",
                steps: ["Executed `\(command)`"]
            )
        }

        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", command]
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let outData = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let snippet = output.isEmpty ? "Finished with exit code \(proc.terminationStatus)." : String(output.prefix(500))
            return IntegrationActionResult(
                success: proc.terminationStatus == 0,
                summary: snippet,
                appName: "Terminal",
                steps: ["Ran `\(command)` (exit \(proc.terminationStatus))"]
            )
        } catch {
            return IntegrationActionResult(
                success: false,
                summary: "Failed to run terminal command: \(error.localizedDescription)",
                appName: "Terminal"
            )
        }
    }

    // MARK: - Shared Helpers (Zero Duplication)

    private func driveQuickSwitcherMessenger(
        appName: String,
        deepLink: String,
        target: String,
        body: String,
        autoSend: Bool
    ) async -> IntegrationActionResult {
        guard AccessibilityControlEngine.shared.launchApp(named: appName) else {
            return IntegrationActionResult(
                success: false,
                summary: "\(appName) is not installed or could not be opened on this Mac.",
                appName: appName
            )
        }
        try? await Task.sleep(nanoseconds: 450_000_000)

        if !target.isEmpty && target.lowercased() != "contact" {
            _ = AccessibilityControlEngine.shared.simulateKeystroke("Command+K")
            try? await Task.sleep(nanoseconds: 250_000_000)
            pasteViaClipboard(target, pressEnter: true)
            try? await Task.sleep(nanoseconds: 450_000_000)
        }

        if !body.isEmpty {
            pasteViaClipboard(body, pressEnter: autoSend)
            return IntegrationActionResult(
                success: true,
                summary: autoSend
                    ? "Sent \(appName) message to \(target.isEmpty ? "channel" : target): \"\(body)\"."
                    : "Drafted \(appName) message for \(target.isEmpty ? "channel" : target): \"\(body)\".",
                appName: appName,
                deepLinkURL: URL(string: deepLink),
                steps: ["Switched \(appName) conversation", autoSend ? "Sent message" : "Prepared draft in composer"]
            )
        }

        return IntegrationActionResult(
            success: true,
            summary: target.isEmpty ? "Opened \(appName)." : "Opened \(target) in \(appName).",
            appName: appName,
            deepLinkURL: URL(string: deepLink),
            steps: ["Opened \(appName)"]
        )
    }

    private func pasteViaClipboard(_ text: String, pressEnter: Bool) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        _ = AccessibilityControlEngine.shared.simulateKeystroke("Command+V")
        if pressEnter {
            usleep(120_000)
            _ = AccessibilityControlEngine.shared.simulateKeystroke("Return")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let prev = previous {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prev, forType: .string)
            }
        }
    }

    private func escapeAppleScript(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func openURL(_ url: URL, inBrowser browser: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", browser, url.absoluteString]
        try? proc.run()
    }

    private func hasAppleMailAccounts() -> Bool {
        let res = AccessibilityControlEngine.shared.executeAppleScript("tell application \"Mail\" to count of accounts")
        if res.success, let countStr = res.output, let count = Int(countStr) {
            return count > 0
        }
        return false
    }

    private func resolveEmailAddress(for recipient: String) -> String? {
        let trimmed = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("@") && trimmed.contains(".") {
            return trimmed
        }
        let esc = escapeAppleScript(trimmed)
        let contactsScript = """
        tell application "Contacts"
            try
                set pList to (every person whose name contains "\(esc)")
                if (count of pList) > 0 then
                    set p to item 1 of pList
                    if (count of emails of p) > 0 then
                        return value of email 1 of p
                    end if
                end if
            end try
        end tell
        return ""
        """
        let res = AccessibilityControlEngine.shared.executeAppleScript(contactsScript)
        if res.success, let email = res.output?.trimmingCharacters(in: .whitespacesAndNewlines), email.contains("@") {
            return email
        }
        return nil
    }

    private func composeEmailWithBrain(recipient: String, topic: String, isReply: Bool) async -> (subject: String, body: String) {
        let chatModel = ModelRouter.shared.resolveChatModel()
        let prompt = """
        Write a concise, clear, natural \(isReply ? "email reply" : "email") on behalf of the user.
        Recipient: \(recipient.isEmpty ? "Colleague" : recipient)
        Instructions/Topic: \(topic)

        Return ONLY valid JSON:
        {"subject": "short clear subject", "body": "clean ready-to-send email body"}
        """
        if let resp = try? await chatModel.sendMessage(
            messages: [
                LLMChatMessage(role: .system, content: "You draft concise, professional emails. Return ONLY valid JSON."),
                LLMChatMessage(role: .user, content: prompt)
            ],
            tools: nil,
            jsonMode: true
        ) {
            var jsonText = resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let s = jsonText.firstIndex(of: "{"), let e = jsonText.lastIndex(of: "}") {
                jsonText = String(jsonText[s...e])
            }
            if let data = jsonText.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                return (dict["subject"] ?? "Follow-up", dict["body"] ?? topic)
            }
        }
        return ("Follow-up", topic)
    }

    private func runJSOnDomain(_ domain: String, js: String) -> String? {
        let escJS = escapeAppleScript(js)
        let chromeScript = """
        tell application "System Events"
            set isChromeRunning to exists (processes where name is "Google Chrome")
        end tell
        if isChromeRunning then
            tell application "Google Chrome"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "\(domain)" then
                            tell t to return (execute javascript "\(escJS)")
                        end if
                    end repeat
                end repeat
            end tell
        end if
        return ""
        """
        let chromeRes = AccessibilityControlEngine.shared.executeAppleScript(chromeScript)
        if chromeRes.success, let out = chromeRes.output, !out.isEmpty {
            return out
        }

        let safariScript = """
        tell application "System Events"
            set isSafariRunning to exists (processes where name is "Safari")
        end tell
        if isSafariRunning then
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "\(domain)" then
                            tell t to return (do JavaScript "\(escJS)" in it)
                        end if
                    end repeat
                end repeat
            end tell
        end if
        return ""
        """
        let safariRes = AccessibilityControlEngine.shared.executeAppleScript(safariScript)
        if safariRes.success, let out = safariRes.output, !out.isEmpty {
            return out
        }
        return nil
    }

    private func readGmailBrowserSummaryIfOpen() async -> IntegrationActionResult? {
        let js = "(function(){const rows=Array.from(document.querySelectorAll('tr.zA')).slice(0,5); if(!rows.length) return ''; return rows.map(r=>{const s=r.querySelector('.yP, .zF')?.innerText||''; const sub=r.querySelector('.bog')?.innerText||''; return s+' — '+sub;}).join('\\n');})();"
        if let out = runJSOnDomain("mail.google.com", js: js), !out.isEmpty {
            return IntegrationActionResult(
                success: true,
                summary: "Latest Gmail messages:\n\(out)",
                appName: "Gmail",
                deepLinkURL: URL(string: "https://mail.google.com"),
                steps: ["Read inbox from open Gmail tab"]
            )
        }
        return nil
    }

    private func readGmailBrowserSummary(searchQuery: String) async -> IntegrationActionResult {
        if let openRes = await readGmailBrowserSummaryIfOpen() {
            return openRes
        }
        let settings = currentSettings()
        let q = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: q.isEmpty ? "https://mail.google.com" : "https://mail.google.com/mail/u/0/#search/\(q)")!
        openURL(url, inBrowser: settings.youtubePreferredBrowser)
        return IntegrationActionResult(
            success: true,
            summary: searchQuery.isEmpty ? "Opened Gmail inbox." : "Searched Gmail for '\(searchQuery)'.",
            appName: "Gmail",
            deepLinkURL: url,
            steps: ["Opened Gmail in \(settings.youtubePreferredBrowser)"]
        )
    }

    private func replyInOpenGmailTab(body: String, autoSend: Bool) async -> Bool {
        let js = """
        (function(){
          const rBtn = document.querySelector('div[aria-label="Reply"][role="button"], span[role="link"].ams.bkH');
          if (rBtn) { rBtn.click(); return 'clicked_reply'; }
          return 'no_reply';
        })();
        """
        guard let res = runJSOnDomain("mail.google.com", js: js), res.contains("clicked_reply") else {
            return false
        }
        try? await Task.sleep(nanoseconds: 450_000_000)
        if !body.isEmpty {
            pasteViaClipboard(body, pressEnter: false)
        }
        if autoSend {
            try? await Task.sleep(nanoseconds: 180_000_000)
            _ = AccessibilityControlEngine.shared.simulateKeystroke("Command+Return")
        }
        return true
    }

    private func postJSONWebhook(url: URL, payload: [String: String]) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 8.0
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    private func createNotionPageViaAPI(token: String, parentId: String, title: String, body: String) async -> URL? {
        guard let url = URL(string: "https://api.notion.com/v1/pages") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var children: [[String: Any]] = []
        if !body.isEmpty {
            children.append([
                "object": "block",
                "type": "paragraph",
                "paragraph": [
                    "rich_text": [["type": "text", "text": ["content": String(body.prefix(1900))]]]
                ]
            ])
        }

        let payload: [String: Any] = [
            "parent": ["page_id": parentId],
            "properties": [
                "title": [
                    "title": [["text": ["content": title]]]
                ]
            ],
            "children": children
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pageUrlStr = obj["url"] as? String else {
            return nil
        }
        return URL(string: pageUrlStr)
    }

    // MARK: - 9. Timer Integration (islandcn preset port)

    private func handleTimer(operation: String, params: [String: String]) async -> IntegrationActionResult {
        switch operation {
        case "start":
            let duration = Double(params["duration"] ?? "600") ?? 600.0
            let label = params["label"] ?? "Timer"
            let timer = await MainActor.run {
                TimerActivityManager.shared.createTimer(durationSeconds: duration, label: label)
            }
            let mins = Int(duration / 60)
            let secs = Int(duration) % 60
            let timeStr = mins > 0 ? "\(mins) minute\(mins == 1 ? "" : "s")" : "\(secs) seconds"
            return IntegrationActionResult(
                success: true,
                summary: "Started a \(timeStr) timer for \(label).",
                appName: "Timer",
                steps: ["Created timer: \(timer.id)"]
            )
        case "pause":
            let ok = await MainActor.run {
                TimerActivityManager.shared.pauseTimer()
            }
            return IntegrationActionResult(
                success: ok,
                summary: ok ? "Timer paused." : "No running timer to pause.",
                appName: "Timer"
            )
        case "resume":
            let ok = await MainActor.run {
                TimerActivityManager.shared.resumeTimer()
            }
            return IntegrationActionResult(
                success: ok,
                summary: ok ? "Timer resumed." : "No paused timer to resume.",
                appName: "Timer"
            )
        case "cancel":
            let ok = await MainActor.run {
                TimerActivityManager.shared.cancelTimer()
            }
            return IntegrationActionResult(
                success: ok,
                summary: ok ? "Timer cancelled." : "No active timer to cancel.",
                appName: "Timer"
            )
        case "remaining":
            let info = await MainActor.run {
                TimerActivityManager.shared.getRemainingTime()
            }
            if let (label, rem) = info {
                let s = Int(rem)
                let timeStr = String(format: "%d:%02d", s / 60, s % 60)
                return IntegrationActionResult(
                    success: true,
                    summary: "\(label) has \(timeStr) remaining.",
                    appName: "Timer"
                )
            } else {
                return IntegrationActionResult(
                    success: false,
                    summary: "No timer is currently running.",
                    appName: "Timer"
                )
            }
        default:
            return IntegrationActionResult(success: false, summary: "Unknown timer action '\(operation)'.", appName: "Timer")
        }
    }

    // MARK: - 10. Notch Island Integration

    private func handleNotch(operation: String, params: [String: String]) async -> IntegrationActionResult {
        switch operation {
        case "what_is_running":
            let summary = await MainActor.run { () -> String in
                let acts = ActivityCenter.shared.activities
                if acts.isEmpty {
                    return "The notch is currently idle with no active activities."
                }
                let names = acts.map { $0.label }.joined(separator: ", ")
                return "The notch currently has: \(names)."
            }
            return IntegrationActionResult(success: true, summary: summary, appName: "Notch")

        case "dismiss":
            await MainActor.run {
                ActivityCenter.shared.collapse()
            }
            return IntegrationActionResult(success: true, summary: "Dismissed.", appName: "Notch")

        case "show_battery":
            let summary = await MainActor.run { () -> String in
                BatteryActivityMonitor.shared.triggerManualBatteryDisplay()
                return BatteryActivityMonitor.shared.getVoiceBatterySummary()
            }
            return IntegrationActionResult(success: true, summary: summary, appName: "Notch")

        case "stop_recording":
            await MainActor.run {
                RecordingActivityBridge.shared.stopRecording()
            }
            return IntegrationActionResult(success: true, summary: "Stopped recording.", appName: "Notch")

        case "mute_alerts":
            await MainActor.run {
                ActivityCenter.shared.isDNDActive = true
            }
            return IntegrationActionResult(success: true, summary: "Notch alerts muted.", appName: "Notch")

        case "show_previews":
            await MainActor.run {
                ActivityCenter.shared.showSensitivePreviewsInNotch = true
            }
            return IntegrationActionResult(success: true, summary: "Message previews will be shown in the notch.", appName: "Notch")

        case "hide_previews":
            await MainActor.run {
                ActivityCenter.shared.showSensitivePreviewsInNotch = false
            }
            return IntegrationActionResult(success: true, summary: "Message previews are now hidden in the compact notch.", appName: "Notch")

        default:
            return IntegrationActionResult(success: false, summary: "Unknown notch action '\(operation)'.", appName: "Notch")
        }
    }
}

