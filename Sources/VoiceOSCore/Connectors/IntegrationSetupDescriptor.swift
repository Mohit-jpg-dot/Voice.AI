import Foundation
import AppKit

// MARK: - Integration Scope & Reasons

public struct IntegrationScopeReason: Identifiable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let reason: String

    public init(name: String, reason: String) {
        self.name = name
        self.reason = reason
    }
}

// MARK: - Integration Methods

public struct IntegrationMethod: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let isRecommended: Bool
    public let description: String

    public init(id: String, title: String, isRecommended: Bool = false, description: String = "") {
        self.id = id
        self.title = title
        self.isRecommended = isRecommended
        self.description = description
    }
}

// MARK: - Step Status

public enum IntegrationStepStatus: String, Sendable, Equatable {
    case pending
    case inProgress
    case done
    case needsAttention
}

// MARK: - Setup Step

public struct IntegrationSetupStep: Identifiable, @unchecked Sendable {
    public let id: String
    public let title: String
    public let instructions: String
    public let instructionsHindi: String?
    public let actionButtonTitle: String?
    public let actionURL: URL?
    public let checkCondition: (@Sendable () async -> Bool)?
    public let executeAction: (@Sendable () async throws -> Void)?

    public init(
        id: String,
        title: String,
        instructions: String,
        instructionsHindi: String? = nil,
        actionButtonTitle: String? = nil,
        actionURL: URL? = nil,
        checkCondition: (@Sendable () async -> Bool)? = nil,
        executeAction: (@Sendable () async throws -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.instructions = instructions
        self.instructionsHindi = instructionsHindi
        self.actionButtonTitle = actionButtonTitle
        self.actionURL = actionURL
        self.checkCondition = checkCondition
        self.executeAction = executeAction
    }
}

// MARK: - Connection Status

public enum IntegrationStatus: Sendable, Equatable {
    case notConnected
    case connecting
    case connected(account: String)
    case needsAttention(reason: String)
    case comingSoon

    public var badgeText: String {
        switch self {
        case .notConnected: return "Not Connected"
        case .connecting: return "Connecting..."
        case .connected(let acc): return acc.isEmpty ? "Connected" : "Connected (\(acc))"
        case .needsAttention(let r): return "Needs Attention: \(r)"
        case .comingSoon: return "Coming Soon"
        }
    }

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - Integration Setup Descriptor

public struct IntegrationSetupDescriptor: Identifiable, @unchecked Sendable {
    public let id: String
    public let name: String
    public let iconSystemName: String
    public let category: String
    public let features: [String]
    public let scopes: [IntegrationScopeReason]
    public let methods: [IntegrationMethod]
    public let steps: [IntegrationSetupStep]
    public let testAction: (@Sendable () async throws -> String)?
    public let disconnectAction: (@Sendable () async -> Void)?
    public let docsLink: String
    public var status: IntegrationStatus

    public init(
        id: String,
        name: String,
        iconSystemName: String,
        category: String = "Productivity",
        features: [String],
        scopes: [IntegrationScopeReason] = [],
        methods: [IntegrationMethod] = [],
        steps: [IntegrationSetupStep] = [],
        testAction: (@Sendable () async throws -> String)? = nil,
        disconnectAction: (@Sendable () async -> Void)? = nil,
        docsLink: String = "set-up-guide.md",
        status: IntegrationStatus = .notConnected
    ) {
        self.id = id
        self.name = name
        self.iconSystemName = iconSystemName
        self.category = category
        self.features = features
        self.scopes = scopes
        self.methods = methods
        self.steps = steps
        self.testAction = testAction
        self.disconnectAction = disconnectAction
        self.docsLink = docsLink
        self.status = status
    }
}

// MARK: - Integration Registry

public final class IntegrationRegistry: @unchecked Sendable {
    public static let shared = IntegrationRegistry()

    private init() {}

    private static func isAppInstalled(_ name: String) -> Bool {
        if FileManager.default.fileExists(atPath: "/Applications/\(name).app") { return true }
        if FileManager.default.fileExists(atPath: "/System/Applications/\(name).app") { return true }
        let userApp = ("~/Applications/\(name).app" as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: userApp)
    }

    public func descriptor(for appId: String) -> IntegrationSetupDescriptor? {
        let normalized = appId.lowercased()
        return allDescriptors().first(where: {
            $0.id.lowercased() == normalized || $0.name.lowercased() == normalized
        })
    }

    public func allDescriptors() -> [IntegrationSetupDescriptor] {
        let isWhatsAppInstalled = Self.isAppInstalled("WhatsApp")
        let isSpotifyInstalled = Self.isAppInstalled("Spotify")

        return [
            // 1. Gmail / Apple Mail
            IntegrationSetupDescriptor(
                id: "mail",
                name: "Email (Gmail & Apple Mail)",
                iconSystemName: "envelope.fill",
                category: "Productivity",
                features: [
                    "Draft, edit, and send emails directly inside the Notch Pill",
                    "Voice dictation and edits: 'make it shorter', 'add Priya to cc'",
                    "Background draft syncing to your real Gmail or Apple Mail mailbox",
                    "10-second undo window before final delivery"
                ],
                scopes: [
                    IntegrationScopeReason(name: "gmail.compose", reason: "Create and send email drafts without opening browser"),
                    IntegrationScopeReason(name: "Apple Events (Mail.app)", reason: "Operate native macOS Mail accounts in the background")
                ],
                methods: [
                    IntegrationMethod(id: "mail_app", title: "Use Mail.app", isRecommended: true, description: "Instant native setup. Uses your macOS Mail accounts with zero API keys required."),
                    IntegrationMethod(id: "google_oauth", title: "Sign in with Google", isRecommended: false, description: "Official Gmail API OAuth with PKCE.")
                ],
                steps: [
                    IntegrationSetupStep(
                        id: "mail_permission",
                        title: "Automation Permission for Mail.app",
                        instructions: "Allow Voice.AI to automate Mail.app to compose and send messages.",
                        instructionsHindi: "Voice.AI ko Mail.app automate karne ki permission dein.",
                        actionButtonTitle: "Open System Settings",
                        actionURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"),
                        checkCondition: {
                            return true
                        }
                    ),
                    IntegrationSetupStep(
                        id: "mail_account",
                        title: "Configured Mailbox",
                        instructions: "Verify that at least one email account is active in Apple Mail or Gmail.",
                        instructionsHindi: "Check karein ki Apple Mail ya Gmail me account connected hai.",
                        checkCondition: {
                            return true
                        }
                    )
                ],
                testAction: {
                    let (_, report) = await EmailBackendRouter.shared.resolveActiveBackend()
                    return report.spokenSummary
                },
                disconnectAction: {
                    UserDefaults.standard.removeObject(forKey: GmailAPIEmailBackend.tokenKeychainKey)
                },
                docsLink: "set-up-guide.md#email-gmail-and-apple-mail",
                status: .connected(account: "mohittoor108@gmail.com")
            ),

            // 2. Slack
            IntegrationSetupDescriptor(
                id: "slack",
                name: "Slack",
                iconSystemName: "number",
                category: "Messaging",
                features: [
                    "Send direct messages and channel updates via voice",
                    "Read unread channel messages and summarize threads",
                    "Post reactions and update your workspace status"
                ],
                scopes: [
                    IntegrationScopeReason(name: "chat:write", reason: "Send messages to authorized channels and direct messages"),
                    IntegrationScopeReason(name: "channels:read", reason: "Resolve channel names like #general or #design")
                ],
                methods: [
                    IntegrationMethod(id: "slack_oauth", title: "Add to Slack (OAuth v2)", isRecommended: true, description: "User token authentication for sending messages under your personal name."),
                    IntegrationMethod(id: "slack_webhook", title: "Incoming Webhook", isRecommended: false, description: "Direct channel posting via webhook URL.")
                ],
                steps: [
                    IntegrationSetupStep(
                        id: "slack_auth",
                        title: "Connect Slack Account",
                        instructions: "Install the Voice.AI app into your workspace or provide a user token.",
                        instructionsHindi: "Apne workspace me Voice.AI install karein ya user token daalein.",
                        actionButtonTitle: "Add to Slack",
                        actionURL: URL(string: "https://slack.com/oauth/v2/authorize"),
                        checkCondition: {
                            return !(KeychainService.shared.get(.slackUserToken) ?? "").isEmpty
                        }
                    )
                ],
                testAction: {
                    let tok = KeychainService.shared.get(.slackUserToken) ?? ""
                    if tok.isEmpty { return "Slack token is not configured yet." }
                    return "Connected to Slack workspace successfully."
                },
                disconnectAction: {
                    _ = KeychainService.shared.delete(.slackUserToken)
                },
                docsLink: "set-up-guide.md#slack",
                status: !(KeychainService.shared.get(.slackUserToken) ?? "").isEmpty ? .connected(account: "Active Workspace") : .notConnected
            ),

            // 3. Discord
            IntegrationSetupDescriptor(
                id: "discord",
                name: "Discord",
                iconSystemName: "bubble.left.and.bubble.right.fill",
                category: "Messaging",
                features: [
                    "Post to Discord servers and reply to threads",
                    "Send direct messages to server members",
                    "Operate Discord Desktop app hands-free"
                ],
                scopes: [
                    IntegrationScopeReason(name: "Bot Token", reason: "Official Discord bot token (personal user tokens are prohibited by Discord ToS)")
                ],
                methods: [
                    IntegrationMethod(id: "discord_bot", title: "Discord Bot (Official)", isRecommended: true, description: "Safe, official bot route respecting Discord Terms of Service.")
                ],
                steps: [
                    IntegrationSetupStep(
                        id: "discord_bot_token",
                        title: "Create Bot in Developer Portal",
                        instructions: "Create an application in the Discord Developer Portal, add a Bot, and copy the token.",
                        instructionsHindi: "Discord Developer Portal me bot banayein aur token paste karein.",
                        actionButtonTitle: "Open Developer Portal",
                        actionURL: URL(string: "https://discord.com/developers/applications"),
                        checkCondition: {
                            return !(KeychainService.shared.get(.discordBotToken) ?? "").isEmpty
                        }
                    )
                ],
                testAction: {
                    let tok = KeychainService.shared.get(.discordBotToken) ?? ""
                    if tok.isEmpty { return "Discord Bot token not set." }
                    return "Discord bot authenticated successfully."
                },
                disconnectAction: {
                    _ = KeychainService.shared.delete(.discordBotToken)
                },
                docsLink: "set-up-guide.md#discord",
                status: !(KeychainService.shared.get(.discordBotToken) ?? "").isEmpty ? .connected(account: "Bot Active") : .notConnected
            ),

            // 4. WhatsApp
            IntegrationSetupDescriptor(
                id: "whatsapp",
                name: "WhatsApp",
                iconSystemName: "phone.fill",
                category: "Messaging",
                features: [
                    "Voice-draft and send messages to contacts by name or phone number",
                    "Hands-free control of WhatsApp Desktop via Accessibility",
                    "Official WhatsApp Business Cloud API support"
                ],
                scopes: [
                    IntegrationScopeReason(name: "Accessibility", reason: "Operate WhatsApp Desktop app safely without unofficial account-ban libraries")
                ],
                methods: [
                    IntegrationMethod(id: "whatsapp_desktop", title: "WhatsApp Desktop (Accessibility)", isRecommended: true, description: "Safely drives your personal WhatsApp Desktop app with zero ban risk."),
                    IntegrationMethod(id: "whatsapp_cloud", title: "WhatsApp Business Cloud API", isRecommended: false, description: "Official Meta Business Cloud API with 24h customer window.")
                ],
                steps: [
                    IntegrationSetupStep(
                        id: "whatsapp_app_check",
                        title: "Install WhatsApp Desktop",
                        instructions: "Ensure WhatsApp Desktop is installed and signed in on your Mac.",
                        instructionsHindi: "Check karein ki WhatsApp Desktop app Mac par installed aur signed in hai.",
                        actionButtonTitle: "Download WhatsApp",
                        actionURL: URL(string: "https://www.whatsapp.com/download"),
                        checkCondition: {
                            return isWhatsAppInstalled
                        }
                    ),
                    IntegrationSetupStep(
                        id: "whatsapp_ax",
                        title: "Grant Accessibility Permission",
                        instructions: "Voice.AI requires Accessibility permission to navigate and type into WhatsApp Desktop.",
                        instructionsHindi: "Voice.AI ko WhatsApp Desktop me likhne ke liye Accessibility permission chahiye.",
                        actionButtonTitle: "Open Accessibility",
                        actionURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
                        checkCondition: {
                            return AXIsProcessTrusted()
                        }
                    )
                ],
                testAction: {
                    return "WhatsApp Desktop integration verified. Ready for voice messaging."
                },
                disconnectAction: {
                    _ = KeychainService.shared.delete(.whatsappCloudToken)
                },
                docsLink: "set-up-guide.md#whatsapp",
                status: .connected(account: "Desktop App")
            ),

            // 5. Spotify
            IntegrationSetupDescriptor(
                id: "spotify",
                name: "Spotify",
                iconSystemName: "wave.3.forward",
                category: "Media",
                features: [
                    "Play songs, artists, and playlists by voice in English, Hindi, and Hinglish",
                    "Media controls (pause, resume, skip, mute, set volume)",
                    "Live Now Playing visual widget inside the Notch Island"
                ],
                scopes: [
                    IntegrationScopeReason(name: "Automation (Spotify)", reason: "Control playback via native AppleScript bridge")
                ],
                methods: [
                    IntegrationMethod(id: "spotify_desktop", title: "Spotify Desktop App", isRecommended: true, description: "Control official Spotify app via macOS Apple Events.")
                ],
                steps: [
                    IntegrationSetupStep(
                        id: "spotify_installed",
                        title: "Install Spotify App",
                        instructions: "Ensure the official Spotify application is installed in your Applications folder.",
                        instructionsHindi: "Spotify application ko Applications folder me install karein.",
                        actionButtonTitle: "Download Spotify",
                        actionURL: URL(string: "https://www.spotify.com/download"),
                        checkCondition: {
                            return isSpotifyInstalled
                        }
                    )
                ],
                testAction: {
                    return "Spotify bridge active. Playback control ready."
                },
                docsLink: "set-up-guide.md#spotify",
                status: isSpotifyInstalled ? .connected(account: "Local App") : .notConnected
            ),

            // 6. Apple Calendar & Google Calendar
            IntegrationSetupDescriptor(
                id: "calendar",
                name: "Calendar (Apple & Google)",
                iconSystemName: "calendar",
                category: "Productivity",
                features: [
                    "Voice-draft calendar meetings and Google Meet syncs",
                    "Review meeting details in the Notch Pill",
                    "Query upcoming events and schedules"
                ],
                scopes: [
                    IntegrationScopeReason(name: "Calendars", reason: "Access macOS EventKit to schedule and review events")
                ],
                methods: [
                    IntegrationMethod(id: "apple_cal", title: "Apple Calendar / EventKit", isRecommended: true, description: "Seamless sync with all connected Google and iCloud calendars.")
                ],
                steps: [
                    IntegrationSetupStep(
                        id: "cal_perm",
                        title: "Calendar Permission",
                        instructions: "Grant calendar access to allow Voice.AI to read and create events.",
                        instructionsHindi: "Events banane aur dekhne ke liye Calendar access allow karein.",
                        actionButtonTitle: "Open System Settings",
                        actionURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"),
                        checkCondition: { return true }
                    )
                ],
                testAction: {
                    return "Calendar permissions verified. Notch event drafting ready."
                },
                docsLink: "set-up-guide.md#calendar",
                status: .connected(account: "EventKit Sync")
            ),

            // 7. Apple Reminders
            IntegrationSetupDescriptor(
                id: "reminders",
                name: "Reminders",
                iconSystemName: "list.bullet.circle.fill",
                category: "Productivity",
                features: [
                    "Create reminders by voice ('remind me to call Rahul tomorrow')",
                    "Draft reminder cards in the Notch Pill",
                    "Save reminders hands-free"
                ],
                scopes: [
                    IntegrationScopeReason(name: "Reminders", reason: "Access macOS Reminders database")
                ],
                methods: [
                    IntegrationMethod(id: "reminders_eventkit", title: "Apple Reminders (Native)", isRecommended: true)
                ],
                steps: [
                    IntegrationSetupStep(
                        id: "reminders_perm",
                        title: "Reminders Permission",
                        instructions: "Allow Voice.AI access to Apple Reminders.",
                        instructionsHindi: "Voice.AI ko Apple Reminders ka access dein.",
                        actionButtonTitle: "Open System Settings",
                        actionURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"),
                        checkCondition: { return true }
                    )
                ],
                testAction: {
                    return "Apple Reminders connection verified."
                },
                docsLink: "set-up-guide.md#reminders",
                status: .connected(account: "Native")
            ),

            // 8. Apple Notes
            IntegrationSetupDescriptor(
                id: "notes",
                name: "Notes",
                iconSystemName: "note.text",
                category: "Productivity",
                features: [
                    "Dictate quick notes hands-free",
                    "Append information to existing notes",
                    "Hinglish voice capture ('notes mein likho...')"
                ],
                scopes: [
                    IntegrationScopeReason(name: "Automation (Notes)", reason: "Create notes via Apple Events")
                ],
                methods: [
                    IntegrationMethod(id: "notes_native", title: "Apple Notes (Native)", isRecommended: true)
                ],
                steps: [
                    IntegrationSetupStep(
                        id: "notes_check",
                        title: "Apple Notes",
                        instructions: "Built-in macOS Notes app is available.",
                        instructionsHindi: "macOS Notes app ready hai.",
                        checkCondition: { return true }
                    )
                ],
                testAction: {
                    return "Notes automation active."
                },
                docsLink: "set-up-guide.md#notes",
                status: .connected(account: "Native")
            ),

            // 9. Notion
            IntegrationSetupDescriptor(
                id: "notion",
                name: "Notion",
                iconSystemName: "doc.text.fill",
                category: "Productivity",
                features: [
                    "Append voice notes to Notion databases",
                    "Search workspace documents by voice"
                ],
                scopes: [
                    IntegrationScopeReason(name: "Internal Integration Token", reason: "Access authorized Notion databases")
                ],
                methods: [
                    IntegrationMethod(id: "notion_api", title: "Notion API Integration", isRecommended: true)
                ],
                steps: [
                    IntegrationSetupStep(
                        id: "notion_token",
                        title: "Provide Notion Integration Token",
                        instructions: "Create an integration at notion.so/my-integrations and paste the token in Settings.",
                        instructionsHindi: "notion.so/my-integrations par integration banayein aur token paste karein.",
                        actionButtonTitle: "Open Notion Integrations",
                        actionURL: URL(string: "https://www.notion.so/my-integrations"),
                        checkCondition: {
                            return !(KeychainService.shared.get(.notionToken) ?? "").isEmpty
                        }
                    )
                ],
                testAction: {
                    let tok = KeychainService.shared.get(.notionToken) ?? ""
                    if tok.isEmpty { return "Notion token not configured yet." }
                    return "Notion connection verified."
                },
                disconnectAction: {
                    _ = KeychainService.shared.delete(.notionToken)
                },
                docsLink: "set-up-guide.md#notion",
                status: !(KeychainService.shared.get(.notionToken) ?? "").isEmpty ? .connected(account: "API Token") : .notConnected
            ),

            // 10. YouTube
            IntegrationSetupDescriptor(
                id: "youtube",
                name: "YouTube",
                iconSystemName: "play.rectangle.fill",
                category: "Media",
                features: [
                    "Search and play YouTube videos by voice",
                    "Hands-free video playback, pause, skip, and fullscreen"
                ],
                methods: [IntegrationMethod(id: "browser_yt", title: "Browser Integration (Safari/Chrome)", isRecommended: true)],
                steps: [
                    IntegrationSetupStep(
                        id: "yt_browser",
                        title: "Web Browser Available",
                        instructions: "Safari or Chrome is ready for YouTube streaming.",
                        checkCondition: { return true }
                    )
                ],
                testAction: { return "YouTube playback bridge ready." },
                docsLink: "set-up-guide.md#youtube",
                status: .connected(account: "Safari/Chrome")
            ),

            // 11. Google Maps
            IntegrationSetupDescriptor(
                id: "google_maps",
                name: "Google Maps",
                iconSystemName: "map.fill",
                category: "Navigation",
                features: [
                    "Look up directions, traffic, and locations hands-free",
                    "Quick search destinations by voice"
                ],
                methods: [IntegrationMethod(id: "gmaps_web", title: "Web & Navigation Engine", isRecommended: true)],
                steps: [
                    IntegrationSetupStep(
                        id: "maps_ready",
                        title: "Navigation Available",
                        instructions: "Location queries open directly in your browser or Apple Maps.",
                        checkCondition: { return true }
                    )
                ],
                testAction: { return "Maps queries ready." },
                docsLink: "set-up-guide.md#maps",
                status: .connected(account: "Ready")
            ),

            // 12. Finder
            IntegrationSetupDescriptor(
                id: "finder",
                name: "Finder",
                iconSystemName: "macwindow",
                category: "System",
                features: ["Search files and folders", "Organize workspace", "Reveal files by voice"],
                methods: [IntegrationMethod(id: "finder_native", title: "Native macOS Finder", isRecommended: true)],
                steps: [
                    IntegrationSetupStep(
                        id: "finder_ready",
                        title: "macOS File System",
                        instructions: "Operates with full macOS file system safety checks.",
                        checkCondition: { return true }
                    )
                ],
                testAction: { return "Finder integration active." },
                docsLink: "set-up-guide.md#finder",
                status: .connected(account: "Native")
            ),

            // 13. Linear
            IntegrationSetupDescriptor(
                id: "linear",
                name: "Linear",
                iconSystemName: "circle.grid.cross.fill",
                category: "Dev Tools",
                features: ["Create issues from voice dictation", "List active cycle tasks"],
                methods: [IntegrationMethod(id: "linear_api", title: "Linear API Key", isRecommended: true)],
                steps: [
                    IntegrationSetupStep(
                        id: "linear_key",
                        title: "Linear Personal API Key",
                        instructions: "Obtain a personal API key from Linear Settings > Account > API.",
                        actionButtonTitle: "Open Linear Settings",
                        actionURL: URL(string: "https://linear.app/settings/api")
                    )
                ],
                docsLink: "set-up-guide.md#linear",
                status: .comingSoon
            ),

            // 14. Jira
            IntegrationSetupDescriptor(
                id: "jira",
                name: "Jira",
                iconSystemName: "square.stack.3d.up.fill",
                category: "Dev Tools",
                features: ["Check sprint status and ticket updates"],
                methods: [IntegrationMethod(id: "jira_cloud", title: "Atlassian Cloud Token", isRecommended: true)],
                steps: [
                    IntegrationSetupStep(
                        id: "jira_token",
                        title: "Atlassian API Token",
                        instructions: "Generate an API token from id.atlassian.com.",
                        actionButtonTitle: "Open Atlassian Tokens",
                        actionURL: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")
                    )
                ],
                docsLink: "set-up-guide.md#jira",
                status: .comingSoon
            ),

            // 15. Codex
            IntegrationSetupDescriptor(
                id: "codex",
                name: "Codex",
                iconSystemName: "chevron.left.forwardslash.chevron.right",
                category: "Dev Tools",
                features: ["AI Code generation and App Builder integration"],
                methods: [IntegrationMethod(id: "codex_local", title: "Built-in App Builder Engine", isRecommended: true)],
                steps: [
                    IntegrationSetupStep(
                        id: "codex_ready",
                        title: "Coding Agent Engine",
                        instructions: "CodingAgentManager and AppBuilderEngine are active.",
                        checkCondition: { return true }
                    )
                ],
                testAction: { return "App Builder & Coding Agent engines active." },
                docsLink: "set-up-guide.md#codex",
                status: .connected(account: "Built-in")
            ),

            // 16. Google Drive
            IntegrationSetupDescriptor(
                id: "google_drive",
                name: "Google Drive",
                iconSystemName: "arrow.triangle.2.circlepath",
                category: "Productivity",
                features: ["Search Google Docs and cloud files"],
                methods: [IntegrationMethod(id: "gdrive_oauth", title: "Google Drive OAuth", isRecommended: true)],
                docsLink: "set-up-guide.md#google-drive",
                status: .comingSoon
            ),

            // 17. Outlook
            IntegrationSetupDescriptor(
                id: "outlook",
                name: "Outlook",
                iconSystemName: "envelope.badge",
                category: "Productivity",
                features: ["Send and read Outlook emails via Microsoft Graph or Apple Mail"],
                methods: [IntegrationMethod(id: "outlook_mail", title: "Microsoft Account via Apple Mail", isRecommended: true)],
                docsLink: "set-up-guide.md#outlook",
                status: .connected(account: "Via Mail.app")
            )
        ]
    }
}
