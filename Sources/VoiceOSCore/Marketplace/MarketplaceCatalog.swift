import Foundation

public final class MarketplaceCatalog: Sendable {
    public static let shared = MarketplaceCatalog()

    // 10 Real Integration Manifests
    public let manifests: [IntegrationManifest] = [
        IntegrationManifest(
            id: "linear",
            name: "Linear",
            publisher: "Linear Orbit, Inc.",
            version: "2.4.0",
            icon: "📐",
            summary: "Create issues, update project cycles, and assign tasks via voice.",
            categories: [.productivity, .developer],
            authType: .oauth2,
            permissionsRequired: [
                PermissionScope(scope: "read:issues", justification: "View assigned and team sprint tasks"),
                PermissionScope(scope: "write:issues", justification: "Create and update issues from spoken requests")
            ],
            actions: [
                ManifestAction(id: "create_issue", name: "Create Issue", description: "Create a new Linear issue", riskLevel: .reversible, parameters: ["title": "String", "team": "String"]),
                ManifestAction(id: "list_my_issues", name: "List My Issues", description: "Fetch issues assigned to me", riskLevel: .readOnly)
            ],
            verificationBadge: .verifiedByVoiceAI,
            deepLinkTemplate: "https://linear.app/issue/{id}",
            platformSupport: [.macOS, .windows, .web]
        ),
        IntegrationManifest(
            id: "spotify",
            name: "Spotify",
            publisher: "Spotify AB",
            version: "1.8.2",
            icon: "🎵",
            summary: "Play songs, search playlists, and control audio playback in background.",
            categories: [.musicAndMedia],
            authType: .oauth2,
            permissionsRequired: [
                PermissionScope(scope: "user-modify-playback-state", justification: "Change tracks and resume playback"),
                PermissionScope(scope: "user-read-playback-state", justification: "Read currently playing track title")
            ],
            actions: [
                ManifestAction(id: "play_playlist", name: "Play Playlist", description: "Start playback of a named playlist", riskLevel: .reversible, parameters: ["query": "String"]),
                ManifestAction(id: "pause", name: "Pause Playback", description: "Pause currently playing media", riskLevel: .reversible)
            ],
            verificationBadge: .verifiedByVoiceAI,
            deepLinkTemplate: "spotify:playlist:{id}",
            platformSupport: [.macOS, .windows, .web]
        ),
        IntegrationManifest(
            id: "slack",
            name: "Slack",
            publisher: "Slack Technologies",
            version: "4.1.0",
            icon: "💬",
            summary: "Post status messages, notify channels, and read unread mentions.",
            categories: [.communication],
            authType: .oauth2,
            permissionsRequired: [
                PermissionScope(scope: "chat:write", justification: "Send message to specified channel"),
                PermissionScope(scope: "channels:history", justification: "Check recent mentions")
            ],
            actions: [
                ManifestAction(id: "send_message", name: "Send Message", description: "Post message to channel or direct user", riskLevel: .consequential, parameters: ["channel": "String", "message": "String"]),
                ManifestAction(id: "set_status", name: "Set Status", description: "Update your Slack presence and status emoji", riskLevel: .reversible, parameters: ["text": "String", "emoji": "String"])
            ],
            verificationBadge: .verifiedByVoiceAI,
            deepLinkTemplate: "slack://channel?team={team}&id={channel}",
            platformSupport: [.macOS, .windows, .web]
        ),
        IntegrationManifest(
            id: "github",
            name: "GitHub",
            publisher: "GitHub, Inc.",
            version: "3.2.1",
            icon: "🐙",
            summary: "Inspect pull requests, review workflow runs, and check open notifications.",
            categories: [.developer],
            authType: .oauth2,
            permissionsRequired: [
                PermissionScope(scope: "repo:read", justification: "Fetch open pull requests and issues")
            ],
            actions: [
                ManifestAction(id: "list_prs", name: "List Pull Requests", description: "List open PRs awaiting review", riskLevel: .readOnly, parameters: ["repo": "String"]),
                ManifestAction(id: "merge_pr", name: "Merge Pull Request", description: "Merge an approved pull request", riskLevel: .consequential, parameters: ["pr_number": "Int"])
            ],
            verificationBadge: .verifiedByVoiceAI,
            deepLinkTemplate: "https://github.com/{repo}/pull/{pr}",
            platformSupport: [.macOS, .windows, .web]
        ),
        IntegrationManifest(
            id: "notion",
            name: "Notion",
            publisher: "Notion Labs",
            version: "2.1.0",
            icon: "📓",
            summary: "Create pages, capture quick notes into databases, and query workspace blocks.",
            categories: [.productivity, .notesAndKnowledge],
            authType: .oauth2,
            permissionsRequired: [
                PermissionScope(scope: "pages:create", justification: "Add newly transcribed notes to target database")
            ],
            actions: [
                ManifestAction(id: "append_note", name: "Append Note", description: "Add content to daily journal page", riskLevel: .reversible, parameters: ["content": "String"])
            ],
            verificationBadge: .verifiedByVoiceAI,
            deepLinkTemplate: "https://notion.so/{pageId}",
            platformSupport: [.macOS, .windows, .web]
        ),
        IntegrationManifest(
            id: "youtube",
            name: "YouTube Studio",
            publisher: "Google LLC",
            version: "1.5.0",
            icon: "▶",
            summary: "Look up video analytics, subscriber growth, and channel comments.",
            categories: [.musicAndMedia],
            authType: .oauth2,
            permissionsRequired: [
                PermissionScope(scope: "youtube.readonly", justification: "Read channel view stats and subscriber counts")
            ],
            actions: [
                ManifestAction(id: "get_stats", name: "Get Channel Stats", description: "Returns latest video analytics", riskLevel: .readOnly)
            ],
            verificationBadge: .verifiedByVoiceAI,
            deepLinkTemplate: "https://studio.youtube.com/channel/{channelId}",
            platformSupport: [.macOS, .windows, .web]
        ),
        IntegrationManifest(
            id: "vscode",
            name: "VS Code",
            publisher: "Microsoft",
            version: "1.92.0",
            icon: "💻",
            summary: "Open files, run workspace tasks, and jump to definition without mouse navigation.",
            categories: [.developer],
            authType: .appIntent,
            permissionsRequired: [
                PermissionScope(scope: "local:cli", justification: "Execute code binary commands in active project")
            ],
            actions: [
                ManifestAction(id: "open_file", name: "Open File", description: "Open file at line number", riskLevel: .readOnly, parameters: ["path": "String", "line": "Int"])
            ],
            verificationBadge: .verifiedByVoiceAI,
            deepLinkTemplate: "vscode://file/{path}:{line}",
            platformSupport: [.macOS, .windows]
        ),
        IntegrationManifest(
            id: "jira",
            name: "Jira Software",
            publisher: "Atlassian",
            version: "3.0.0",
            icon: "🔷",
            summary: "Log sprint story points, transition tickets, and comment on bug reports.",
            categories: [.productivity, .developer],
            authType: .oauth2,
            permissionsRequired: [
                PermissionScope(scope: "read:jira-work", justification: "Inspect assigned sprint tickets"),
                PermissionScope(scope: "write:jira-work", justification: "Update ticket status and add worklog")
            ],
            actions: [
                ManifestAction(id: "transition_ticket", name: "Transition Ticket", description: "Move ticket to In Review or Done", riskLevel: .consequential, parameters: ["key": "String", "status": "String"])
            ],
            verificationBadge: .verifiedByVoiceAI,
            deepLinkTemplate: "https://atlassian.net/browse/{key}",
            platformSupport: [.macOS, .windows, .web]
        ),
        IntegrationManifest(
            id: "discord",
            name: "Discord",
            publisher: "Discord Inc.",
            version: "2.1.4",
            icon: "🎮",
            summary: "Send voice-to-text messages to gaming guild channels and listen to soundboards.",
            categories: [.communication],
            authType: .oauth2,
            permissionsRequired: [
                PermissionScope(scope: "messages.write", justification: "Send message to authorized channel")
            ],
            actions: [
                ManifestAction(id: "post_message", name: "Post Message", description: "Post to text channel", riskLevel: .consequential, parameters: ["channelId": "String", "content": "String"])
            ],
            verificationBadge: .verifiedByVoiceAI,
            deepLinkTemplate: "discord://discord.com/channels/{guild}/{channel}",
            platformSupport: [.macOS, .windows, .web]
        ),
        IntegrationManifest(
            id: "gmail",
            name: "Google Gmail",
            publisher: "Google LLC",
            version: "2.8.0",
            icon: "✉️",
            summary: "Draft emails, search message threads, and reply politely with AI summaries.",
            categories: [.communication, .productivity],
            authType: .oauth2,
            permissionsRequired: [
                PermissionScope(scope: "gmail.compose", justification: "Create email drafts for user review"),
                PermissionScope(scope: "gmail.readonly", justification: "Summarize recent incoming messages")
            ],
            actions: [
                ManifestAction(id: "create_draft", name: "Create Draft", description: "Save email draft in Gmail", riskLevel: .reversible, parameters: ["to": "String", "subject": "String", "body": "String"]),
                ManifestAction(id: "send_email", name: "Send Email", description: "Send email immediately", riskLevel: .consequential, parameters: ["to": "String", "subject": "String", "body": "String"])
            ],
            verificationBadge: .verifiedByVoiceAI,
            deepLinkTemplate: "https://mail.google.com/mail/u/0/#inbox/{threadId}",
            platformSupport: [.macOS, .windows, .web]
        )
    ]

    /// Validates an integration manifest against security and schema rules
    public func validate(manifest: IntegrationManifest) -> [String] {
        var errors: [String] = []

        if manifest.id.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Manifest ID cannot be empty")
        }
        if manifest.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Manifest Name cannot be empty")
        }
        if manifest.actions.isEmpty {
            errors.append("Manifest must declare at least one action")
        }
        for scope in manifest.permissionsRequired {
            if scope.justification.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append("Scope '\(scope.scope)' must include a user-facing justification")
            }
        }
        if manifest.deepLinkTemplate.isEmpty {
            errors.append("Deep link template must be provided for non-intrusive jumps")
        }

        return errors
    }

    /// Search and filter catalog
    public func filter(query: String = "", category: IntegrationCategory? = nil, platform: IntegrationPlatform? = nil) -> [IntegrationManifest] {
        return manifests.filter { m in
            if let cat = category, !m.categories.contains(cat) {
                return false
            }
            if let plat = platform, !m.platformSupport.contains(plat) {
                return false
            }
            if !query.isEmpty {
                let q = query.lowercased()
                let match = m.name.lowercased().contains(q) || m.summary.lowercased().contains(q) || m.publisher.lowercased().contains(q)
                if !match { return false }
            }
            return true
        }
    }
}

