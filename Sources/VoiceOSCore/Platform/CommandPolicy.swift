import Foundation
import CryptoKit

// MARK: - Shell Tokenizer & Policy Types

public enum ShellToken: Equatable, Sendable {
    case word(String, wasQuoted: Bool)
    case pipe                  // |
    case andIf                 // &&
    case orIf                  // ||
    case semicolon             // ;
    case redirectOut(append: Bool) // > or >>
    case redirectErr(append: Bool) // 2> or 2>>
    case redirectBoth          // &>
    case redirectIn            // <
}

public enum ShellParseError: Error, Equatable, Sendable {
    case emptyCommand
    case unterminatedQuote
    case trailingEscape
    case unsupportedConstruct(String)
}

public enum CommandClassification: String, Codable, Sendable, Comparable {
    case readOnly = "READ_ONLY"
    case needsApproval = "NEEDS_APPROVAL"
    case blocked = "BLOCKED"

    private var severity: Int {
        switch self {
        case .readOnly: return 0
        case .needsApproval: return 1
        case .blocked: return 2
        }
    }

    public static func < (lhs: CommandClassification, rhs: CommandClassification) -> Bool {
        lhs.severity < rhs.severity
    }
}

public struct CommandSegment: Equatable, Sendable {
    public let program: String
    public let args: [String]
    public let redirections: [(operatorLabel: String, target: String)]
    public let classification: CommandClassification
    public let reason: String?

    public static func == (lhs: CommandSegment, rhs: CommandSegment) -> Bool {
        lhs.program == rhs.program &&
        lhs.args == rhs.args &&
        lhs.classification == rhs.classification &&
        lhs.reason == rhs.reason &&
        lhs.redirections.count == rhs.redirections.count &&
        zip(lhs.redirections, rhs.redirections).allSatisfy {
            $0.operatorLabel == $1.operatorLabel && $0.target == $1.target
        }
    }
}

public struct CommandPolicyDecision: Equatable, Sendable, Error {
    public let classification: CommandClassification
    public let segments: [CommandSegment]
    public let resolvedWorkingDirectory: String
    public let commandHash: String
    public let reason: String
    public let touchedPaths: [String]
    public let isSafeForShellPipeline: Bool

    public var isAllowedToPromptOrRun: Bool {
        classification != .blocked
    }
}

// MARK: - Shell Tokenizer (Real Parser, Not Regex)

public enum ShellTokenizer {
    public static func tokenize(_ raw: String) -> Result<[ShellToken], ShellParseError> {
        let chars = Array(raw)
        var i = 0
        var tokens: [ShellToken] = []

        func skipWhitespace() {
            while i < chars.count && (chars[i] == " " || chars[i] == "\t" || chars[i] == "\n" || chars[i] == "\r") {
                i += 1
            }
        }

        while i < chars.count {
            skipWhitespace()
            if i >= chars.count { break }

            let c = chars[i]

            // Unsupported/obfuscation constructs
            if c == "`" {
                return .failure(.unsupportedConstruct("Backtick command substitution (`...`) is not allowed."))
            }
            if c == "(" || c == ")" {
                return .failure(.unsupportedConstruct("Subshell grouping '(...)' is not allowed."))
            }

            // Check two-char operators first
            if c == "|" {
                if i + 1 < chars.count && chars[i + 1] == "|" {
                    tokens.append(.orIf)
                    i += 2
                } else {
                    tokens.append(.pipe)
                    i += 1
                }
                continue
            }
            if c == "&" {
                if i + 1 < chars.count && chars[i + 1] == "&" {
                    tokens.append(.andIf)
                    i += 2
                    continue
                }
                if i + 1 < chars.count && chars[i + 1] == ">" {
                    tokens.append(.redirectBoth)
                    i += 2
                    continue
                }
                return .failure(.unsupportedConstruct("Background execution '&' is not allowed."))
            }
            if c == ";" {
                tokens.append(.semicolon)
                i += 1
                continue
            }
            if c == ">" {
                if i + 1 < chars.count && chars[i + 1] == ">" {
                    tokens.append(.redirectOut(append: true))
                    i += 2
                } else if i + 1 < chars.count && chars[i + 1] == "(" {
                    return .failure(.unsupportedConstruct("Process substitution '>(' is not allowed."))
                } else {
                    tokens.append(.redirectOut(append: false))
                    i += 1
                }
                continue
            }
            if c == "<" {
                if i + 1 < chars.count && chars[i + 1] == "<" {
                    return .failure(.unsupportedConstruct("Here-doc '<<' is not allowed."))
                } else if i + 1 < chars.count && chars[i + 1] == "(" {
                    return .failure(.unsupportedConstruct("Process substitution '<(' is not allowed."))
                } else {
                    tokens.append(.redirectIn)
                    i += 1
                }
                continue
            }
            if c == "2" && i + 1 < chars.count && chars[i + 1] == ">" &&
                (tokens.isEmpty || (i == 0 || chars[i - 1].isWhitespace)) {
                if i + 2 < chars.count && chars[i + 2] == ">" {
                    tokens.append(.redirectErr(append: true))
                    i += 3
                } else {
                    tokens.append(.redirectErr(append: false))
                    i += 2
                }
                continue
            }

            // Parse word (handling quotes, escapes, and rejecting $(...) / ${...} / unquoted $)
            var buf = ""
            var wasQuoted = false
            var inSingle = false
            var inDouble = false

            while i < chars.count {
                let ch = chars[i]
                if inSingle {
                    if ch == "'" {
                        inSingle = false
                        i += 1
                    } else {
                        buf.append(ch)
                        i += 1
                    }
                    continue
                }
                if inDouble {
                    if ch == "\"" {
                        inDouble = false
                        i += 1
                    } else if ch == "\\" {
                        guard i + 1 < chars.count else { return .failure(.trailingEscape) }
                        let next = chars[i + 1]
                        if next == "\"" || next == "\\" || next == "$" || next == "`" {
                            buf.append(next)
                        } else {
                            buf.append("\\")
                            buf.append(next)
                        }
                        i += 2
                    } else if ch == "`" {
                        return .failure(.unsupportedConstruct("Backtick command substitution inside quotes is not allowed."))
                    } else if ch == "$" && i + 1 < chars.count && (chars[i + 1] == "(" || chars[i + 1] == "{") {
                        return .failure(.unsupportedConstruct("Command or variable expansion inside quotes is not allowed."))
                    } else if ch == "$" {
                        return .failure(.unsupportedConstruct("Shell variable expansion '$...' is not allowed."))
                    } else {
                        buf.append(ch)
                        i += 1
                    }
                    continue
                }

                // Unquoted state
                if ch.isWhitespace || ch == "|" || ch == "&" || ch == ";" || ch == "<" || ch == ">" || ch == "(" || ch == ")" {
                    break
                }
                if ch == "`" {
                    return .failure(.unsupportedConstruct("Backtick command substitution is not allowed."))
                }
                if ch == "$" {
                    return .failure(.unsupportedConstruct("Shell variable or command substitution '$...' is not allowed."))
                }
                if ch == "'" {
                    inSingle = true
                    wasQuoted = true
                    i += 1
                    continue
                }
                if ch == "\"" {
                    inDouble = true
                    wasQuoted = true
                    i += 1
                    continue
                }
                if ch == "\\" {
                    guard i + 1 < chars.count else { return .failure(.trailingEscape) }
                    buf.append(chars[i + 1])
                    i += 2
                    continue
                }
                buf.append(ch)
                i += 1
            }

            if inSingle || inDouble {
                return .failure(.unterminatedQuote)
            }
            tokens.append(.word(buf, wasQuoted: wasQuoted))
        }

        if tokens.isEmpty {
            return .failure(.emptyCommand)
        }
        return .success(tokens)
    }
}

// MARK: - Path Policy & Canonicalization

public enum PathPolicy {
    public static let allowedRootsDefaultsKey = "VoiceAI_TerminalAllowedRoots"

    public static func defaultAllowedRoots(homeDirectory: String = NSHomeDirectory()) -> [String] {
        let home = URL(fileURLWithPath: homeDirectory, isDirectory: true).standardizedFileURL.path
        return [
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/VoiceAI-Workspace"
        ]
    }

    public static func configuredAllowedRoots(homeDirectory: String = NSHomeDirectory()) -> [String] {
        var roots = defaultAllowedRoots(homeDirectory: homeDirectory)
        if let custom = UserDefaults.standard.stringArray(forKey: allowedRootsDefaultsKey) {
            for r in custom where !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let expanded = (r as NSString).expandingTildeInPath
                let real = canonicalizeExistingOrParent(path: expanded)
                if !roots.contains(real) {
                    roots.append(real)
                }
            }
        }
        return roots.map { canonicalizeExistingOrParent(path: $0) }
    }

    /// Expands `~` (for current user only), resolves relative paths against `workingDirectory`,
    /// resolves `..`, and resolves symlinks via `realpath` (or deepest existing parent).
    public static func canonicalize(
        _ rawPath: String,
        workingDirectory: String,
        homeDirectory: String = NSHomeDirectory()
    ) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Reject ~otheruser syntax
        if trimmed.hasPrefix("~") && trimmed != "~" && !trimmed.hasPrefix("~/") {
            return nil
        }

        let expanded: String
        if trimmed == "~" {
            expanded = homeDirectory
        } else if trimmed.hasPrefix("~/") {
            expanded = (homeDirectory as NSString).appendingPathComponent(String(trimmed.dropFirst(2)))
        } else if trimmed.hasPrefix("/") {
            expanded = trimmed
        } else {
            expanded = (workingDirectory as NSString).appendingPathComponent(trimmed)
        }

        return canonicalizeExistingOrParent(path: expanded)
    }

    public static func canonicalizeExistingOrParent(path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if let resolvedPtr = realpath(standardized, nil) {
            let resolved = String(cString: resolvedPtr)
            free(resolvedPtr)
            return resolved
        }

        // Walk up to the deepest existing ancestor, resolve its symlinks, then append remaining components
        var current = URL(fileURLWithPath: standardized)
        var trailing: [String] = []
        let fm = FileManager.default
        while !fm.fileExists(atPath: current.path) && current.path != "/" {
            trailing.insert(current.lastPathComponent, at: 0)
            current = current.deletingLastPathComponent()
        }
        var basePath = current.path
        if let resolvedPtr = realpath(basePath, nil) {
            basePath = String(cString: resolvedPtr)
            free(resolvedPtr)
        }
        var out = URL(fileURLWithPath: basePath)
        for comp in trailing {
            out.appendPathComponent(comp)
        }
        return out.standardizedFileURL.path
    }

    public static func isPathInsideRoots(_ realPath: String, roots: [String]) -> Bool {
        let normalizedTarget = canonicalizeExistingOrParent(path: realPath)
        for root in roots {
            let normalizedRoot = canonicalizeExistingOrParent(path: root)
            if normalizedTarget == normalizedRoot {
                return true
            }
            let prefix = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"
            if normalizedTarget.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }

    public static func isProtectedSensitivePath(_ realPath: String) -> Bool {
        let lower = realPath.lowercased()
        let last = URL(fileURLWithPath: realPath).lastPathComponent.lowercased()

        // Dotfiles & sensitive directories anywhere
        if last.hasPrefix(".") && last != "." && last != ".." {
            return true
        }
        let protectedSubstrings = [
            "/.ssh", "/.aws", "/.gnupg", "/.kube", "/.docker/config.json",
            "/library/keychains", "/library/application support/google/chrome",
            "/library/application support/firefox", "/library/safari",
            "/.zshrc", "/.bashrc", "/.bash_profile", "/.zprofile",
            "/library/launchagents", "/library/launchdaemons",
            "/etc/", "/system/", "/private/etc/", "/usr/", "/bin/", "/sbin/"
        ]
        if protectedSubstrings.contains(where: { lower.contains($0) }) {
            return true
        }

        if last == "id_rsa" || last == "id_ed25519" || last == "id_dsa" ||
           last.hasPrefix("credentials") || last.contains("keychain") ||
           last.hasSuffix(".pem") || last.hasSuffix(".key") || last.hasSuffix(".p12") ||
           last.hasSuffix(".pfx") || last == "known_hosts" || last == "authorized_keys" {
            return true
        }
        return false
    }
}

// MARK: - CommandPolicy (Pure-Logic Classifier)

public final class CommandPolicy: @unchecked Sendable {
    public static let extraProgramsDefaultsKey = "VoiceAI_TerminalAllowedPrograms"

    public static let readOnlyPrograms: Set<String> = [
        "ls", "cat", "head", "tail", "wc", "find", "grep", "stat",
        "du", "df", "pwd", "file", "mdfind", "which", "date", "sort", "uniq", "diff"
    ]

    public static let mutatingAllowedPrograms: Set<String> = [
        "cp", "mv", "mkdir", "touch", "tar", "zip", "unzip", "open", "sed", "awk"
    ]

    public static let alwaysBlockedPrograms: Set<String> = [
        "sudo", "su", "doas", "rm", "rmdir", "srm", "unlink",
        "mkfs", "dd", "diskutil", "fdisk", "newfs", "newfs_apfs", "newfs_hfs",
        "shutdown", "reboot", "halt", "poweroff",
        "launchctl", "systemsetup", "csrutil", "spctl", "nvram", "kextload", "kextunload",
        "security", "passwd", "dscl", "chsh", "visudo",
        "curl", "wget", "nc", "ncat", "netcat", "telnet", "ssh", "scp", "sftp", "rsync",
        "python", "python3", "python2", "node", "ruby", "perl", "php", "lua",
        "osascript", "sh", "bash", "zsh", "fish", "csh", "tcsh", "dash", "ksh",
        "eval", "exec", "source", "crontab", "at", "kill", "killall", "pkill",
        "defaults", "chmod", "chown", "chgrp", "xargs", "env",
        "brew", "npm", "npx", "pip", "pip3", "cargo", "xcodebuild", "swift", "make", "cmake"
    ]

    private let allowedRootsProvider: @Sendable () -> [String]

    public var allowedRoots: [String] {
        allowedRootsProvider()
    }
    private let extraProgramsProvider: @Sendable () -> Set<String>
    private let homeDirectory: String

    public init(
        allowedRoots: [String]? = nil,
        extraAllowedPrograms: Set<String>? = nil,
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.homeDirectory = homeDirectory
        if let roots = allowedRoots {
            let normalized = roots.map { PathPolicy.canonicalizeExistingOrParent(path: $0) }
            self.allowedRootsProvider = { normalized }
        } else {
            self.allowedRootsProvider = { PathPolicy.configuredAllowedRoots(homeDirectory: homeDirectory) }
        }
        if let extra = extraAllowedPrograms {
            let lowered = Set(extra.map { $0.lowercased() })
            self.extraProgramsProvider = { lowered }
        } else {
            self.extraProgramsProvider = {
                Set((UserDefaults.standard.stringArray(forKey: Self.extraProgramsDefaultsKey) ?? []).map { $0.lowercased() })
            }
        }
    }

    public static func bindingHash(command: String, workingDirectory: String) -> String {
        let canonicalPayload = "\(workingDirectory)\n\(command)"
        let digest = SHA256.hash(data: Data(canonicalPayload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func evaluate(command rawCommand: String, workingDirectory rawWorkingDir: String? = nil) -> CommandPolicyDecision {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let roots = allowedRootsProvider()
        let defaultRoot = roots.first ?? PathPolicy.canonicalizeExistingOrParent(path: "\(homeDirectory)/Desktop")
        let candidateWD = rawWorkingDir?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedWD: String
        if let wd = candidateWD, !wd.isEmpty {
            resolvedWD = PathPolicy.canonicalize(wd, workingDirectory: defaultRoot, homeDirectory: homeDirectory) ?? defaultRoot
        } else {
            resolvedWD = defaultRoot
        }

        let hash = Self.bindingHash(command: trimmed, workingDirectory: resolvedWD)

        guard PathPolicy.isPathInsideRoots(resolvedWD, roots: roots) && !PathPolicy.isProtectedSensitivePath(resolvedWD) else {
            return CommandPolicyDecision(
                classification: .blocked,
                segments: [],
                resolvedWorkingDirectory: resolvedWD,
                commandHash: hash,
                reason: "Working directory '\(resolvedWD)' is outside allowed folders.",
                touchedPaths: [resolvedWD],
                isSafeForShellPipeline: false
            )
        }

        let tokens: [ShellToken]
        switch ShellTokenizer.tokenize(trimmed) {
        case .failure(let err):
            let msg: String
            switch err {
            case .emptyCommand: msg = "Empty command."
            case .unterminatedQuote: msg = "Command has an unterminated quote and cannot be parsed safely."
            case .trailingEscape: msg = "Command ends with an incomplete escape."
            case .unsupportedConstruct(let detail): msg = detail
            }
            return CommandPolicyDecision(
                classification: .blocked,
                segments: [],
                resolvedWorkingDirectory: resolvedWD,
                commandHash: hash,
                reason: msg,
                touchedPaths: [],
                isSafeForShellPipeline: false
            )
        case .success(let parsed):
            tokens = parsed
        }

        // Split tokens into segments separated by |, &&, ||, ;
        var rawSegments: [(words: [String], redirections: [(String, String)])] = []
        var curWords: [String] = []
        var curRedirs: [(String, String)] = []
        var hasPipelineOrChain = false
        var idx = 0

        while idx < tokens.count {
            switch tokens[idx] {
            case .word(let w, _):
                curWords.append(w)
                idx += 1
            case .pipe, .andIf, .orIf, .semicolon:
                hasPipelineOrChain = true
                if curWords.isEmpty {
                    return blockedDecision(wd: resolvedWD, hash: hash, reason: "Empty command segment around operator.")
                }
                rawSegments.append((curWords, curRedirs))
                curWords = []
                curRedirs = []
                idx += 1
            case .redirectOut(let append):
                let op = append ? ">>" : ">"
                guard idx + 1 < tokens.count, case .word(let target, _) = tokens[idx + 1] else {
                    return blockedDecision(wd: resolvedWD, hash: hash, reason: "Missing redirection target after '\(op)'.")
                }
                curRedirs.append((op, target))
                hasPipelineOrChain = true
                idx += 2
            case .redirectErr(let append):
                let op = append ? "2>>" : "2>"
                guard idx + 1 < tokens.count, case .word(let target, _) = tokens[idx + 1] else {
                    return blockedDecision(wd: resolvedWD, hash: hash, reason: "Missing redirection target after '\(op)'.")
                }
                curRedirs.append((op, target))
                hasPipelineOrChain = true
                idx += 2
            case .redirectBoth:
                guard idx + 1 < tokens.count, case .word(let target, _) = tokens[idx + 1] else {
                    return blockedDecision(wd: resolvedWD, hash: hash, reason: "Missing redirection target after '&>'.")
                }
                curRedirs.append(("&>", target))
                hasPipelineOrChain = true
                idx += 2
            case .redirectIn:
                guard idx + 1 < tokens.count, case .word(let target, _) = tokens[idx + 1] else {
                    return blockedDecision(wd: resolvedWD, hash: hash, reason: "Missing input redirection target after '<'.")
                }
                curRedirs.append(("<", target))
                hasPipelineOrChain = true
                idx += 2
            }
        }
        if curWords.isEmpty {
            return blockedDecision(wd: resolvedWD, hash: hash, reason: "Trailing operator with no command.")
        }
        rawSegments.append((curWords, curRedirs))

        var evaluatedSegments: [CommandSegment] = []
        var highestClassification: CommandClassification = .readOnly
        var collectedPaths: [String] = []
        var firstReason: String?

        for seg in rawSegments {
            // Reject inline VAR=val prefixes before program
            if seg.words[0].contains("=") && !seg.words[0].hasPrefix("/") {
                return blockedDecision(wd: resolvedWD, hash: hash, reason: "Environment variable assignment prefixes are not allowed.")
            }

            let rawProgram = seg.words[0]
            let progName = URL(fileURLWithPath: rawProgram).lastPathComponent.lowercased()
            let args = Array(seg.words.dropFirst())

            // Validate redirection targets first
            var segHasWriteRedirection = false
            for (op, target) in seg.redirections {
                if op != "<" { segHasWriteRedirection = true }
                guard let resolvedTarget = PathPolicy.canonicalize(target, workingDirectory: resolvedWD, homeDirectory: homeDirectory) else {
                    return blockedDecision(wd: resolvedWD, hash: hash, reason: "Invalid redirection path '\(target)'.")
                }
                if PathPolicy.isProtectedSensitivePath(resolvedTarget) {
                    return blockedDecision(wd: resolvedWD, hash: hash, reason: "Access to protected file '\(target)' is blocked.")
                }
                if !PathPolicy.isPathInsideRoots(resolvedTarget, roots: roots) {
                    return blockedDecision(wd: resolvedWD, hash: hash, reason: "Redirection target '\(target)' is outside allowed folders.")
                }
                collectedPaths.append(resolvedTarget)
            }

            let segEval = classifySegment(
                program: progName,
                rawProgram: rawProgram,
                args: args,
                hasWriteRedirection: segHasWriteRedirection,
                workingDirectory: resolvedWD,
                roots: roots,
                touchedPaths: &collectedPaths
            )
            let segment = CommandSegment(
                program: rawProgram,
                args: args,
                redirections: seg.redirections,
                classification: segEval.classification,
                reason: segEval.reason
            )
            evaluatedSegments.append(segment)
            if segEval.classification > highestClassification {
                highestClassification = segEval.classification
                firstReason = segEval.reason
            } else if firstReason == nil && segEval.reason != nil {
                firstReason = segEval.reason
            }
        }

        let summaryReason = firstReason ?? (highestClassification == .readOnly ? "Read-only inspection command." : "Modifies or opens user files inside allowed workspace.")
        return CommandPolicyDecision(
            classification: highestClassification,
            segments: evaluatedSegments,
            resolvedWorkingDirectory: resolvedWD,
            commandHash: hash,
            reason: summaryReason,
            touchedPaths: Array(Set(collectedPaths)).sorted(),
            isSafeForShellPipeline: hasPipelineOrChain && highestClassification != .blocked
        )
    }

    private func blockedDecision(wd: String, hash: String, reason: String) -> CommandPolicyDecision {
        CommandPolicyDecision(
            classification: .blocked,
            segments: [],
            resolvedWorkingDirectory: wd,
            commandHash: hash,
            reason: reason,
            touchedPaths: [],
            isSafeForShellPipeline: false
        )
    }

    private func classifySegment(
        program: String,
        rawProgram: String,
        args: [String],
        hasWriteRedirection: Bool,
        workingDirectory: String,
        roots: [String],
        touchedPaths: inout [String]
    ) -> (classification: CommandClassification, reason: String?) {
        // 1. Always-blocked programs (no override possible)
        if Self.alwaysBlockedPrograms.contains(program) || program.hasPrefix("mkfs") || program.hasPrefix("newfs") {
            let reason: String
            if program == "rm" || program == "rmdir" || program == "srm" || program == "unlink" {
                reason = "Direct 'rm' deletion is blocked; Voice.AI safely moves items to Trash after confirmation."
            } else if ["brew", "npm", "npx", "pip", "pip3", "cargo", "xcodebuild", "swift", "make", "cmake"].contains(program) {
                reason = "Long-running build/install tasks ('\(program)') are not permitted in Voice Terminal."
            } else {
                reason = "Program '\(program)' is permanently blocked by CommandPolicy."
            }
            return (.blocked, reason)
        }

        // 2. Reject path-qualified binaries outside standard system bins
        if rawProgram.contains("/") {
            let allowedBinPrefixes = ["/bin/", "/usr/bin/", "/usr/sbin/", "/opt/homebrew/bin/"]
            if !allowedBinPrefixes.contains(where: { rawProgram.hasPrefix($0) }) {
                return (.blocked, "Executing arbitrary binaries by path ('\(rawProgram)') is blocked.")
            }
        }

        // 3. Program allow-list check
        let extra = extraProgramsProvider()
        let isReadOnly = Self.readOnlyPrograms.contains(program)
        let isMutating = Self.mutatingAllowedPrograms.contains(program)
        let isGit = (program == "git")
        let isUserAllowed = extra.contains(program)

        guard isReadOnly || isMutating || isGit || isUserAllowed else {
            return (.blocked, "Program '\(program)' is not in the allowed terminal program list.")
        }

        // 4. Program-specific argument rules
        if isGit {
            guard let sub = args.first(where: { !$0.hasPrefix("-") })?.lowercased() else {
                return (.blocked, "Missing git subcommand.")
            }
            let safeGitSubs: Set<String> = ["status", "log", "diff", "show", "branch"]
            if !safeGitSubs.contains(sub) {
                return (.blocked, "Only read-only git subcommands (status, log, diff, show, branch) are allowed; '\(sub)' is blocked.")
            }
            if args.contains("--force") || args.contains("-f") {
                return (.blocked, "Forced git flags are blocked.")
            }
        }

        if program == "find" {
            let dangerousFindFlags: Set<String> = ["-delete", "-exec", "-execdir", "-ok", "-okdir", "-fls", "-fprint", "-fprint0", "-fprintf"]
            for arg in args {
                if dangerousFindFlags.contains(arg.lowercased()) {
                    return (.blocked, "Dangerous find flag '\(arg)' is blocked.")
                }
            }
        }

        if program == "awk" {
            let joined = args.joined(separator: " ").lowercased()
            if joined.contains("system(") || joined.contains("| getline") {
                return (.blocked, "awk command execution via system() or getline pipe is blocked.")
            }
        }

        var sedInPlace = false
        if program == "sed" {
            for arg in args {
                if arg == "-i" || arg.hasPrefix("-i.") || arg.hasPrefix("--in-place") {
                    sedInPlace = true
                }
                if arg.lowercased().contains("e ") || arg.lowercased().hasSuffix("e") {
                    // GNU sed /e execution check
                    if arg.contains("/") && arg.lowercased().contains("/e") {
                        return (.blocked, "sed '/e' shell execution modifier is blocked.")
                    }
                }
            }
        }

        // 5. Validate all path-like arguments against allowed roots & protected files
        let pathCheck = validatePathArguments(
            program: program,
            args: args,
            workingDirectory: workingDirectory,
            roots: roots,
            touchedPaths: &touchedPaths
        )
        if let blockReason = pathCheck {
            return (.blocked, blockReason)
        }

        // 6. Final classification
        if isUserAllowed || isMutating || sedInPlace || hasWriteRedirection {
            if program == "sed" && !sedInPlace && !hasWriteRedirection {
                return (.readOnly, nil)
            }
            if program == "awk" && !hasWriteRedirection {
                return (.readOnly, nil)
            }
            return (.needsApproval, nil)
        }

        return (.readOnly, nil)
    }

    private func validatePathArguments(
        program: String,
        args: [String],
        workingDirectory: String,
        roots: [String],
        touchedPaths: inout [String]
    ) -> String? {
        // Programs whose first non-flag arg is a pattern (not a path)
        let firstArgIsPattern = (program == "grep" || program == "sed" || program == "awk" || program == "mdfind")
        var sawPattern = false

        for (index, arg) in args.enumerated() {
            if arg == "--" { continue }
            if arg.hasPrefix("-") {
                // Check embedded path in --flag=path
                if let eqIdx = arg.firstIndex(of: "=") {
                    let val = String(arg[arg.index(after: eqIdx)...])
                    if looksLikePath(val) {
                        if let err = checkSinglePath(val, workingDirectory: workingDirectory, roots: roots, touchedPaths: &touchedPaths) {
                            return err
                        }
                    }
                }
                continue
            }

            if firstArgIsPattern && !sawPattern {
                // Skip pattern argument unless it's explicitly a ~/ or / path or .. traversal
                sawPattern = true
                if !arg.hasPrefix("/") && !arg.hasPrefix("~") && !arg.contains("..") {
                    continue
                }
            }

            // Skip flags' non-path numeric/name parameters (e.g. find -size +10M, -name *.pdf, head -n 20)
            if index > 0 {
                let prev = args[index - 1].lowercased()
                if ["-name", "-iname", "-type", "-size", "-mtime", "-maxdepth", "-mindepth", "-n", "-c", "-d", "-k"].contains(prev) {
                    continue
                }
            }

            if program == "which" || program == "date" || program == "pwd" || program == "df" {
                if !looksLikePath(arg) { continue }
            }

            // Handle ~otheruser explicitly
            if arg.hasPrefix("~") && arg != "~" && !arg.hasPrefix("~/") {
                return "Access to another user's home directory ('\(arg)') is blocked."
            }

            // Check wildcards / globs by validating parent directory
            if arg.contains("*") || arg.contains("?") || arg.contains("[") {
                let parent = (arg as NSString).deletingLastPathComponent
                let checkTarget = parent.isEmpty ? "." : parent
                if let err = checkSinglePath(checkTarget, workingDirectory: workingDirectory, roots: roots, touchedPaths: &touchedPaths) {
                    return err
                }
                // Check if glob explicitly names a dotfile or protected pattern
                let last = (arg as NSString).lastPathComponent.lowercased()
                if last.hasPrefix(".") || last.contains(".pem") || last.contains(".key") || last.contains("id_rsa") {
                    return "Access to protected file pattern '\(arg)' is blocked."
                }
                continue
            }

            if let err = checkSinglePath(arg, workingDirectory: workingDirectory, roots: roots, touchedPaths: &touchedPaths) {
                return err
            }
        }
        return nil
    }

    private func looksLikePath(_ value: String) -> Bool {
        value.hasPrefix("/") || value.hasPrefix("~") || value.hasPrefix("./") || value.hasPrefix("../") || value.contains("/")
    }

    private func checkSinglePath(
        _ rawPath: String,
        workingDirectory: String,
        roots: [String],
        touchedPaths: inout [String]
    ) -> String? {
        guard let real = PathPolicy.canonicalize(rawPath, workingDirectory: workingDirectory, homeDirectory: homeDirectory) else {
            return "Path '\(rawPath)' could not be canonicalized safely."
        }
        if PathPolicy.isProtectedSensitivePath(real) {
            return "Access to protected path '\(rawPath)' is blocked."
        }
        if !PathPolicy.isPathInsideRoots(real, roots: roots) {
            return "Path '\(rawPath)' resolves to '\(real)' outside allowed folders."
        }
        touchedPaths.append(real)
        return nil
    }
}
