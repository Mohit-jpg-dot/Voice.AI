import Foundation

public struct MCPServerConfig: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let endpointURL: URL
    public let keychainTokenKey: String?

    public init(id: String, name: String, endpointURL: URL, keychainTokenKey: String? = nil) {
        self.id = id
        self.name = name
        self.endpointURL = endpointURL
        self.keychainTokenKey = keychainTokenKey
    }
}

/// Real MCP (Model Context Protocol) JSON-RPC 2.0 client adapter.
/// Discovers external MCP tools (`initialize`, `tools/list`), maps risk hints -> PermissionTier,
/// executes `tools/call`, and registers discovered tools into `ToolRegistry.shared`.
public final class MCPClientAdapter: @unchecked Sendable {
    public static let shared = MCPClientAdapter()

    public typealias RPCTransport = @Sendable (URL, [String: Any], String?) async throws -> [String: Any]

    private let lock = NSLock()
    private var transportOverride: RPCTransport?

    public init() {}

    public func setTransportOverride(_ transport: RPCTransport?) {
        lock.lock()
        self.transportOverride = transport
        lock.unlock()
    }

    /// Discovers tools from an MCP server (or provided mock tools during offline verification)
    /// and registers each discovered tool into `ToolRegistry.shared` under `.mcpServer`.
    public func connectAndRegisterServer(
        config: MCPServerConfig,
        preloadedTools: [MCPToolDefinition]? = nil
    ) async throws -> [RegisteredTool] {
        // Persist optional bearer token key reference only; secret itself stays strictly in KeychainService.
        let discovered: [MCPToolDefinition]
        if let mock = preloadedTools {
            discovered = mock
        } else {
            let token = config.keychainTokenKey.flatMap { KeychainService.shared.get($0) }
            _ = try? await sendJSONRPC(
                endpoint: config.endpointURL,
                method: "initialize",
                params: [
                    "protocolVersion": "2024-11-05",
                    "clientInfo": ["name": AppBrand.name, "version": AppBrand.version]
                ],
                bearerToken: token
            )
            let listResponse = try await sendJSONRPC(
                endpoint: config.endpointURL,
                method: "tools/list",
                params: [:],
                bearerToken: token
            )
            discovered = parseToolsListResponse(listResponse)
        }

        ToolRegistry.shared.unregisterMCPServer(serverId: config.id)
        var registered: [RegisteredTool] = []

        for toolDef in discovered {
            let tier: PermissionTier = toolDef.isDestructive ? .consequential : .readOnly
            let properties = Dictionary(uniqueKeysWithValues: toolDef.inputSchema.map { key, typeName in
                (key, ToolSchemaProperty(type: typeName.lowercased(), description: key))
            })
            let schema = RegisteredToolSchema(properties: properties, required: Array(toolDef.inputSchema.keys).sorted())

            let namespacedName = "mcp.\(config.id).\(toolDef.name)"
            let tool = RegisteredTool(
                name: namespacedName,
                appName: config.name,
                description: toolDef.description,
                inputSchema: schema,
                permissionTier: tier,
                source: .mcpServer(serverId: config.id, endpoint: config.endpointURL.absoluteString)
            ) { [weak self] args in
                guard let self = self else {
                    return ToolInvocationResult(success: false, summary: "MCP client unavailable.")
                }
                return await self.callTool(
                    config: config,
                    remoteToolName: toolDef.name,
                    arguments: args
                )
            }

            ToolRegistry.shared.register(tool)
            registered.append(tool)
        }

        return registered
    }

    public func callTool(
        config: MCPServerConfig,
        remoteToolName: String,
        arguments: [String: String]
    ) async -> ToolInvocationResult {
        let token = config.keychainTokenKey.flatMap { KeychainService.shared.get($0) }
        do {
            let resp = try await sendJSONRPC(
                endpoint: config.endpointURL,
                method: "tools/call",
                params: [
                    "name": remoteToolName,
                    "arguments": arguments
                ],
                bearerToken: token
            )
            if let resultObj = resp["result"] as? [String: Any] {
                if let contentArray = resultObj["content"] as? [[String: Any]] {
                    let texts = contentArray.compactMap { $0["text"] as? String }
                    let output = texts.joined(separator: "\n")
                    let isError = (resultObj["isError"] as? Bool) ?? false
                    return ToolInvocationResult(
                        success: !isError,
                        summary: output.isEmpty ? "MCP tool '\(remoteToolName)' completed." : SecretRedactor.redact(output)
                    )
                }
                if let text = resultObj["summary"] as? String ?? resultObj["output"] as? String {
                    return ToolInvocationResult(success: true, summary: SecretRedactor.redact(text))
                }
                return ToolInvocationResult(success: true, summary: "MCP tool '\(remoteToolName)' executed.")
            }
            if let errorObj = resp["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                return ToolInvocationResult(success: false, summary: "MCP error: \(SecretRedactor.redact(msg))")
            }
            return ToolInvocationResult(success: true, summary: "MCP tool '\(remoteToolName)' completed.")
        } catch {
            return ToolInvocationResult(
                success: false,
                summary: "MCP call '\(remoteToolName)' failed: \(SecretRedactor.redact(error.localizedDescription))"
            )
        }
    }

    private func currentTransportOverride() -> RPCTransport? {
        lock.withLock { transportOverride }
    }

    private func sendJSONRPC(
        endpoint: URL,
        method: String,
        params: [String: Any],
        bearerToken: String?
    ) async throws -> [String: Any] {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": method,
            "params": params
        ]

        if let custom = currentTransportOverride() {
            return try await custom(endpoint, payload, bearerToken)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        if let token = bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "MCPClientAdapter", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "MCP endpoint returned non-2xx status"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "MCPClientAdapter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON-RPC response"])
        }
        return json
    }

    private func parseToolsListResponse(_ resp: [String: Any]) -> [MCPToolDefinition] {
        guard let result = resp["result"] as? [String: Any],
              let tools = result["tools"] as? [[String: Any]] else {
            return []
        }
        return tools.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            let desc = (dict["description"] as? String) ?? ""
            var schemaMap: [String: String] = [:]
            if let schema = dict["inputSchema"] as? [String: Any],
               let props = schema["properties"] as? [String: Any] {
                for (propName, propVal) in props {
                    if let propDict = propVal as? [String: Any], let t = propDict["type"] as? String {
                        schemaMap[propName] = t
                    } else {
                        schemaMap[propName] = "string"
                    }
                }
            }
            let annotations = dict["annotations"] as? [String: Any]
            let destructive = (annotations?["destructiveHint"] as? Bool) ??
                              (dict["isDestructive"] as? Bool) ?? false
            return MCPToolDefinition(
                name: name,
                title: name,
                description: desc,
                inputSchema: schemaMap,
                isDestructive: destructive
            )
        }
    }
}

