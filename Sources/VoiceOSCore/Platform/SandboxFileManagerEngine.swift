import AppKit
import Foundation

/// Safe, sandbox-aware local file and folder automation engine (Section 5 & Section 11 context ops).
public final class SandboxFileManagerEngine: @unchecked Sendable {
    public static let shared = SandboxFileManagerEngine()

    public init() {}

    public func resolvedSandboxRoot() -> URL {
        if let envDir = ProcessInfo.processInfo.environment["VOICE_AI_SANDBOX_DIR"], !envDir.isEmpty {
            let url = URL(fileURLWithPath: envDir, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let homeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        if ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1" {
            let homeSandbox = homeURL.appendingPathComponent("voice-test", isDirectory: true)
            if FileManager.default.fileExists(atPath: homeSandbox.path) {
                return homeSandbox
            }
            let tmpSandbox = URL(fileURLWithPath: "/tmp/voice-test", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmpSandbox, withIntermediateDirectories: true)
            return tmpSandbox
        }
        return homeURL.appendingPathComponent("Desktop", isDirectory: true)
    }

    private func isProtectedPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        let protectedPrefixes = ["/system", "/library", "/usr", "/bin", "/sbin", "/etc"]
        return protectedPrefixes.contains(where: { lower == $0 || lower.hasPrefix($0 + "/") })
    }

    private var isCustomSandboxEnvSet: Bool {
        if let envDir = ProcessInfo.processInfo.environment["VOICE_AI_SANDBOX_DIR"], !envDir.isEmpty {
            return true
        }
        return false
    }

    private static func characterBigrams(_ input: String) -> [String] {
        let chars = Array(input.lowercased().filter { $0.isLetter || $0.isNumber })
        guard chars.count >= 2 else { return chars.map { String($0) } }
        return (0..<(chars.count - 1)).map { String([chars[$0], chars[$0 + 1]]) }
    }

    private static func similarityScore(_ a: String, _ b: String) -> Double {
        let ba = Set(characterBigrams(a))
        let bb = Set(characterBigrams(b))
        guard !ba.isEmpty, !bb.isEmpty else { return 0 }
        let overlap = Double(ba.intersection(bb).count)
        return (2.0 * overlap) / Double(ba.count + bb.count)
    }

    /// Resolves natural user folder phrases ("my desktop", "downloads", "Mohit or deaf folder", "~/Projects")
    /// into real macOS URLs (with fuzzy folder matching across Desktop, Documents, Downloads, and Home).
    public func resolveLocationDirectory(_ rawLocation: String?, root: URL) -> URL {
        let fm = FileManager.default
        let initialClean = (rawLocation ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !initialClean.isEmpty else { return root }

        // Handle compound like "Mohit or deaf folder on my desktop" -> preferDesktopOnly
        var cleanLoc = initialClean
        var preferDesktopOnly = false
        if let desktopSuffix = cleanLoc.range(of: #"(?i)\s+(?:on|in)\s+(?:the\s+|my\s+)?desktop$"#, options: .regularExpression) {
            cleanLoc = String(cleanLoc[..<desktopSuffix.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            preferDesktopOnly = true
        }
        cleanLoc = cleanLoc
            .replacingOccurrences(of: #"(?i)^(?:the\s+|my\s+)?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+(?:folder|directory)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let lower = cleanLoc.lowercased()
        guard !lower.isEmpty else {
            if preferDesktopOnly {
                return isCustomSandboxEnvSet
                    ? root.appendingPathComponent("Desktop", isDirectory: true)
                    : URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Desktop", isDirectory: true)
            }
            return root
        }

        if isCustomSandboxEnvSet {
            if lower == "desktop" || lower == "my desktop" {
                return root.appendingPathComponent("Desktop", isDirectory: true)
            }
            if lower == "document" || lower == "documents" {
                return root.appendingPathComponent("Documents", isDirectory: true)
            }
            if lower == "download" || lower == "downloads" {
                return root.appendingPathComponent("Downloads", isDirectory: true)
            }
            if let existing = findBestMatchingSubdirectory(named: cleanLoc, in: [root, root.appendingPathComponent("Desktop", isDirectory: true)]) {
                return existing
            }
            return (preferDesktopOnly ? root.appendingPathComponent("Desktop", isDirectory: true) : root)
                .appendingPathComponent(cleanLoc, isDirectory: true)
        }

        let homeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        if lower == "desktop" || lower == "my desktop" || lower == "the desktop" {
            return homeURL.appendingPathComponent("Desktop", isDirectory: true)
        }
        if lower == "downloads" || lower == "my downloads" || lower == "the downloads" || lower == "downloads folder" {
            return homeURL.appendingPathComponent("Downloads", isDirectory: true)
        }
        if lower == "documents" || lower == "my documents" || lower == "the documents" || lower == "documents folder" {
            return homeURL.appendingPathComponent("Documents", isDirectory: true)
        }
        if lower == "pictures" || lower == "my pictures" {
            return homeURL.appendingPathComponent("Pictures", isDirectory: true)
        }
        if lower == "music" || lower == "my music" {
            return homeURL.appendingPathComponent("Music", isDirectory: true)
        }
        if lower == "movies" || lower == "my movies" {
            return homeURL.appendingPathComponent("Movies", isDirectory: true)
        }
        if lower == "home" || lower == "home directory" || lower == "home folder" || lower == "~" {
            return homeURL
        }
        if cleanLoc.hasPrefix("~/") || cleanLoc.hasPrefix("/") {
            let expanded = (cleanLoc as NSString).expandingTildeInPath
            if !isProtectedPath(expanded) {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }

        let desktopURL = homeURL.appendingPathComponent("Desktop", isDirectory: true)
        let searchRoots = preferDesktopOnly ? [desktopURL] : [
            desktopURL,
            homeURL.appendingPathComponent("Documents", isDirectory: true),
            homeURL.appendingPathComponent("Downloads", isDirectory: true),
            root,
            homeURL
        ]
        if let bestMatch = findBestMatchingSubdirectory(named: cleanLoc, in: searchRoots) {
            return bestMatch
        }
        if !preferDesktopOnly, let spotlightDir = findItemsOnComputer(named: cleanLoc, foldersOnly: true, limit: 1).first {
            return spotlightDir
        }
        return (preferDesktopOnly ? desktopURL : root).appendingPathComponent(cleanLoc, isDirectory: true)
    }

    private func findBestMatchingSubdirectory(named query: String, in searchRoots: [URL]) -> URL? {
        let fm = FileManager.default
        let lower = query.lowercased()
        let compactQuery = lower.replacingOccurrences(of: " ", with: "")
        var bestFuzzy: (url: URL, score: Double)?

        for dirRoot in searchRoots {
            // Direct check first
            let direct = dirRoot.appendingPathComponent(query, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: direct.path, isDirectory: &isDir), isDir.boolValue {
                return direct
            }
            guard let children = try? fm.contentsOfDirectory(at: dirRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            for child in children {
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let folderName = child.lastPathComponent
                let folderLower = folderName.lowercased()
                let folderCompact = folderLower.replacingOccurrences(of: " ", with: "")
                if folderLower == lower || folderCompact == compactQuery {
                    return child
                }
                if folderLower.contains(lower) || lower.contains(folderLower) {
                    return child
                }
                let score = Self.similarityScore(lower, folderLower)
                if score >= 0.50 && (bestFuzzy == nil || score > bestFuzzy!.score) {
                    bestFuzzy = (child, score)
                }
            }
        }
        return bestFuzzy?.url
    }

    /// Searches across sandbox root, real user folders (Desktop/Documents/Downloads), and macOS Spotlight (`mdfind`).
    public func findItemsOnComputer(named rawQuery: String, foldersOnly: Bool = false, limit: Int = 10) -> [URL] {
        let query = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
        guard !query.isEmpty else { return [] }

        let fm = FileManager.default
        let root = resolvedSandboxRoot()
        let homeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        var results: [URL] = []
        var seenPaths = Set<String>()

        func addIfMatch(_ url: URL) {
            let standardized = url.standardizedFileURL.path
            guard !seenPaths.contains(standardized) else { return }
            if foldersOnly {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: standardized, isDirectory: &isDir), isDir.boolValue else { return }
            }
            seenPaths.insert(standardized)
            results.append(url)
        }

        // 1. Always search active sandbox root first (preserves test isolation)
        if let enumRoot = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            while let url = enumRoot.nextObject() as? URL {
                let name = url.lastPathComponent.lowercased()
                let stem = url.deletingPathExtension().lastPathComponent.lowercased()
                if name == query || stem == query || name.contains(query) {
                    addIfMatch(url)
                    if results.count >= limit { return results }
                }
            }
        }

        guard !isCustomSandboxEnvSet else { return results }

        // 2. Real user directories (Desktop, Downloads, Documents, Pictures up to depth 3, plus Home top-level)
        let recursiveRoots = [
            homeURL.appendingPathComponent("Desktop", isDirectory: true),
            homeURL.appendingPathComponent("Downloads", isDirectory: true),
            homeURL.appendingPathComponent("Documents", isDirectory: true),
            homeURL.appendingPathComponent("Pictures", isDirectory: true)
        ]
        var fuzzyCandidates: [URL] = []
        let skipDirNames: Set<String> = ["node_modules", ".git", ".build", "Library", "DerivedData", ".Trash"]
        for dir in recursiveRoots {
            if let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                while let url = enumerator.nextObject() as? URL {
                    let lastComp = url.lastPathComponent
                    if skipDirNames.contains(lastComp) || enumerator.level > 3 {
                        enumerator.skipDescendants()
                        continue
                    }
                    fuzzyCandidates.append(url)
                    let name = lastComp.lowercased()
                    let stem = url.deletingPathExtension().lastPathComponent.lowercased()
                    if name == query || stem == query || name.contains(query) {
                        addIfMatch(url)
                        if results.count >= limit { return results }
                    }
                }
            }
        }
        if let homeItems = try? fm.contentsOfDirectory(at: homeURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for url in homeItems {
                fuzzyCandidates.append(url)
                let name = url.lastPathComponent.lowercased()
                let stem = url.deletingPathExtension().lastPathComponent.lowercased()
                if name == query || stem == query || name.contains(query) {
                    addIfMatch(url)
                    if results.count >= limit { return results }
                }
            }
        }

        // 3. Fast macOS Spotlight index search (`mdfind`) scoped to user's Home directory
        if ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] != "1" && results.count < limit {
            let safeQuery = query.replacingOccurrences(of: "\"", with: "")
            let proc = Process()
            let pipe = Pipe()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            proc.arguments = ["-onlyin", homeURL.path, "kMDItemFSName == '*\(safeQuery)*'cd"]
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            if (try? proc.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                if let output = String(data: data, encoding: .utf8) {
                    for line in output.components(separatedBy: .newlines) where !line.isEmpty {
                        if line.contains("/Library/") || line.contains("/node_modules/") || line.contains("/.git/") {
                            continue
                        }
                        addIfMatch(URL(fileURLWithPath: line))
                        if results.count >= limit { break }
                    }
                }
            }
        }

        // 4. Fuzzy bigram fallback for speech-to-text typos (e.g. "Moto deaf" -> "Mohit or deaf")
        if results.isEmpty {
            let scored = fuzzyCandidates.compactMap { url -> (url: URL, score: Double)? in
                if foldersOnly {
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
                }
                let score = max(
                    Self.similarityScore(query, url.lastPathComponent),
                    Self.similarityScore(query, url.deletingPathExtension().lastPathComponent)
                )
                return score >= 0.45 ? (url, score) : nil
            }.sorted { $0.score > $1.score }
            for item in scored.prefix(limit) {
                addIfMatch(item.url)
            }
        }

        return results
    }

    private func findItem(named rawName: String, in root: URL) -> URL? {
        let clean = rawName
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
        guard !clean.isEmpty else { return nil }

        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            var desktopExact: URL?
            var fallbackContains: URL?
            while let url = enumerator.nextObject() as? URL {
                let file = url.lastPathComponent.lowercased()
                let stem = url.deletingPathExtension().lastPathComponent.lowercased()
                let inDesktopBackup = url.path.lowercased().contains("/desktop/")
                if file == clean || stem == clean || file == "\(clean).txt" {
                    if inDesktopBackup {
                        desktopExact = desktopExact ?? url
                    } else {
                        return url
                    }
                }
                if fallbackContains == nil && !inDesktopBackup && (file.contains(clean) || stem.contains(clean)) {
                    fallbackContains = url
                }
            }
            return desktopExact ?? fallbackContains
        }
        return nil
    }

    /// Extracts optional filename, target folder/location, and content generation/write instruction from natural file commands.
    /// Supports both `<name> inside <dir> and write <content> in it` and `inside <dir> and write <content> in it`.
    public static func parseFileCreationSpec(from rawBody: String) -> (fileName: String?, location: String?, writeInstruction: String?) {
        var remaining = rawBody.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        var writeInstruction: String? = nil

        // Extract trailing/embedded "and write ... in it" or "with content ..."
        let writePatterns = [
            #"(?i)\s+and\s+(write\s+.+?)(?:\s+(?:in|inside|into)\s+(?:it|that|the\s+file))?(?=\s+(?:in|inside|on|at)\s+(?:the\s+|my\s+)?|$)"#,
            #"(?i)\s+(?:with\s+content|saying|containing)\s+(.+?)(?=\s+(?:in|inside|on|at)\s+(?:the\s+|my\s+)?|$)"#
        ]
        for wp in writePatterns {
            if let wr = try? NSRegularExpression(pattern: wp),
               let wm = wr.firstMatch(in: remaining, range: NSRange(location: 0, length: remaining.utf16.count)),
               let fullRange = Range(wm.range(at: 0), in: remaining),
               let capRange = Range(wm.range(at: 1), in: remaining) {
                writeInstruction = String(remaining[capRange])
                    .replacingOccurrences(of: #"(?i)\s+(?:in|inside|into)\s+(?:it|that|the\s+file)$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                remaining.removeSubrange(fullRange)
                remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                break
            }
        }

        // Case A: Starts directly with location ("inside Mohit or deaf folder" / "on my desktop") with no filename given
        if let startLocRegex = try? NSRegularExpression(
            pattern: #"^(?:inside|in|on|at)\s+(?:the\s+|my\s+)?(.+)$"#,
            options: .caseInsensitive
        ),
           let sm = startLocRegex.firstMatch(in: remaining, range: NSRange(location: 0, length: remaining.utf16.count)),
           let locRange = Range(sm.range(at: 1), in: remaining) {
            let loc = String(remaining[locRange]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if loc.lowercased().hasPrefix("it") && writeInstruction != nil {
                return (nil, nil, writeInstruction)
            }
            return (nil, loc, writeInstruction)
        }

        // Case B: Starts with "and write ..." right after "create a file " -> optional location inside trailing phrase
        if remaining.lowercased().hasPrefix("and write ") {
            let sub = String(remaining.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let locMatch = sub.range(of: #"(?i)\s+(?:in|inside|on|at)\s+(?:the\s+|my\s+)?(.+)$"#, options: .regularExpression) {
                let writePart = String(sub[..<locMatch.lowerBound])
                    .replacingOccurrences(of: #"(?i)\s+(?:in|inside|into)\s+(?:it|that|the\s+file)$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let locPart = String(sub[locMatch])
                    .replacingOccurrences(of: #"(?i)^(?:in|inside|on|at)\s+(?:the\s+|my\s+)?"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                return (nil, locPart, writePart)
            }
            let writePart = sub.replacingOccurrences(of: #"(?i)\s+(?:in|inside|into)\s+(?:it|that|the\s+file)$"#, with: "", options: .regularExpression)
            return (nil, nil, writePart)
        }

        // Case C: Both filename and location ("poem.txt inside Mohit or deaf" / "on desktop called poem.txt")
        let parsed = SandboxFileManagerEngine().splitNameAndLocation(from: remaining)
        let nm = parsed.name.isEmpty ? nil : parsed.name
        return (nm, parsed.location, writeInstruction)
    }

    private func generateContentForFileCreation(_ instruction: String?) async -> String {
        guard let raw = instruction?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ""
        }
        let lower = raw.lowercased()
        let needsCreativeGeneration = lower.hasPrefix("write ") && (
            lower.contains("poem") || lower.contains("story") || lower.contains("essay") ||
            lower.contains("haiku") || lower.contains("letter") || lower.contains("note") ||
            lower.contains("code") || lower.contains("function") || lower.contains("about ")
        )

        if !needsCreativeGeneration {
            return raw.replacingOccurrences(of: #"(?i)^write\s+"#, with: "", options: .regularExpression)
        }

        if ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] != "1" &&
           ModelRouter.shared.currentMode != .googleSearch {
            let model = ModelRouter.shared.resolveChatModel()
            if let resp = try? await model.sendMessage(
                messages: [
                    LLMChatMessage(role: .system, content: "Write ONLY the requested creative text directly. Do not include any conversational preamble or markdown fences."),
                    LLMChatMessage(role: .user, content: raw)
                ],
                tools: nil,
                jsonMode: false
            ) {
                let text = resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }

        if lower.contains("poem") {
            return """
            Beneath the quiet morning sky,
            Where silver clouds go drifting by,
            Each whisper turns a thought to light,
            And guides the wandering mind aright.
            """
        }
        return raw.replacingOccurrences(of: #"(?i)^write\s+"#, with: "", options: .regularExpression)
    }

    private func ensureTxtFilename(_ raw: String) -> String {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: " ", with: "_")
        if trimmed.contains(".") { return trimmed }
        return "\(trimmed).txt"
    }

    private func splitNameAndLocation(from body: String) -> (name: String, location: String?) {
        let original = body.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // Pattern 1: "on my desktop called mohit.dev" / "in downloads named report.txt"
        if let revRegex = try? NSRegularExpression(
            pattern: #"^(?:on|in|inside|at)\s+(?:the\s+|my\s+)?(.+?)\s+(?:called|named)\s+(.+)$"#,
            options: .caseInsensitive
        ),
           let rm = revRegex.firstMatch(in: original, range: NSRange(location: 0, length: original.utf16.count)),
           let locRange = Range(rm.range(at: 1), in: original),
           let nameRange = Range(rm.range(at: 2), in: original) {
            let loc = String(original[locRange]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let nm = String(original[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return (nm, loc)
        }
        // Pattern 2: "mohit.dev on my desktop" / "todo inside Work"
        if let fwdRegex = try? NSRegularExpression(
            pattern: #"^(.+?)\s+(?:inside|in|on|at)\s+(?:the\s+|my\s+)?(.+)$"#,
            options: .caseInsensitive
        ),
           let fm = fwdRegex.firstMatch(in: original, range: NSRange(location: 0, length: original.utf16.count)),
           let nameRange = Range(fm.range(at: 1), in: original),
           let locRange = Range(fm.range(at: 2), in: original) {
            let nm = String(original[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let loc = String(original[locRange]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return (nm, loc)
        }
        return (original, nil)
    }

    public func handleFileCommand(_ rawCommand: String) async -> AutonomousExecutionResult? {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let root = resolvedSandboxRoot()
        let fm = FileManager.default

        // 0. Undo last reversible file operation
        if lower == "undo that" || lower == "undo last action" {
            guard let op = ConversationSessionContext.shared.popUndo() else {
                return AutonomousExecutionResult(
                    success: false,
                    summary: "Nothing recent to undo.",
                    targetAppName: "Finder"
                )
            }
            switch op {
            case .createdFile(let path), .createdFolder(let path), .copiedFile(let path):
                try? fm.removeItem(atPath: path)
                ConversationSessionContext.shared.clearLastFilePathIfMatching(path)
                let name = URL(fileURLWithPath: path).lastPathComponent
                return AutonomousExecutionResult(
                    success: true,
                    summary: "Undid creation of '\(name)'.",
                    targetAppName: "Finder",
                    executedSteps: ["Removed '\(name)' via undo stack"]
                )
            case .renamedFile(let fromPath, let toPath), .movedFile(let fromPath, let toPath):
                if fm.fileExists(atPath: toPath) {
                    try? fm.moveItem(atPath: toPath, toPath: fromPath)
                }
                return AutonomousExecutionResult(
                    success: true,
                    summary: "Undid rename/move back to '\(URL(fileURLWithPath: fromPath).lastPathComponent)'.",
                    targetAppName: "Finder"
                )
            }
        }

        // 1. Confirmation follow-up ("Yes, delete it")
        if (lower == "yes, delete it" || lower == "yes delete it" || lower == "confirm delete" || lower == "delete it"),
           let pendingPath = ConversationSessionContext.shared.pendingDeletePath {
            let targetURL = URL(fileURLWithPath: pendingPath)
            guard fm.fileExists(atPath: targetURL.path) else {
                ConversationSessionContext.shared.setPendingDeletePath(nil)
                return AutonomousExecutionResult(success: false, summary: "Target file no longer exists.", targetAppName: "Finder")
            }
            let gate = await ToolApprovalCoordinator.shared.requestAuthorizationIfNeeded(
                toolName: "file_delete_confirmed",
                appName: "Finder",
                title: "Confirm delete of \(targetURL.lastPathComponent)?",
                subtitle: targetURL.path,
                payload: ["path": targetURL.path],
                tier: .consequential
            )
            if !gate.approved {
                return AutonomousExecutionResult(
                    success: false,
                    summary: "Cancelled deletion of '\(targetURL.lastPathComponent)'.",
                    targetAppName: "Finder"
                )
            }
            try? fm.removeItem(at: targetURL)
            ConversationSessionContext.shared.setPendingDeletePath(nil)
            return AutonomousExecutionResult(
                success: true,
                summary: "Moved '\(targetURL.lastPathComponent)' to Trash.",
                targetAppName: "Finder",
                executedSteps: ["Deleted '\(targetURL.lastPathComponent)' inside sandbox"]
            )
        }

        // 2. Open explicit missing or existing file ("Open file foo.txt")
        if lower.hasPrefix("open file ") {
            let name = String(trimmed.dropFirst(10)).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if isProtectedPath(name) {
                return AutonomousExecutionResult(success: false, summary: "Refused access to protected system file.", targetAppName: "Safety")
            }
            if let found = findItem(named: name, in: root) {
                if ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] != "1" {
                    NSWorkspace.shared.open(found)
                }
                return AutonomousExecutionResult(success: true, summary: "Opened file '\(found.lastPathComponent)'.", targetAppName: "Finder", targetURL: found)
            }
            return AutonomousExecutionResult(
                success: false,
                summary: "File not found: '\(name)' does not exist in \(root.path).",
                targetAppName: "Finder"
            )
        }

        // 3. Create folder ("Create folder mohit.dev on my desktop", "Make a folder on Desktop called Projects")
        if let folderRegex = try? NSRegularExpression(
            pattern: #"^(?:create|make)(?:\s+a)?(?:\s+new)?\s+(?:folder|directory)(?:\s+called|\s+named)?\s+(.+)$"#,
            options: .caseInsensitive
        ),
           let fmMatch = folderRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
           let bodyRange = Range(fmMatch.range(at: 1), in: trimmed) {
            let parsed = splitNameAndLocation(from: String(trimmed[bodyRange]))
            var name = parsed.name
            let locationHint = parsed.location

            if !name.isEmpty {
                let baseDir: URL
                let folderURL: URL
                if name.hasPrefix("~/") || name.hasPrefix("/") {
                    let expanded = (name as NSString).expandingTildeInPath
                    if isProtectedPath(expanded) {
                        return AutonomousExecutionResult(success: false, summary: "Refused creating folder inside protected system path.", targetAppName: "Safety")
                    }
                    folderURL = URL(fileURLWithPath: expanded, isDirectory: true)
                    baseDir = folderURL.deletingLastPathComponent()
                    name = folderURL.lastPathComponent
                } else {
                    baseDir = resolveLocationDirectory(locationHint, root: root)
                    folderURL = baseDir.appendingPathComponent(name, isDirectory: true)
                }

                do {
                    try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
                        return AutonomousExecutionResult(success: false, summary: "Could not verify folder creation at \(folderURL.path).", targetAppName: "Finder")
                    }
                    ConversationSessionContext.shared.setLastFilePath(folderURL.path)
                    ConversationSessionContext.shared.pushUndo(.createdFolder(path: folderURL.path))
                    let displayLoc = baseDir.lastPathComponent
                    return AutonomousExecutionResult(
                        success: true,
                        summary: "Created folder '\(name)' in \(displayLoc) (\(folderURL.path)).",
                        targetAppName: "Finder",
                        targetURL: folderURL,
                        executedSteps: ["Created directory \(folderURL.path)"]
                    )
                } catch {
                    return AutonomousExecutionResult(
                        success: false,
                        summary: "Failed to create folder '\(name)' in \(baseDir.lastPathComponent): \(error.localizedDescription)",
                        targetAppName: "Finder"
                    )
                }
            }
        }

        // 4. Create file ("Create a file inside Mohit or deaf folder and write a poem in it", "Create file notes.txt on my desktop")
        if let fileRegex = try? NSRegularExpression(
            pattern: #"^(?:create|make)(?:\s+a)?(?:\s+new)?\s+(?:text\s+)?file(?:\s+(?:called|named))?\s*(.*)$"#,
            options: .caseInsensitive
        ),
           let m = fileRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
           let bodyRange = Range(m.range(at: 1), in: trimmed) {
            let spec = Self.parseFileCreationSpec(from: String(trimmed[bodyRange]))
            let rawName = spec.fileName ?? {
                let wLower = (spec.writeInstruction ?? "").lowercased()
                if wLower.contains("poem") { return "poem.txt" }
                if wLower.contains("story") { return "story.txt" }
                return "note_\(Int(Date().timeIntervalSince1970) % 10000).txt"
            }()
            var locationHint = spec.location

            if locationHint?.lowercased() == "it",
               let last = ConversationSessionContext.shared.lastCreatedOrModifiedPath,
               fm.fileExists(atPath: last) {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: last, isDirectory: &isDir), isDir.boolValue {
                    locationHint = last
                }
            }

            let targetFile: URL
            let destDir: URL
            let finalFileName: String
            if rawName.hasPrefix("~/") || rawName.hasPrefix("/") {
                let expanded = (rawName as NSString).expandingTildeInPath
                if isProtectedPath(expanded) {
                    return AutonomousExecutionResult(success: false, summary: "Refused creating file inside protected system path.", targetAppName: "Safety")
                }
                let rawURL = URL(fileURLWithPath: expanded)
                finalFileName = rawURL.lastPathComponent.contains(".") ? rawURL.lastPathComponent : ensureTxtFilename(rawURL.lastPathComponent)
                destDir = rawURL.deletingLastPathComponent()
                targetFile = destDir.appendingPathComponent(finalFileName)
            } else {
                finalFileName = ensureTxtFilename(rawName)
                destDir = resolveLocationDirectory(locationHint, root: root)
                targetFile = destDir.appendingPathComponent(finalFileName)
            }

            let fileContent = await generateContentForFileCreation(spec.writeInstruction)

            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                try fileContent.write(to: targetFile, atomically: true, encoding: .utf8)
                guard fm.fileExists(atPath: targetFile.path) else {
                    return AutonomousExecutionResult(success: false, summary: "Could not verify file creation at \(targetFile.path).", targetAppName: "Finder")
                }
                ConversationSessionContext.shared.setLastFilePath(targetFile.path)
                ConversationSessionContext.shared.pushUndo(.createdFile(path: targetFile.path))
                let wroteNote = fileContent.isEmpty ? "" : " and wrote your content inside it"
                return AutonomousExecutionResult(
                    success: true,
                    summary: "Created file '\(finalFileName)' in \(destDir.lastPathComponent)\(wroteNote) (\(targetFile.path)).",
                    targetAppName: "Finder",
                    targetURL: targetFile,
                    executedSteps: ["Created file \(targetFile.path)"]
                )
            } catch {
                return AutonomousExecutionResult(
                    success: false,
                    summary: "Failed to create file '\(finalFileName)': \(error.localizedDescription)",
                    targetAppName: "Finder"
                )
            }
        }

        // 4b. Follow-up write into last created file ("write a poem in it", "write a short note inside it")
        if let followWriteRegex = try? NSRegularExpression(
            pattern: #"^(write\s+.+?)\s+(?:in|inside|into)\s+(?:it|that|this\s+file)$"#,
            options: .caseInsensitive
        ),
           let fwMatch = followWriteRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
           let instrRange = Range(fwMatch.range(at: 1), in: trimmed),
           let lastPath = ConversationSessionContext.shared.lastCreatedOrModifiedPath {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: lastPath, isDirectory: &isDir), !isDir.boolValue {
                let targetURL = URL(fileURLWithPath: lastPath)
                let content = await generateContentForFileCreation(String(trimmed[instrRange]))
                do {
                    try content.write(to: targetURL, atomically: true, encoding: .utf8)
                    return AutonomousExecutionResult(
                        success: true,
                        summary: "Wrote content into '\(targetURL.lastPathComponent)' (\(targetURL.path)).",
                        targetAppName: "Finder",
                        targetURL: targetURL,
                        executedSteps: ["Wrote content to \(targetURL.path)"]
                    )
                } catch {
                    return AutonomousExecutionResult(success: false, summary: "Failed to write into '\(targetURL.lastPathComponent)': \(error.localizedDescription)", targetAppName: "Finder")
                }
            }
        }

        // 5. Rename file ("Rename notes to ideas" / "Rename it to beta")
        if let renameRegex = try? NSRegularExpression(pattern: #"^rename\s+(?:the\s+file\s+)?(.+?)\s+to\s+(.+)$"#, options: .caseInsensitive),
           let m = renameRegex.firstMatch(in: lower, range: NSRange(location: 0, length: lower.utf16.count)),
           let srcRange = Range(m.range(at: 1), in: lower),
           let dstRange = Range(m.range(at: 2), in: lower) {
            let srcRaw = String(lower[srcRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let dstRaw = String(lower[dstRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            var srcURL: URL?
            if srcRaw == "it" || srcRaw == "that" || srcRaw == "this file",
               let lastPath = ConversationSessionContext.shared.lastCreatedOrModifiedPath {
                srcURL = URL(fileURLWithPath: lastPath)
            } else {
                srcURL = findItem(named: srcRaw, in: root)
            }
            guard let source = srcURL, fm.fileExists(atPath: source.path) else {
                return AutonomousExecutionResult(success: false, summary: "Could not find '\(srcRaw)' to rename.", targetAppName: "Finder")
            }

            let ext = source.pathExtension
            let cleanDst = dstRaw.contains(".") || ext.isEmpty ? dstRaw : "\(dstRaw).\(ext)"
            let destURL = source.deletingLastPathComponent().appendingPathComponent(cleanDst)
            try? fm.removeItem(at: destURL)
            do {
                try fm.moveItem(at: source, to: destURL)
                ConversationSessionContext.shared.setLastFilePath(destURL.path)
                ConversationSessionContext.shared.pushUndo(.renamedFile(fromPath: source.path, toPath: destURL.path))
                return AutonomousExecutionResult(
                    success: true,
                    summary: "Renamed '\(source.lastPathComponent)' to '\(destURL.lastPathComponent)'.",
                    targetAppName: "Finder",
                    targetURL: destURL,
                    executedSteps: ["Renamed \(source.lastPathComponent) -> \(destURL.lastPathComponent)"]
                )
            } catch {
                return AutonomousExecutionResult(success: false, summary: "Failed to rename '\(source.lastPathComponent)': \(error.localizedDescription)", targetAppName: "Finder")
            }
        }

        // 6. Move file ("Move ideas into Projects" / "Move it to Projects")
        if let moveRegex = try? NSRegularExpression(pattern: #"^move\s+(.+?)\s+(?:into|to)(?:\s+the)?\s+(.+?)(?:\s+folder)?$"#, options: .caseInsensitive),
           let m = moveRegex.firstMatch(in: lower, range: NSRange(location: 0, length: lower.utf16.count)),
           let srcRange = Range(m.range(at: 1), in: lower),
           let folderRange = Range(m.range(at: 2), in: lower) {
            let srcRaw = String(lower[srcRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let folderRaw = String(lower[folderRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            var srcURL: URL?
            if srcRaw == "it" || srcRaw == "that" || srcRaw == "the screenshot" || srcRaw == "screenshot",
               let lastPath = ConversationSessionContext.shared.lastCreatedOrModifiedPath {
                srcURL = URL(fileURLWithPath: lastPath)
            } else {
                srcURL = findItem(named: srcRaw, in: root)
            }
            guard let source = srcURL, fm.fileExists(atPath: source.path) else {
                return AutonomousExecutionResult(success: false, summary: "Could not find '\(srcRaw)' to move.", targetAppName: "Finder")
            }

            let destFolder = findItem(named: folderRaw, in: root) ?? root.appendingPathComponent(folderRaw.capitalized, isDirectory: true)
            try? fm.createDirectory(at: destFolder, withIntermediateDirectories: true)
            let destURL = destFolder.appendingPathComponent(source.lastPathComponent)
            try? fm.removeItem(at: destURL)
            do {
                try fm.moveItem(at: source, to: destURL)
                ConversationSessionContext.shared.setLastFilePath(destURL.path)
                ConversationSessionContext.shared.pushUndo(.movedFile(fromPath: source.path, toPath: destURL.path))
                return AutonomousExecutionResult(
                    success: true,
                    summary: "Moved '\(source.lastPathComponent)' into '\(destFolder.lastPathComponent)'.",
                    targetAppName: "Finder",
                    targetURL: destURL,
                    executedSteps: ["Moved \(source.lastPathComponent) -> \(destFolder.lastPathComponent)/"]
                )
            } catch {
                return AutonomousExecutionResult(success: false, summary: "Failed to move file: \(error.localizedDescription)", targetAppName: "Finder")
            }
        }

        // 7. Copy file ("Copy ideas to the desktop")
        if let copyRegex = try? NSRegularExpression(pattern: #"^copy\s+(.+?)\s+to(?:\s+the)?\s+(.+)$"#, options: .caseInsensitive),
           let m = copyRegex.firstMatch(in: lower, range: NSRange(location: 0, length: lower.utf16.count)),
           let srcRange = Range(m.range(at: 1), in: lower),
           let dstRange = Range(m.range(at: 2), in: lower) {
            let srcRaw = String(lower[srcRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let dstRaw = String(lower[dstRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let isClipboardCopy = dstRaw == "clipboard" || dstRaw == "pasteboard" ||
                ["this", "that", "it", "text", "the text", "selected text", "selection", "all", "everything"].contains(srcRaw)
            if !isClipboardCopy {
                guard let source = findItem(named: srcRaw, in: root) else {
                    return AutonomousExecutionResult(success: false, summary: "Could not find '\(srcRaw)' to copy.", targetAppName: "Finder")
                }
                let destDir: URL
                if dstRaw.contains("desktop") {
                    destDir = root.appendingPathComponent("Desktop", isDirectory: true)
                } else {
                    destDir = findItem(named: dstRaw, in: root) ?? root.appendingPathComponent(dstRaw, isDirectory: true)
                }
                try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                let destURL = destDir.appendingPathComponent(source.lastPathComponent)
            try? fm.removeItem(at: destURL)
            do {
                try fm.copyItem(at: source, to: destURL)
                ConversationSessionContext.shared.pushUndo(.copiedFile(createdPath: destURL.path))
                return AutonomousExecutionResult(
                    success: true,
                    summary: "Copied '\(source.lastPathComponent)' to \(destDir.lastPathComponent).",
                    targetAppName: "Finder",
                    targetURL: destURL,
                    executedSteps: ["Copied \(source.lastPathComponent) to \(destDir.lastPathComponent)"]
                )
                } catch {
                    return AutonomousExecutionResult(success: false, summary: "Copy failed: \(error.localizedDescription)", targetAppName: "Finder")
                }
            }
        }

        // 8. Locate or find any file or folder on the local Mac
        let mentionsFileOrFolder = lower.contains("file") || lower.contains("folder") || lower.contains("directory") ||
            lower.contains("on my computer") || lower.contains("on my mac") || lower.contains("on desktop") ||
            lower.contains("on my desktop") || lower.contains("in downloads") || lower.contains("in documents") ||
            lower.range(of: #"\.[a-z0-9]{1,5}\b"#, options: .regularExpression) != nil
        let isLocalSearchPattern = lower.hasPrefix("locate ") ||
            ((lower.hasPrefix("find ") || lower.hasPrefix("search ") || lower.hasPrefix("where is ") || lower.hasPrefix("show me where ") || lower.hasPrefix("check if ")) && mentionsFileOrFolder)

        if isLocalSearchPattern {
            let foldersOnly = lower.contains("folder") && !lower.contains("file")
            var query = lower
                .replacingOccurrences(of: #"(?i)^(?:find|locate|search|where\s+is|show\s+me\s+where|check\s+if)(?:\s+my\s+computer\s+for|\s+for|\s+me)?(?:\s+(?:the|my|a|an))?(?:\s+(?:files?|folders?|directory))?(?:\s+(?:named|called))?\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)\s+(?:on\s+my\s+computer|on\s+my\s+mac|on\s+this\s+mac|on\s+my\s+desktop|on\s+desktop|in\s+downloads|in\s+documents|exists?)$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)\s+(?:folder|file|directory)$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if query.hasPrefix("the ") { query = String(query.dropFirst(4)) }
            if query.hasPrefix("my ") { query = String(query.dropFirst(3)) }
            query = query.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

            let matchedURLs = findItemsOnComputer(named: query, foldersOnly: foldersOnly, limit: 8)
            if matchedURLs.isEmpty {
                let kindLabel = foldersOnly ? "folders" : "files or folders"
                return AutonomousExecutionResult(
                    success: false,
                    summary: "No \(kindLabel) matching '\(query)' found on your computer.",
                    targetAppName: "Finder"
                )
            }
            let displayPaths = matchedURLs.prefix(4).map { url -> String in
                url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            }
            return AutonomousExecutionResult(
                success: true,
                summary: "Found \(matchedURLs.count) match(es): \(displayPaths.joined(separator: ", ")).",
                targetAppName: "Finder",
                targetURL: matchedURLs.first,
                executedSteps: ["Searched local computer & Spotlight for '\(query)'"]
            )
        }

        // 9. Open latest file in Downloads
        if lower.contains("latest file in downloads") || lower.contains("newest file in downloads") || lower.contains("most recent file in downloads") {
            let sandboxDownloads = root.appendingPathComponent("Downloads", isDirectory: true)
            let realDownloads = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Downloads", isDirectory: true)
            let targetDir = fm.fileExists(atPath: sandboxDownloads.path) ? sandboxDownloads : realDownloads
            if let items = try? fm.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
                let filesOnly = items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
                if let latest = filesOnly.max(by: {
                    let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return d1 < d2
                }) {
                    return AutonomousExecutionResult(
                        success: true,
                        summary: "Latest file in Downloads: '\(latest.lastPathComponent)'.",
                        targetAppName: "Finder",
                        targetURL: latest
                    )
                }
            }
            return AutonomousExecutionResult(
                success: true,
                summary: "Checked Downloads folder (latest file lookup complete; folder has no user files).",
                targetAppName: "Finder",
                targetURL: targetDir
            )
        }

        // 10. Folder size query ("How big is the Projects folder?")
        if lower.contains("how big is") || lower.hasPrefix("size of ") || lower.contains("folder size") {
            let cleaned = lower
                .replacingOccurrences(of: "how big is the ", with: "")
                .replacingOccurrences(of: "how big is ", with: "")
                .replacingOccurrences(of: "size of the ", with: "")
                .replacingOccurrences(of: "size of ", with: "")
                .replacingOccurrences(of: " folder", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard let target = findItem(named: cleaned, in: root) else {
                return AutonomousExecutionResult(success: false, summary: "Could not find folder '\(cleaned)'.", targetAppName: "Finder")
            }
            var totalBytes: Int64 = 0
            var fileCount = 0
            if let enumerator = fm.enumerator(at: target, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
                while let url = enumerator.nextObject() as? URL {
                    let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    if vals?.isRegularFile == true {
                        fileCount += 1
                        totalBytes += Int64(vals?.fileSize ?? 0)
                    }
                }
            }
            return AutonomousExecutionResult(
                success: true,
                summary: "The '\(target.lastPathComponent)' folder has \(fileCount) file(s) using \(totalBytes) bytes.",
                targetAppName: "Finder",
                targetURL: target
            )
        }

        // 11. Single-file delete ("Delete ideas") -> always confirm via ToolApprovalCoordinator (.consequential)
        if lower.hasPrefix("delete ") && !lower.contains("last word") && !lower.contains("memory") {
            let targetRaw = String(lower.dropFirst("delete ".count))
                .replacingOccurrences(of: "the file ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard let targetURL = findItem(named: targetRaw, in: root) else {
                return AutonomousExecutionResult(
                    success: false,
                    summary: "Could not find '\(targetRaw)' to delete.",
                    targetAppName: "Finder"
                )
            }
            ConversationSessionContext.shared.setPendingDeletePath(targetURL.path)
            let gate = await ToolApprovalCoordinator.shared.requestAuthorizationIfNeeded(
                toolName: "file_delete",
                appName: "Finder",
                title: "Delete '\(targetURL.lastPathComponent)'?",
                subtitle: "File path: \(targetURL.path)",
                payload: ["path": targetURL.path],
                tier: .consequential
            )
            if !gate.approved {
                return AutonomousExecutionResult(
                    success: false,
                    summary: "Confirmation required: delete '\(targetURL.lastPathComponent)'? Say 'Yes, delete it' or approve in the Notch.",
                    targetAppName: "Finder",
                    executedSteps: ["Paused deletion awaiting confirmation for '\(targetURL.lastPathComponent)'"]
                )
            }
            try? fm.removeItem(at: targetURL)
            ConversationSessionContext.shared.setPendingDeletePath(nil)
            return AutonomousExecutionResult(
                success: true,
                summary: "Moved '\(targetURL.lastPathComponent)' to Trash.",
                targetAppName: "Finder"
            )
        }

        return nil
    }
}
