import Foundation
import AppKit

public enum ShelfVoiceAction: Equatable, Sendable {
    case listItems
    case showShelf
    case clearShelf
    case removeItem(target: String)
    case openItem(target: String)
    case addNamedItem(name: String)
    case addFolder(name: String)
    case addFilesInFolder(folderName: String, fileTypeFilter: String?)
    case addLatestDownload
    case addLastScreenshot
    case addFinderSelection
    case browseForFile
    case undoAdd
    case airDrop(target: String?)
    case attachToEmail(target: String?)
    case sendToContact(target: String?, contact: String, platform: String)
    case moveFiles(target: String?, destinationFolder: String)
    case moveToTrash(target: String)
    case summarizeFile(target: String)
    case none
}

public struct ShelfVoiceDisambiguation: Sendable, Equatable {
    public let query: String
    public let candidates: [URL]

    public var promptText: String {
        let list = candidates.enumerated().map { "\($0.offset + 1). \($0.element.lastPathComponent) (in \($0.element.deletingLastPathComponent().lastPathComponent))" }.joined(separator: "\n")
        return "Multiple files match '\(query)'. Which one would you like to add?\n\(list)\nSay 1, 2, or 3."
    }
}

public final class ShelfVoiceEngine: @unchecked Sendable {
    public static let shared = ShelfVoiceEngine()

    private let shelfStore: ShelfStore
    private var lastAddedItemId: UUID?
    private var pendingDisambiguation: ShelfVoiceDisambiguation?
    public var customAllowedRoots: [String]?

    public init(shelfStore: ShelfStore = .shared, customAllowedRoots: [String]? = nil) {
        self.shelfStore = shelfStore
        self.customAllowedRoots = customAllowedRoots
    }

    public var effectiveAllowedRoots: [String] {
        if let roots = customAllowedRoots {
            return roots.map { PathPolicy.canonicalizeExistingOrParent(path: $0) }
        }
        return PathPolicy.configuredAllowedRoots()
    }

    // MARK: - Spoken Path Normalization
    /// Converts phrases like "add slash Users slash mohit slash Documents slash report.pdf"
    /// into a canonicalized path string.
    public static func normalizeSpokenPath(_ raw: String) -> String {
        var text = raw.lowercased()
        text = text.replacingOccurrences(of: "slash", with: "/")
        text = text.replacingOccurrences(of: "backslash", with: "/")
        text = text.replacingOccurrences(of: "forward slash", with: "/")
        text = text.replacingOccurrences(of: "dot dot", with: "..")
        text = text.replacingOccurrences(of: "tilde", with: "~")
        text = text.replacingOccurrences(of: "dot", with: ".")
        text = text.replacingOccurrences(of: "hyphen", with: "-")
        text = text.replacingOccurrences(of: "underscore", with: "_")

        let tokens = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var result = tokens.joined()
        if result.contains("://") {
            return result
        }
        // Clean leading/trailing quotes
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        return result
    }

    // MARK: - Intent Parsing (English, Hindi, Hinglish)
    public func parseVoiceIntent(_ utterance: String) -> ShelfVoiceAction {
        let lower = utterance.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        // 1. Unrelated checks (fast rejection)
        if lower.hasPrefix("what is the weather") || lower.hasPrefix("tell me a joke") ||
           lower.hasPrefix("play music") || lower.hasPrefix("volume up") ||
           lower.hasPrefix("open safari") || lower.hasPrefix("open chrome") ||
           lower.hasPrefix("what time is it") || lower.hasPrefix("set timer") ||
           lower.hasPrefix("who is the president") || lower.hasPrefix("how are you") ||
           lower.hasPrefix("take a screenshot") || lower.hasPrefix("lock screen") ||
           lower.hasPrefix("increase brightness") || lower.hasPrefix("close window") ||
           lower.hasPrefix("shutdown mac") {
            return .none
        }

        // 2. AirDrop
        if lower.contains("airdrop") || lower.contains("air drop") {
            if lower.contains("shelf") || lower.contains("these") || lower.contains("files") || lower.contains("item") {
                return .airDrop(target: "shelf_items")
            }
            return .airDrop(target: nil)
        }

        // 3. Attach to Email
        if (lower.contains("attach") && (lower.contains("shelf") || lower.contains("email") || lower.contains("mail"))) ||
           lower.contains("email mein attach karo") || lower.contains("mail pe lagao") {
            return .attachToEmail(target: nil)
        }

        // 4. Send to Contact via Messaging (Slack, WhatsApp)
        if lower.contains("send ") && (lower.contains("whatsapp") || lower.contains("slack")) {
            let platform = lower.contains("whatsapp") ? "WhatsApp" : "Slack"
            var contact = "contact"
            if let toIdx = lower.range(of: "to ") {
                let afterTo = lower[toIdx.upperBound...]
                let words = afterTo.components(separatedBy: " ")
                if let name = words.first, !name.isEmpty {
                    contact = name.capitalized
                }
            } else if let koIdx = lower.range(of: "ko ") {
                let beforeKo = lower[..<koIdx.lowerBound]
                let words = beforeKo.components(separatedBy: " ")
                if let name = words.last, !name.isEmpty {
                    contact = name.capitalized
                }
            }
            return .sendToContact(target: "first item", contact: contact, platform: platform)
        }

        // 5. Move files into Folder
        if lower.contains("move ") && (lower.contains("folder") || lower.contains("directory")) {
            var destFolder = "Reports"
            if let intoIdx = lower.range(of: "into ") {
                let rest = lower[intoIdx.upperBound...].replacingOccurrences(of: "folder", with: "").trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { destFolder = rest.capitalized }
            }
            return .moveFiles(target: "shelf_items", destinationFolder: destFolder)
        }

        // 6. Move to Trash
        if lower.contains("trash") || lower.contains("delete from shelf") || lower.contains("delete file") || lower.contains("trash mein daalo") {
            let target = lower.replacingOccurrences(of: "move to trash", with: "")
                .replacingOccurrences(of: "move", with: "")
                .replacingOccurrences(of: "to trash", with: "")
                .trimmingCharacters(in: .whitespaces)
            return .moveToTrash(target: target.isEmpty ? "selected item" : target)
        }

        // 7. Summarize / Explain / Extract
        if lower.contains("summarize") || lower.contains("explain file") || lower.contains("summary") || lower.contains("kya likha hai") {
            if lower.contains("shelf") || lower.contains("file") || lower.contains("notes") || lower.contains(".txt") || lower.contains(".pdf") {
                let clean = lower.replacingOccurrences(of: "summarize", with: "")
                    .replacingOccurrences(of: "the file on my shelf", with: "")
                    .replacingOccurrences(of: "on my shelf", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return .summarizeFile(target: clean.isEmpty ? "file on shelf" : clean)
            }
        }

        // 8. Undo Add
        if lower == "undo that" || lower == "undo" || lower == "undo shelf" || lower == "undo add" ||
           lower == "wapas lo" || lower == "piche jao" {
            return .undoAdd
        }

        // 9. Clear Shelf
        if lower.contains("clear the shelf") || lower.contains("clear shelf") || lower == "empty the shelf" ||
           lower.contains("shelf saaf karo") || lower.contains("shelf empty karo") || lower.contains("shelf clear kar do") {
            return .clearShelf
        }

        // 10. Remove specific item
        if lower.contains("remove ") || lower.contains("hatao") {
            if lower.contains("second") || lower.contains("doosra") {
                return .removeItem(target: "second")
            } else if lower.contains("first") || lower.contains("pehla") {
                return .removeItem(target: "first")
            } else if lower.contains("shelf") {
                let target = lower.replacingOccurrences(of: "remove", with: "")
                    .replacingOccurrences(of: "from the shelf", with: "")
                    .replacingOccurrences(of: "from shelf", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return .removeItem(target: target)
            }
        }

        // 11. Open specific item
        if lower.contains("open ") && (lower.contains("shelf") || lower.contains("pdf")) {
            if lower.contains("pdf") {
                return .openItem(target: "pdf")
            } else if lower.contains("first") {
                return .openItem(target: "first")
            }
            return .openItem(target: "item")
        }

        // 12. Show / List Shelf
        if lower == "what's on my shelf?" || lower == "whats on my shelf" || lower == "what is on my shelf" ||
           lower == "shelf mein kya hai?" || lower == "shelf mein kya hai" || lower == "show the shelf" ||
           lower == "show shelf" || lower == "open the shelf" || lower == "shelf dikhao" || lower == "shelf kholo" {
            if lower.contains("show") || lower.contains("open") || lower.contains("kholo") || lower.contains("dikhao") {
                return .showShelf
            }
            return .listItems
        }

        // 13. Browse for a file
        if lower == "browse for a file" || lower == "browse a file" || lower == "pick a file" ||
           lower == "file choose karo" || lower == "file browse karo" {
            return .browseForFile
        }

        // 14. Add latest download
        if lower.contains("latest download") || lower.contains("last download") ||
           lower.contains("aakhri download") || lower.contains("last downloaded file") {
            return .addLatestDownload
        }

        // 15. Add last screenshot
        if lower.contains("last screenshot") || lower.contains("latest screenshot") ||
           lower.contains("aakhri screenshot") || lower.contains("add the last screenshot to the shelf") {
            return .addLastScreenshot
        }

        // 16. Add Finder selection or current folder
        if lower.contains("files i selected in finder") || lower.contains("finder selection") ||
           lower.contains("selected in finder") || lower == "put this file on the shelf" {
            return .addFinderSelection
        }
        if lower == "add this folder" || lower == "add current folder" || lower == "ye folder daalo" {
            return .addFolder(name: "front_finder_folder")
        }

        // 17. Add all files in a folder (e.g. "Add all the PDFs in Documents")
        if (lower.contains("add all") || lower.contains("add the files in")) && lower.contains("in ") {
            var filter: String? = nil
            if lower.contains("pdf") { filter = "pdf" }
            if lower.contains("image") { filter = "image" }

            var folder = "Documents"
            if lower.contains("documents") { folder = "Documents" }
            else if lower.contains("downloads") { folder = "Downloads" }
            else if lower.contains("desktop") { folder = "Desktop" }
            return .addFilesInFolder(folderName: folder, fileTypeFilter: filter)
        }

        // 18. Add folder (e.g. "Add the Downloads folder to the shelf")
        if (lower.contains("folder") && (lower.contains("shelf") || lower.contains("add") || lower.contains("put"))) ||
           lower.contains("downloads folder shelf mein daalo") {
            var folder = "Downloads"
            if lower.contains("downloads") { folder = "Downloads" }
            else if lower.contains("documents") { folder = "Documents" }
            else if lower.contains("desktop") { folder = "Desktop" }
            else if lower.contains("project") { folder = "my project folder" }
            return .addFolder(name: folder)
        }

        // 19. Add named item (e.g. "Put report.pdf on the shelf", "report.pdf ko shelf pe rakho")
        if (lower.contains("shelf") && (lower.contains("put ") || lower.contains("add "))) ||
           lower.contains("shelf pe rakho") || lower.contains("shelf mein daalo") {
            var name = lower
                .replacingOccurrences(of: "put ", with: "")
                .replacingOccurrences(of: "add ", with: "")
                .replacingOccurrences(of: "on the shelf", with: "")
                .replacingOccurrences(of: "to the shelf", with: "")
                .replacingOccurrences(of: "ko shelf pe rakho", with: "")
                .replacingOccurrences(of: "shelf mein daalo", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                return .addNamedItem(name: name)
            }
        }

        return .none
    }

    // MARK: - Safe Name / Path Resolution
    public func resolveFileOrFolder(named name: String) -> (resolvedURL: URL?, matches: [URL], wasRefusedSensitive: Bool, isOutsideRoots: Bool) {
        let spokenNormalized = Self.normalizeSpokenPath(name)

        // 1. Check if path is absolute or tilde-prefixed
        if spokenNormalized.hasPrefix("/") || spokenNormalized.hasPrefix("~") {
            guard let canonical = PathPolicy.canonicalize(spokenNormalized, workingDirectory: NSHomeDirectory()) else {
                return (nil, [], false, false)
            }

            // Check if protected sensitive path
            if PathPolicy.isProtectedSensitivePath(canonical) {
                return (nil, [], true, false)
            }

            // Check if inside allowed roots
            let inside = PathPolicy.isPathInsideRoots(canonical, roots: effectiveAllowedRoots)
            let u = URL(fileURLWithPath: canonical)
            if FileManager.default.fileExists(atPath: canonical) {
                return (inside ? u : nil, [u], false, !inside)
            } else {
                return (nil, [], false, !inside)
            }
        }

        // 2. Search inside allowed roots for matching filename
        let searchTarget = spokenNormalized.lowercased().replacingOccurrences(of: " ", with: "")
        var candidates: [URL] = []

        let fm = FileManager.default
        for root in effectiveAllowedRoots {
            let rootURL = URL(fileURLWithPath: root)
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            var count = 0
            while let fileURL = enumerator.nextObject() as? URL {
                count += 1
                if count > 500 { break } // Time and count limit

                let path = fileURL.path
                if PathPolicy.isProtectedSensitivePath(path) { continue }

                let lastComp = fileURL.lastPathComponent.lowercased()
                let cleanComp = lastComp.replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")

                // Exact or substring or fuzzy match
                if lastComp == searchTarget || cleanComp.contains(searchTarget) || searchTarget.contains(cleanComp) {
                    candidates.append(fileURL)
                }
            }
        }

        // Deduplicate candidates
        let unique = Array(Set(candidates)).sorted(by: { $0.path < $1.path })
        if unique.count == 1 {
            return (unique[0], unique, false, false)
        } else if unique.count > 1 {
            return (nil, unique, false, false)
        }

        return (nil, [], false, false)
    }

    // MARK: - Execute Voice Action
    public func executeAction(_ action: ShelfVoiceAction) async -> (speech: String, disambiguation: ShelfVoiceDisambiguation?, actionForApproval: AgentAction?) {
        switch action {
        case .listItems:
            let items = shelfStore.getItems()
            if items.isEmpty {
                return ("Your shelf is empty. Drop files near the notch or say 'add <file>' to put something on it.", nil, nil)
            }
            let names = items.prefix(5).map { $0.displayName }.joined(separator: ", ")
            let countStr = items.count == 1 ? "1 item" : "\(items.count) items"
            return ("You have \(countStr) on your shelf: \(names).", nil, nil)

        case .showShelf:
            return ("Showing your shelf.", nil, nil)

        case .clearShelf:
            // Consequential action requires confirmation
            let count = shelfStore.count
            let act = AgentAction(
                appName: "Shelf",
                appIcon: "tray.2.fill",
                title: "Clear Shelf (\(count) items)",
                subtitle: "Remove all items from your shelf",
                payload: ["operation": "clear_shelf", "count": "\(count)"],
                riskLevel: .high
            )
            return ("Clearing the shelf will remove \(count) items from your tray. Please confirm.", nil, act)

        case .removeItem(let target):
            let items = shelfStore.getItems()
            guard !items.isEmpty else {
                return ("Your shelf is already empty.", nil, nil)
            }
            let itemToRemove: ShelfItem?
            if target == "first" || target == "pehla" {
                itemToRemove = items.first
            } else if target == "second" || target == "doosra" {
                itemToRemove = items.count > 1 ? items[1] : nil
            } else {
                itemToRemove = items.first(where: { $0.displayName.lowercased().contains(target.lowercased()) })
            }

            if let item = itemToRemove {
                shelfStore.removeItem(byId: item.id)
                return ("Removed \(item.displayName) from your shelf.", nil, nil)
            } else {
                return ("I couldn't find '\(target)' on your shelf.", nil, nil)
            }

        case .openItem(let target):
            let items = shelfStore.getItems()
            let itemToOpen: ShelfItem?
            if target == "pdf" {
                itemToOpen = items.first(where: { $0.displayName.lowercased().hasSuffix(".pdf") })
            } else if target == "first" {
                itemToOpen = items.first
            } else {
                itemToOpen = items.first(where: { $0.displayName.lowercased().contains(target.lowercased()) })
            }

            guard let item = itemToOpen else {
                return ("I couldn't find a matching file to open on your shelf.", nil, nil)
            }

            if let url = shelfStore.resolveURL(for: item) {
                NSWorkspace.shared.open(url)
                return ("Opening \(item.displayName).", nil, nil)
            } else {
                return ("\(item.displayName) is unavailable or was moved.", nil, nil)
            }

        case .addNamedItem(let name):
            let res = resolveFileOrFolder(named: name)
            if res.wasRefusedSensitive {
                return ("I can't add that for safety.", nil, nil)
            }
            if res.isOutsideRoots, let candidate = res.matches.first {
                let act = AgentAction(
                    appName: "Shelf",
                    appIcon: "tray.2.fill",
                    title: "Add file outside allowed roots",
                    subtitle: candidate.path,
                    payload: ["operation": "add_file", "path": candidate.path],
                    riskLevel: .high
                )
                return ("The file '\(candidate.lastPathComponent)' is outside your standard roots. Please approve adding it to the shelf.", nil, act)
            }
            if res.matches.count > 1 {
                let dis = ShelfVoiceDisambiguation(query: name, candidates: res.matches)
                self.pendingDisambiguation = dis
                return (dis.promptText, dis, nil)
            }
            guard let resolved = res.resolvedURL else {
                return ("I couldn't find '\(name)'. Say 'browse for a file' to choose it manually.", nil, nil)
            }

            let item = shelfStore.addFileURL(resolved, sourceAppName: "Voice Search")
            self.lastAddedItemId = item.id
            let folderName = resolved.deletingLastPathComponent().lastPathComponent
            return ("Adding \(item.displayName) from \(folderName) to your shelf.", nil, nil)

        case .addFolder(let folderName):
            if folderName == "front_finder_folder" {
                return addFrontFinderFolder()
            }
            let res = resolveFileOrFolder(named: folderName)
            if res.wasRefusedSensitive {
                return ("I can't add that for safety.", nil, nil)
            }
            guard let resolved = res.resolvedURL else {
                return ("I couldn't find the folder '\(folderName)'.", nil, nil)
            }
            let item = shelfStore.addFileURL(resolved, sourceAppName: "Voice")
            self.lastAddedItemId = item.id
            return ("Added \(item.displayName) folder to the shelf.", nil, nil)

        case .addFilesInFolder(let folderName, let filter):
            let res = resolveFileOrFolder(named: folderName)
            guard let resolved = res.resolvedURL else {
                return ("I couldn't find the folder '\(folderName)'.", nil, nil)
            }
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(at: resolved, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                return ("Could not read contents of \(folderName).", nil, nil)
            }
            let matchingFiles = contents.filter { url in
                if let f = filter {
                    return url.pathExtension.lowercased() == f.lowercased()
                }
                return true
            }

            if matchingFiles.count > 20 {
                let act = AgentAction(
                    appName: "Shelf",
                    appIcon: "tray.2.fill",
                    title: "Add \(matchingFiles.count) files to shelf",
                    subtitle: "From \(resolved.lastPathComponent)",
                    payload: ["operation": "bulk_add", "count": "\(matchingFiles.count)"],
                    riskLevel: .high
                )
                return ("Found \(matchingFiles.count) files in \(resolved.lastPathComponent). Adding more than 20 items requires confirmation. Please approve.", nil, act)
            }

            for f in matchingFiles {
                shelfStore.addFileURL(f, sourceAppName: "Voice Bulk Add")
            }
            return ("Added \(matchingFiles.count) files from \(resolved.lastPathComponent) to your shelf.", nil, nil)

        case .addLatestDownload:
            let downloads = PathPolicy.defaultAllowedRoots().first(where: { $0.hasSuffix("/Downloads") }) ?? "\(NSHomeDirectory())/Downloads"
            let newest = findNewestItem(in: URL(fileURLWithPath: downloads))
            guard let file = newest else {
                return ("No recent downloads found.", nil, nil)
            }
            let item = shelfStore.addFileURL(file, sourceAppName: "Downloads")
            self.lastAddedItemId = item.id
            return ("Added latest download \(item.displayName) to your shelf.", nil, nil)

        case .addLastScreenshot:
            let desktop = "\(NSHomeDirectory())/Desktop"
            let newest = findNewestScreenshot(in: URL(fileURLWithPath: desktop))
            guard let file = newest else {
                return ("No recent screenshots found.", nil, nil)
            }
            let item = shelfStore.addFileURL(file, sourceAppName: "Screenshots")
            self.lastAddedItemId = item.id
            return ("Added last screenshot \(item.displayName) to your shelf.", nil, nil)

        case .addFinderSelection:
            return addFinderSelectionInternal()

        case .browseForFile:
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = true
                panel.prompt = "Add to Shelf"
                if panel.runModal() == .OK {
                    for url in panel.urls {
                        self.shelfStore.addFileURL(url, sourceAppName: "File Chooser")
                    }
                }
            }
            return ("Opening file chooser.", nil, nil)

        case .undoAdd:
            if let id = lastAddedItemId, let removed = shelfStore.removeItem(byId: id) {
                lastAddedItemId = nil
                return ("Undid adding \(removed.displayName). Removed from your shelf.", nil, nil)
            }
            return ("Nothing to undo on the shelf.", nil, nil)

        case .airDrop:
            let items = shelfStore.getItems()
            guard !items.isEmpty else {
                return ("Your shelf is empty. Put something on it first to AirDrop.", nil, nil)
            }
            let act = AgentAction(
                appName: "AirDrop",
                appIcon: "airdrop",
                title: "AirDrop \(items.count) items",
                subtitle: "Select recipient in share sheet",
                payload: ["operation": "airdrop", "count": "\(items.count)"],
                riskLevel: .high
            )
            return ("AirDrop recipients cannot be chosen automatically. Please confirm on the card to open the share sheet and select the recipient.", nil, act)

        case .attachToEmail:
            let items = shelfStore.getItems()
            guard !items.isEmpty else {
                return ("Your shelf is empty. No files to attach.", nil, nil)
            }
            let filePaths = items.compactMap { shelfStore.resolveURL(for: $0)?.path }
            let act = AgentAction(
                appName: "Mail",
                appIcon: "envelope.fill",
                title: "Attach \(filePaths.count) shelf files to draft",
                subtitle: filePaths.joined(separator: ", "),
                payload: ["operation": "attach_email", "paths": filePaths.joined(separator: "|")],
                riskLevel: .high
            )
            return ("Attaching \(filePaths.count) files from your shelf to this email draft. Please confirm.", nil, act)

        case .sendToContact(_, let contact, let platform):
            let items = shelfStore.getItems()
            guard let first = items.first, let url = shelfStore.resolveURL(for: first) else {
                return ("No valid files on your shelf to send.", nil, nil)
            }
            let act = AgentAction(
                appName: platform,
                appIcon: "message.fill",
                title: "Send \(first.displayName) to \(contact) on \(platform)",
                subtitle: url.path,
                payload: ["operation": "send_messaging", "file": url.path, "recipient": contact, "platform": platform],
                riskLevel: .high
            )
            return ("Sending \(first.displayName) to \(contact) on \(platform) requires confirmation. Please approve.", nil, act)

        case .moveFiles(_, let destFolder):
            let items = shelfStore.getItems()
            let files = items.compactMap { shelfStore.resolveURL(for: $0) }
            guard !files.isEmpty else {
                return ("No files on your shelf to move.", nil, nil)
            }
            let act = AgentAction(
                appName: "Finder",
                appIcon: "folder.fill",
                title: "Move \(files.count) files into \(destFolder)",
                subtitle: "Destination: \(destFolder)",
                payload: ["operation": "move_files", "destination": destFolder],
                riskLevel: .high
            )
            return ("Moving \(files.count) files into \(destFolder) requires confirmation. Please approve.", nil, act)

        case .moveToTrash(let target):
            let items = shelfStore.getItems()
            guard let item = items.first(where: { $0.displayName.lowercased().contains(target.lowercased()) }) ?? items.first,
                  let url = shelfStore.resolveURL(for: item) else {
                return ("Could not find file to move to Trash.", nil, nil)
            }
            let act = AgentAction(
                appName: "Finder",
                appIcon: "trash.fill",
                title: "Move \(item.displayName) to Trash",
                subtitle: url.path,
                payload: ["operation": "trash_file", "path": url.path],
                riskLevel: .high
            )
            return ("Moving \(item.displayName) to the Trash requires your confirmation. Never permanently deleted.", nil, act)

        case .summarizeFile(let target):
            return summarizeFileSafely(target: target)

        case .none:
            return ("I didn't recognize that shelf command.", nil, nil)
        }
    }

    // MARK: - Safe AI File Summarization
    private func summarizeFileSafely(target: String) -> (speech: String, disambiguation: ShelfVoiceDisambiguation?, actionForApproval: AgentAction?) {
        let items = shelfStore.getItems()
        guard let item = items.first(where: { $0.displayName.lowercased().contains(target.lowercased()) }) ?? items.first else {
            return ("No file found on your shelf to summarize.", nil, nil)
        }

        // Check if sensitive
        if let path = item.lastKnownPath, PathPolicy.isProtectedSensitivePath(path) {
            return ("I cannot read protected sensitive files like .env or keys for safety.", nil, nil)
        }

        guard let url = shelfStore.resolveURL(for: item) else {
            return ("\(item.displayName) is unavailable or could not be found.", nil, nil)
        }

        // Size cap: 64 KB
        let maxBytes = 64 * 1024
        guard let data = try? Data(contentsOf: url) else {
            return ("Could not read \(item.displayName).", nil, nil)
        }

        let isTruncated = data.count > maxBytes
        let slice = data.prefix(maxBytes)
        let rawText = String(decoding: slice, as: UTF8.self)

        // Pass through SecretRedactor
        let redacted = SecretRedactor.redact(rawText)

        // Untrusted file content wrapper
        let wrapped = """
        <UNTRUSTED_FILE_DATA filename="\(item.displayName)">
        \(redacted)
        </UNTRUSTED_FILE_DATA>
        """

        let truncationNotice = isTruncated ? " (Note: File was truncated to 64 KB for safety)." : ""
        return ("Summary of \(item.displayName)\(truncationNotice):\n\n\(wrapped)", nil, nil)
    }

    // MARK: - Finder Helpers
    private func addFrontFinderFolder() -> (speech: String, disambiguation: ShelfVoiceDisambiguation?, actionForApproval: AgentAction?) {
        let script = """
        tell application "Finder"
            try
                set targetFolder to (target of front window) as alias
                return POSIX path of targetFolder
            on error
                return "ERROR"
            end try
        end tell
        """
        let res = AccessibilityControlEngine.shared.executeAppleScript(script)
        guard res.success, let output = res.output?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty, output != "ERROR" else {
            return ("Please grant Automation permission for Finder in System Settings -> Privacy & Security -> Automation (see docs/how-to-grant-permissions.md).", nil, nil)
        }

        let url = URL(fileURLWithPath: output)
        if PathPolicy.isProtectedSensitivePath(output) {
            return ("I can't add that for safety.", nil, nil)
        }
        let item = shelfStore.addFileURL(url, sourceAppName: "Finder")
        self.lastAddedItemId = item.id
        return ("Added folder \(item.displayName) from Finder to your shelf.", nil, nil)
    }

    private func addFinderSelectionInternal() -> (speech: String, disambiguation: ShelfVoiceDisambiguation?, actionForApproval: AgentAction?) {
        let script = """
        tell application "Finder"
            try
                set sel to selection as alias list
                set outPaths to {}
                repeat with f in sel
                    set end of outPaths to POSIX path of f
                end repeat
                set AppleScript's text item delimiters to "\\n"
                return outPaths as text
            on error
                return "ERROR"
            end try
        end tell
        """
        let res = AccessibilityControlEngine.shared.executeAppleScript(script)
        guard res.success, let output = res.output?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty, output != "ERROR" else {
            return ("Please grant Automation permission for Finder in System Settings -> Privacy & Security -> Automation (see docs/how-to-grant-permissions.md).", nil, nil)
        }

        let paths = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !paths.isEmpty else {
            return ("No files are currently selected in Finder.", nil, nil)
        }

        var addedCount = 0
        for p in paths {
            if PathPolicy.isProtectedSensitivePath(p) { continue }
            let u = URL(fileURLWithPath: p)
            let item = shelfStore.addFileURL(u, sourceAppName: "Finder Selection")
            self.lastAddedItemId = item.id
            addedCount += 1
        }

        return ("Added \(addedCount) file(s) selected in Finder to your shelf.", nil, nil)
    }

    private func findNewestItem(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        return files.sorted(by: {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return d1 > d2
        }).first
    }

    private func findNewestScreenshot(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        let screenshots = files.filter {
            let name = $0.lastPathComponent.lowercased()
            return (name.contains("screenshot") || name.contains("screen shot")) && ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased())
        }
        return screenshots.sorted(by: {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return d1 > d2
        }).first
    }
}
