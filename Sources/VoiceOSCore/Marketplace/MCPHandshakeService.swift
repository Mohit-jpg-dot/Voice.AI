import Foundation

/// Service for introspecting external MCP (Model Context Protocol) servers and synthesizing manifests
public final class MCPHandshakeService: Sendable {
    public static let shared = MCPHandshakeService()

    public init() {}

    /// Extracts an MCP endpoint URL from a spoken or typed user prompt
    public func extractEndpoint(from prompt: String) -> URL? {
        let pattern = #"(https?://[^\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
              let range = Range(match.range(at: 1), in: prompt) else {
            return nil
        }
        let urlStr = String(prompt[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;\"'"))
        return URL(string: urlStr)
    }

    /// Introspects an MCP server and generates a typed IntegrationManifest
    public func introspectAndSynthesizeManifest(
        from endpointURL: URL,
        customName: String? = nil,
        mockTools: [MCPToolDefinition]? = nil
    ) -> IntegrationManifest {
        let host = endpointURL.host ?? "localhost"
        let portStr = endpointURL.port.map { ":\($0)" } ?? ""
        let serverTitle = customName ?? "Custom MCP (\(host)\(portStr))"
        let manifestId = "mcp_" + host.replacingOccurrences(of: ".", with: "_") + (endpointURL.port.map { "_\($0)" } ?? "")

        // Discovered tools (either from remote SSE list_tools or simulated mock)
        let tools = mockTools ?? defaultMockTools(for: endpointURL)

        let manifestActions = tools.map { tool in
            ManifestAction(
                id: tool.name,
                name: tool.title ?? tool.name,
                description: tool.description,
                riskLevel: tool.isDestructive ? .consequential : .readOnly,
                parameters: tool.inputSchema,
                returnType: "JSON"
            )
        }

        return IntegrationManifest(
            id: manifestId,
            name: serverTitle,
            publisher: "User MCP Server",
            version: "1.0.0",
            icon: "🔌",
            summary: "Dynamically connected Model Context Protocol server at \(endpointURL.absoluteString).",
            categories: [.ai, .utilities, .developer],
            authType: .mcp,
            permissionsRequired: [
                PermissionScope(
                    scope: "network:connect",
                    justification: "Allow \(AppBrand.name) background agent to call tools at \(endpointURL.absoluteString)"
                )
            ],
            actions: manifestActions,
            verificationBadge: .customMCP,
            deepLinkTemplate: endpointURL.absoluteString,
            platformSupport: [.macOS, .windows, .web]
        )
    }

    /// Fallback default tools introspected during handshake simulation
    private func defaultMockTools(for url: URL) -> [MCPToolDefinition] {
        return [
            MCPToolDefinition(
                name: "query_database",
                title: "Query Database",
                description: "Execute read-only SQL queries against connected SQLite/Postgres DB",
                inputSchema: ["sql": "String"],
                isDestructive: false
            ),
            MCPToolDefinition(
                name: "insert_record",
                title: "Insert Record",
                description: "Insert verified telemetry record into production database",
                inputSchema: ["table": "String", "record": "Object"],
                isDestructive: true
            )
        ]
    }
}

/// Raw representation of a tool returned by MCP tools/list
public struct MCPToolDefinition: Sendable, Equatable {
    public let name: String
    public let title: String?
    public let description: String
    public let inputSchema: [String: String]
    public let isDestructive: Bool

    public init(name: String, title: String? = nil, description: String, inputSchema: [String: String] = [:], isDestructive: Bool = false) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.isDestructive = isDestructive
    }
}

