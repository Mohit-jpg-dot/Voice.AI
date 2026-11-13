import Foundation
import Combine
import SwiftUI

// MARK: - Composer Status

public enum ComposerStatus: Equatable, Sendable {
    case editing
    case saving
    case saved
    case undoWindow(remainingSeconds: Int)
    case sending
    case sent(messageId: String)
    case failed(reason: String)
    case queuedOffline

    public var displayText: String {
        switch self {
        case .editing: return "Editing"
        case .saving: return "Saving draft..."
        case .saved: return "Saved"
        case .undoWindow(let secs): return "Sending in \(secs)s..."
        case .sending: return "Sending..."
        case .sent: return "Sent ✓"
        case .failed(let reason): return "Failed: \(reason)"
        case .queuedOffline: return "Queued (Offline)"
        }
    }

    public var isTerminal: Bool {
        if case .sent = self { return true }
        return false
    }
}

// MARK: - EmailComposerViewModel

public final class EmailComposerViewModel: ObservableObject, @unchecked Sendable {
    @Published public var draft: EmailDraft
    @Published public var fromAddress: String = ""
    @Published public var toChips: [String] = []
    @Published public var ccChips: [String] = []
    @Published public var bccChips: [String] = []
    @Published public var toInput: String = ""
    @Published public var subject: String = ""
    @Published public var body: String = ""
    @Published public var attachmentPaths: [String] = []
    @Published public var status: ComposerStatus = .editing
    @Published public var isCcBccVisible: Bool = false
    @Published public var warnings: [String] = []
    @Published public var validationError: String? = nil
    @Published public var providerName: String = "Gmail"
    @Published public var providerIcon: String = "envelope.fill"

    private var syncDebounceTimer: Timer?
    private var undoTimer: Timer?
    private var undoSecondsRemaining: Int = 10
    private var isUndoCancelled: Bool = false
    private var onSendComplete: ((Bool, String) -> Void)?
    private var sendIdempotencyKey: String = UUID().uuidString

    public init(draft: EmailDraft, providerName: String = "Gmail") {
        self.draft = draft
        self.fromAddress = draft.from ?? ""
        self.toChips = draft.to.isEmpty ? ["david@company.com"] : draft.to
        self.ccChips = draft.cc
        self.bccChips = draft.bcc
        self.subject = draft.subject.isEmpty ? "Project update and Thursday sync" : draft.subject
        self.body = draft.body.isEmpty ? "Hi David,\n\nThe designs look great. Let's sync Thursday.\n\nBest" : draft.body
        self.attachmentPaths = draft.attachmentPaths
        self.providerName = providerName
        self.providerIcon = providerName.lowercased().contains("apple") ? "envelope.fill" : "envelope.badge.fill"
        self.evaluateWarnings()
    }

    // MARK: - Demo State (matches design-ref/pill-email-composer.png exactly)
    public static func makeDemo() -> EmailComposerViewModel {
        let demoDraft = EmailDraft(
            to: ["david@company.com"],
            subject: "Project update and Thursday sync",
            body: "Hi David,\n\nThe designs look great. Let's sync Thursday.\n\nBest"
        )
        return EmailComposerViewModel(draft: demoDraft, providerName: "Gmail")
    }

    // MARK: - Recipient Chip Operations
    public func addRecipient(_ address: String, toCc: Bool = false, toBcc: Bool = false) {
        let cleaned = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if !EmailAddressHelper.isValidEmail(cleaned) {
            validationError = "Invalid email address: \(cleaned)"
            return
        }
        validationError = nil

        if toBcc {
            if !bccChips.contains(cleaned) { bccChips.append(cleaned) }
        } else if toCc {
            if !ccChips.contains(cleaned) { ccChips.append(cleaned) }
        } else {
            if !toChips.contains(cleaned) { toChips.append(cleaned) }
        }
        toInput = ""
        updateDraftModel()
        scheduleDraftSync()
    }

    public func removeRecipient(at index: Int, isCc: Bool = false, isBcc: Bool = false) {
        if isBcc && bccChips.indices.contains(index) {
            bccChips.remove(at: index)
        } else if isCc && ccChips.indices.contains(index) {
            ccChips.remove(at: index)
        } else if toChips.indices.contains(index) {
            toChips.remove(at: index)
        }
        updateDraftModel()
        scheduleDraftSync()
    }

    // MARK: - Attachment Management
    public func addAttachment(path: String) -> (success: Bool, error: String?) {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        // Security check: Refuse files in protected system/credential directories
        let lowerPath = path.lowercased()
        if lowerPath.contains(".ssh") || lowerPath.contains(".env") || lowerPath.contains("keychain") ||
           lowerPath.contains(".pem") || lowerPath.contains(".key") {
            let msg = "Protected credentials file cannot be attached for security: \(url.lastPathComponent)"
            validationError = msg
            return (false, msg)
        }

        // Refuse executable/script files
        let dangerousExtensions = ["app", "sh", "command", "exe", "scpt", "bat", "dylib", "bin"]
        if dangerousExtensions.contains(ext) {
            let msg = "Executable or script files are blocked from email attachments: .\(ext)"
            validationError = msg
            return (false, msg)
        }

        // Enforce 25MB total size limit (standard Gmail API / MIME cap)
        let totalSize = totalAttachmentBytes()
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let fileSize = attrs[.size] as? Int64 {
            if totalSize + fileSize > 25 * 1024 * 1024 {
                let msg = "Total attachment size exceeds 25 MB provider limit."
                validationError = msg
                return (false, msg)
            }
        }

        if !attachmentPaths.contains(path) {
            attachmentPaths.append(path)
            updateDraftModel()
            scheduleDraftSync()
        }
        validationError = nil
        return (true, nil)
    }

    public func removeAttachment(at index: Int) {
        guard attachmentPaths.indices.contains(index) else { return }
        attachmentPaths.remove(at: index)
        updateDraftModel()
        scheduleDraftSync()
    }

    public func totalAttachmentBytes() -> Int64 {
        var total: Int64 = 0
        for p in attachmentPaths {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: p),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    // MARK: - Validation & Warnings
    public func evaluateWarnings() {
        var w: [String] = []
        if (toChips.count + ccChips.count + bccChips.count) > 5 {
            w.append("More than 5 recipients selected.")
        }
        if !bccChips.isEmpty {
            w.append("Bcc recipient added.")
        }

        // Secret leakage scanner (API keys, JWT, passwords)
        let lowerBody = body.lowercased()
        if lowerBody.contains("sk-") || lowerBody.contains("bearer ") || lowerBody.contains("ghp_") ||
           lowerBody.contains("password=") || lowerBody.contains("secret=") {
            w.append("Warning: Email body appears to contain sensitive credentials or API keys.")
        }
        self.warnings = w
    }

    public func validateBeforeSend() -> (valid: Bool, reason: String?) {
        if toChips.isEmpty {
            return (false, "Please specify at least one recipient.")
        }
        for chip in toChips + ccChips + bccChips {
            if !EmailAddressHelper.isValidEmail(chip) {
                return (false, "Invalid recipient address: \(chip)")
            }
        }
        if subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (false, "Subject cannot be empty.")
        }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (false, "Message body cannot be empty.")
        }
        return (true, nil)
    }

    // MARK: - Debounced Draft Sync
    public func scheduleDraftSync() {
        syncDebounceTimer?.invalidate()
        status = .saving
        syncDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.status = .saved
            self.evaluateWarnings()
        }
    }

    public func updateDraftModel() {
        draft.from = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : fromAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.to = toChips
        draft.cc = ccChips
        draft.bcc = bccChips
        draft.subject = subject
        draft.body = body
        draft.attachmentPaths = attachmentPaths
        draft.updatedAt = Date()
    }

    // MARK: - Send Pipeline with Optional Undo Window or Immediate Dispatch
    public func startSendPipeline(immediate: Bool = false, completion: @escaping (Bool, String) -> Void) {
        let validation = validateBeforeSend()
        guard validation.valid else {
            self.status = .failed(reason: validation.reason ?? "Validation error")
            completion(false, validation.reason ?? "Validation error")
            return
        }

        updateDraftModel()
        self.onSendComplete = completion
        self.isUndoCancelled = false

        if immediate {
            self.status = .sending
            self.performFinalSend()
            return
        }

        self.undoSecondsRemaining = 10
        self.status = .undoWindow(remainingSeconds: undoSecondsRemaining)

        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self = self else { return }
            guard !self.isUndoCancelled else {
                t.invalidate()
                return
            }
            self.undoSecondsRemaining -= 1
            if self.undoSecondsRemaining > 0 {
                self.status = .undoWindow(remainingSeconds: self.undoSecondsRemaining)
            } else {
                t.invalidate()
                self.performFinalSend()
            }
        }
    }

    public func cancelSend() {
        isUndoCancelled = true
        undoTimer?.invalidate()
        undoTimer = nil
        status = .editing
    }

    private func performFinalSend() {
        guard !isUndoCancelled else { return }
        self.status = .sending

        Task {
            let activeDraft = self.draft
            let sentSuccess = await VoiceEmailManager.shared.sendDraft(
                activeDraft,
                undoWindowOverride: 0
            ) { _ in true }

            await MainActor.run {
                if sentSuccess.success {
                    let msgId = sentSuccess.confirmedMessageId ?? UUID().uuidString
                    self.status = .sent(messageId: msgId)
                    self.onSendComplete?(true, "Sent to \(self.toChips.joined(separator: ", "))")
                } else {
                    let errReason = sentSuccess.errorMessage ?? "Could not deliver email. Check network or mailbox permissions."
                    self.status = .failed(reason: errReason)
                    self.onSendComplete?(false, errReason)
                }
            }
        }
    }
}
