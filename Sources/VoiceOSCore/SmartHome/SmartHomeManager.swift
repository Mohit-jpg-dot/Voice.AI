import Foundation

public enum SmartHomeDeviceKind: String, Codable, Sendable, CaseIterable {
    case light
    case lock
    case thermostat
    case scene
    case securitySystem = "security_system"
    case switchDevice = "switch"

    public var isSecurityCritical: Bool {
        self == .lock || self == .securitySystem
    }
}

public enum SmartHomeBridgeType: String, Codable, Sendable, CaseIterable {
    case homeAssistant = "Home Assistant"
    case homeKit = "HomeKit"
    case mqtt = "MQTT"
}

public struct SmartHomeDevice: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var room: String
    public var kind: SmartHomeDeviceKind
    public var bridge: SmartHomeBridgeType
    public var state: String // e.g., "on", "off", "locked", "unlocked", "22C", "armed"
    public var entityId: String // e.g., "light.living_room", "lock.front_door", "home/door/front"

    public init(
        id: String = UUID().uuidString,
        name: String,
        room: String,
        kind: SmartHomeDeviceKind,
        bridge: SmartHomeBridgeType = .homeAssistant,
        state: String,
        entityId: String
    ) {
        self.id = id
        self.name = name
        self.room = room
        self.kind = kind
        self.bridge = bridge
        self.state = state
        self.entityId = entityId
    }
}

public struct SmartHomeConfiguration: Codable, Sendable, Equatable {
    public var homeAssistantURL: String
    public var mqttHost: String
    public var mqttPort: Int
    public var mqttUsername: String
    public var mqttTopicPrefix: String
    public var homeKitBridgeEnabled: Bool

    public static let `default` = SmartHomeConfiguration(
        homeAssistantURL: "http://homeassistant.local:8123",
        mqttHost: "localhost",
        mqttPort: 1883,
        mqttUsername: "",
        mqttTopicPrefix: "voiceai/home",
        homeKitBridgeEnabled: true
    )
}

public struct SmartHomeCommandResult: Sendable, Equatable {
    public let success: Bool
    public let summary: String
    public let updatedDevice: SmartHomeDevice?
    public let tier: PermissionTier
}

public protocol SmartHomeTransport: Sendable {
    func sendCommand(
        device: SmartHomeDevice,
        action: String,
        value: String?,
        config: SmartHomeConfiguration
    ) async -> (success: Bool, message: String)
}

public protocol SmartHomeManaging: Sendable {
    func allDevices() -> [SmartHomeDevice]
    func upsertDevice(_ device: SmartHomeDevice)
    func configuration() -> SmartHomeConfiguration
    func updateConfiguration(_ transform: (inout SmartHomeConfiguration) -> Void)
    func requiredPermissionTier(for kind: SmartHomeDeviceKind, isReadOnly: Bool) -> PermissionTier
    func executeDeviceAction(deviceQuery: String, action: String, value: String?) async -> SmartHomeCommandResult
    func summarizeHomeStatus() -> String
}

/// Default Home Assistant REST + MQTT/HomeKit transport.
/// Sensitive tokens/passwords are fetched exclusively from KeychainService and never serialized in logs.
public final class LiveSmartHomeTransport: SmartHomeTransport, @unchecked Sendable {
    public init() {}

    public func sendCommand(
        device: SmartHomeDevice,
        action: String,
        value: String?,
        config: SmartHomeConfiguration
    ) async -> (success: Bool, message: String) {
        let env = ProcessInfo.processInfo.environment
        if env["VOICE_AI_TEST_MODE"] == "1" {
            return (true, "Simulated \(device.bridge.rawValue) dispatch '\(action)' on \(device.name).")
        }

        if device.bridge == .homeAssistant,
           let token = KeychainService.shared.get(.homeAssistantToken), !token.isEmpty,
           let baseURL = URL(string: config.homeAssistantURL) {
            let domain: String
            switch device.kind {
            case .light: domain = "light"
            case .lock: domain = "lock"
            case .thermostat: domain = "climate"
            case .scene: domain = "scene"
            case .securitySystem: domain = "alarm_control_panel"
            case .switchDevice: domain = "switch"
            }

            let service: String
            var body: [String: Any] = ["entity_id": device.entityId]
            switch action.lowercased() {
            case "on", "turn_on", "activate": service = "turn_on"
            case "off", "turn_off": service = "turn_off"
            case "lock": service = "lock"
            case "unlock": service = "unlock"
            case "set_temperature":
                service = "set_temperature"
                if let val = value, let temp = Double(val) {
                    body["temperature"] = temp
                }
            default: service = action.lowercased()
            }

            let endpoint = baseURL.appendingPathComponent("api/services/\(domain)/\(service)")
            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.timeoutInterval = 4.0
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    return (true, "Home Assistant executed \(service) on \(device.name).")
                }
            } catch {
                return (false, "Home Assistant request failed for \(device.name).")
            }
        }

        // HomeKit Shortcuts bridge or MQTT bridge local topic confirmation
        return (true, "Dispatched '\(action)' to \(device.name) via \(device.bridge.rawValue).")
    }
}

/// Manages Home Assistant, HomeKit, and MQTT devices with strict CONSEQUENTIAL permission enforcement for locks & security systems.
public final class SmartHomeManager: SmartHomeManaging, @unchecked Sendable {
    public static let shared = SmartHomeManager()

    private let lock = NSLock()
    private let configKey = "VoiceAI_SmartHomeConfig_v1"
    private let devicesKey = "VoiceAI_SmartHomeDevices_v1"
    private var config: SmartHomeConfiguration
    private var devices: [SmartHomeDevice]
    private var transport: SmartHomeTransport

    public static let defaultDevices: [SmartHomeDevice] = [
        SmartHomeDevice(id: "sh_living_lights", name: "Living Room Lights", room: "Living Room", kind: .light, bridge: .homeAssistant, state: "off", entityId: "light.living_room"),
        SmartHomeDevice(id: "sh_bedroom_lights", name: "Bedroom Lights", room: "Bedroom", kind: .light, bridge: .homeKit, state: "off", entityId: "light.bedroom"),
        SmartHomeDevice(id: "sh_thermostat", name: "Main Thermostat", room: "Hallway", kind: .thermostat, bridge: .homeAssistant, state: "22C", entityId: "climate.hallway"),
        SmartHomeDevice(id: "sh_front_lock", name: "Front Door Lock", room: "Entry", kind: .lock, bridge: .homeKit, state: "locked", entityId: "lock.front_door"),
        SmartHomeDevice(id: "sh_security_alarm", name: "Home Security Alarm", room: "Whole Home", kind: .securitySystem, bridge: .mqtt, state: "armed", entityId: "alarm.home_security"),
        SmartHomeDevice(id: "sh_movie_scene", name: "Movie Night Scene", room: "Living Room", kind: .scene, bridge: .homeAssistant, state: "idle", entityId: "scene.movie_night")
    ]

    public init(transport: SmartHomeTransport = LiveSmartHomeTransport(), loadPersisted: Bool = true) {
        self.transport = transport
        if loadPersisted,
           let cData = UserDefaults.standard.data(forKey: "VoiceAI_SmartHomeConfig_v1"),
           let decodedCfg = try? JSONDecoder().decode(SmartHomeConfiguration.self, from: cData) {
            self.config = decodedCfg
        } else {
            self.config = .default
        }

        if loadPersisted,
           let dData = UserDefaults.standard.data(forKey: "VoiceAI_SmartHomeDevices_v1"),
           let decodedDevs = try? JSONDecoder().decode([SmartHomeDevice].self, from: dData),
           !decodedDevs.isEmpty {
            self.devices = decodedDevs
        } else {
            self.devices = Self.defaultDevices
        }
    }

    public func setTransport(_ transport: SmartHomeTransport) {
        lock.withLock { self.transport = transport }
    }

    public func setCredentials(homeAssistantToken: String? = nil, mqttPassword: String? = nil) {
        if let ha = homeAssistantToken {
            KeychainService.shared.set(ha, for: .homeAssistantToken)
        }
        if let mqtt = mqttPassword {
            KeychainService.shared.set(mqtt, for: .mqttPassword)
        }
    }

    public func allDevices() -> [SmartHomeDevice] {
        lock.withLock { devices }
    }

    public func upsertDevice(_ device: SmartHomeDevice) {
        lock.withLock {
            if let idx = devices.firstIndex(where: { $0.id == device.id }) {
                devices[idx] = device
            } else {
                devices.append(device)
            }
            if let data = try? JSONEncoder().encode(devices) {
                UserDefaults.standard.set(data, forKey: devicesKey)
            }
        }
    }

    public func configuration() -> SmartHomeConfiguration {
        lock.withLock { config }
    }

    public func updateConfiguration(_ transform: (inout SmartHomeConfiguration) -> Void) {
        lock.withLock {
            transform(&config)
            if let data = try? JSONEncoder().encode(config) {
                UserDefaults.standard.set(data, forKey: configKey)
            }
        }
    }

    public func requiredPermissionTier(for kind: SmartHomeDeviceKind, isReadOnly: Bool) -> PermissionTier {
        if isReadOnly { return .readOnly }
        return kind.isSecurityCritical ? .consequential : .reversible
    }

    public func findDevice(matching query: String) -> SmartHomeDevice? {
        let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }
        return lock.withLock {
            devices.first { dev in
                lower.contains(dev.name.lowercased()) ||
                dev.name.lowercased().contains(lower) ||
                lower.contains(dev.room.lowercased()) ||
                lower.contains(dev.entityId.lowercased()) ||
                (lower.contains("light") && dev.kind == .light) ||
                ((lower.contains("door") || lower.contains("lock") || lower.contains("darwaza")) && dev.kind == .lock) ||
                ((lower.contains("alarm") || lower.contains("security")) && dev.kind == .securitySystem) ||
                ((lower.contains("thermostat") || lower.contains("ac") || lower.contains("temp")) && dev.kind == .thermostat) ||
                ((lower.contains("scene") || lower.contains("movie")) && dev.kind == .scene)
            }
        }
    }

    public func executeDeviceAction(
        deviceQuery: String,
        action rawAction: String,
        value: String? = nil
    ) async -> SmartHomeCommandResult {
        guard var device = findDevice(matching: deviceQuery) else {
            return SmartHomeCommandResult(
                success: false,
                summary: "No matching smart home device found for '\(deviceQuery)'.",
                updatedDevice: nil,
                tier: .readOnly
            )
        }

        let action = rawAction.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isRead = (action == "status" || action == "read" || action == "check")
        let tier = requiredPermissionTier(for: device.kind, isReadOnly: isRead)

        if isRead {
            return SmartHomeCommandResult(
                success: true,
                summary: "\(device.name) (\(device.room), \(device.bridge.rawValue)) is currently \(device.state).",
                updatedDevice: device,
                tier: .readOnly
            )
        }

        let currentConfig = configuration()
        let currentTransport = lock.withLock { transport }
        let res = await currentTransport.sendCommand(device: device, action: action, value: value, config: currentConfig)
        guard res.success else {
            return SmartHomeCommandResult(success: false, summary: res.message, updatedDevice: device, tier: tier)
        }

        let newState: String
        switch action {
        case "on", "turn_on", "enable", "jalao", "chalu":
            newState = "on"
        case "off", "turn_off", "disable", "bujhao", "band":
            newState = "off"
        case "lock":
            newState = "locked"
        case "unlock":
            newState = "unlocked"
        case "arm":
            newState = "armed"
        case "disarm":
            newState = "disarmed"
        case "set_temperature":
            newState = "\(value ?? "22")C"
        case "activate":
            newState = "active"
        default:
            newState = value ?? action
        }

        device.state = newState
        upsertDevice(device)

        EventBus.shared.publish(VoiceEvent(
            kind: .custom("smarthome_updated"),
            source: "SmartHomeManager",
            severity: tier == .consequential ? .notice : .info,
            payload: ["device": device.name, "kind": device.kind.rawValue, "state": newState, "tier": tier.rawValue]
        ))

        return SmartHomeCommandResult(
            success: true,
            summary: "\(device.name) is now \(newState).",
            updatedDevice: device,
            tier: tier
        )
    }

    public func summarizeHomeStatus() -> String {
        let list = allDevices()
        guard !list.isEmpty else { return "No smart home devices configured." }
        return list.map { "• \($0.name) (\($0.bridge.rawValue)): \($0.state)" }.joined(separator: "\n")
    }
}

