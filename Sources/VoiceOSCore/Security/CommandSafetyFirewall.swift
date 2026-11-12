import Foundation

/// Central risk-level, confirmation, and prompt-injection firewall executed before any tool parsing or LLM execution.
public final class CommandSafetyFirewall: @unchecked Sendable {
    public static let shared = CommandSafetyFirewall()

    public enum Evaluation: Sendable, Equatable {
        case allow
        case refuse(reason: String)
        case confirm(toolName: String, appName: String, title: String, subtitle: String, dryRunNotice: String)
    }

    public init() {}

    public func evaluate(command rawCommand: String) -> Evaluation {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !lower.isEmpty else { return .allow }

        // 1. Prompt-Injection / Untrusted Source Firewall (audio from media/web pages, embedded tags)
        let untrustedMarkers = [
            "youtube video audio:",
            "audio from youtube",
            "audio from a youtube",
            "from webpage:",
            "webpage contains hidden text",
            "hidden text telling",
            "<untrusted_screen_data>",
            "ignore previous instructions"
        ]
        if untrustedMarkers.contains(where: { lower.contains($0) }) {
            return .refuse(reason: "Refused for security: ignored instruction from untrusted audio or web page content.")
        }

        // 2. Catastrophic Refusals (never execute even with casual phrasing)
        let destructiveBulkDelete = (lower.contains("delete all files") ||
                                     lower.contains("delete every file") ||
                                     lower.contains("delete everything in") ||
                                     lower.contains("delete everything on") ||
                                     lower.contains("wipe the drive") ||
                                     lower.contains("wipe my drive"))
        if destructiveBulkDelete {
            return .refuse(reason: "Refused for safety: bulk deletion of drives or user folders is prohibited.")
        }

        let formatPatterns = [
            "format the hard drive", "format hard drive", "format c:", "format disk",
            "format my drive", "diskutil erase", "erase the hard drive"
        ]
        if formatPatterns.contains(where: { lower.contains($0) }) {
            return .refuse(reason: "Refused for safety: formatting or erasing storage drives is prohibited.")
        }

        let catastrophicShellPatterns = [
            "rm -rf", "rm -fr", "mkfs", "dd if=/dev/", ":(){", "chmod -r 777"
        ]
        if catastrophicShellPatterns.contains(where: { lower.contains($0) }) {
            return .refuse(reason: "Refused for safety: catastrophic shell command blocked.")
        }

        if lower.contains("disable the antivirus") || lower.contains("disable antivirus") ||
           lower.contains("turn off antivirus") || lower.contains("turn off the antivirus") ||
           lower.contains("disable firewall") || lower.contains("disable gatekeeper") ||
           lower.contains("spctl --master-disable") {
            return .refuse(reason: "Refused for safety: disabling security or antivirus protection is prohibited.")
        }

        // Protected OS system path write refusal
        let protectedPrefixes = ["/system/", "/library/application", "/usr/bin/", "/bin/", "/sbin/", "/etc/"]
        if (lower.contains("save") || lower.contains("write") || lower.contains("create") || lower.contains("move") || lower.contains("delete")) &&
           protectedPrefixes.contains(where: { lower.contains($0) }) {
            return .refuse(reason: "Refused for safety: writing to protected OS system directories is not allowed.")
        }

        // Sensitive credentials protection
        if (lower.contains("saved password") || lower.contains("my password") || lower.contains("show password") ||
            lower.contains("reveal password") || lower.contains("dump keychain")) &&
           (lower.contains("show") || lower.contains("give") || lower.contains("list") || lower.contains("tell") || lower.contains("export") || lower.contains("read")) {
            return .refuse(reason: "Blocked for security: displaying saved passwords requires explicit macOS Keychain authentication.")
        }

        // 3. Consequential Actions Requiring Explicit Confirmation
        if lower.hasPrefix("uninstall ") || lower.contains(" uninstall ") {
            let target = trimmed.replacingOccurrences(of: "(?i)^.*uninstall\\s+", with: "", options: .regularExpression)
            let appLabel = target.isEmpty ? "Application" : target
            return .confirm(
                toolName: "system_uninstall",
                appName: appLabel,
                title: "Confirm uninstall of \(appLabel)?",
                subtitle: "Uninstalling removes the application bundle and cannot be easily undone.",
                dryRunNotice: "Dry-run: confirmed uninstall request for \(appLabel) safely."
            )
        }

        if (lower.contains("send all") || lower.contains("email all") || lower.contains("upload all")) &&
           (lower.contains("document") || lower.contains("file") || lower.contains("folder")) {
            return .confirm(
                toolName: "bulk_document_send",
                appName: "Mail",
                title: "Confirm sending all documents?",
                subtitle: "Bulk external transfer of documents requires explicit approval.",
                dryRunNotice: "Dry-run: blocked/confirmed bulk document transfer cleanly."
            )
        }

        if lower.contains("make a payment") || lower.contains("send money") || lower.contains("transfer money") ||
           (lower.contains("pay ") && (lower.contains("rupee") || lower.contains("dollar") || lower.contains("$") || lower.contains("₹") || lower.contains("inr"))) {
            return .confirm(
                toolName: "financial_payment",
                appName: "Payments",
                title: "Confirm financial payment?",
                subtitle: "Monetary payments require multi-step user confirmation before execution.",
                dryRunNotice: "Dry-run: payment action intercepted for multi-step confirmation."
            )
        }

        if lower.contains("install") && (lower.contains("http://") || lower.contains("https://") || lower.contains(".pkg") || lower.contains(".dmg") || lower.contains("random link")) {
            return .confirm(
                toolName: "external_software_install",
                appName: "Installer",
                title: "Confirm external software installation?",
                subtitle: "Installing unverified software from external links poses security risks.",
                dryRunNotice: "Dry-run: external software installation gated with warning."
            )
        }

        if lower.contains("shut down") || lower == "shutdown" || lower.hasPrefix("shutdown ") {
            return .confirm(
                toolName: "system_shutdown",
                appName: "System Power",
                title: "Confirm computer shut down?",
                subtitle: "All unsaved open applications will be closed.",
                dryRunNotice: "Dry-run: shut down request gated safely."
            )
        }

        if lower.contains("restart the computer") || lower.contains("restart computer") || lower.contains("restart mac") || lower == "restart" || lower == "reboot" {
            return .confirm(
                toolName: "system_restart",
                appName: "System Power",
                title: "Confirm computer restart?",
                subtitle: "Restarting closes active sessions.",
                dryRunNotice: "Dry-run: restart request gated safely."
            )
        }

        return .allow
    }

    /// Evaluates firewall and awaits `ToolApprovalCoordinator` (`.consequential`) when confirmation is needed.
    /// Returns `nil` when allowed to proceed, or an `AutonomousExecutionResult` when blocked/refused/dry-run completed.
    public func enforce(
        command: String,
        customApprovalHandler: (@Sendable (AgentAction) async -> Bool)? = nil
    ) async -> AutonomousExecutionResult? {
        switch evaluate(command: command) {
        case .allow:
            return nil

        case .refuse(let reason):
            EventBus.shared.publish(VoiceEvent(
                kind: .custom("safety_refusal"),
                source: "CommandSafetyFirewall",
                severity: .warning,
                payload: ["reason": String(reason.prefix(160))]
            ))
            return AutonomousExecutionResult(
                success: false,
                summary: reason,
                targetAppName: "Safety Guardrail",
                targetURL: nil,
                executedSteps: ["Blocked by central safety firewall: \(reason)"]
            )

        case .confirm(let toolName, let appName, let title, let subtitle, let dryRunNotice):
            let gate = await ToolApprovalCoordinator.shared.requestAuthorizationIfNeeded(
                toolName: toolName,
                appName: appName,
                title: title,
                subtitle: subtitle,
                payload: ["command": SecretRedactor.redact(command)],
                tier: .consequential,
                customApprovalHandler: customApprovalHandler
            )
            if !gate.approved {
                return AutonomousExecutionResult(
                    success: false,
                    summary: "Confirmation required: \(title) Cancelled safely.",
                    targetAppName: appName,
                    targetURL: nil,
                    executedSteps: ["Paused for explicit confirmation: \(title)"]
                )
            }
            if ProcessInfo.processInfo.environment["VOICE_AI_DRY_RUN"] == "1" {
                return AutonomousExecutionResult(
                    success: true,
                    summary: dryRunNotice,
                    targetAppName: appName,
                    targetURL: nil,
                    executedSteps: ["Confirmed in dry-run mode without system mutation"]
                )
            }
            if toolName == "system_shutdown" {
                let ok = AccessibilityControlEngine.shared.performSystemControl("shutdown")
                return AutonomousExecutionResult(success: ok, summary: ok ? "Shutting down." : "Shutdown cancelled.", targetAppName: "System Power")
            }
            if toolName == "system_restart" {
                let ok = AccessibilityControlEngine.shared.performSystemControl("restart")
                return AutonomousExecutionResult(success: ok, summary: ok ? "Restarting." : "Restart cancelled.", targetAppName: "System Power")
            }
            return AutonomousExecutionResult(
                success: false,
                summary: "\(title) Cannot automatically complete without interactive confirmation in target installer/payment app.",
                targetAppName: appName,
                targetURL: nil,
                executedSteps: ["Explicitly approved, deferred to interactive host flow"]
            )
        }
    }
}

