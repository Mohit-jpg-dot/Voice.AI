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
        case ("mail", "send"), ("mail", "reply_and_send"):
            return "mail_send"
        case ("mail", _):
            return "mail_draft"
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
