import Foundation

public enum ConnectorCategory: String, Codable, Sendable {
    case music = "Music & Media"
    case communication = "Communication"
    case productivity = "Productivity & Notes"
    case developer = "Developer & Code"
    case browser = "Web & Search"
    case aiRelay = "Chatbot Relay"
    case appleSystem = "Apple Ecosystem"
}

public enum VerificationStatus: String, Codable, Sendable {
    case verified = "Verified"
    case ready = "Ready"
    case pendingAuth = "Requires Token"
}

public struct AppConnector: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let category: ConnectorCategory
    public let iconName: String
    public let iconColor: String
    public let status: VerificationStatus
    public let primaryMethod: String // "Official API" | "AppleScript/JXA" | "MCP" | "URL Scheme"
    public let supportedActions: [String]
    public let defaultDeepLinkScheme: String

    public init(
        id: String,
        name: String,
        category: ConnectorCategory,
        iconName: String,
        iconColor: String,
        status: VerificationStatus,
        primaryMethod: String,
        supportedActions: [String],
        defaultDeepLinkScheme: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.iconName = iconName
        self.iconColor = iconColor
        self.status = status
        self.primaryMethod = primaryMethod
        self.supportedActions = supportedActions
        self.defaultDeepLinkScheme = defaultDeepLinkScheme
    }
}

public final class ConnectorRegistry: Sendable {
    public static let shared = ConnectorRegistry()

    // 24 Full Production App Connectors (catalog parity with voiceos.com)
    public let connectors: [AppConnector] = [
        // --- Music & Media ---
        AppConnector(
            id: "spotify",
            name: "Spotify",
            category: .music,
            iconName: "music.note",
            iconColor: "#1DB954",
            status: .verified,
            primaryMethod: "AppleScript / Spotify Web API",
            supportedActions: ["play_playlist", "pause", "resume", "search_track", "current_track"],
            defaultDeepLinkScheme: "spotify:playlist:chill"
        ),
        AppConnector(
            id: "youtube",
            name: "YouTube",
            category: .music,
            iconName: "play.rectangle.fill",
            iconColor: "#FF0000",
            status: .verified,
            primaryMethod: "YouTube Data API v3 / Browser Profile",
            supportedActions: ["search_video", "play_video", "get_channel_stats"],
            defaultDeepLinkScheme: "https://youtube.com/watch?v=demo"
        ),

        // --- Communication ---
        AppConnector(
            id: "gmail",
            name: "Gmail",
            category: .communication,
            iconName: "envelope.fill",
            iconColor: "#EA4335",
            status: .verified,
            primaryMethod: "Gmail REST API (Minimal Scopes)",
            supportedActions: ["draft_email", "list_unread", "search_threads"],
            defaultDeepLinkScheme: "https://mail.google.com/mail/u/0/#inbox"
        ),
        AppConnector(
            id: "outlook",
            name: "Microsoft Outlook",
            category: .communication,
            iconName: "envelope.badge.fill",
            iconColor: "#0078D4",
            status: .verified,
            primaryMethod: "Microsoft Graph REST API",
            supportedActions: ["read_emails", "draft_reply", "calendar_events"],
            defaultDeepLinkScheme: "https://outlook.office.com/mail/drafts"
        ),
        AppConnector(
            id: "slack",
            name: "Slack",
            category: .communication,
            iconName: "number.square.fill",
            iconColor: "#4A154B",
            status: .verified,
            primaryMethod: "Slack Web API (User/Bot Token)",
            supportedActions: ["post_message", "list_channels", "search_messages"],
            defaultDeepLinkScheme: "slack://channel"
        ),
        AppConnector(
            id: "discord",
            name: "Discord",
            category: .communication,
            iconName: "bubble.left.and.bubble.right.fill",
            iconColor: "#5865F2",
            status: .verified,
            primaryMethod: "Discord Bot API",
            supportedActions: ["send_channel_message", "get_status"],
            defaultDeepLinkScheme: "discord://channels"
        ),
        AppConnector(
            id: "x_twitter",
            name: "X / Twitter",
            category: .communication,
            iconName: "message.fill",
            iconColor: "#000000",
            status: .verified,
            primaryMethod: "X API v2 / Browser Profile",
            supportedActions: ["post_tweet", "check_notifications", "search_tweets"],
            defaultDeepLinkScheme: "https://x.com/compose/post"
        ),

        // --- Productivity & Notes ---
        AppConnector(
            id: "apple_notes",
            name: "Apple Notes",
            category: .productivity,
            iconName: "note.text",
            iconColor: "#E4B622",
            status: .verified,
            primaryMethod: "AppleScript & Shortcuts Intents",
            supportedActions: ["create_note", "append_to_note", "search_notes"],
            defaultDeepLinkScheme: "notes://notes"
        ),
        AppConnector(
            id: "notion",
            name: "Notion",
            category: .productivity,
            iconName: "square.grid.3x3.fill",
            iconColor: "#000000",
            status: .verified,
            primaryMethod: "Notion API & MCP Client",
            supportedActions: ["add_page", "query_database", "update_task"],
            defaultDeepLinkScheme: "notion://page"
        ),
        AppConnector(
            id: "obsidian",
            name: "Obsidian",
            category: .productivity,
            iconName: "book.closed.fill",
            iconColor: "#7C3AED",
            status: .verified,
            primaryMethod: "Obsidian Advanced URI / Local Markdown Vault",
            supportedActions: ["create_note", "search_notes", "append_daily_note"],
            defaultDeepLinkScheme: "obsidian://open"
        ),
        AppConnector(
            id: "google_drive",
            name: "Google Drive",
            category: .productivity,
            iconName: "externaldrive.fill",
            iconColor: "#34A853",
            status: .verified,
            primaryMethod: "Google Drive API v3",
            supportedActions: ["search_files", "open_doc", "summarize_file"],
            defaultDeepLinkScheme: "https://drive.google.com"
        ),
        AppConnector(
            id: "canvas_lms",
            name: "Canvas LMS",
            category: .productivity,
            iconName: "graduationcap.fill",
            iconColor: "#E02424",
            status: .verified,
            primaryMethod: "Canvas LMS REST API",
            supportedActions: ["list_assignments", "upcoming_deadlines", "grades_summary"],
            defaultDeepLinkScheme: "https://canvas.instructure.com/calendar"
        ),
        AppConnector(
            id: "google_maps",
            name: "Google Maps",
            category: .browser,
            iconName: "map.fill",
            iconColor: "#4285F4",
            status: .verified,
            primaryMethod: "Google Places API / URL Scheme",
            supportedActions: ["search_places", "directions", "eta_saved_location"],
            defaultDeepLinkScheme: "https://maps.google.com"
        ),

        // --- Developer & Issue Trackers ---
        AppConnector(
            id: "linear",
            name: "Linear",
            category: .developer,
            iconName: "square.stack.3d.up.fill",
            iconColor: "#5E6AD2",
            status: .verified,
            primaryMethod: "Linear GraphQL API / Webhooks",
            supportedActions: ["create_issue", "list_my_issues", "update_cycle"],
            defaultDeepLinkScheme: "https://linear.app/issue"
        ),
        AppConnector(
            id: "jira",
            name: "Jira Software",
            category: .developer,
            iconName: "flowchart.fill",
            iconColor: "#0052CC",
            status: .verified,
            primaryMethod: "Atlassian Jira REST API v3",
            supportedActions: ["create_ticket", "transition_status", "log_work"],
            defaultDeepLinkScheme: "https://atlassian.net/browse"
        ),
        AppConnector(
            id: "github",
            name: "GitHub",
            category: .developer,
            iconName: "chevron.left.forwardslash.chevron.right",
            iconColor: "#24292E",
            status: .verified,
            primaryMethod: "GitHub REST API / gh CLI",
            supportedActions: ["list_prs", "view_issues", "trigger_workflow"],
            defaultDeepLinkScheme: "https://github.com/pulls"
        ),
        AppConnector(
            id: "vscode",
            name: "VS Code",
            category: .developer,
            iconName: "terminal.fill",
            iconColor: "#007ACC",
            status: .verified,
            primaryMethod: "code CLI & Extension URI",
            supportedActions: ["open_project", "jump_to_file", "search_symbols"],
            defaultDeepLinkScheme: "vscode://file"
        ),

        // --- Native Apple Ecosystem ---
        AppConnector(
            id: "apple_mail",
            name: "Apple Mail",
            category: .appleSystem,
            iconName: "envelope.circle.fill",
            iconColor: "#007AFF",
            status: .verified,
            primaryMethod: "AppleScript & Mail App Intents",
            supportedActions: ["create_mail", "check_inbox", "search_messages"],
            defaultDeepLinkScheme: "message://"
        ),
        AppConnector(
            id: "apple_imessage",
            name: "Apple iMessage",
            category: .appleSystem,
            iconName: "message.circle.fill",
            iconColor: "#34C759",
            status: .verified,
            primaryMethod: "Messages App Intents & AppleScript",
            supportedActions: ["send_message", "read_last_message"],
            defaultDeepLinkScheme: "messages://"
        ),
        AppConnector(
            id: "apple_reminders",
            name: "Apple Reminders",
            category: .appleSystem,
            iconName: "list.bullet.circle.fill",
            iconColor: "#FF9500",
            status: .verified,
            primaryMethod: "EventKit & Shortcuts Intents",
            supportedActions: ["add_reminder", "list_today", "complete_reminder"],
            defaultDeepLinkScheme: "x-apple-reminderkit://"
        ),
        AppConnector(
            id: "apple_finder",
            name: "Apple Finder",
            category: .appleSystem,
            iconName: "folder.fill",
            iconColor: "#007AFF",
            status: .verified,
            primaryMethod: "AppleScript & POSIX File System",
            supportedActions: ["reveal_folder", "find_recent_files", "move_file"],
            defaultDeepLinkScheme: "file://"
        ),
        AppConnector(
            id: "apple_calendar",
            name: "Apple Calendar",
            category: .appleSystem,
            iconName: "calendar.circle.fill",
            iconColor: "#FF3B30",
            status: .verified,
            primaryMethod: "EventKit & Calendar Intents",
            supportedActions: ["add_event", "show_schedule", "next_meeting"],
            defaultDeepLinkScheme: "ical://"
        ),

        // --- Browsers & AI ---
        AppConnector(
            id: "browser",
            name: "Safari / Chrome / Arc",
            category: .browser,
            iconName: "safari.fill",
            iconColor: "#007AFF",
            status: .verified,
            primaryMethod: "AppleScript & Background Profile",
            supportedActions: ["open_tab", "search_query", "extract_page_content"],
            defaultDeepLinkScheme: "https://google.com"
        ),
        AppConnector(
            id: "chatgpt_claude_relay",
            name: "ChatGPT & Claude Relay",
            category: .aiRelay,
            iconName: "sparkles",
            iconColor: "#74AA9C",
            status: .verified,
            primaryMethod: "Official API / Isolated Background Browser",
            supportedActions: ["ask_chatgpt", "ask_claude", "stream_answer"],
            defaultDeepLinkScheme: "https://chatgpt.com"
        )
    ]
}
