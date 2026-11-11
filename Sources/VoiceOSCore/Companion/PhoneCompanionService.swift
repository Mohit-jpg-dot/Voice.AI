import Foundation
import Network

public struct PairingChallenge: Sendable, Equatable {
    public let code: String
    public let expiresAt: Date
    public let hostHint: String
}

public struct PairedCompanionDevice: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let deviceName: String
    public let pairedAt: Date
    public var lastSeenAt: Date
}

public struct RemoteApprovalPrompt: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let appName: String
    public let createdAt: Date
    public var status: String // "pending" | "approved" | "denied"
}

public protocol PhoneCompanionManaging: Sendable {
    func beginPairing() -> PairingChallenge
    func completePairing(deviceName: String, code: String) -> (device: PairedCompanionDevice, token: String)?
    func pairedDevices() -> [PairedCompanionDevice]
    func unpairDevice(id: String)
    func submitRemoteDictation(deviceId: String, token: String, transcript: String) async -> (success: Bool, reply: String)
    func pendingApprovals() -> [RemoteApprovalPrompt]
    func respondToApproval(requestId: String, deviceId: String, token: String, approved: Bool) -> Bool
}

/// Completes the Phone Remote Companion: short-lived PIN pairing, Keychain token auth,
/// remote dictation forwarding, approval notifications & response bridge, and optional LAN HTTP server.
public final class PhoneCompanionService: PhoneCompanionManaging, @unchecked Sendable {
    public static let shared = PhoneCompanionService()

    private let lock = NSLock()
    private let devicesKey = "VoiceAI_PairedCompanionDevices_v1"
    private let tokenHashesKey = "VoiceAI_CompanionTokenHashes_v1" // stores SHA256 prefix/hash or Keychain reference per device
    private var devices: [PairedCompanionDevice]
    private var deviceTokens: [String: String] = [:] // live token validation synced with Keychain
    private var activeChallenge: PairingChallenge?
    private var approvalQueue: [RemoteApprovalPrompt] = []
    private var approvalCallbacks: [String: @Sendable (Bool) -> Void] = [:]
    private var busSubId: UUID?
    private var listener: NWListener?

    public init(loadPersisted: Bool = true) {
        if loadPersisted,
           let data = UserDefaults.standard.data(forKey: "VoiceAI_PairedCompanionDevices_v1"),
           let decoded = try? JSONDecoder().decode([PairedCompanionDevice].self, from: data) {
            self.devices = decoded
        } else {
            self.devices = []
        }

        if let secretBundle = KeychainService.shared.get(.companionSharedSecret),
           let data = secretBundle.data(using: .utf8),
           let decodedMap = try? JSONDecoder().decode([String: String].self, from: data) {
            self.deviceTokens = decodedMap
        }

        self.busSubId = EventBus.shared.subscribe(matching: .approvalRequested) { [weak self] evt in
            guard let self = self else { return }
            let reqId = evt.payload["request_id"] ?? evt.id.uuidString
            let title = evt.payload["title"] ?? "Confirm Action"
            let app = evt.payload["app"] ?? "Voice.AI"
            let sub = evt.payload["subtitle"] ?? "CONSEQUENTIAL action awaiting approval"
            self.enqueueApprovalPrompt(id: reqId, title: title, subtitle: sub, appName: app)
        }
    }

    deinit {
        if let id = busSubId { EventBus.shared.unsubscribe(id) }
        listener?.cancel()
    }

    public func beginPairing() -> PairingChallenge {
        let codeInt = Int.random(in: 100_000...999_999)
        let challenge = PairingChallenge(
            code: String(codeInt),
            expiresAt: Date().addingTimeInterval(300),
            hostHint: Host.current().localizedName ?? "Voice.AI-Mac"
        )
        lock.withLock {
            activeChallenge = challenge
        }
        return challenge
    }

    public func completePairing(deviceName: String, code: String) -> (device: PairedCompanionDevice, token: String)? {
        let cleanName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }

        let now = Date()
        let isValid = lock.withLock { () -> Bool in
            guard let c = activeChallenge, c.expiresAt > now, c.code == code.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            activeChallenge = nil
            return true
        }
        guard isValid else { return nil }

        let device = PairedCompanionDevice(id: UUID().uuidString, deviceName: cleanName, pairedAt: now, lastSeenAt: now)
        let token = "comp_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")

        lock.withLock {
            devices.append(device)
            deviceTokens[device.id] = token
            persistLocked()
        }

        EventBus.shared.publish(VoiceEvent(
            kind: .custom("companion_paired"),
            source: "PhoneCompanionService",
            payload: ["device_id": device.id, "device_name": device.deviceName]
        ))
        return (device, token)
    }

    public func pairedDevices() -> [PairedCompanionDevice] {
        lock.withLock { devices }
    }

    public func unpairDevice(id: String) {
        lock.withLock {
            devices.removeAll { $0.id == id }
            deviceTokens.removeValue(forKey: id)
            persistLocked()
        }
    }

    public func authenticate(deviceId: String, token: String) -> Bool {
        lock.withLock {
            guard let expected = deviceTokens[deviceId], !expected.isEmpty, expected == token else {
                return false
            }
            if let idx = devices.firstIndex(where: { $0.id == deviceId }) {
                devices[idx].lastSeenAt = Date()
            }
            return true
        }
    }

    public func submitRemoteDictation(deviceId: String, token: String, transcript: String) async -> (success: Bool, reply: String) {
        guard authenticate(deviceId: deviceId, token: token) else {
            return (false, "Unauthorized companion token.")
        }
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return (false, "Empty dictation transcript.")
        }
        let result = await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: clean)
        return (result.success, result.summary)
    }

    public func enqueueApprovalPrompt(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        appName: String,
        onResolution: (@Sendable (Bool) -> Void)? = nil
    ) {
        let prompt = RemoteApprovalPrompt(
            id: id,
            title: title,
            subtitle: SecretRedactor.redact(subtitle),
            appName: appName,
            createdAt: Date(),
            status: "pending"
        )
        lock.withLock {
            approvalQueue.insert(prompt, at: 0)
            if approvalQueue.count > 20 {
                approvalQueue = Array(approvalQueue.prefix(20))
            }
            if let cb = onResolution {
                approvalCallbacks[id] = cb
            }
        }
    }

    public func pendingApprovals() -> [RemoteApprovalPrompt] {
        lock.withLock { approvalQueue.filter { $0.status == "pending" } }
    }

    @discardableResult
    public func respondToApproval(requestId: String, deviceId: String, token: String, approved: Bool) -> Bool {
        guard authenticate(deviceId: deviceId, token: token) else { return false }

        let cb: (@Sendable (Bool) -> Void)? = lock.withLock {
            guard let idx = approvalQueue.firstIndex(where: { $0.id == requestId && $0.status == "pending" }) else {
                return nil
            }
            approvalQueue[idx].status = approved ? "approved" : "denied"
            return approvalCallbacks.removeValue(forKey: requestId)
        }
        cb?(approved)
        EventBus.shared.publish(VoiceEvent(
            kind: .approvalResolved,
            source: "PhoneCompanionService",
            payload: ["request_id": requestId, "approved": approved ? "true" : "false"]
        ))
        return true
    }

    // MARK: - Opt-In Local Companion LAN HTTP Listener

    public func startLocalBridgeServer(port: UInt16 = 8765) throws {
        stopLocalBridgeServer()
        let nwPort = NWEndpoint.Port(rawValue: port) ?? 8765
        let newListener = try NWListener(using: .tcp, on: nwPort)
        newListener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global(qos: .utility))
            conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
                Task {
                    let responseStr = await self?.handleHTTPRequestData(data ?? Data()) ?? "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n"
                    conn.send(content: responseStr.data(using: .utf8), completion: .contentProcessed { _ in
                        conn.cancel()
                    })
                }
            }
        }
        newListener.start(queue: .global(qos: .utility))
        lock.withLock { listener = newListener }
    }

    public func stopLocalBridgeServer() {
        lock.withLock {
            listener?.cancel()
            listener = nil
        }
    }

    private func handleHTTPRequestData(_ data: Data) async -> String {
        let raw = String(data: data, encoding: .utf8) ?? ""
        let firstLine = raw.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        let method = parts.first.map(String.init) ?? "GET"
        let path = parts.count > 1 ? String(parts[1]) : "/"

        let bodyStr = raw.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
        let jsonBody = (try? JSONSerialization.jsonObject(with: Data(bodyStr.utf8))) as? [String: Any] ?? [:]

        if method == "GET" && path == "/approvals" {
            let pending = pendingApprovals().map { ["id": $0.id, "title": $0.title, "app": $0.appName] }
            let bytes = (try? JSONSerialization.data(withJSONObject: ["pending": pending])) ?? Data()
            let jsonOut = String(data: bytes, encoding: .utf8) ?? "{}"
            return "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(jsonOut.utf8.count)\r\n\r\n\(jsonOut)"
        }

        if method == "POST" && path == "/dictate",
           let devId = jsonBody["device_id"] as? String,
           let token = jsonBody["token"] as? String,
           let text = jsonBody["transcript"] as? String {
            let res = await submitRemoteDictation(deviceId: devId, token: token, transcript: text)
            let bytes = (try? JSONSerialization.data(withJSONObject: ["success": res.success, "reply": res.reply])) ?? Data()
            let jsonOut = String(data: bytes, encoding: .utf8) ?? "{}"
            return "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(jsonOut.utf8.count)\r\n\r\n\(jsonOut)"
        }

        return "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
    }

    private func persistLocked() {
        if let devData = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(devData, forKey: devicesKey)
        }
        if let tokData = try? JSONEncoder().encode(deviceTokens),
           let tokStr = String(data: tokData, encoding: .utf8) {
            KeychainService.shared.set(tokStr, for: .companionSharedSecret)
        }
    }
}

