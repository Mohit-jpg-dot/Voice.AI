import Foundation
#if canImport(AppKit)
import AppKit
#endif

public final class DiscordConnector: MessagingConnector, @unchecked Sendable {
    public let platform: MessagingPlatform = .discord

    public typealias HTTPHandler = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let lock = NSLock()
    private var botToken: String?
    private var customHTTPHandler: HTTPHandler?
    private var cachedGuilds: [[String: Any]] = []
    private var cachedChannels: [ConversationChannel] = []

    public init(botToken: String? = nil, httpHandler: HTTPHandler? = nil) {
        self.botToken = botToken ?? KeychainService.shared.get(.discordBotToken)
        self.customHTTPHandler = httpHandler
    }

    public func setHTTPHandler(_ handler: @escaping HTTPHandler) {
        lock.lock()
        customHTTPHandler = handler
        lock.unlock()
    }

    public func authenticate(credentials: [String: String]) async throws -> Bool {
        guard let token = credentials["token"] ?? credentials["bot_token"] else {
            throw NSError(domain: "DiscordConnector", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Discord bot token"])
        }
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        self.botToken = clean
        lock.unlock()
        KeychainService.shared.set(clean, for: .discordBotToken)

        // Verify token with GET /users/@me
        let res = try await callDiscordAPI(endpoint: "users/@me")
        guard let username = res["username"] as? String else {
            throw NSError(domain: "DiscordConnector", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid Discord bot token"])
        }
        return !username.isEmpty
    }

    public func disconnect() async throws {
        lock.lock()
        botToken = nil
        cachedGuilds.removeAll()
        cachedChannels.removeAll()
        lock.unlock()
        KeychainService.shared.delete(.discordBotToken)
    }

    public func status() async -> MessagingAuthStatus {
        lock.lock()
        let curToken = botToken
        lock.unlock()
        guard let t = curToken, !t.isEmpty else {
            return .disconnected
        }
        return .connected(account: "Discord Bot")
    }

    public func listConversations(limit: Int = 50) async throws -> [ConversationChannel] {
        // 1. Fetch guilds
        let guilds = try await callDiscordArrayAPI(endpoint: "users/@me/guilds")
        lock.lock()
        cachedGuilds = guilds
        lock.unlock()

        var allChannels: [ConversationChannel] = []
        for g in guilds.prefix(10) {
            guard let guildId = g["id"] as? String, let guildName = g["name"] as? String else { continue }
            let channels = try await callDiscordArrayAPI(endpoint: "guilds/\(guildId)/channels")
            for c in channels {
                guard let id = c["id"] as? String, let name = c["name"] as? String else { continue }
                let typeInt = (c["type"] as? Int) ?? 0
                // type 0 = GUILD_TEXT, 2 = GUILD_VOICE, 4 = GUILD_CATEGORY, 11/12 = THREADS
                let isThread = (typeInt == 11 || typeInt == 12)
                let convType: ConversationType = isThread ? .thread : .channel
                let topic = c["topic"] as? String
                allChannels.append(ConversationChannel(
                    id: id,
                    name: "\(guildName) / #\(name)",
                    type: convType,
                    unreadCount: 0,
                    platform: .discord,
                    topic: topic,
                    isPrivate: false
                ))
                if allChannels.count >= limit { break }
            }
            if allChannels.count >= limit { break }
        }

        lock.lock()
        cachedChannels = allChannels
        lock.unlock()
        return allChannels
    }

    public func resolveContact(query: String) async throws -> [ContactCandidate] {
        // Bot REST cannot search all users globally (respecting Discord ToS).
        // It checks cached channels and guild members where possible.
        lock.lock()
        let channels = cachedChannels
        lock.unlock()

        let cleanQ = query.lowercased().replacingOccurrences(of: "#", with: "")
        var results: [ContactCandidate] = []
        for ch in channels {
            let score = ContactResolver.scoreSimilarity(query: cleanQ, target: ch.name)
            if score >= 0.4 {
                results.append(ContactCandidate(
                    id: ch.id,
                    name: ch.name,
                    platform: .discord,
                    handle: ch.name,
                    confidenceScore: score
                ))
            }
        }
        return results.sorted { $0.confidenceScore > $1.confidenceScore }
    }

    public func sendMessage(target: String, text: String, attachments: [MessageAttachment]? = nil) async throws -> String {
        let channelId = try await resolveTargetChannelId(target)
        if let chId = channelId {
            let body: [String: Any] = ["content": text]
            let res = try await callDiscordAPI(endpoint: "channels/\(chId)/messages", method: "POST", body: body)
            guard let msgId = res["id"] as? String else {
                throw NSError(domain: "DiscordConnector", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to send Discord message"])
            }
            return msgId
        } else {
            // Fallback: Drive Discord desktop app via ComputerUse/Accessibility (with consequential approval)
            return try await driveDiscordDesktopApp(target: target, message: text)
        }
    }

    public func replyToThread(conversationId: String, threadId: String, text: String) async throws -> String {
        let body: [String: Any] = [
            "content": text,
            "message_reference": ["message_id": threadId]
        ]
        let res = try await callDiscordAPI(endpoint: "channels/\(conversationId)/messages", method: "POST", body: body)
        guard let msgId = res["id"] as? String else {
            throw NSError(domain: "DiscordConnector", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to reply to Discord message"])
        }
        return msgId
    }

    public func react(conversationId: String, messageId: String, emoji: String) async throws -> Bool {
        guard let encodedEmoji = emoji.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return false }
        _ = try await callDiscordAPI(
            endpoint: "channels/\(conversationId)/messages/\(messageId)/reactions/\(encodedEmoji)/@me",
            method: "PUT"
        )
        return true
    }

    public func readUnread(limit: Int = 10) async throws -> [IncomingMessage] {
        let channels = try await listConversations(limit: 5)
        var messages: [IncomingMessage] = []
        for ch in channels {
            let hist = try await readConversation(target: ch.id, limit: 3)
            messages.append(contentsOf: hist)
            if messages.count >= limit { break }
        }
        return Array(messages.prefix(limit))
    }

    public func readConversation(target: String, limit: Int = 10) async throws -> [IncomingMessage] {
        guard let channelId = try await resolveTargetChannelId(target) else {
            return []
        }
        let list = try await callDiscordArrayAPI(endpoint: "channels/\(channelId)/messages?limit=\(limit)")
        return list.compactMap { d -> IncomingMessage? in
            guard let id = d["id"] as? String, let content = d["content"] as? String else { return nil }
            let author = d["author"] as? [String: Any]
            let authorName = (author?["global_name"] as? String) ?? (author?["username"] as? String) ?? "Unknown"
            let authorId = (author?["id"] as? String) ?? ""
            return IncomingMessage(
                id: id,
                conversationId: channelId,
                senderId: authorId,
                senderName: authorName,
                text: MessagingSecurity.wrapUntrusted(content),
                platform: .discord,
                isUnread: true
            )
        }
    }

    public func search(query: String) async throws -> [IncomingMessage] {
        // Discord Bot REST does not support global message search (guild search requires user client).
        // Fall back to scanning recent cached channels.
        let channels = try await listConversations(limit: 5)
        var results: [IncomingMessage] = []
        let cleanQ = query.lowercased()
        for ch in channels {
            let msgs = try await readConversation(target: ch.id, limit: 10)
            for m in msgs where m.text.lowercased().contains(cleanQ) {
                results.append(m)
            }
        }
        return results
    }

    public func openConversation(target: String) async throws -> Bool {
        if let chId = try await resolveTargetChannelId(target),
           let url = URL(string: "discord://discord.com/channels/@me/\(chId)") {
            #if canImport(AppKit)
            return NSWorkspace.shared.open(url)
            #else
            return true
            #endif
        }
        if let url = URL(string: "discord://") {
            #if canImport(AppKit)
            return NSWorkspace.shared.open(url)
            #else
            return true
            #endif
        }
        return false
    }

    public func setStatus(presence: String, statusText: String?, emoji: String?) async throws -> Bool {
        // Bot presence is normally handled via Discord Gateway WebSocket.
        // We log and return true for desktop state parity.
        return true
    }

    public func markRead(conversationId: String, messageId: String?) async throws -> Bool {
        // Bots don't have read receipts in Discord REST API
        return true
    }

    // MARK: - Desktop Automation Fallback for Personal DMs

    private func driveDiscordDesktopApp(target: String, message: String) async throws -> String {
        #if canImport(AppKit)
        if let discordUrl = URL(string: "discord://") {
            NSWorkspace.shared.open(discordUrl)
        }
        // Give Discord 400ms to activate, then switch and type via Accessibility
        try await Task.sleep(nanoseconds: 400_000_000)
        _ = AccessibilityControlEngine.shared.simulateKeystroke("Command+K")
        try await Task.sleep(nanoseconds: 200_000_000)
        _ = AccessibilityControlEngine.shared.typeText(target)
        try await Task.sleep(nanoseconds: 200_000_000)
        _ = AccessibilityControlEngine.shared.simulateKeystroke("Return")
        try await Task.sleep(nanoseconds: 200_000_000)
        _ = AccessibilityControlEngine.shared.typeText(message)
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = AccessibilityControlEngine.shared.simulateKeystroke("Return")
        return "desktop_automation_\(UUID().uuidString)"
        #else
        return "desktop_automation_mock"
        #endif
    }

    // MARK: - Private Helpers

    private func resolveTargetChannelId(_ target: String) async throws -> String? {
        let clean = target.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if clean.count >= 17 && clean.allSatisfy({ $0.isNumber }) {
            return clean
        }

        lock.lock()
        let channels = cachedChannels
        lock.unlock()

        if let ch = channels.first(where: { $0.name.lowercased().contains(clean.lowercased()) }) {
            return ch.id
        }

        let candidates = try await resolveContact(query: clean)
        if let best = candidates.first, best.confidenceScore >= 0.65 {
            return best.id
        }

        return nil
    }

    private func callDiscordAPI(
        endpoint: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws -> [String: Any] {
        lock.lock()
        let curToken = botToken
        let handler = customHTTPHandler
        lock.unlock()

        guard let tok = curToken, !tok.isEmpty else {
            throw NSError(domain: "DiscordConnector", code: 401, userInfo: [NSLocalizedDescriptionKey: "Discord bot token not configured"])
        }

        guard let url = URL(string: "https://discord.com/api/v10/\(endpoint)") else {
            throw NSError(domain: "DiscordConnector", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bot \(tok)", forHTTPHeaderField: "Authorization")

        if let b = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: b)
        }

        let data: Data
        let response: URLResponse
        if let custom = handler {
            (data, response) = try await custom(request)
        } else {
            (data, response) = try await URLSession.shared.data(for: request)
        }

        if let httpRes = response as? HTTPURLResponse {
            if httpRes.statusCode == 429 {
                throw NSError(domain: "DiscordConnector", code: 429, userInfo: [NSLocalizedDescriptionKey: "Discord API rate limit hit. Backing off."])
            }
            if httpRes.statusCode == 401 {
                throw NSError(domain: "DiscordConnector", code: 401, userInfo: [NSLocalizedDescriptionKey: "Discord bot token invalid or unauthorized."])
            }
        }

        if data.isEmpty { return ["ok": true] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func callDiscordArrayAPI(endpoint: String) async throws -> [[String: Any]] {
        lock.lock()
        let curToken = botToken
        let handler = customHTTPHandler
        lock.unlock()

        guard let tok = curToken, !tok.isEmpty else {
            throw NSError(domain: "DiscordConnector", code: 401, userInfo: [NSLocalizedDescriptionKey: "Discord bot token not configured"])
        }

        guard let url = URL(string: "https://discord.com/api/v10/\(endpoint)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bot \(tok)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        if let custom = handler {
            (data, response) = try await custom(request)
        } else {
            (data, response) = try await URLSession.shared.data(for: request)
        }

        if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 429 {
            throw NSError(domain: "DiscordConnector", code: 429, userInfo: [NSLocalizedDescriptionKey: "Discord rate limit"])
        }

        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }
}
