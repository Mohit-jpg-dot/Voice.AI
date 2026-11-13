import Foundation
#if canImport(AppKit)
import AppKit
#endif

public final class SlackConnector: MessagingConnector, @unchecked Sendable {
    public let platform: MessagingPlatform = .slack

    public typealias HTTPHandler = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let lock = NSLock()
    private var token: String?
    private var customHTTPHandler: HTTPHandler?
    private var cachedChannels: [ConversationChannel] = []
    private var cachedUsers: [ContactCandidate] = []

    public init(token: String? = nil, httpHandler: HTTPHandler? = nil) {
        self.token = token ?? KeychainService.shared.get(.slackUserToken)
        self.customHTTPHandler = httpHandler
    }

    public func setHTTPHandler(_ handler: @escaping HTTPHandler) {
        lock.lock()
        customHTTPHandler = handler
        lock.unlock()
    }

    public func authenticate(credentials: [String: String]) async throws -> Bool {
        guard let tok = credentials["token"] ?? credentials["user_token"] else {
            throw NSError(domain: "SlackConnector", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing token"])
        }
        let clean = tok.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        self.token = clean
        lock.unlock()
        KeychainService.shared.set(clean, for: .slackUserToken)

        // Verify token with auth.test
        let res = try await callSlackAPI(endpoint: "auth.test", body: [:])
        guard let ok = res["ok"] as? Bool, ok else {
            let err = res["error"] as? String ?? "auth_failed"
            throw NSError(domain: "SlackConnector", code: 401, userInfo: [NSLocalizedDescriptionKey: "Slack auth failed: \(err)"])
        }
        return true
    }

    public func disconnect() async throws {
        lock.lock()
        token = nil
        cachedChannels.removeAll()
        cachedUsers.removeAll()
        lock.unlock()
        KeychainService.shared.delete(.slackUserToken)
    }

    public func status() async -> MessagingAuthStatus {
        lock.lock()
        let curToken = token
        lock.unlock()
        guard let t = curToken, !t.isEmpty else {
            return .disconnected
        }
        return .connected(account: "Slack User")
    }

    public func listConversations(limit: Int = 50) async throws -> [ConversationChannel] {
        let res = try await callSlackAPI(
            endpoint: "conversations.list",
            query: ["types": "public_channel,private_channel,im,mpim", "limit": "\(limit)"]
        )
        guard let ok = res["ok"] as? Bool, ok, let channels = res["channels"] as? [[String: Any]] else {
            throw NSError(domain: "SlackConnector", code: 500, userInfo: [NSLocalizedDescriptionKey: res["error"] as? String ?? "Failed to list conversations"])
        }
        let mapped = channels.compactMap { d -> ConversationChannel? in
            guard let id = d["id"] as? String else { return nil }
            let name = (d["name"] as? String) ?? id
            let isChannel = (d["is_channel"] as? Bool) ?? false
            let isGroup = (d["is_group"] as? Bool) ?? false
            let isIm = (d["is_im"] as? Bool) ?? false
            let type: ConversationType = isIm ? .directMessage : (isGroup ? .groupDM : .channel)
            let unread = (d["unread_count"] as? Int) ?? 0
            let isPrivate = (d["is_private"] as? Bool) ?? false
            let topic = (d["topic"] as? [String: Any])?["value"] as? String
            return ConversationChannel(id: id, name: name, type: type, unreadCount: unread, platform: .slack, topic: topic, isPrivate: isPrivate)
        }
        lock.lock()
        cachedChannels = mapped
        lock.unlock()
        return mapped
    }

    public func resolveContact(query: String) async throws -> [ContactCandidate] {
        // Fetch users if not cached
        lock.lock()
        var users = cachedUsers
        lock.unlock()

        if users.isEmpty {
            let res = try await callSlackAPI(endpoint: "users.list", query: ["limit": "100"])
            if let ok = res["ok"] as? Bool, ok, let members = res["members"] as? [[String: Any]] {
                users = members.compactMap { m -> ContactCandidate? in
                    guard let id = m["id"] as? String else { return nil }
                    let name = (m["real_name"] as? String) ?? (m["name"] as? String) ?? id
                    let handle = m["name"] as? String
                    let profile = m["profile"] as? [String: Any]
                    let phone = profile?["phone"] as? String
                    let avatar = profile?["image_72"] as? String
                    return ContactCandidate(
                        id: id,
                        name: name,
                        platform: .slack,
                        handle: handle,
                        phoneNumber: phone,
                        avatarURL: avatar
                    )
                }
                lock.lock()
                cachedUsers = users
                lock.unlock()
            }
        }

        // Use ContactResolver scoring
        let scored = users.map { candidate -> ContactCandidate in
            let score = ContactResolver.scoreSimilarity(query: query, target: candidate.name)
            return ContactCandidate(
                id: candidate.id,
                name: candidate.name,
                platform: candidate.platform,
                handle: candidate.handle,
                phoneNumber: candidate.phoneNumber,
                avatarURL: candidate.avatarURL,
                confidenceScore: score,
                aliases: candidate.aliases
            )
        }.filter { $0.confidenceScore >= 0.4 }
        .sorted { $0.confidenceScore > $1.confidenceScore }

        return scored
    }

    public func sendMessage(target: String, text: String, attachments: [MessageAttachment]? = nil) async throws -> String {
        // Resolve channel or user ID
        let resolvedTarget = try await resolveTargetId(target)
        let body: [String: Any] = [
            "channel": resolvedTarget,
            "text": text
        ]
        let res = try await callSlackAPI(endpoint: "chat.postMessage", body: body)
        guard let ok = res["ok"] as? Bool, ok, let ts = res["ts"] as? String else {
            let err = res["error"] as? String ?? "send_failed"
            throw NSError(domain: "SlackConnector", code: 500, userInfo: [NSLocalizedDescriptionKey: "Slack send failed: \(err)"])
        }
        return ts
    }

    public func replyToThread(conversationId: String, threadId: String, text: String) async throws -> String {
        let body: [String: Any] = [
            "channel": conversationId,
            "thread_ts": threadId,
            "text": text
        ]
        let res = try await callSlackAPI(endpoint: "chat.postMessage", body: body)
        guard let ok = res["ok"] as? Bool, ok, let ts = res["ts"] as? String else {
            let err = res["error"] as? String ?? "reply_failed"
            throw NSError(domain: "SlackConnector", code: 500, userInfo: [NSLocalizedDescriptionKey: "Slack thread reply failed: \(err)"])
        }
        return ts
    }

    public func react(conversationId: String, messageId: String, emoji: String) async throws -> Bool {
        let cleanEmoji = emoji.replacingOccurrences(of: ":", with: "")
        let body: [String: Any] = [
            "channel": conversationId,
            "timestamp": messageId,
            "name": cleanEmoji
        ]
        let res = try await callSlackAPI(endpoint: "reactions.add", body: body)
        return (res["ok"] as? Bool) ?? false
    }

    public func readUnread(limit: Int = 10) async throws -> [IncomingMessage] {
        let channels = try await listConversations(limit: 20)
        var unread: [IncomingMessage] = []
        for ch in channels where ch.unreadCount > 0 {
            let msgs = try await readConversation(target: ch.id, limit: min(limit, ch.unreadCount))
            unread.append(contentsOf: msgs.filter(\.isUnread))
            if unread.count >= limit { break }
        }
        return Array(unread.prefix(limit))
    }

    public func readConversation(target: String, limit: Int = 10) async throws -> [IncomingMessage] {
        let channelId = try await resolveTargetId(target)
        let res = try await callSlackAPI(endpoint: "conversations.history", query: ["channel": channelId, "limit": "\(limit)"])
        guard let ok = res["ok"] as? Bool, ok, let messages = res["messages"] as? [[String: Any]] else {
            throw NSError(domain: "SlackConnector", code: 500, userInfo: [NSLocalizedDescriptionKey: res["error"] as? String ?? "Failed to read history"])
        }
        return messages.compactMap { d -> IncomingMessage? in
            guard let ts = d["ts"] as? String, let text = d["text"] as? String else { return nil }
            let sender = (d["user"] as? String) ?? "unknown"
            let thread = d["thread_ts"] as? String
            // Wrap text as untrusted
            let safeText = MessagingSecurity.wrapUntrusted(text)
            return IncomingMessage(
                id: ts,
                conversationId: channelId,
                senderId: sender,
                senderName: sender,
                text: safeText,
                platform: .slack,
                threadId: thread,
                isUnread: true
            )
        }
    }

    public func search(query: String) async throws -> [IncomingMessage] {
        let res = try await callSlackAPI(endpoint: "search.messages", query: ["query": query, "count": "10"])
        guard let ok = res["ok"] as? Bool, ok,
              let messagesObj = res["messages"] as? [String: Any],
              let matches = messagesObj["matches"] as? [[String: Any]] else {
            return []
        }
        return matches.compactMap { m -> IncomingMessage? in
            guard let ts = m["ts"] as? String, let text = m["text"] as? String else { return nil }
            let ch = (m["channel"] as? [String: Any])?["id"] as? String ?? "search"
            let sender = (m["username"] as? String) ?? "user"
            return IncomingMessage(
                id: ts,
                conversationId: ch,
                senderId: sender,
                senderName: sender,
                text: MessagingSecurity.wrapUntrusted(text),
                platform: .slack
            )
        }
    }

    public func openConversation(target: String) async throws -> Bool {
        // Deep link open
        let clean = target.replacingOccurrences(of: "#", with: "")
        if let url = URL(string: "slack://channel?team=&id=\(clean)") {
            #if canImport(AppKit)
            return NSWorkspace.shared.open(url)
            #else
            return true
            #endif
        }
        return false
    }

    public func setStatus(presence: String, statusText: String?, emoji: String?) async throws -> Bool {
        if !presence.isEmpty {
            _ = try? await callSlackAPI(endpoint: "users.setPresence", body: ["presence": presence])
        }
        if let text = statusText {
            let profile: [String: Any] = [
                "status_text": text,
                "status_emoji": emoji ?? ":speech_balloon:"
            ]
            let res = try await callSlackAPI(endpoint: "users.profile.set", body: ["profile": profile])
            return (res["ok"] as? Bool) ?? false
        }
        return true
    }

    public func markRead(conversationId: String, messageId: String?) async throws -> Bool {
        guard let ts = messageId else { return true }
        let res = try await callSlackAPI(endpoint: "conversations.mark", body: ["channel": conversationId, "ts": ts])
        return (res["ok"] as? Bool) ?? false
    }

    // MARK: - Private Helpers

    private func resolveTargetId(_ target: String) async throws -> String {
        let clean = target.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        // If already looks like a Slack ID (C... or U... or D...)
        if clean.count >= 9 && clean.allSatisfy({ $0.isLetter || $0.isNumber }) && (clean.hasPrefix("C") || clean.hasPrefix("U") || clean.hasPrefix("D")) {
            return clean
        }

        // Check cached channels
        lock.lock()
        let channels = cachedChannels
        lock.unlock()

        if let match = channels.first(where: { $0.name.lowercased() == clean.lowercased() }) {
            return match.id
        }

        // Try searching contacts
        let candidates = try await resolveContact(query: clean)
        if let best = candidates.first, best.confidenceScore >= 0.7 {
            return best.id
        }

        return clean
    }

    private func callSlackAPI(
        endpoint: String,
        body: [String: Any]? = nil,
        query: [String: String]? = nil
    ) async throws -> [String: Any] {
        lock.lock()
        let curToken = token
        let handler = customHTTPHandler
        lock.unlock()

        guard let tok = curToken, !tok.isEmpty else {
            throw NSError(domain: "SlackConnector", code: 401, userInfo: [NSLocalizedDescriptionKey: "Slack connector is not authenticated. Please configure a Slack token."])
        }

        var components = URLComponents(string: "https://slack.com/api/\(endpoint)")!
        if let q = query {
            components.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")

        if let b = body {
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: b)
        } else {
            request.httpMethod = "GET"
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
                throw NSError(domain: "SlackConnector", code: 429, userInfo: [NSLocalizedDescriptionKey: "Slack API rate limit reached. Please back off."])
            }
            if httpRes.statusCode == 401 {
                throw NSError(domain: "SlackConnector", code: 401, userInfo: [NSLocalizedDescriptionKey: "Slack token expired or invalid."])
            }
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "SlackConnector", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response from Slack"])
        }
        return json
    }
}
