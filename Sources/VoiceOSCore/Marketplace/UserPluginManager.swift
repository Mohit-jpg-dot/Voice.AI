import Foundation

public struct DeclarativePluginToolSpec: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let permissionTier: String // "READ_ONLY" | "REVERSIBLE" | "CONSEQUENTIAL"
    public let responseTemplate: String
    public let webhookURL: String?

    public init(
        name: String,
        description: String,
        permissionTier: String = "REVERSIBLE",
        responseTemplate: String,
        webhookURL: String? = nil
    ) {
        self.name = name
        self.description = description
        self.permissionTier = permissionTier
        self.responseTemplate = responseTemplate
        self.webhookURL = webhookURL
    }
}

public struct ExternalPluginManifest: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let mcpEndpointURL: String?
    public let mcpKeychainTokenKey: String?
    public let declarativeTools: [DeclarativePluginToolSpec]

    public init(
        id: String,
        name: String,
        version: String = "1.0.0",
        mcpEndpointURL: String? = nil,
        mcpKeychainTokenKey: String? = nil,
        declarativeTools: [DeclarativePluginToolSpec] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.mcpEndpointURL = mcpEndpointURL
        self.mcpKeychainTokenKey = mcpKeychainTokenKey
        self.declarativeTools = declarativeTools
    }
}

public protocol UserPluginManaging: Sendable {
    func installedPlugins() -> [ExternalPluginManifest]
    @discardableResult
    func installPlugin(manifest: ExternalPluginManifest) async -> [String]
    func uninstallPlugin(id: String)
    @discardableResult
    func loadPluginsFromDirectory(_ dirURL: URL) async -> Int
}

/// Extensible runtime Plugin & MCP loader (`~/.voiceos/plugins/*.json`) enabling users
/// to add new declarative tools or external MCP servers cleanly without editing core code.
public final class UserPluginManager: UserPluginManaging, @unchecked Sendable {
    public static let shared = UserPluginManager()

    private let lock = NSLock()
    private let storageKey = "VoiceAI_InstalledUserPlugins_v1"
    private var plugins: [ExternalPluginManifest] = []
    private var pluginRegisteredToolNames: [String: [String]] = [:]

    public static var defaultPluginsDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".voiceos", isDirectory: true)
            .appendingPathComponent("plugins", isDirectory: true)
    }

    public init(loadPersisted: Bool = true) {
        if loadPersisted,
           let data = UserDefaults.standard.data(forKey: "VoiceAI_InstalledUserPlugins_v1"),
           let decoded = try? JSONDecoder().decode([ExternalPluginManifest].self, from: data) {
            self.plugins = decoded
        }
    }

    public func installedPlugins() -> [ExternalPluginManifest] {
        lock.withLock { plugins }
    }

    @discardableResult
    public func installPlugin(manifest: ExternalPluginManifest) async -> [String] {
        uninstallPlugin(id: manifest.id)

        var addedToolNames: [String] = []

        // 1. Register declarative user tools
        for spec in manifest.declarativeTools {
            let namespaced = "plugin.\(manifest.id).\(spec.name)"
            let tier: PermissionTier
            switch spec.permissionTier.uppercased() {
            case "READ_ONLY", "READONLY": tier = .readOnly
            case "CONSEQUENTIAL": tier = .consequential
            default: tier = .reversible
            }

            let tool = RegisteredTool(
                name: namespaced,
                appName: manifest.name,
                description: spec.description,
                inputSchema: RegisteredToolSchema(
                    properties: ["input": ToolSchemaProperty(description: "Optional parameter input")],
                    required: []
                ),
                permissionTier: tier,
                source: .builtIn
            ) { args in
                let inputVal = args["input"] ?? ""
                let expanded = spec.responseTemplate.replacingOccurrences(of: "{{input}}", with: inputVal)

                if let rawWebhook = spec.webhookURL, let url = URL(string: rawWebhook),
                   ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] != "1" {
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.timeoutInterval = 4.0
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try? JSONSerialization.data(withJSONObject: ["input": inputVal, "plugin": manifest.id])
                    _ = try? await URLSession.shared.data(for: req)
                }

                return ToolInvocationResult(
                    success: true,
                    summary: SecretRedactor.redact(expanded),
                    data: ["plugin": manifest.id]
                )
            }
            ToolRegistry.shared.register(tool)
            addedToolNames.append(namespaced)
        }

        // 2. Optionally discover & register external MCP server tools
        if let endpointStr = manifest.mcpEndpointURL, let url = URL(string: endpointStr) {
            let config = MCPServerConfig(
                id: manifest.id,
                name: manifest.name,
                endpointURL: url,
                keychainTokenKey: manifest.mcpKeychainTokenKey
            )
            if let mcpTools = try? await MCPClientAdapter.shared.connectAndRegisterServer(config: config) {
                addedToolNames.append(contentsOf: mcpTools.map(\.name))
            }
        }

        lock.withLock {
            plugins.append(manifest)
            pluginRegisteredToolNames[manifest.id] = addedToolNames
            if let data = try? JSONEncoder().encode(plugins) {
                UserDefaults.standard.set(data, forKey: storageKey)
            }
        }

        EventBus.shared.publish(VoiceEvent(
            kind: .custom("plugin_installed"),
            source: "UserPluginManager",
            payload: ["plugin_id": manifest.id, "tools": "\(addedToolNames.count)"]
        ))
        return addedToolNames
    }

    public func uninstallPlugin(id: String) {
        let names = lock.withLock { () -> [String] in
            plugins.removeAll { $0.id == id }
            if let data = try? JSONEncoder().encode(plugins) {
                UserDefaults.standard.set(data, forKey: storageKey)
            }
            return pluginRegisteredToolNames.removeValue(forKey: id) ?? []
        }
        for toolName in names {
            ToolRegistry.shared.unregister(named: toolName)
        }
        ToolRegistry.shared.unregisterMCPServer(serverId: id)
    }

    @discardableResult
    public func loadPluginsFromDirectory(_ dirURL: URL = UserPluginManager.defaultPluginsDirectory) async -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else {
            return 0
        }
        var count = 0
        for file in files where file.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: file),
                  let manifest = try? JSONDecoder().decode(ExternalPluginManifest.self, from: data) else {
                continue
            }
            _ = await installPlugin(manifest: manifest)
            count += 1
        }
        return count
    }
}
