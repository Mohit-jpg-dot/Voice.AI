import Foundation

public struct ToolSchemaProperty: Codable, Sendable, Equatable {
    public let type: String
    public let description: String
    public let enumValues: [String]?

    public init(type: String = "string", description: String, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }

    enum CodingKeys: String, CodingKey {
        case type, description
        case enumValues = "enum"
    }
}

public struct RegisteredToolSchema: Codable, Sendable, Equatable {
    public let type: String
    public let properties: [String: ToolSchemaProperty]
    public let required: [String]

    public init(
        type: String = "object",
        properties: [String: ToolSchemaProperty] = [:],
        required: [String] = []
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }

    public func toDictionary() -> [String: Any] {
        var propsDict: [String: Any] = [:]
        for (key, prop) in properties {
            var p: [String: Any] = [
                "type": prop.type,
                "description": prop.description
            ]
            if let enums = prop.enumValues {
                p["enum"] = enums
            }
            propsDict[key] = p
        }
        return [
            "type": type,
            "properties": propsDict,
            "required": required
        ]
    }
}

public enum ToolSource: Codable, Sendable, Equatable {
    case builtIn
    case mcpServer(serverId: String, endpoint: String)

    public var label: String {
        switch self {
        case .builtIn: return "built_in"
        case .mcpServer(let serverId, _): return "mcp:\(serverId)"
        }
    }
}

public struct ToolInvocationResult: Sendable {
    public let success: Bool
    public let summary: String
    public let data: [String: String]
    public let requiresApproval: Bool
    public let wasApproved: Bool
    public let pendingAction: AgentAction?

    public init(
        success: Bool,
        summary: String,
        data: [String: String] = [:],
        requiresApproval: Bool = false,
        wasApproved: Bool = true,
        pendingAction: AgentAction? = nil
    ) {
        self.success = success
        self.summary = summary
        self.data = data
        self.requiresApproval = requiresApproval
        self.wasApproved = wasApproved
        self.pendingAction = pendingAction
    }
}

public struct RegisteredTool: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let appName: String
    public let description: String
    public let inputSchema: RegisteredToolSchema
    public let permissionTier: PermissionTier
    public let source: ToolSource
    public let handler: @Sendable ([String: String]) async -> ToolInvocationResult

    public init(
        name: String,
        appName: String = "Voice.AI",
        description: String,
        inputSchema: RegisteredToolSchema = RegisteredToolSchema(),
        permissionTier: PermissionTier,
        source: ToolSource = .builtIn,
        handler: @escaping @Sendable ([String: String]) async -> ToolInvocationResult
    ) {
        self.name = name
        self.appName = appName
        self.description = description
        self.inputSchema = inputSchema
        self.permissionTier = permissionTier
        self.source = source
        self.handler = handler
    }

    /// Exports an MCP `tools/list` compatible tool object.
    public func toMCPDictionary() -> [String: Any] {
        return [
            "name": name,
            "description": description,
            "inputSchema": inputSchema.toDictionary(),
            "annotations": [
                "permissionTier": permissionTier.rawValue,
                "readOnlyHint": permissionTier == .readOnly,
                "destructiveHint": permissionTier == .consequential
            ]
        ]
    }
}

public protocol ToolRegistryProtocol: Sendable {
    func register(_ tool: RegisteredTool)
    func unregister(named name: String)
    func unregisterMCPServer(serverId: String)
    func allTools() -> [RegisteredTool]
    func tool(named name: String) -> RegisteredTool?
    func exportMCPToolsList() -> [[String: Any]]
    func invoke(
        name: String,
        arguments: [String: String],
        bypassApproval: Bool,
        customApprovalHandler: (@Sendable (AgentAction) async -> Bool)?
    ) async -> ToolInvocationResult
}

/// Central permission-tiered, MCP-compatible runtime registry of all native and plugin abilities.
public final class ToolRegistry: ToolRegistryProtocol, @unchecked Sendable {
    public static let shared = ToolRegistry()

    private let lock = NSLock()
    private var toolsByName: [String: RegisteredTool] = [:]

    public init(registerBuiltIns: Bool = true) {
        if registerBuiltIns {
            registerBuiltInTools()
        }
    }

    public func register(_ tool: RegisteredTool) {
        lock.lock()
        toolsByName[tool.name] = tool
        lock.unlock()
    }

    public func unregister(named name: String) {
        lock.lock()
        toolsByName.removeValue(forKey: name)
        lock.unlock()
    }

    public func unregisterMCPServer(serverId: String) {
        lock.lock()
        toolsByName = toolsByName.filter { _, tool in
            if case .mcpServer(let id, _) = tool.source {
                return id != serverId
            }
            return true
        }
        lock.unlock()
    }

    public func allTools() -> [RegisteredTool] {
        lock.lock()
        let list = Array(toolsByName.values).sorted { $0.name < $1.name }
        lock.unlock()
        return list
    }

    public func tool(named name: String) -> RegisteredTool? {
        lock.lock()
        let found = toolsByName[name]
        lock.unlock()
        return found
    }

    public func exportMCPToolsList() -> [[String: Any]] {
        return allTools().map { $0.toMCPDictionary() }
    }

    public func invoke(
        name: String,
        arguments: [String: String] = [:],
        bypassApproval: Bool = false,
        customApprovalHandler: (@Sendable (AgentAction) async -> Bool)? = nil
    ) async -> ToolInvocationResult {
        guard let tool = tool(named: name) else {
            return ToolInvocationResult(success: false, summary: "Tool '\(name)' is not registered.")
        }

        if name == "run_terminal_command" && !bypassApproval {
            let outcome = await SafeTerminalEngine.shared.execute(
                command: arguments["command"] ?? "",
                workingDirectory: arguments["working_directory"],
                purpose: arguments["purpose"],
                approvalSource: .liveMicrophone,
                customApprovalHandler: customApprovalHandler
            )
            EventBus.shared.publish(VoiceEvent(
                kind: .toolInvoked,
                source: "ToolRegistry",
                severity: outcome.success ? .info : .warning,
                payload: [
                    "tool": tool.name,
                    "tier": tool.permissionTier.rawValue,
                    "source": tool.source.label,
                    "success": outcome.success ? "true" : "false",
                    "decision": outcome.decision
                ]
            ))
            return ToolInvocationResult(
                success: outcome.success,
                summary: outcome.plainSummary,
                data: [
                    "decision": outcome.decision,
                    "classification": outcome.classification.rawValue,
                    "command_hash": outcome.commandHash,
                    "untrusted_output": outcome.untrustedWrappedOutput
                ],
                requiresApproval: outcome.classification != .blocked,
                wasApproved: outcome.decision == "approved" || outcome.decision == "approved_auto"
            )
        }

        if (name == "email_send" || name == "email_reply") && !bypassApproval {
            let res = await VoiceEmailManager.shared.sendFocusedDraft(customApprovalHandler: customApprovalHandler)
            return ToolInvocationResult(
                success: res.success,
                summary: res.success ? "Email sent via \(res.backendUsed)." : (res.errorMessage ?? "Email send cancelled or failed."),
                data: ["backend": res.backendUsed, "message_id": res.confirmedMessageId ?? ""],
                requiresApproval: true,
                wasApproved: res.success
            )
        }

        var pendingAction: AgentAction? = nil
        if !bypassApproval && tool.permissionTier == .consequential {
            let argPreview = SecretRedactor.redactDictionary(arguments)
                .map { "\($0.key): \($0.value)" }
                .sorted()
                .joined(separator: " • ")
            let auth = await ToolApprovalCoordinator.shared.requestAuthorizationIfNeeded(
                toolName: tool.name,
                appName: tool.appName,
                title: "Allow \(tool.name.replacingOccurrences(of: "_", with: " "))?",
                subtitle: argPreview.isEmpty ? tool.description : argPreview,
                payload: arguments,
                tier: tool.permissionTier,
                customApprovalHandler: customApprovalHandler
            )
            pendingAction = auth.action
            if !auth.approved {
                return ToolInvocationResult(
                    success: false,
                    summary: "Cancelled: approval required before running '\(tool.name)' (\(tool.permissionTier.rawValue)).",
                    requiresApproval: true,
                    wasApproved: false,
                    pendingAction: auth.action
                )
            }
        }

        let result = await tool.handler(arguments)
        EventBus.shared.publish(VoiceEvent(
            kind: .toolInvoked,
            source: "ToolRegistry",
            severity: result.success ? .info : .warning,
            payload: [
                "tool": tool.name,
                "tier": tool.permissionTier.rawValue,
                "source": tool.source.label,
                "success": result.success ? "true" : "false",
                "summary": String(result.summary.prefix(240))
            ]
        ))

        return ToolInvocationResult(
            success: result.success,
            summary: result.summary,
            data: result.data,
            requiresApproval: tool.permissionTier == .consequential,
            wasApproved: true,
            pendingAction: pendingAction
        )
    }

    /// Maps an integration `(app, operation)` pair to its registered `ToolRegistry` tool identifier.
    public static func registryToolName(forApp rawApp: String, operation rawOperation: String) -> String? {
        let app = AppIntegrationEngine.shared.canonicalIntegrationId(for: rawApp)
        let op = rawOperation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch (app, op) {
        case ("mail", "check_inbox"), ("mail", "unread"), ("mail", "read"), ("mail", "read_latest"), ("mail", "search"):
            return "mail_check_inbox"
        case ("mail", "summarize"):
            return "mail_summarize"
        case ("mail", "send"), ("mail", "reply_and_send"):
            return "mail_send"
        case ("mail", _):
            return "mail_draft"
        case ("calendar", "read"), ("calendar", "summarize"), ("calendar", "check"):
            return "calendar_summarize"
        case ("calendar", _):
            return "calendar_create_event"
        case ("messages", "read"), ("messages", "summarize"):
            return "messages_read"
        case ("messages", "send"):
            return "messages_send"
        case ("messages", _):
            return "messages_draft"
        case ("whatsapp", "send"):
            return "whatsapp_send"
        case ("whatsapp", _):
            return "whatsapp_draft"
        case ("slack", "send"):
            return "slack_send"
        case ("discord", "send"):
            return "discord_send"
        case ("notes", "read"), ("notes", "list"):
            return "notes_read"
        case ("notes", _):
            return "notes_create"
        case ("notion", _):
            return "notion_create_page"
        case ("youtube", _):
            return "youtube_control"
        case ("terminal", "run_headless"), ("terminal", "run_in_window"):
            return "terminal_run"
        default:
            return nil
        }
    }

    // MARK: - Built-In Capabilities

    public func registerBuiltInTools() {
        // MARK: - Notch Shelf Tools
        registerIntegrationTool(
            name: "shelf_list", appName: "Shelf",
            description: "List items currently saved on the Notch Shelf tray.",
            tier: .readOnly, appId: "shelf", operation: "list",
            props: [:]
        )
        registerIntegrationTool(
            name: "shelf_add", appName: "Shelf",
            description: "Add a file, folder, text snippet, or URL to the Shelf tray.",
            tier: .reversible, appId: "shelf", operation: "add",
            props: ["path": ToolSchemaProperty(description: "Path or URL of the file to add")],
            required: ["path"]
        )
        registerIntegrationTool(
            name: "shelf_remove", appName: "Shelf",
            description: "Remove a file tile from the Shelf tray (does not delete file).",
            tier: .reversible, appId: "shelf", operation: "remove",
            props: ["target": ToolSchemaProperty(description: "Name or index of item to remove")],
            required: ["target"]
        )
        registerIntegrationTool(
            name: "shelf_clear", appName: "Shelf",
            description: "Clear all items from the Shelf tray. Requires user approval.",
            tier: .consequential, appId: "shelf", operation: "clear",
            props: [:]
        )
        registerIntegrationTool(
            name: "shelf_airdrop", appName: "Shelf",
            description: "AirDrop shelf items to a nearby Apple device. Requires user approval.",
            tier: .consequential, appId: "shelf", operation: "airdrop",
            props: ["target": ToolSchemaProperty(description: "Items to AirDrop")]
        )
        registerIntegrationTool(
            name: "shelf_move", appName: "Shelf",
            description: "Move shelf files to a destination folder. Requires user approval.",
            tier: .consequential, appId: "shelf", operation: "move",
            props: [
                "destination": ToolSchemaProperty(description: "Destination folder path")
            ],
            required: ["destination"]
        )
        registerIntegrationTool(
            name: "shelf_trash", appName: "Shelf",
            description: "Move a shelf file to the macOS Trash. Requires user approval.",
            tier: .consequential, appId: "shelf", operation: "trash",
            props: [
                "path": ToolSchemaProperty(description: "File to trash")
            ],
            required: ["path"]
        )
        registerIntegrationTool(
            name: "shelf_summarize", appName: "Shelf",
            description: "Summarize a text document on the Shelf tray safely.",
            tier: .readOnly, appId: "shelf", operation: "summarize",
            props: [
                "target": ToolSchemaProperty(description: "Name of the file on shelf")
            ]
        )

        registerIntegrationTool(
            name: "mail_check_inbox", appName: "Apple Mail",
            description: "Read unread count and latest messages from Mail or Gmail inbox.",
            tier: .readOnly, appId: "mail", operation: "check_inbox",
            props: ["query": ToolSchemaProperty(description: "Optional filter subject or sender")]
        )
        registerIntegrationTool(
            name: "mail_draft", appName: "Apple Mail",
            description: "Draft an email or reply in Mail or Gmail without sending.",
            tier: .reversible, appId: "mail", operation: "draft",
            props: [
                "recipient": ToolSchemaProperty(description: "Recipient email or contact name"),
                "subject": ToolSchemaProperty(description: "Email subject"),
                "body": ToolSchemaProperty(description: "Email body")
            ]
        )
        registerIntegrationTool(
            name: "mail_send", appName: "Apple Mail",
            description: "Send an email or reply via Mail/Gmail. Requires user approval.",
            tier: .consequential, appId: "mail", operation: "send",
            props: [
                "recipient": ToolSchemaProperty(description: "Recipient email or contact name"),
                "subject": ToolSchemaProperty(description: "Email subject"),
                "body": ToolSchemaProperty(description: "Email body")
            ],
            required: ["recipient", "body"]
        )

        registerIntegrationTool(
            name: "whatsapp_draft", appName: "WhatsApp",
            description: "Open a WhatsApp chat and stage a message draft.",
            tier: .reversible, appId: "whatsapp", operation: "draft",
            props: [
                "recipient": ToolSchemaProperty(description: "Contact name or phone"),
                "body": ToolSchemaProperty(description: "Message text")
            ]
        )
        registerIntegrationTool(
            name: "whatsapp_send", appName: "WhatsApp",
            description: "Send a WhatsApp message immediately. Requires user approval.",
            tier: .consequential, appId: "whatsapp", operation: "send",
            props: [
                "recipient": ToolSchemaProperty(description: "Contact name or phone"),
                "body": ToolSchemaProperty(description: "Message text")
            ],
            required: ["recipient", "body"]
        )

        registerIntegrationTool(
            name: "whatsapp_read", appName: "WhatsApp",
            description: "Read unread messages or recent conversation from WhatsApp.",
            tier: .readOnly, appId: "whatsapp", operation: "read",
            props: ["recipient": ToolSchemaProperty(description: "Optional contact name or phone")]
        )

        registerIntegrationTool(
            name: "slack_send", appName: "Slack",
            description: "Send a message to a Slack channel or DM. Requires user approval.",
            tier: .consequential, appId: "slack", operation: "send",
            props: [
                "recipient": ToolSchemaProperty(description: "#channel or @user"),
                "body": ToolSchemaProperty(description: "Message text")
            ],
            required: ["recipient", "body"]
        )
        registerIntegrationTool(
            name: "slack_read", appName: "Slack",
            description: "Read unread messages or channel history from Slack.",
            tier: .readOnly, appId: "slack", operation: "read",
            props: ["recipient": ToolSchemaProperty(description: "Optional channel name or DM target")]
        )
        registerIntegrationTool(
            name: "slack_react", appName: "Slack",
            description: "Add an emoji reaction to a message in Slack.",
            tier: .reversible, appId: "slack", operation: "react",
            props: [
                "recipient": ToolSchemaProperty(description: "Channel or message target"),
                "body": ToolSchemaProperty(description: "Emoji to add (e.g. thumbsup)")
            ],
            required: ["recipient", "body"]
        )
        registerIntegrationTool(
            name: "discord_send", appName: "Discord",
            description: "Send a message to a Discord channel or user. Requires user approval.",
            tier: .consequential, appId: "discord", operation: "send",
            props: [
                "recipient": ToolSchemaProperty(description: "#channel or @user"),
                "body": ToolSchemaProperty(description: "Message text")
            ],
            required: ["recipient", "body"]
        )
        registerIntegrationTool(
            name: "discord_read", appName: "Discord",
            description: "Read unread messages or channel history from Discord.",
            tier: .readOnly, appId: "discord", operation: "read",
            props: ["recipient": ToolSchemaProperty(description: "Optional channel name or target")]
        )
        registerIntegrationTool(
            name: "discord_react", appName: "Discord",
            description: "Add an emoji reaction to a message in Discord.",
            tier: .reversible, appId: "discord", operation: "react",
            props: [
                "recipient": ToolSchemaProperty(description: "Channel or message target"),
                "body": ToolSchemaProperty(description: "Emoji to add")
            ],
            required: ["recipient", "body"]
        )

        registerIntegrationTool(
            name: "notes_read", appName: "Apple Notes",
            description: "List recent notes or read a matching note from Apple Notes.",
            tier: .readOnly, appId: "notes", operation: "read",
            props: ["query": ToolSchemaProperty(description: "Optional note title keyword")]
        )
        registerIntegrationTool(
            name: "notes_create", appName: "Apple Notes",
            description: "Create or append to a note in Apple Notes.",
            tier: .reversible, appId: "notes", operation: "create",
            props: [
                "title": ToolSchemaProperty(description: "Note title"),
                "body": ToolSchemaProperty(description: "Note content")
            ]
        )

        registerIntegrationTool(
            name: "notion_create_page", appName: "Notion",
            description: "Create a Notion page or quick-search pages in Notion.",
            tier: .reversible, appId: "notion", operation: "create_page",
            props: [
                "title": ToolSchemaProperty(description: "Page title"),
                "body": ToolSchemaProperty(description: "Page body")
            ]
        )

        registerIntegrationTool(
            name: "youtube_control", appName: "YouTube",
            description: "Control playback or search on YouTube (play, pause, next, mute, search).",
            tier: .reversible, appId: "youtube", operation: "play",
            props: [
                "operation": ToolSchemaProperty(description: "play, pause, next, previous, mute, unmute, forward, rewind, search, summarize"),
                "query": ToolSchemaProperty(description: "Optional search query")
            ]
        )

        registerIntegrationTool(
            name: "terminal_run", appName: "Terminal",
            description: "Execute a shell command in zsh or visible Terminal window. Requires user approval.",
            tier: .consequential, appId: "terminal", operation: "run_headless",
            props: ["command": ToolSchemaProperty(description: "Shell command to execute")],
            required: ["command"]
        )

        register(RegisteredTool(
            name: "math_evaluate",
            appName: "Calculator",
            description: "Evaluate arithmetic, percentages, powers, and square roots deterministically offline.",
            inputSchema: RegisteredToolSchema(
                properties: ["expression": ToolSchemaProperty(description: "Math expression")],
                required: ["expression"]
            ),
            permissionTier: .readOnly
        ) { args in
            let expr = args["expression"] ?? ""
            if let res = MathEngine.shared.evaluate(expr) {
                return ToolInvocationResult(success: true, summary: res.displaySummary, data: ["answer": res.answer])
            }
            return ToolInvocationResult(success: false, summary: "Could not evaluate '\(expr)'.")
        })

        register(RegisteredTool(
            name: "memory_remember",
            appName: "MemoryStore",
            description: "Persist a personal preference, fact, or project detail into encrypted per-account memory.",
            inputSchema: RegisteredToolSchema(
                properties: [
                    "content": ToolSchemaProperty(description: "Fact or preference to remember"),
                    "kind": ToolSchemaProperty(description: "fact, preference, project, person, or turn")
                ],
                required: ["content"]
            ),
            permissionTier: .reversible
        ) { args in
            let content = args["content"] ?? ""
            let kind = MemoryFactKind(rawValue: (args["kind"] ?? "fact").lowercased()) ?? .fact
            let saved = await MemoryStore.shared.remember(content: content, scope: .longTerm, kind: kind, tags: ["tool"])
            return ToolInvocationResult(success: true, summary: "Remembered: \(saved.content)", data: ["id": saved.id])
        })

        register(RegisteredTool(
            name: "memory_search",
            appName: "MemoryStore",
            description: "Semantically search encrypted per-account long-term & short-term memories.",
            inputSchema: RegisteredToolSchema(
                properties: ["query": ToolSchemaProperty(description: "Semantic search query")],
                required: ["query"]
            ),
            permissionTier: .readOnly
        ) { args in
            let query = args["query"] ?? ""
            let hits = await MemoryStore.shared.searchSemantic(query: query, scope: nil, limit: 5)
            let summary = hits.isEmpty
                ? "No matching memories found."
                : hits.map { "- \($0.item.content)" }.joined(separator: "\n")
            return ToolInvocationResult(success: true, summary: summary, data: ["count": "\(hits.count)"])
        })

        register(RegisteredTool(
            name: "memory_forget",
            appName: "MemoryStore",
            description: "Remove matching items from persistent memory.",
            inputSchema: RegisteredToolSchema(
                properties: ["query": ToolSchemaProperty(description: "Memory ID or matching phrase to forget")],
                required: ["query"]
            ),
            permissionTier: .reversible
        ) { args in
            let query = args["query"] ?? ""
            if await MemoryStore.shared.forget(id: query) {
                return ToolInvocationResult(success: true, summary: "Forgot memory entry \(query).")
            }
            let removed = await MemoryStore.shared.forget(matching: query)
            return ToolInvocationResult(success: removed > 0, summary: "Removed \(removed) matching memory item(s).")
        })

        // Phase 2 Tools: Proactive Alerts, Calendar, Email/Messages Summaries, RAG, VLM Screen, Smart Home & Health
        register(RegisteredTool(
            name: "proactive_alerts_status",
            appName: "Proactive Engine",
            description: "List active rate-limited proactive system alerts (battery, CPU/RAM, builds, calendar conflicts, important emails).",
            inputSchema: RegisteredToolSchema(properties: [:]),
            permissionTier: .readOnly
        ) { _ in
            let alerts = ProactiveRulesEngine.shared.activeAlerts()
            let summary = alerts.isEmpty
                ? "All systems nominal. Zero active proactive alerts."
                : alerts.map { "• [\($0.severity.rawValue.uppercased())] \($0.title): \($0.message)" }.joined(separator: "\n")
            return ToolInvocationResult(success: true, summary: summary, data: ["count": "\(alerts.count)"])
        })

        register(RegisteredTool(
            name: "mail_summarize",
            appName: "Apple Mail",
            description: "Read and summarize recent or matching emails cleanly.",
            inputSchema: RegisteredToolSchema(properties: ["query": ToolSchemaProperty(description: "Optional topic or sender filter")]),
            permissionTier: .readOnly
        ) { args in
            let summary = await CalendarMessagesService.shared.summarizeRecentEmails(query: args["query"] ?? "")
            return ToolInvocationResult(success: true, summary: summary)
        })

        register(RegisteredTool(
            name: "calendar_summarize",
            appName: "Apple Calendar",
            description: "Read upcoming events, detect schedule conflicts, and summarize the calendar.",
            inputSchema: RegisteredToolSchema(properties: ["range": ToolSchemaProperty(description: "today or week")]),
            permissionTier: .readOnly
        ) { args in
            let summary = await CalendarMessagesService.shared.summarizeCalendar(range: args["range"] ?? "today")
            return ToolInvocationResult(success: true, summary: summary)
        })

        register(RegisteredTool(
            name: "calendar_create_event",
            appName: "Apple Calendar",
            description: "Create a new calendar event.",
            inputSchema: RegisteredToolSchema(
                properties: [
                    "title": ToolSchemaProperty(description: "Event title"),
                    "duration_minutes": ToolSchemaProperty(description: "Duration in minutes (default 30)")
                ],
                required: ["title"]
            ),
            permissionTier: .reversible
        ) { args in
            let duration = Int(args["duration_minutes"] ?? "30") ?? 30
            let res = await CalendarMessagesService.shared.createCalendarEvent(
                title: args["title"] ?? "",
                startsInMinutes: 60,
                durationMinutes: duration
            )
            return ToolInvocationResult(success: res.success, summary: res.summary)
        })

        register(RegisteredTool(
            name: "messages_read",
            appName: "Messages",
            description: "Read and summarize recent Apple Messages threads.",
            inputSchema: RegisteredToolSchema(properties: ["contact": ToolSchemaProperty(description: "Optional contact filter")]),
            permissionTier: .readOnly
        ) { args in
            let res = await CalendarMessagesService.shared.readMessages(contactFilter: args["contact"] ?? "")
            return ToolInvocationResult(success: true, summary: res.summary, data: ["count": "\(res.threads.count)"])
        })

        register(RegisteredTool(
            name: "messages_draft",
            appName: "Messages",
            description: "Draft a message in Apple Messages without sending.",
            inputSchema: RegisteredToolSchema(
                properties: [
                    "recipient": ToolSchemaProperty(description: "Recipient name or handle"),
                    "body": ToolSchemaProperty(description: "Message body")
                ],
                required: ["recipient"]
            ),
            permissionTier: .reversible
        ) { args in
            let res = await CalendarMessagesService.shared.draftMessage(recipient: args["recipient"] ?? "", body: args["body"] ?? "")
            return ToolInvocationResult(success: res.success, summary: res.summary)
        })

        register(RegisteredTool(
            name: "messages_send",
            appName: "Messages",
            description: "Send an external message via Apple Messages. Requires Notch Approval Card confirmation.",
            inputSchema: RegisteredToolSchema(
                properties: [
                    "recipient": ToolSchemaProperty(description: "Recipient handle or contact"),
                    "body": ToolSchemaProperty(description: "Message body")
                ],
                required: ["recipient", "body"]
            ),
            permissionTier: .consequential
        ) { args in
            let res = await CalendarMessagesService.shared.sendMessage(recipient: args["recipient"] ?? "", body: args["body"] ?? "")
            return ToolInvocationResult(success: res.success, summary: res.summary)
        })

        register(RegisteredTool(
            name: "rag_search_files",
            appName: "Local Knowledge",
            description: "Search locally indexed folders and files using on-device semantic embeddings (RAG).",
            inputSchema: RegisteredToolSchema(
                properties: ["query": ToolSchemaProperty(description: "Search question or keywords")],
                required: ["query"]
            ),
            permissionTier: .readOnly
        ) { args in
            let query = args["query"] ?? ""
            let hits = await LocalKnowledgeStore.shared.search(query: query, limit: 4)
            let summary = hits.isEmpty
                ? "No matching passages found in indexed local folders."
                : hits.map { "• [\($0.chunk.fileName)] \($0.chunk.snippet.prefix(180))" }.joined(separator: "\n")
            return ToolInvocationResult(success: true, summary: summary, data: ["count": "\(hits.count)"])
        })

        register(RegisteredTool(
            name: "rag_index_folder",
            appName: "Local Knowledge",
            description: "Index a user-chosen local folder on-device for semantic RAG search.",
            inputSchema: RegisteredToolSchema(
                properties: ["path": ToolSchemaProperty(description: "Absolute folder path")],
                required: ["path"]
            ),
            permissionTier: .reversible
        ) { args in
            let path = args["path"] ?? ""
            let count = await LocalKnowledgeStore.shared.indexFolder(path: path)
            return ToolInvocationResult(success: count > 0, summary: "Indexed \(count) chunk(s) from \(path).", data: ["chunks": "\(count)"])
        })

        register(RegisteredTool(
            name: "screen_understand_region",
            appName: "Circle to Ask",
            description: "Understand screen OCR/image context and answer UI/error questions.",
            inputSchema: RegisteredToolSchema(
                properties: [
                    "question": ToolSchemaProperty(description: "User question about screen content"),
                    "ocr_text": ToolSchemaProperty(description: "Extracted OCR text"),
                    "app_name": ToolSchemaProperty(description: "Active application name")
                ],
                required: ["question"]
            ),
            permissionTier: .readOnly
        ) { args in
            let res = await ScreenVisionService.shared.understandScreenQuestion(
                pngData: nil,
                ocrText: args["ocr_text"] ?? "",
                appName: args["app_name"] ?? "Screen",
                question: args["question"] ?? "Explain this"
            )
            return ToolInvocationResult(success: true, summary: res.answer, data: ["provider": res.providerLabel, "privacy": res.privacyBadge])
        })

        register(RegisteredTool(
            name: "smarthome_status",
            appName: "Smart Home",
            description: "Read status of Home Assistant / HomeKit / MQTT smart home devices.",
            inputSchema: RegisteredToolSchema(properties: [:]),
            permissionTier: .readOnly
        ) { _ in
            return ToolInvocationResult(success: true, summary: SmartHomeManager.shared.summarizeHomeStatus())
        })

        register(RegisteredTool(
            name: "smarthome_control_comfort",
            appName: "Smart Home",
            description: "Control non-security smart home devices (lights, thermostat, scenes).",
            inputSchema: RegisteredToolSchema(
                properties: [
                    "device": ToolSchemaProperty(description: "Device name or room"),
                    "action": ToolSchemaProperty(description: "on, off, set_temperature, activate"),
                    "value": ToolSchemaProperty(description: "Optional setpoint value")
                ],
                required: ["device", "action"]
            ),
            permissionTier: .reversible
        ) { args in
            let res = await SmartHomeManager.shared.executeDeviceAction(
                deviceQuery: args["device"] ?? "",
                action: args["action"] ?? "on",
                value: args["value"]
            )
            return ToolInvocationResult(success: res.success, summary: res.summary)
        })

        register(RegisteredTool(
            name: "smarthome_control_security",
            appName: "Smart Home Security",
            description: "Control locks, garage doors, or security alarms. Strictly requires Approval Card confirmation.",
            inputSchema: RegisteredToolSchema(
                properties: [
                    "device": ToolSchemaProperty(description: "Lock or alarm device name"),
                    "action": ToolSchemaProperty(description: "lock, unlock, arm, disarm")
                ],
                required: ["device", "action"]
            ),
            permissionTier: .consequential
        ) { args in
            let res = await SmartHomeManager.shared.executeDeviceAction(
                deviceQuery: args["device"] ?? "",
                action: args["action"] ?? "lock",
                value: args["value"]
            )
            return ToolInvocationResult(success: res.success, summary: res.summary)
        })

        register(RegisteredTool(
            name: "health_summary",
            appName: "Apple Health (Opt-In)",
            description: "Summarize opt-in on-device Apple Health metrics and trend warnings.",
            inputSchema: RegisteredToolSchema(properties: [:]),
            permissionTier: .readOnly
        ) { _ in
            let digest = HealthInsightsManager.shared.computeDigest()
            return ToolInvocationResult(success: true, summary: digest.summaryText, data: ["opted_in": digest.isOptedIn ? "true" : "false"])
        })

        register(RegisteredTool(
            name: "health_add_reminder",
            appName: "Apple Health (Opt-In)",
            description: "Add an on-device wellness, hydration, or medication reminder.",
            inputSchema: RegisteredToolSchema(
                properties: [
                    "title": ToolSchemaProperty(description: "Reminder title"),
                    "schedule": ToolSchemaProperty(description: "Schedule string, e.g. Daily 09:00")
                ],
                required: ["title"]
            ),
            permissionTier: .reversible
        ) { args in
            let reminder = HealthInsightsManager.shared.addReminder(
                title: args["title"] ?? "Hydrate",
                scheduleText: args["schedule"] ?? "Daily"
            )
            return ToolInvocationResult(success: true, summary: "Added health reminder: \(reminder.title) (\(reminder.scheduleText)).")
        })

        // Phase 3 Tools: Iron Legion, Engineering CAD & Physics, Cyber Defense & Lockdown, Camera Vision
        register(RegisteredTool(
            name: "iron_legion_dispatch",
            appName: "Iron Legion",
            description: "Spawn and coordinate parallel Research, Code, and Summarize subagents shown live in the Agents tab.",
            inputSchema: RegisteredToolSchema(
                properties: ["goal": ToolSchemaProperty(description: "Mission goal for parallel subagents")],
                required: ["goal"]
            ),
            permissionTier: .reversible
        ) { args in
            let mission = await IronLegionCoordinator.shared.dispatchParallelMission(goal: args["goal"] ?? "Analyze workspace")
            return ToolInvocationResult(
                success: true,
                summary: mission.unifiedSummary,
                data: ["workers": "\(mission.workerResults.count)", "duration_ms": "\(mission.totalDurationMs)"]
            )
        })

        register(RegisteredTool(
            name: "engineering_generate_cad",
            appName: "Engineering Studio",
            description: "Generate OpenSCAD or CadQuery parametric CAD code plus a 3D wireframe hologram HTML scene.",
            inputSchema: RegisteredToolSchema(
                properties: [
                    "shape": ToolSchemaProperty(description: "bracket, gear, enclosure, or heatsink"),
                    "backend": ToolSchemaProperty(description: "openscad or cadquery")
                ]
            ),
            permissionTier: .reversible
        ) { args in
            let shape = EngineeringStudioEngine.shared.inferShape(from: args["shape"] ?? "bracket")
            let backend: CADBackend = (args["backend"] ?? "").lowercased().contains("cadquery") ? .cadquery : .openscad
            let res = EngineeringStudioEngine.shared.generateCAD(shape: shape, backend: backend)
            return ToolInvocationResult(
                success: true,
                summary: "Generated \(res.title) CAD model & 3D Hologram view.",
                data: ["code": res.sourceCode, "hologram_html": res.hologramHTML]
            )
        })

        register(RegisteredTool(
            name: "engineering_physics_sim",
            appName: "Engineering Studio",
            description: "Run deterministic projectile kinematics, spring-harmonic, or steady-state thermal simulations.",
            inputSchema: RegisteredToolSchema(
                properties: [
                    "type": ToolSchemaProperty(description: "projectile, spring, or thermal"),
                    "value": ToolSchemaProperty(description: "Initial velocity (m/s), mass (kg), or power (W)")
                ]
            ),
            permissionTier: .readOnly
        ) { args in
            let kind = (args["type"] ?? "projectile").lowercased()
            let val = Double(args["value"] ?? "") ?? (kind == "thermal" ? 45.0 : 25.0)
            let sim: PhysicsSimulationResult
            if kind == "spring" {
                sim = EngineeringStudioEngine.shared.simulateSpringHarmonic(massKg: val, springConstantNM: 40.0)
            } else if kind == "thermal" {
                sim = EngineeringStudioEngine.shared.simulateThermal(powerWatts: val)
            } else {
                sim = EngineeringStudioEngine.shared.simulateProjectile(velocityMS: val, angleDegrees: 45.0)
            }
            return ToolInvocationResult(success: true, summary: "\(sim.simulationType): \(sim.summary)")
        })

        register(RegisteredTool(
            name: "security_anomaly_scan",
            appName: "Cyber Defense",
            description: "Scan local listeners/processes and ARP table for suspicious ports or new LAN devices.",
            inputSchema: RegisteredToolSchema(properties: [:]),
            permissionTier: .readOnly
        ) { _ in
            let report = await CyberDefenseMonitor.shared.runLiveAnomalyScan()
            return ToolInvocationResult(success: true, summary: report.summary, data: ["findings": "\(report.findings.count)"])
        })

        register(RegisteredTool(
            name: "security_lockdown",
            appName: "Cyber Defense",
            description: "Emergency Lockdown: locks screen, mutes microphone, and disables Wi-Fi. Strictly requires Approval Card confirmation.",
            inputSchema: RegisteredToolSchema(properties: ["reason": ToolSchemaProperty(description: "Optional security reason")]),
            permissionTier: .consequential
        ) { _ in
            let report = await CyberDefenseMonitor.shared.executeLockdown()
            return ToolInvocationResult(success: report.success, summary: report.summary)
        })

        register(RegisteredTool(
            name: "camera_gesture_control",
            appName: "Local Camera Vision",
            description: "Execute an opt-in local hand gesture action (thumbs_up, thumbs_down, open_palm, pinch).",
            inputSchema: RegisteredToolSchema(
                properties: ["gesture": ToolSchemaProperty(description: "thumbs_up, thumbs_down, open_palm, or pinch")],
                required: ["gesture"]
            ),
            permissionTier: .reversible
        ) { args in
            let kind = HandGestureKind(rawValue: (args["gesture"] ?? "open_palm").lowercased()) ?? .openPalm
            let res = await LocalCameraVisionService.shared.executeGestureAction(kind)
            return ToolInvocationResult(success: res.success, summary: res.summary)
        })

        register(RegisteredTool(
            name: "brain_switch_model",
            appName: "AI Brain Router",
            description: "Switch between local Ollama model sizes (smaller 3B / larger 8B+) or paid Cloud models (Claude / ChatGPT).",
            inputSchema: RegisteredToolSchema(
                properties: ["command": ToolSchemaProperty(description: "Target model or tier instruction, e.g. 'smaller local model', 'larger model', 'paid claude model'")],
                required: ["command"]
            ),
            permissionTier: .reversible
        ) { args in
            let cmd = args["command"] ?? "local model"
            if let switched = await ModelRouter.shared.switchModelByVoice(cmd) {
                return ToolInvocationResult(
                    success: true,
                    summary: switched.summary,
                    data: ["mode": switched.mode.rawValue, "provider": switched.providerName, "model": switched.selectedModelId]
                )
            }
            return ToolInvocationResult(success: false, summary: "Could not interpret model switch target from '\(cmd)'.")
        })

        register(RegisteredTool(
            name: "computer_use_operate",
            appName: "Computer Use",
            description: "Run an iterative See-Decide-Act multimodal screen control loop for open-ended UI tasks (max 15 steps; gates risky actions with Approval Cards).",
            inputSchema: RegisteredToolSchema(
                properties: [
                    "goal": ToolSchemaProperty(description: "Spoken user goal to execute on screen"),
                    "max_steps": ToolSchemaProperty(description: "Maximum loop steps (default 15)")
                ],
                required: ["goal"]
            ),
            permissionTier: .reversible
        ) { args in
            let goal = args["goal"] ?? ""
            let steps = Int(args["max_steps"] ?? "15") ?? 15
            let res = await ComputerUseOperator.shared.runAgentTask(goal: goal, maxSteps: steps)
            return ToolInvocationResult(success: res.success, summary: res.summary)
        })
        register(RegisteredTool(
            name: "run_terminal_command",
            appName: "Terminal",
            description: "Execute a validated macOS terminal command inside allowed user directories after CommandPolicy verification and voice/UI approval.",
            inputSchema: RegisteredToolSchema(
                properties: [
                    "command": ToolSchemaProperty(description: "Shell command to execute within allowed roots"),
                    "working_directory": ToolSchemaProperty(description: "Working directory (Desktop, Documents, Downloads, or VoiceAI-Workspace)"),
                    "purpose": ToolSchemaProperty(description: "Plain-English explanation shown on the approval card")
                ],
                required: ["command", "purpose"]
            ),
            permissionTier: .consequential,
            source: .builtIn
        ) { args in
            let outcome = await SafeTerminalEngine.shared.execute(
                command: args["command"] ?? "",
                workingDirectory: args["working_directory"],
                purpose: args["purpose"],
                approvalSource: .liveMicrophone
            )
            return ToolInvocationResult(
                success: outcome.success,
                summary: outcome.plainSummary,
                data: [
                    "decision": outcome.decision,
                    "classification": outcome.classification.rawValue,
                    "command_hash": outcome.commandHash,
                    "untrusted_output": outcome.untrustedWrappedOutput
                ],
                requiresApproval: outcome.classification != .blocked,
                wasApproved: outcome.decision == "approved" || outcome.decision == "approved_auto"
            )
        })

        // Voice Email Tools
        register(RegisteredTool(
            name: "email_capabilities",
            appName: "Mail",
            description: "Test the active email backend (Mail.app, Gmail API, IMAP/SMTP, or mailto:) and report whether reading/sending is available.",
            permissionTier: .readOnly
        ) { _ in
            let rep = await VoiceEmailManager.shared.capabilitiesReport()
            return ToolInvocationResult(
                success: rep.status == .canSendAndRead || rep.status == .canSendOnly,
                summary: rep.spokenSummary,
                data: ["status": rep.status.rawValue, "backend": rep.activeBackend, "reason": rep.reason, "fix": rep.fixInstructions]
            )
        })

        register(RegisteredTool(
            name: "email_read",
            appName: "Mail",
            description: "Fetch and summarize recent incoming emails (wrapped in <UNTRUSTED_EMAIL_DATA>).",
            inputSchema: RegisteredToolSchema(properties: ["sender": ToolSchemaProperty(description: "Optional sender name or email filter")]),
            permissionTier: .readOnly
        ) { args in
            let (msgs, summary) = await VoiceEmailManager.shared.fetchAndSummarizeRecent(limit: 5, senderFilter: args["sender"])
            let untrusted = msgs.first.map { VoiceEmailManager.wrapUntrustedEmailData(subject: $0.subject, body: $0.body, sender: $0.from) } ?? ""
            return ToolInvocationResult(success: !msgs.isEmpty, summary: summary, data: ["count": "\(msgs.count)", "untrusted_email": untrusted])
        })

        register(RegisteredTool(
            name: "email_draft",
            appName: "Mail",
            description: "Create or update a persistent encrypted email draft without sending.",
            inputSchema: RegisteredToolSchema(properties: [
                "to": ToolSchemaProperty(description: "Recipient email or contact query"),
                "subject": ToolSchemaProperty(description: "Email subject"),
                "body": ToolSchemaProperty(description: "Email body")
            ]),
            permissionTier: .reversible
        ) { args in
            let draft = VoiceEmailManager.shared.createDraft(
                to: (args["to"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                subject: args["subject"] ?? "",
                body: args["body"] ?? ""
            )
            return ToolInvocationResult(success: true, summary: VoiceEmailManager.shared.formatDraftPreview(draft), data: ["draft_id": draft.id])
        })

        register(RegisteredTool(
            name: "email_send",
            appName: "Mail",
            description: "Send the focused persistent email draft after .consequential approval card and undo window.",
            permissionTier: .consequential
        ) { _ in
            let res = await VoiceEmailManager.shared.sendFocusedDraft()
            return ToolInvocationResult(success: res.success, summary: res.success ? "Email sent via \(res.backendUsed)." : (res.errorMessage ?? "Email not sent."), requiresApproval: true, wasApproved: res.success)
        })

        register(RegisteredTool(
            name: "email_reply",
            appName: "Mail",
            description: "Reply to the currently focused incoming email after .consequential approval card and undo window.",
            inputSchema: RegisteredToolSchema(properties: ["body": ToolSchemaProperty(description: "Reply text")]),
            permissionTier: .consequential
        ) { _ in
            let res = await VoiceEmailManager.shared.sendFocusedDraft()
            return ToolInvocationResult(success: res.success, summary: res.success ? "Reply sent via \(res.backendUsed)." : (res.errorMessage ?? "Reply not sent."), requiresApproval: true, wasApproved: res.success)
        })

        register(RegisteredTool(
            name: "email_watch",
            appName: "Mail",
            description: "Watch a thread or sender for replies and alert the user via ProactiveRulesEngine and EventBus.",
            inputSchema: RegisteredToolSchema(properties: ["sender": ToolSchemaProperty(description: "Sender email or name to watch")]),
            permissionTier: .reversible
        ) { args in
            if let sender = args["sender"], !sender.isEmpty {
                let rule = VoiceEmailManager.shared.addSenderWatch(address: sender, displayLabel: sender)
                return ToolInvocationResult(success: true, summary: "Watching for replies from \(rule.displayLabel).")
            }
            if let focused = VoiceEmailManager.shared.currentFocusedIncomingMessage() {
                let rule = VoiceEmailManager.shared.addThreadWatch(for: focused)
                return ToolInvocationResult(success: true, summary: "Watching thread '\(focused.subject)' for replies from \(rule.displayLabel).")
            }
            return ToolInvocationResult(success: false, summary: "No email or sender specified to watch.")
        })
    }

    private func registerIntegrationTool(
        name: String,
        appName: String,
        description: String,
        tier: PermissionTier,
        appId: String,
        operation defaultOperation: String,
        props: [String: ToolSchemaProperty],
        required: [String] = []
    ) {
        register(RegisteredTool(
            name: name,
            appName: appName,
            description: description,
            inputSchema: RegisteredToolSchema(properties: props, required: required),
            permissionTier: tier,
            source: .builtIn
        ) { args in
            let op = args["operation"] ?? defaultOperation
            let res = await AppIntegrationEngine.shared.execute(app: appId, operation: op, params: args)
            return ToolInvocationResult(
                success: res.success,
                summary: res.summary,
                data: ["app": res.appName]
            )
        })
    }
}
