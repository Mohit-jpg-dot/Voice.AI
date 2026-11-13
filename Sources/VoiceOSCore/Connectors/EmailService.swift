import AppKit
import Foundation

// MARK: - Capability & Address Models

public enum EmailCapabilityStatus: String, Codable, Sendable, Equatable {
    case canSendAndRead
    case canSendOnly
    case canOnlyDraft
    case cannotSend
}

public struct EmailCapabilityReport: Codable, Sendable, Equatable {
    public let status: EmailCapabilityStatus
    public let activeBackend: String
    public let reason: String
    public let fixInstructions: String
    public let accountEmails: [String]

    public init(
        status: EmailCapabilityStatus,
        activeBackend: String,
        reason: String,
        fixInstructions: String,
        accountEmails: [String] = []
    ) {
        self.status = status
        self.activeBackend = activeBackend
        self.reason = reason
        self.fixInstructions = fixInstructions
        self.accountEmails = accountEmails
    }

    public var spokenSummary: String {
        switch status {
        case .canSendAndRead:
            let acct = accountEmails.first.map { " using \($0)" } ?? ""
            return "Yes, I can read and send emails via \(activeBackend)\(acct)."
        case .canSendOnly:
            return "I can send emails via \(activeBackend), but reading inbox messages is not available. \(fixInstructions)"
        case .canOnlyDraft:
            return "I can only open a pre-filled draft via \(activeBackend); I cannot send emails automatically. \(fixInstructions)"
        case .cannotSend:
            return "I cannot send emails right now. \(reason) Fix: \(fixInstructions)"
        }
    }
}

public enum EmailAddressHelper {
    private static let digitWords: [String: String] = [
        "zero": "0", "oh": "0",
        "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9"
    ]

    /// Normalizes spoken email phrases (e.g. "mohit dot toor one zero eight at gmail dot com")
    /// into a validated email address, or returns nil if invalid.
    public static func normalizeSpokenAddress(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // If already looks like a clean email address, validate directly
        if !trimmed.contains(" ") && trimmed.contains("@") {
            let lowered = trimmed.lowercased()
            return isValidEmail(lowered) ? lowered : nil
        }

        // Tokenize words, convert spoken punctuation & digits
        let rawTokens = trimmed.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        var parts: [String] = []
        var i = 0
        while i < rawTokens.count {
            let tok = rawTokens[i]
            if tok == "at" || tok == "attherate" || (tok == "at" && i + 1 < rawTokens.count) {
                if i + 2 < rawTokens.count && rawTokens[i + 1] == "the" && rawTokens[i + 2] == "rate" {
                    parts.append("@")
                    i += 3
                    continue
                }
                parts.append("@")
            } else if tok == "dot" || tok == "period" || tok == "point" {
                parts.append(".")
            } else if tok == "underscore" || tok == "under_score" {
                parts.append("_")
            } else if tok == "dash" || tok == "hyphen" || tok == "minus" {
                parts.append("-")
            } else if tok == "plus" {
                parts.append("+")
            } else if let d = digitWords[tok] {
                parts.append(d)
            } else {
                parts.append(tok)
            }
            i += 1
        }

        let joined = parts.joined()
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?'\"<>()"))

        return isValidEmail(joined) ? joined : nil
    }

    public static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return false }
        let pieces = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard pieces.count == 2 else { return false }
        let local = String(pieces[0])
        let domain = String(pieces[1])
        guard !local.isEmpty, !local.hasPrefix("."), !local.hasSuffix("."), !local.contains("..") else { return false }
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix("."), !domain.contains("..") else { return false }
        let tld = domain.split(separator: ".").last.map(String.init) ?? ""
        guard tld.count >= 2 else { return false }
        let allowedLocal = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-")
        let allowedDomain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        return local.unicodeScalars.allSatisfy { allowedLocal.contains($0) } &&
               domain.unicodeScalars.allSatisfy { allowedDomain.contains($0) }
    }

    /// Canonicalizes an email address for comparison (lowercase, strips Gmail +tags).
    public static func canonicalAddress(_ email: String) -> String {
        let lower = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = lower.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return lower }
        var local = String(parts[0])
        let domain = String(parts[1])
        if domain == "gmail.com" || domain == "googlemail.com" {
            if let plusIdx = local.firstIndex(of: "+") {
                local = String(local[..<plusIdx])
            }
        }
        return "\(local)@\(domain)"
    }

    public static func formatForReadback(_ email: String) -> String {
        email
            .replacingOccurrences(of: "@", with: " at ")
            .replacingOccurrences(of: ".", with: " dot ")
    }

    public static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let s1 = Array(a.lowercased())
        let s2 = Array(b.lowercased())
        if s1.isEmpty { return s2.count }
        if s2.isEmpty { return s1.count }
        var prev = Array(0...s2.count)
        for i in 1...s1.count {
            var curr = [i] + Array(repeating: 0, count: s2.count)
            for j in 1...s2.count {
                let cost = (s1[i - 1] == s2[j - 1]) ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = curr
        }
        return prev[s2.count]
    }
}

// MARK: - Email Domain Models

public struct EmailMessage: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let threadId: String
    public let messageIdHeader: String
    public let inReplyToHeader: String?
    public let referencesHeader: String?
    public let from: String
    public let fromName: String?
    public let to: [String]
    public let cc: [String]
    public let subject: String
    public let snippet: String
    public let body: String
    public let date: Date
    public let isFromMe: Bool
    public let isRead: Bool

    public init(
        id: String = UUID().uuidString,
        threadId: String,
        messageIdHeader: String,
        inReplyToHeader: String? = nil,
        referencesHeader: String? = nil,
        from: String,
        fromName: String? = nil,
        to: [String] = [],
        cc: [String] = [],
        subject: String,
        snippet: String = "",
        body: String,
        date: Date = Date(),
        isFromMe: Bool = false,
        isRead: Bool = false
    ) {
        self.id = id
        self.threadId = threadId
        self.messageIdHeader = messageIdHeader
        self.inReplyToHeader = inReplyToHeader
        self.referencesHeader = referencesHeader
        self.from = from
        self.fromName = fromName
        self.to = to
        self.cc = cc
        self.subject = subject
        self.snippet = snippet.isEmpty ? String(body.prefix(140)) : snippet
        self.body = body
        self.date = date
        self.isFromMe = isFromMe
        self.isRead = isRead
    }
}

public struct EmailDraft: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var from: String?
    public var to: [String]
    public var cc: [String]
    public var bcc: [String]
    public var subject: String
    public var body: String
    public var attachmentPaths: [String]
    public var replyToMessageId: String?
    public var inReplyToHeader: String?
    public var referencesHeader: String?
    public var threadId: String?
    public var isReplyAll: Bool
    public var isForward: Bool
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        from: String? = nil,
        to: [String] = [],
        cc: [String] = [],
        bcc: [String] = [],
        subject: String = "",
        body: String = "",
        attachmentPaths: [String] = [],
        replyToMessageId: String? = nil,
        inReplyToHeader: String? = nil,
        referencesHeader: String? = nil,
        threadId: String? = nil,
        isReplyAll: Bool = false,
        isForward: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.attachmentPaths = attachmentPaths
        self.replyToMessageId = replyToMessageId
        self.inReplyToHeader = inReplyToHeader
        self.referencesHeader = referencesHeader
        self.threadId = threadId
        self.isReplyAll = isReplyAll
        self.isForward = isForward
        self.updatedAt = updatedAt
    }

    public var allRecipients: [String] {
        to + cc + bcc
    }
}

public struct EmailSendResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let confirmedMessageId: String?
    public let backendUsed: String
    public let errorMessage: String?

    public init(
        success: Bool,
        confirmedMessageId: String? = nil,
        backendUsed: String,
        errorMessage: String? = nil
    ) {
        self.success = success
        self.confirmedMessageId = confirmedMessageId
        self.backendUsed = backendUsed
        self.errorMessage = errorMessage
    }
}

// MARK: - EmailService Protocol

public protocol EmailService: Sendable {
    var backendName: String { get }
    func capabilities() async -> EmailCapabilityReport
    func send(draft: EmailDraft) async -> EmailSendResult
    func reply(to original: EmailMessage, draft: EmailDraft) async -> EmailSendResult
    func fetchRecent(limit: Int) async -> [EmailMessage]
    func fetchThread(id: String) async -> [EmailMessage]
    func observeNewIncoming(sinceMessageId: String?) async -> [EmailMessage]
}

// MARK: - 1. Mail.app via Apple Events (Preferred on macOS)

public final class MailAppEmailBackend: EmailService, @unchecked Sendable {
    public let backendName = "Mail.app"

    public init() {}

    public func capabilities() async -> EmailCapabilityReport {
        if ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1" {
            return EmailCapabilityReport(
                status: .cannotSend,
                activeBackend: backendName,
                reason: "Mail.app Apple Events probe is disabled in VOICE_AI_TEST_MODE.",
                fixInstructions: "Run outside test mode with Mail.app configured and Automation permission granted (see docs/how-to-grant-permissions.md)."
            )
        }

        let res = AccessibilityControlEngine.shared.executeAppleScript("""
        tell application "Mail"
            set acctEmails to {}
            repeat with a in accounts
                try
                    set end of acctEmails to (email addresses of a) as string
                end try
            end repeat
            return (count of accounts) & "||" & (acctEmails as string)
        end tell
        """)

        if !res.success {
            let err = res.output ?? "Automation permission for Mail.app may be denied."
            return EmailCapabilityReport(
                status: .cannotSend,
                activeBackend: backendName,
                reason: err,
                fixInstructions: "Grant Automation access for Voice.AI -> Mail in System Settings -> Privacy & Security -> Automation (see docs/how-to-grant-permissions.md)."
            )
        }

        let output = res.output ?? ""
        let parts = output.components(separatedBy: "||")
        let count = Int(parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
        guard count > 0 else {
            return EmailCapabilityReport(
                status: .cannotSend,
                activeBackend: backendName,
                reason: "Mail.app has no email accounts configured.",
                fixInstructions: "Open Apple Mail and add an email account, or configure Gmail OAuth in Keychain."
            )
        }

        let rawEmails = parts.dropFirst().joined(separator: " ")
        let emails = rawEmails
            .components(separatedBy: CharacterSet(charactersIn: ", ;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { EmailAddressHelper.isValidEmail($0) }

        return EmailCapabilityReport(
            status: .canSendAndRead,
            activeBackend: backendName,
            reason: "Mail.app is accessible with \(count) configured account(s).",
            fixInstructions: "",
            accountEmails: emails
        )
    }

    public func send(draft: EmailDraft) async -> EmailSendResult {
        guard !draft.to.isEmpty else {
            return EmailSendResult(success: false, backendUsed: backendName, errorMessage: "No recipient specified.")
        }
        let escapedSubject = escapeAS(draft.subject)
        let escapedBody = escapeAS(draft.body)
        let toLines = draft.to.map { "make new to recipient at end of to recipients with properties {address:\"\(escapeAS($0))\"}" }.joined(separator: "\n")
        let ccLines = draft.cc.map { "make new cc recipient at end of cc recipients with properties {address:\"\(escapeAS($0))\"}" }.joined(separator: "\n")
        let bccLines = draft.bcc.map { "make new bcc recipient at end of bcc recipients with properties {address:\"\(escapeAS($0))\"}" }.joined(separator: "\n")
        let attachLines = draft.attachmentPaths.filter { FileManager.default.fileExists(atPath: $0) }.map {
            "make new attachment with properties {file name:(POSIX file \"\(escapeAS($0))\")} at after the last paragraph"
        }.joined(separator: "\n")

        let senderProp: String
        if let from = draft.from, !from.isEmpty {
            senderProp = ", sender:\"\(escapeAS(from))\""
        } else {
            senderProp = ""
        }
        let script = """
        tell application "Mail"
            set newMsg to make new outgoing message with properties {subject:"\(escapedSubject)", content:"\(escapedBody)"\(senderProp), visible:false}
            tell newMsg
                \(toLines)
                \(ccLines)
                \(bccLines)
                \(attachLines)
                send
            end tell
            return "sent"
        end tell
        """
        let res = AccessibilityControlEngine.shared.executeAppleScript(script)
        if res.success, (res.output ?? "").contains("sent") {
            return EmailSendResult(success: true, confirmedMessageId: "mailapp-\(UUID().uuidString)", backendUsed: backendName)
        }
        return EmailSendResult(success: false, backendUsed: backendName, errorMessage: res.output ?? "Mail.app failed to send the message.")
    }

    public func reply(to original: EmailMessage, draft: EmailDraft) async -> EmailSendResult {
        var replyDraft = draft
        if !replyDraft.subject.lowercased().hasPrefix("re:") && !replyDraft.isForward {
            replyDraft.subject = "Re: \(original.subject)"
        }
        if !replyDraft.body.contains(original.from) {
            replyDraft.body += "\n\nOn \(original.date), \(original.from) wrote:\n> " +
                original.body.replacingOccurrences(of: "\n", with: "\n> ")
        }
        return await send(draft: replyDraft)
    }

    public func fetchRecent(limit: Int = 10) async -> [EmailMessage] {
        let clamped = max(1, min(limit, 25))
        let script = """
        tell application "Mail"
            set outText to ""
            set msgs to messages 1 thru (my minVal(\(clamped), count of messages of inbox)) of inbox
            repeat with m in msgs
                try
                    set mid to message id of m
                    set snd to sender of m
                    set subj to subject of m
                    set dt to (date received of m) as string
                    set bod to content of m
                    if (length of bod) > 600 then set bod to text 1 thru 600 of bod
                    set outText to outText & mid & "|||" & snd & "|||" & subj & "|||" & dt & "|||" & bod & "\\n<<<MSG_END>>>\\n"
                end try
            end repeat
            return outText
        end tell
        on minVal(a, b)
            if a < b then return a
            return b
        end minVal
        """
        let res = AccessibilityControlEngine.shared.executeAppleScript(script)
        guard res.success, let raw = res.output else { return [] }
        return parseMailAppMessages(raw)
    }

    public func fetchThread(id: String) async -> [EmailMessage] {
        let recent = await fetchRecent(limit: 25)
        return recent.filter { $0.threadId == id || $0.id == id }
    }

    public func observeNewIncoming(sinceMessageId: String?) async -> [EmailMessage] {
        let recent = await fetchRecent(limit: 15)
        guard let marker = sinceMessageId else { return recent }
        var out: [EmailMessage] = []
        for msg in recent {
            if msg.id == marker || msg.messageIdHeader == marker { break }
            out.append(msg)
        }
        return out
    }

    private func parseMailAppMessages(_ raw: String) -> [EmailMessage] {
        raw.components(separatedBy: "\n<<<MSG_END>>>\n").compactMap { block in
            let cols = block.components(separatedBy: "|||")
            guard cols.count >= 5 else { return nil }
            let msgId = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let senderRaw = cols[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = cols[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let body = cols[4].trimmingCharacters(in: .whitespacesAndNewlines)
            let email = extractEmailAddress(from: senderRaw) ?? senderRaw
            let normSubj = subject.replacingOccurrences(of: "(?i)^re:\\s*", with: "", options: .regularExpression)
            return EmailMessage(
                id: msgId,
                threadId: normSubj.lowercased(),
                messageIdHeader: msgId,
                from: email,
                fromName: senderRaw,
                to: [],
                subject: subject,
                body: body,
                date: Date(),
                isFromMe: false,
                isRead: false
            )
        }
    }

    private func extractEmailAddress(from raw: String) -> String? {
        if let start = raw.firstIndex(of: "<"), let end = raw.firstIndex(of: ">"), start < end {
            return String(raw[raw.index(after: start)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return EmailAddressHelper.isValidEmail(raw) ? raw : nil
    }

    private func escapeAS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
    }
}

// MARK: - 2. Gmail API with OAuth (Keychain-backed, Minimal Scopes)

public final class GmailAPIEmailBackend: EmailService, @unchecked Sendable {
    public let backendName = "Gmail API"
    public static let tokenKeychainKey = "ai.voice.app.gmail.oauth_access_token"
    public static let accountKeychainKey = "ai.voice.app.gmail.account_email"
    public static let requiredScopes = [
        "https://www.googleapis.com/auth/gmail.send",
        "https://www.googleapis.com/auth/gmail.readonly"
    ]

    public init() {}

    public func capabilities() async -> EmailCapabilityReport {
        guard let token = KeychainService.shared.get(Self.tokenKeychainKey), !token.isEmpty else {
            return EmailCapabilityReport(
                status: .cannotSend,
                activeBackend: backendName,
                reason: "No Gmail OAuth token is stored in the Keychain.",
                fixInstructions: "Connect Gmail OAuth in Settings (scopes: gmail.send, gmail.readonly) or configure an account in Mail.app."
            )
        }

        if ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1" {
            return EmailCapabilityReport(
                status: .cannotSend,
                activeBackend: backendName,
                reason: "Network calls disabled in VOICE_AI_TEST_MODE.",
                fixInstructions: "Use MockEmailService in tests."
            )
        }

        var req = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return EmailCapabilityReport(
                    status: .cannotSend,
                    activeBackend: backendName,
                    reason: "Gmail API rejected the stored OAuth token.",
                    fixInstructions: "Re-authenticate Gmail OAuth in Settings so fresh tokens are saved to Keychain."
                )
            }
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let email = (json["emailAddress"] as? String) ?? KeychainService.shared.get(Self.accountKeychainKey) ?? ""
            return EmailCapabilityReport(
                status: .canSendAndRead,
                activeBackend: backendName,
                reason: "Gmail API OAuth token verified.",
                fixInstructions: "",
                accountEmails: email.isEmpty ? [] : [email]
            )
        } catch {
            return EmailCapabilityReport(
                status: .cannotSend,
                activeBackend: backendName,
                reason: "Gmail API unreachable: \(error.localizedDescription)",
                fixInstructions: "Check your internet connection and retry."
            )
        }
    }

    public func send(draft: EmailDraft) async -> EmailSendResult {
        guard let token = KeychainService.shared.get(Self.tokenKeychainKey), !token.isEmpty else {
            return EmailSendResult(success: false, backendUsed: backendName, errorMessage: "Gmail OAuth token missing from Keychain.")
        }
        let rawRFC = buildRFC2822Base64URL(draft: draft)
        var payload: [String: Any] = ["raw": rawRFC]
        if let tid = draft.threadId, !tid.isEmpty {
            payload["threadId"] = tid
        }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            return EmailSendResult(success: false, backendUsed: backendName, errorMessage: "Failed to encode Gmail payload.")
        }

        var req = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData
        req.timeoutInterval = 15

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                return EmailSendResult(success: false, backendUsed: backendName, errorMessage: "Gmail API send failed (HTTP \(code)).")
            }
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let msgId = json["id"] as? String
            return EmailSendResult(success: true, confirmedMessageId: msgId, backendUsed: backendName)
        } catch {
            return EmailSendResult(success: false, backendUsed: backendName, errorMessage: error.localizedDescription)
        }
    }

    public func reply(to original: EmailMessage, draft: EmailDraft) async -> EmailSendResult {
        var updated = draft
        updated.inReplyToHeader = original.messageIdHeader
        updated.referencesHeader = [original.referencesHeader, original.messageIdHeader]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        updated.threadId = original.threadId
        if !updated.subject.lowercased().hasPrefix("re:") {
            updated.subject = "Re: \(original.subject)"
        }
        return await send(draft: updated)
    }

    public func fetchRecent(limit: Int = 10) async -> [EmailMessage] {
        guard let token = KeychainService.shared.get(Self.tokenKeychainKey), !token.isEmpty else { return [] }
        var req = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=\(max(1, min(limit, 25)))")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["messages"] as? [[String: Any]] else {
            return []
        }

        var out: [EmailMessage] = []
        for item in list.prefix(limit) {
            if let id = item["id"] as? String, let msg = await fetchSingleMessage(id: id, token: token) {
                out.append(msg)
            }
        }
        return out
    }

    public func fetchThread(id: String) async -> [EmailMessage] {
        let recent = await fetchRecent(limit: 20)
        return recent.filter { $0.threadId == id }
    }

    public func observeNewIncoming(sinceMessageId: String?) async -> [EmailMessage] {
        let recent = await fetchRecent(limit: 15)
        guard let marker = sinceMessageId else { return recent }
        var out: [EmailMessage] = []
        for m in recent {
            if m.id == marker || m.messageIdHeader == marker { break }
            out.append(m)
        }
        return out
    }

    private func fetchSingleMessage(id: String, token: String) async -> EmailMessage? {
        var req = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=metadata&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Subject&metadataHeaders=Message-ID&metadataHeaders=In-Reply-To&metadataHeaders=References")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let threadId = (json["threadId"] as? String) ?? id
        let snippet = (json["snippet"] as? String) ?? ""
        let payload = (json["payload"] as? [String: Any]) ?? [:]
        let headers = (payload["headers"] as? [[String: Any]]) ?? []
        func hdr(_ name: String) -> String {
            headers.first { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }?["value"] as? String ?? ""
        }
        let from = hdr("From")
        let subj = hdr("Subject")
        let msgId = hdr("Message-ID")
        return EmailMessage(
            id: id,
            threadId: threadId,
            messageIdHeader: msgId.isEmpty ? id : msgId,
            inReplyToHeader: hdr("In-Reply-To").isEmpty ? nil : hdr("In-Reply-To"),
            referencesHeader: hdr("References").isEmpty ? nil : hdr("References"),
            from: from,
            subject: subj,
            snippet: snippet,
            body: snippet,
            date: Date()
        )
    }

    private func buildRFC2822Base64URL(draft: EmailDraft) -> String {
        var lines: [String] = []
        lines.append("To: \(draft.to.joined(separator: ", "))")
        if !draft.cc.isEmpty { lines.append("Cc: \(draft.cc.joined(separator: ", "))") }
        if !draft.bcc.isEmpty { lines.append("Bcc: \(draft.bcc.joined(separator: ", "))") }
        lines.append("Subject: \(draft.subject)")
        if let inReplyTo = draft.inReplyToHeader, !inReplyTo.isEmpty {
            lines.append("In-Reply-To: \(inReplyTo)")
        }
        if let refs = draft.referencesHeader, !refs.isEmpty {
            lines.append("References: \(refs)")
        }
        lines.append("Content-Type: text/plain; charset=\"UTF-8\"")
        lines.append("")
        lines.append(draft.body)
        let raw = lines.joined(separator: "\r\n")
        return Data(raw.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - 3. IMAP/SMTP Keychain Fallback (Configured only if user supplies credentials)

public final class IMAPSMTPEmailBackend: EmailService, @unchecked Sendable {
    public let backendName = "IMAP/SMTP"
    public static let smtpHostKey = "ai.voice.app.email.smtp_host"
    public static let usernameKey = "ai.voice.app.email.username"
    public static let passwordKey = "ai.voice.app.email.password"

    public init() {}

    public func capabilities() async -> EmailCapabilityReport {
        let host = KeychainService.shared.get(Self.smtpHostKey) ?? ""
        let user = KeychainService.shared.get(Self.usernameKey) ?? ""
        let pass = KeychainService.shared.get(Self.passwordKey) ?? ""
        if host.isEmpty || user.isEmpty || pass.isEmpty {
            return EmailCapabilityReport(
                status: .cannotSend,
                activeBackend: backendName,
                reason: "IMAP/SMTP credentials are not configured in Keychain.",
                fixInstructions: "Set up Mail.app or Gmail OAuth (recommended), or add SMTP host and credentials in Keychain."
            )
        }
        return EmailCapabilityReport(
            status: .canSendOnly,
            activeBackend: backendName,
            reason: "SMTP configured for \(user).",
            fixInstructions: "For full inbox reading and reply watching, configure Mail.app or Gmail OAuth.",
            accountEmails: [user]
        )
    }

    public func send(draft: EmailDraft) async -> EmailSendResult {
        EmailSendResult(
            success: false,
            backendUsed: backendName,
            errorMessage: "Direct SMTP socket transport requires Mail.app or Gmail OAuth on macOS; configure Mail.app or Gmail OAuth."
        )
    }

    public func reply(to original: EmailMessage, draft: EmailDraft) async -> EmailSendResult {
        await send(draft: draft)
    }

    public func fetchRecent(limit: Int) async -> [EmailMessage] { [] }
    public func fetchThread(id: String) async -> [EmailMessage] { [] }
    public func observeNewIncoming(sinceMessageId: String?) async -> [EmailMessage] { [] }
}

// MARK: - 4. mailto: Draft Fallback (Never reports "sent")

public final class MailtoDraftFallbackBackend: EmailService, @unchecked Sendable {
    public let backendName = "mailto: Draft"

    public init() {}

    public func capabilities() async -> EmailCapabilityReport {
        EmailCapabilityReport(
            status: .canOnlyDraft,
            activeBackend: backendName,
            reason: "No direct Mail.app account or Gmail OAuth token is active.",
            fixInstructions: "Configure an account in Apple Mail (and grant Automation permission) or connect Gmail OAuth to send directly."
        )
    }

    public func send(draft: EmailDraft) async -> EmailSendResult {
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = draft.to.joined(separator: ",")
        var queryItems: [URLQueryItem] = []
        if !draft.cc.isEmpty { queryItems.append(URLQueryItem(name: "cc", value: draft.cc.joined(separator: ","))) }
        if !draft.bcc.isEmpty { queryItems.append(URLQueryItem(name: "bcc", value: draft.bcc.joined(separator: ","))) }
        if !draft.subject.isEmpty { queryItems.append(URLQueryItem(name: "subject", value: draft.subject)) }
        if !draft.body.isEmpty { queryItems.append(URLQueryItem(name: "body", value: draft.body)) }
        comps.queryItems = queryItems
        if let url = comps.url, ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] != "1" {
            _ = await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
        return EmailSendResult(
            success: false,
            confirmedMessageId: nil,
            backendUsed: backendName,
            errorMessage: "Opened a pre-filled compose window (mailto:); you must press Send yourself. Never treated as sent."
        )
    }

    public func reply(to original: EmailMessage, draft: EmailDraft) async -> EmailSendResult {
        var d = draft
        if !d.subject.lowercased().hasPrefix("re:") { d.subject = "Re: \(original.subject)" }
        return await send(draft: d)
    }

    public func fetchRecent(limit: Int) async -> [EmailMessage] { [] }
    public func fetchThread(id: String) async -> [EmailMessage] { [] }
    public func observeNewIncoming(sinceMessageId: String?) async -> [EmailMessage] { [] }
}

// MARK: - 5. MockEmailService (For Deterministic Automated Testing)

public final class MockEmailService: EmailService, @unchecked Sendable {
    public let backendName = "MockEmailService"
    private let lock = NSLock()
    public var capabilityReport: EmailCapabilityReport
    public var inboxMessages: [EmailMessage] = []
    public var sentDrafts: [EmailDraft] = []
    public var shouldFailNextSend: String?
    public var shouldFailNextObserve: Bool = false

    public init(
        status: EmailCapabilityStatus = .canSendAndRead,
        accountEmails: [String] = ["me@example.com"]
    ) {
        self.capabilityReport = EmailCapabilityReport(
            status: status,
            activeBackend: "MockEmailService",
            reason: "Mock capability status: \(status.rawValue)",
            fixInstructions: status == .canSendAndRead ? "" : "Configure Mail.app or Gmail OAuth.",
            accountEmails: accountEmails
        )
    }

    public func capabilities() async -> EmailCapabilityReport {
        lock.withLock { capabilityReport }
    }

    public func send(draft: EmailDraft) async -> EmailSendResult {
        lock.withLock {
            if let err = shouldFailNextSend {
                shouldFailNextSend = nil
                return EmailSendResult(success: false, backendUsed: backendName, errorMessage: err)
            }
            sentDrafts.append(draft)
            return EmailSendResult(success: true, confirmedMessageId: "mock-sent-\(sentDrafts.count)", backendUsed: backendName)
        }
    }

    public func reply(to original: EmailMessage, draft: EmailDraft) async -> EmailSendResult {
        var updated = draft
        updated.inReplyToHeader = original.messageIdHeader
        updated.referencesHeader = [original.referencesHeader, original.messageIdHeader]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        updated.threadId = original.threadId
        if !updated.subject.lowercased().hasPrefix("re:") && !updated.isForward {
            updated.subject = "Re: \(original.subject)"
        }
        return await send(draft: updated)
    }

    public func fetchRecent(limit: Int) async -> [EmailMessage] {
        lock.withLock { Array(inboxMessages.prefix(limit)) }
    }

    public func fetchThread(id: String) async -> [EmailMessage] {
        lock.withLock { inboxMessages.filter { $0.threadId == id } }
    }

    public func observeNewIncoming(sinceMessageId: String?) async -> [EmailMessage] {
        lock.withLock {
            if shouldFailNextObserve { return [] }
            guard let marker = sinceMessageId else { return inboxMessages }
            var out: [EmailMessage] = []
            for m in inboxMessages {
                if m.id == marker || m.messageIdHeader == marker { break }
                out.append(m)
            }
            return out
        }
    }
}

// MARK: - Ordered Backend Resolver

public final class EmailBackendRouter: @unchecked Sendable {
    public static let shared = EmailBackendRouter()

    private let mailApp = MailAppEmailBackend()
    private let gmail = GmailAPIEmailBackend()
    private let imap = IMAPSMTPEmailBackend()
    private let mailto = MailtoDraftFallbackBackend()

    public init() {}

    public func resolveActiveBackend() async -> (service: EmailService, report: EmailCapabilityReport) {
        let mailCap = await mailApp.capabilities()
        if mailCap.status == .canSendAndRead || mailCap.status == .canSendOnly {
            return (mailApp, mailCap)
        }
        let gmailCap = await gmail.capabilities()
        if gmailCap.status == .canSendAndRead || gmailCap.status == .canSendOnly {
            return (gmail, gmailCap)
        }
        let imapCap = await imap.capabilities()
        if imapCap.status == .canSendAndRead || imapCap.status == .canSendOnly {
            return (imap, imapCap)
        }
        let mailtoCap = await mailto.capabilities()
        // If Mail.app gave a specific permission/account reason, include it clearly
        if mailCap.status == .cannotSend && !mailCap.reason.contains("VOICE_AI_TEST_MODE") {
            let combined = EmailCapabilityReport(
                status: .canOnlyDraft,
                activeBackend: mailto.backendName,
                reason: mailCap.reason,
                fixInstructions: mailCap.fixInstructions
            )
            return (mailto, combined)
        }
        return (mailto, mailtoCap)
    }
}
