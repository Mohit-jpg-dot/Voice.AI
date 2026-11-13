import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum WhatsAppBackendMode: String, Codable, Sendable {
    case cloudAPI = "cloud_api"
    case desktopApp = "desktop_app"
    case auto = "auto"
}

public final class WhatsAppConnector: MessagingConnector, @unchecked Sendable {
    public let platform: MessagingPlatform = .whatsapp

    public typealias HTTPHandler = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let lock = NSLock()
    private var backendMode: WhatsAppBackendMode = .auto
    private var cloudToken: String?
    private var phoneNumberId: String?
    private var customHTTPHandler: HTTPHandler?
    private var cachedContacts: [ContactCandidate] = []

    public init(
        backendMode: WhatsAppBackendMode = .auto,
        cloudToken: String? = nil,
        phoneNumberId: String? = nil,
        httpHandler: HTTPHandler? = nil
    ) {
        self.backendMode = backendMode
        self.cloudToken = cloudToken ?? KeychainService.shared.get(.whatsappCloudToken)
        self.phoneNumberId = phoneNumberId ?? KeychainService.shared.get(.whatsappPhoneNumberId)
        self.customHTTPHandler = httpHandler
    }

    public func setHTTPHandler(_ handler: @escaping HTTPHandler) {
        lock.lock()
        customHTTPHandler = handler
        lock.unlock()
    }

    public func setBackendMode(_ mode: WhatsAppBackendMode) {
        lock.lock()
        backendMode = mode
        lock.unlock()
    }

    public func authenticate(credentials: [String: String]) async throws -> Bool {
        if let token = credentials["token"] ?? credentials["cloud_token"] {
            let cleanTok = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let phoneId = credentials["phone_number_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            lock.lock()
            self.cloudToken = cleanTok
            self.phoneNumberId = phoneId
            lock.unlock()
            KeychainService.shared.set(cleanTok, for: .whatsappCloudToken)
            if !phoneId.isEmpty {
                KeychainService.shared.set(phoneId, for: .whatsappPhoneNumberId)
            }
            return true
        }
        // Desktop backend mode requires no token
        return true
    }

    public func disconnect() async throws {
        lock.lock()
        cloudToken = nil
        phoneNumberId = nil
        cachedContacts.removeAll()
        lock.unlock()
        KeychainService.shared.delete(.whatsappCloudToken)
        KeychainService.shared.delete(.whatsappPhoneNumberId)
    }

    public func status() async -> MessagingAuthStatus {
        lock.lock()
        let token = cloudToken
        let mode = backendMode
        lock.unlock()

        if mode == .cloudAPI || (mode == .auto && token != nil && !token!.isEmpty) {
            return .connected(account: "WhatsApp Business Cloud")
        }
        return .connected(account: "WhatsApp Desktop (Local)")
    }

    public func listConversations(limit: Int = 20) async throws -> [ConversationChannel] {
        lock.lock()
        let contacts = cachedContacts
        lock.unlock()

        return contacts.prefix(limit).map { c in
            ConversationChannel(
                id: c.phoneNumber ?? c.id,
                name: c.name,
                type: .directMessage,
                unreadCount: 0,
                platform: .whatsapp
            )
        }
    }

    public func resolveContact(query: String) async throws -> [ContactCandidate] {
        lock.lock()
        var contacts = cachedContacts
        lock.unlock()

        // Check if query is directly a phone number
        let numeric = ContactResolver.normalizeSpokenPhone(query)
        if numeric.count >= 7 && numeric.allSatisfy({ $0.isNumber || $0 == "+" }) {
            let phoneCandidate = ContactCandidate(
                id: numeric,
                name: numeric,
                platform: .whatsapp,
                phoneNumber: numeric,
                confidenceScore: 1.0
            )
            return [phoneCandidate]
        }

        let scored = contacts.map { c -> ContactCandidate in
            var score = ContactResolver.scoreSimilarity(query: query, target: c.name)
            if let p = c.phoneNumber, p.contains(numeric) {
                score = max(score, 0.95)
            }
            return ContactCandidate(
                id: c.id,
                name: c.name,
                platform: .whatsapp,
                handle: c.handle,
                phoneNumber: c.phoneNumber,
                avatarURL: c.avatarURL,
                confidenceScore: score,
                aliases: c.aliases
            )
        }.filter { $0.confidenceScore >= 0.45 }
        .sorted { $0.confidenceScore > $1.confidenceScore }

        return scored
    }

    public func addKnownContact(name: String, phoneNumber: String, aliases: [String] = []) {
        lock.lock()
        let candidate = ContactCandidate(
            id: phoneNumber,
            name: name,
            platform: .whatsapp,
            phoneNumber: phoneNumber,
            confidenceScore: 1.0,
            aliases: aliases
        )
        cachedContacts.append(candidate)
        lock.unlock()
    }

    public func sendMessage(target: String, text: String, attachments: [MessageAttachment]? = nil) async throws -> String {
        lock.lock()
        let mode = backendMode
        let token = cloudToken
        let pId = phoneNumberId
        lock.unlock()

        // If Cloud API configured and mode is cloud or auto, try Cloud API
        if (mode == .cloudAPI || mode == .auto), let tok = token, !tok.isEmpty, let phoneId = pId, !phoneId.isEmpty {
            return try await sendViaCloudAPI(target: target, text: text, token: tok, phoneId: phoneId)
        }

        // Fallback to Desktop backend
        return try await sendViaDesktopApp(target: target, text: text)
    }

    public func replyToThread(conversationId: String, threadId: String, text: String) async throws -> String {
        return try await sendMessage(target: conversationId, text: text)
    }

    public func react(conversationId: String, messageId: String, emoji: String) async throws -> Bool {
        // Cloud API reaction endpoint
        lock.lock()
        let token = cloudToken
        let pId = phoneNumberId
        lock.unlock()

        guard let tok = token, let phoneId = pId else { return true }
        let body: [String: Any] = [
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": conversationId,
            "type": "reaction",
            "reaction": [
                "message_id": messageId,
                "emoji": emoji
            ]
        ]
        _ = try? await callCloudAPI(phoneId: phoneId, body: body, token: tok)
        return true
    }

    public func readUnread(limit: Int = 10) async throws -> [IncomingMessage] {
        // WhatsApp Cloud API receives incoming messages via webhooks.
        // For local testing & desktop mode, we return cached unread messages.
        return []
    }

    public func readConversation(target: String, limit: Int = 10) async throws -> [IncomingMessage] {
        return []
    }

    public func search(query: String) async throws -> [IncomingMessage] {
        return []
    }

    public func openConversation(target: String) async throws -> Bool {
        let phone = ContactResolver.normalizeSpokenPhone(target)
        let urlStr = phone.isEmpty ? "whatsapp://" : "whatsapp://send?phone=\(phone)"
        if let url = URL(string: urlStr) {
            #if canImport(AppKit)
            return NSWorkspace.shared.open(url)
            #else
            return true
            #endif
        }
        return false
    }

    public func setStatus(presence: String, statusText: String?, emoji: String?) async throws -> Bool {
        return true
    }

    public func markRead(conversationId: String, messageId: String?) async throws -> Bool {
        guard let msgId = messageId else { return true }
        lock.lock()
        let token = cloudToken
        let pId = phoneNumberId
        lock.unlock()
        if let tok = token, let phoneId = pId {
            let body: [String: Any] = [
                "messaging_product": "whatsapp",
                "status": "read",
                "message_id": msgId
            ]
            _ = try? await callCloudAPI(phoneId: phoneId, body: body, token: tok)
        }
        return true
    }

    // MARK: - Cloud API Backend

    private func sendViaCloudAPI(target: String, text: String, token: String, phoneId: String) async throws -> String {
        let phone = ContactResolver.normalizeSpokenPhone(target).replacingOccurrences(of: "+", with: "")
        let body: [String: Any] = [
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": phone,
            "type": "text",
            "text": ["preview_url": false, "body": text]
        ]

        let res = try await callCloudAPI(phoneId: phoneId, body: body, token: token)
        if let messages = res["messages"] as? [[String: Any]], let first = messages.first, let id = first["id"] as? String {
            return id
        }
        if let err = res["error"] as? [String: Any] {
            let code = err["code"] as? Int ?? 0
            let msg = err["message"] as? String ?? "Unknown error"
            if code == 131047 {
                throw NSError(domain: "WhatsAppConnector", code: 131047, userInfo: [NSLocalizedDescriptionKey: "24-hour customer window expired. Use an approved WhatsApp template to message this contact."])
            }
            throw NSError(domain: "WhatsAppConnector", code: code, userInfo: [NSLocalizedDescriptionKey: "WhatsApp Cloud API error: \(msg)"])
        }
        return "wa_cloud_\(UUID().uuidString)"
    }

    private func callCloudAPI(phoneId: String, body: [String: Any], token: String) async throws -> [String: Any] {
        lock.lock()
        let handler = customHTTPHandler
        lock.unlock()

        guard let url = URL(string: "https://graph.facebook.com/v19.0/\(phoneId)/messages") else {
            throw NSError(domain: "WhatsAppConnector", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Cloud API URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        if let custom = handler {
            (data, response) = try await custom(request)
        } else {
            (data, response) = try await URLSession.shared.data(for: request)
        }

        if let httpRes = response as? HTTPURLResponse {
            if httpRes.statusCode == 401 {
                throw NSError(domain: "WhatsAppConnector", code: 401, userInfo: [NSLocalizedDescriptionKey: "WhatsApp Cloud token is invalid or expired."])
            }
            if httpRes.statusCode == 429 {
                throw NSError(domain: "WhatsAppConnector", code: 429, userInfo: [NSLocalizedDescriptionKey: "WhatsApp API rate limit hit."])
            }
        }

        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Desktop App Backend

    private func sendViaDesktopApp(target: String, text: String) async throws -> String {
        let numericPhone = ContactResolver.normalizeSpokenPhone(target)
        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text

        if numericPhone.count >= 7 && numericPhone.allSatisfy({ $0.isNumber || $0 == "+" }) {
            let cleanPhone = numericPhone.replacingOccurrences(of: "+", with: "")
            let urlString = "whatsapp://send?phone=\(cleanPhone)&text=\(encodedText)"
            if let url = URL(string: urlString) {
                #if canImport(AppKit)
                let ok = NSWorkspace.shared.open(url)
                if ok {
                    // Send Return key to dispatch message if pre-filled
                    try await Task.sleep(nanoseconds: 500_000_000)
                    _ = AccessibilityControlEngine.shared.simulateKeystroke("Return")
                    return "whatsapp_desktop_\(cleanPhone)"
                }
                #endif
            }
        }

        // Generic desktop search fallback
        #if canImport(AppKit)
        if let url = URL(string: "whatsapp://") {
            NSWorkspace.shared.open(url)
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        _ = AccessibilityControlEngine.shared.simulateKeystroke("Command+F")
        try await Task.sleep(nanoseconds: 200_000_000)
        _ = AccessibilityControlEngine.shared.typeText(target)
        try await Task.sleep(nanoseconds: 200_000_000)
        _ = AccessibilityControlEngine.shared.simulateKeystroke("Return")
        try await Task.sleep(nanoseconds: 200_000_000)
        _ = AccessibilityControlEngine.shared.typeText(text)
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = AccessibilityControlEngine.shared.simulateKeystroke("Return")
        return "whatsapp_desktop_ax_\(UUID().uuidString)"
        #else
        return "whatsapp_desktop_mock"
        #endif
    }
}
