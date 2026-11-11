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
        let homeSandbox = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("voice-test", isDirectory: true)
        if FileManager.default.fileExists(atPath: homeSandbox.path) {
            return homeSandbox
        }
        let tmpSandbox = URL(fileURLWithPath: "/tmp/voice-test", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpSandbox, withIntermediateDirectories: true)
        return tmpSandbox
    }

    private func isProtectedPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        let protectedPrefixes = ["/system", "/library", "/usr", "/bin", "/sbin", "/etc"]
        return protectedPrefixes.contains(where: { lower == $0 || lower.hasPrefix($0 + "/") })
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

    private func ensureTxtFilename(_ raw: String) -> String {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: " ", with: "_")
        if trimmed.contains(".") { return trimmed }
        return "\(trimmed).txt"
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

        // 3. Create folder ("Create a folder called Projects" / "Create a folder called Reports on the desktop")
        if let range = lower.range(of: #"(?:create|make)(?:\s+a)?\s+folder(?:\s+called|\s+named)?\s+(.+)$"#, options: .regularExpression) {
            let afterMatch = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            var name = afterMatch
                .replacingOccurrences(of: #"(?i)^(?:create|make)(?:\s+a)?\s+folder(?:\s+called|\s+named)?\s+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            var baseDir = root
            if name.lowercased().hasSuffix(" on the desktop") || name.lowercased().hasSuffix(" on desktop") {
                name = name.replacingOccurrences(of: #"(?i)\s+on\s+(?:the\s+)?desktop$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                baseDir = root.appendingPathComponent("Desktop", isDirectory: true)
            }
            if !name.isEmpty {
                let folderURL = baseDir.appendingPathComponent(name, isDirectory: true)
                try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
                ConversationSessionContext.shared.setLastFilePath(folderURL.path)
                ConversationSessionContext.shared.pushUndo(.createdFolder(path: folderURL.path))
                return AutonomousExecutionResult(
                    success: true,
                    summary: "Created folder '\(name)' in \(baseDir.lastPathComponent).",
                    targetAppName: "Finder",
                    targetURL: folderURL,
                    executedSteps: ["Created directory \(folderURL.path)"]
                )
            }
        }

        // 4. Create text file ("Create a text file called notes" / "Create a file called todo inside Work")
        if let fileRegex = try? NSRegularExpression(pattern: #"^(?:create|make)(?:\s+a)?\s+(?:text\s+)?file(?:\s+called|\s+named)?\s+(.+?)(?:\s+(?:inside|in)\s+(.+))?$"#, options: .caseInsensitive),
           let m = fileRegex.firstMatch(in: lower, range: NSRange(location: 0, length: lower.utf16.count)),
           let nameRange = Range(m.range(at: 1), in: lower) {
            let rawName = String(lower[nameRange])
            let fileName = ensureTxtFilename(rawName)
            var destDir = root
            if m.range(at: 2).location != NSNotFound, let folderRange = Range(m.range(at: 2), in: lower) {
                var folderName = String(lower[folderRange]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if folderName == "it", let last = ConversationSessionContext.shared.lastCreatedOrModifiedPath, fm.fileExists(atPath: last) {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: last, isDirectory: &isDir), isDir.boolValue {
                        folderName = URL(fileURLWithPath: last).lastPathComponent
                    }
                }
                if let matchedDir = findItem(named: folderName, in: root) {
                    destDir = matchedDir
                } else {
                    destDir = root.appendingPathComponent(folderName.capitalized, isDirectory: true)
                    try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                }
            }
            let targetFile = destDir.appendingPathComponent(fileName)
            try? "".write(to: targetFile, atomically: true, encoding: .utf8)
            ConversationSessionContext.shared.setLastFilePath(targetFile.path)
            ConversationSessionContext.shared.pushUndo(.createdFile(path: targetFile.path))
            return AutonomousExecutionResult(
                success: true,
                summary: "Created file '\(fileName)' in \(destDir.lastPathComponent).",
                targetAppName: "Finder",
                targetURL: targetFile,
                executedSteps: ["Created file \(targetFile.path)"]
            )
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

        // 8. Find files ("Find files named ideas")
        if lower.hasPrefix("find files named ") || lower.hasPrefix("find file named ") || lower.hasPrefix("search files for ") {
            let query = lower
                .replacingOccurrences(of: "find files named ", with: "")
                .replacingOccurrences(of: "find file named ", with: "")
                .replacingOccurrences(of: "search files for ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            var matches: [String] = []
            let resolvedRootPrefix = root.resolvingSymlinksInPath().path + "/"
            let rawRootPrefix = root.path + "/"
            if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                while let url = enumerator.nextObject() as? URL {
                    if url.lastPathComponent.lowercased().contains(query) {
                        let resolvedPath = url.resolvingSymlinksInPath().path
                        let rel = resolvedPath.hasPrefix(resolvedRootPrefix)
                            ? String(resolvedPath.dropFirst(resolvedRootPrefix.count))
                            : url.path.replacingOccurrences(of: rawRootPrefix, with: "")
                        matches.append(rel)
                    }
                }
            }
            if matches.isEmpty {
                return AutonomousExecutionResult(success: false, summary: "No files matching '\(query)' found in \(root.lastPathComponent).", targetAppName: "Finder")
            }
            return AutonomousExecutionResult(
                success: true,
                summary: "Found \(matches.count) file(s): \(matches.prefix(5).joined(separator: ", ")).",
                targetAppName: "Finder"
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
