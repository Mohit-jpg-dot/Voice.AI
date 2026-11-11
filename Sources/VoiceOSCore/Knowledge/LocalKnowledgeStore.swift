import Foundation

public struct IndexedKnowledgeChunk: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let folderPath: String
    public let filePath: String
    public let fileName: String
    public let snippet: String
    public let embedding: [Float]
    public let modifiedAt: Date

    public init(
        id: String = UUID().uuidString,
        folderPath: String,
        filePath: String,
        fileName: String,
        snippet: String,
        embedding: [Float],
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.folderPath = folderPath
        self.filePath = filePath
        self.fileName = fileName
        self.snippet = snippet
        self.embedding = embedding
        self.modifiedAt = modifiedAt
    }
}

public struct KnowledgeSearchHit: Sendable, Equatable {
    public let chunk: IndexedKnowledgeChunk
    public let score: Double
}

public protocol LocalKnowledgeSearching: Sendable {
    func configuredFolders() -> [String]
    func addFolder(path: String)
    func removeFolder(path: String)
    func indexFolder(path: String) async -> Int
    func reindexAll() async -> Int
    func search(query: String, limit: Int) async -> [KnowledgeSearchHit]
}

/// On-device local file & knowledge search (RAG) indexing user-chosen folders with local embeddings.
/// Files and chunks never leave the device and secrets are scrubbed via SecretRedactor.
public final class LocalKnowledgeStore: LocalKnowledgeSearching, @unchecked Sendable {
    public static let shared = LocalKnowledgeStore()

    private static let supportedExtensions: Set<String> = [
        "md", "txt", "swift", "cs", "py", "js", "ts", "tsx", "jsx",
        "json", "csv", "yaml", "yml", "html", "log", "rst"
    ]
    private static let skippedDirectoryNames: Set<String> = [
        ".git", "node_modules", "build", "dist", ".build", "obj", "bin", "__pycache__"
    ]

    private let lock = NSLock()
    private let foldersDefaultsKey = "VoiceAI_RAG_Folders_v1"
    private let persistenceURL: URL
    private let embeddingProvider: LocalEmbeddingProviding
    private var folders: [String]
    private var chunks: [IndexedKnowledgeChunk] = []

    public init(
        persistenceURL: URL? = nil,
        embeddingProvider: LocalEmbeddingProviding = LocalEmbeddingProvider(),
        loadPersisted: Bool = true
    ) {
        self.embeddingProvider = embeddingProvider
        if let customURL = persistenceURL {
            self.persistenceURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.persistenceURL = appSupport
                .appendingPathComponent("VoiceAI", isDirectory: true)
                .appendingPathComponent("rag_index_v1.json")
        }

        if loadPersisted, let savedFolders = UserDefaults.standard.stringArray(forKey: "VoiceAI_RAG_Folders_v1") {
            self.folders = savedFolders
        } else {
            self.folders = []
        }

        if loadPersisted {
            loadIndexFromDisk()
        }
    }

    public func configuredFolders() -> [String] {
        lock.withLock { folders }
    }

    public func totalIndexedChunks() -> Int {
        lock.withLock { chunks.count }
    }

    public func addFolder(path: String) {
        let normalized = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        guard !normalized.isEmpty else { return }
        lock.withLock {
            if !folders.contains(normalized) {
                folders.append(normalized)
                UserDefaults.standard.set(folders, forKey: foldersDefaultsKey)
            }
        }
    }

    public func removeFolder(path: String) {
        let normalized = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        lock.withLock {
            folders.removeAll { $0 == normalized }
            chunks.removeAll { $0.folderPath == normalized }
            UserDefaults.standard.set(folders, forKey: foldersDefaultsKey)
            saveIndexToDiskLocked()
        }
    }

    @discardableResult
    public func indexFolder(path: String) async -> Int {
        let normalizedFolder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        addFolder(path: normalizedFolder)

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: normalizedFolder, isDirectory: &isDir), isDir.boolValue else {
            return 0
        }

        let folderURL = URL(fileURLWithPath: normalizedFolder, isDirectory: true)
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var collectedFiles: [(url: URL, modifiedAt: Date)] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let name = fileURL.lastPathComponent
            if Self.skippedDirectoryNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else { continue }
            if let size = values?.fileSize, size > 512_000 { continue }
            collectedFiles.append((url: fileURL, modifiedAt: values?.contentModificationDate ?? Date()))
            if collectedFiles.count >= 400 { break }
        }

        var newChunks: [IndexedKnowledgeChunk] = []
        for entry in collectedFiles {
            guard let rawText = try? String(contentsOf: entry.url, encoding: .utf8) else { continue }
            let safeText = SecretRedactor.redact(rawText)
            let pieces = Self.chunkText(safeText, maxChars: 520, overlap: 80)
            for piece in pieces {
                let embedding = await embeddingProvider.embed("\(entry.url.lastPathComponent)\n\(piece)")
                newChunks.append(IndexedKnowledgeChunk(
                    folderPath: normalizedFolder,
                    filePath: entry.url.path,
                    fileName: entry.url.lastPathComponent,
                    snippet: piece,
                    embedding: embedding,
                    modifiedAt: entry.modifiedAt
                ))
            }
        }

        lock.withLock {
            chunks.removeAll { $0.folderPath == normalizedFolder }
            chunks.append(contentsOf: newChunks)
            saveIndexToDiskLocked()
        }

        EventBus.shared.publish(VoiceEvent(
            kind: .custom("rag_folder_indexed"),
            source: "LocalKnowledgeStore",
            payload: ["folder": normalizedFolder, "chunks": "\(newChunks.count)"]
        ))
        return newChunks.count
    }

    @discardableResult
    public func reindexAll() async -> Int {
        let targets = configuredFolders()
        var total = 0
        for folder in targets {
            total += await indexFolder(path: folder)
        }
        return total
    }

    public func search(query: String, limit: Int = 5) async -> [KnowledgeSearchHit] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty, limit > 0 else { return [] }

        let queryVec = await embeddingProvider.embed(cleanQuery)
        let lowerQuery = cleanQuery.lowercased()
        let queryTokens = lowerQuery
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        let snapshot = lock.withLock { chunks }
        var hits: [KnowledgeSearchHit] = []
        hits.reserveCapacity(snapshot.count)

        for chunk in snapshot {
            let cosine = embeddingProvider.cosineSimilarity(queryVec, chunk.embedding)
            let haystack = "\(chunk.fileName.lowercased()) \(chunk.snippet.lowercased())"
            let lexicalBoost: Double
            if haystack.contains(lowerQuery) {
                lexicalBoost = 0.45
            } else if !queryTokens.isEmpty {
                let matches = queryTokens.filter { haystack.contains($0) }.count
                lexicalBoost = 0.30 * (Double(matches) / Double(queryTokens.count))
            } else {
                lexicalBoost = 0.0
            }
            let total = cosine + lexicalBoost
            if total > 0.14 {
                hits.append(KnowledgeSearchHit(chunk: chunk, score: total))
            }
        }

        hits.sort { $0.score > $1.score }
        return Array(hits.prefix(limit))
    }

    public func clearAll() {
        lock.withLock {
            folders.removeAll()
            chunks.removeAll()
            UserDefaults.standard.removeObject(forKey: foldersDefaultsKey)
            try? FileManager.default.removeItem(at: persistenceURL)
        }
    }

    public static func chunkText(_ text: String, maxChars: Int = 520, overlap: Int = 80) -> [String] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        if cleaned.count <= maxChars { return [cleaned] }

        var pieces: [String] = []
        var cursor = cleaned.startIndex
        let safeOverlap = min(overlap, maxChars / 2)

        while cursor < cleaned.endIndex {
            let end = cleaned.index(cursor, offsetBy: maxChars, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            let slice = String(cleaned[cursor..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !slice.isEmpty {
                pieces.append(slice)
            }
            if end == cleaned.endIndex { break }
            let backOffset = -min(safeOverlap, cleaned.distance(from: cursor, to: end))
            cursor = cleaned.index(end, offsetBy: backOffset, limitedBy: cleaned.startIndex) ?? end
        }
        return pieces
    }

    private func loadIndexFromDisk() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let decoded = try? JSONDecoder().decode([IndexedKnowledgeChunk].self, from: data) else {
            return
        }
        lock.withLock {
            self.chunks = decoded
        }
    }

    private func saveIndexToDiskLocked() {
        let dir = persistenceURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(chunks) {
            try? data.write(to: persistenceURL, options: .atomic)
        }
    }
}
