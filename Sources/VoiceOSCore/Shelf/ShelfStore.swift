import Foundation
import CommonCrypto
import Security

public final class ShelfStore: @unchecked Sendable {
    public static let shared = ShelfStore()

    private let lock = NSLock()
    private var items: [ShelfItem] = []
    public var settings: ShelfSettings
    private let storageURL: URL
    private var encryptionKey: Data

    public init(customStorageDirectory: URL? = nil, initialSettings: ShelfSettings = ShelfSettings()) {
        self.settings = initialSettings

        let baseDir: URL
        if let customDir = customStorageDirectory {
            baseDir = customDir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            baseDir = appSupport.appendingPathComponent("Voice.AI", isDirectory: true).appendingPathComponent("Shelf", isDirectory: true)
        }

        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        self.storageURL = baseDir.appendingPathComponent("shelf_items.json")
        self.encryptionKey = Self.resolveOrCreateEncryptionKey()

        loadFromDisk()
    }

    // MARK: - Encryption Key Resolution
    private static func resolveOrCreateEncryptionKey() -> Data {
        let tag = "ai.voice.app.shelf.encryption_key"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data, data.count == 32 {
            return data
        }

        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        let newKey = Data(keyBytes)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecValueData as String: newKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
        return newKey
    }

    // MARK: - AES-256 Helpers
    private func encryptPayload(_ data: Data) -> Data? {
        var iv = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, iv.count, &iv)
        let ivData = Data(iv)

        var outBuffer = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        var numBytesEncrypted: size_t = 0

        let status = CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionPKCS7Padding),
            (encryptionKey as NSData).bytes,
            kCCKeySizeAES256,
            (ivData as NSData).bytes,
            (data as NSData).bytes,
            data.count,
            &outBuffer,
            outBuffer.count,
            &numBytesEncrypted
        )

        guard status == kCCSuccess else { return nil }
        return ivData + Data(outBuffer.prefix(numBytesEncrypted))
    }

    private func decryptPayload(_ encryptedData: Data) -> Data? {
        guard encryptedData.count > 16 else { return nil }
        let ivData = Data(encryptedData.prefix(16))
        let cipherTextData = Data(encryptedData.suffix(from: 16))

        var outBuffer = [UInt8](repeating: 0, count: cipherTextData.count + kCCBlockSizeAES128)
        var numBytesDecrypted: size_t = 0

        let status = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionPKCS7Padding),
            (encryptionKey as NSData).bytes,
            kCCKeySizeAES256,
            (ivData as NSData).bytes,
            (cipherTextData as NSData).bytes,
            cipherTextData.count,
            &outBuffer,
            outBuffer.count,
            &numBytesDecrypted
        )

        guard status == kCCSuccess else { return nil }
        return Data(outBuffer.prefix(numBytesDecrypted))
    }

    // MARK: - Read Access
    public func getItems() -> [ShelfItem] {
        lock.lock()
        defer { lock.unlock() }
        pruneExpiredAndOverflowLocked()
        return items
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    public func getItem(byId id: UUID) -> ShelfItem? {
        lock.lock()
        defer { lock.unlock() }
        return items.first(where: { $0.id == id })
    }

    // MARK: - Add Operations
    @discardableResult
    public func addFileURL(_ url: URL, sourceAppName: String? = nil) -> ShelfItem {
        lock.lock()
        defer {
            saveToDiskLocked()
            lock.unlock()
        }

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let isFolder = isDir.boolValue

        let normalizedPath = url.standardizedFileURL.path
        // Check for deduplication
        if let existingIdx = items.firstIndex(where: { item in
            if let lastPath = item.lastKnownPath, lastPath == normalizedPath { return true }
            if let res = resolveBookmarkLocked(item), res.standardizedFileURL.path == normalizedPath { return true }
            return false
        }) {
            // Update timestamp & move to front
            items[existingIdx].dateAdded = Date()
            items[existingIdx].isUnavailable = !exists
            let updated = items.remove(at: existingIdx)
            items.insert(updated, at: 0)
            return updated
        }

        var bookmark: Data? = nil
        do {
            bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            bookmark = try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }

        let fileSize: Int64
        if isFolder {
            fileSize = 0
        } else {
            let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
            fileSize = (attr?[.size] as? NSNumber)?.int64Value ?? 0
        }

        let isImg = ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff"].contains(url.pathExtension.lowercased())
        let kind: ShelfItemKind = isFolder ? .folder : (isImg ? .image : .file)

        let item = ShelfItem(
            kind: kind,
            displayName: url.lastPathComponent.isEmpty ? "File" : url.lastPathComponent,
            bookmarkData: bookmark,
            lastKnownPath: normalizedPath,
            fileSizeBytes: fileSize,
            dateAdded: Date(),
            sourceAppName: sourceAppName,
            isUnavailable: !exists
        )

        items.insert(item, at: 0)
        pruneExpiredAndOverflowLocked()
        return item
    }

    @discardableResult
    public func addTextSnippet(_ text: String, sourceAppName: String? = nil) -> ShelfItem {
        lock.lock()
        defer {
            saveToDiskLocked()
            lock.unlock()
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingIdx = items.firstIndex(where: { $0.kind == .textSnippet && $0.textContent == trimmed }) {
            items[existingIdx].dateAdded = Date()
            let updated = items.remove(at: existingIdx)
            items.insert(updated, at: 0)
            return updated
        }

        let textData = Data(trimmed.utf8)
        let encrypted = encryptPayload(textData)
        let preview = String(trimmed.prefix(60)).replacingOccurrences(of: "\n", with: " ")

        let item = ShelfItem(
            kind: .textSnippet,
            displayName: preview.isEmpty ? "Text Snippet" : preview,
            storedPayloadEncrypted: encrypted,
            fileSizeBytes: Int64(textData.count),
            dateAdded: Date(),
            sourceAppName: sourceAppName,
            isUnavailable: false,
            textContent: trimmed
        )

        items.insert(item, at: 0)
        pruneExpiredAndOverflowLocked()
        return item
    }

    @discardableResult
    public func addImageData(_ data: Data, suggestedName: String? = nil, sourceAppName: String? = nil) -> ShelfItem {
        lock.lock()
        defer {
            saveToDiskLocked()
            lock.unlock()
        }

        let encrypted = encryptPayload(data)
        let name = suggestedName ?? "Pasted Image (\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)))"

        let item = ShelfItem(
            kind: .image,
            displayName: name,
            storedPayloadEncrypted: encrypted,
            fileSizeBytes: Int64(data.count),
            dateAdded: Date(),
            sourceAppName: sourceAppName,
            isUnavailable: false
        )

        items.insert(item, at: 0)
        pruneExpiredAndOverflowLocked()
        return item
    }

    @discardableResult
    public func addWebURL(_ url: URL, title: String? = nil, sourceAppName: String? = nil) -> ShelfItem {
        lock.lock()
        defer {
            saveToDiskLocked()
            lock.unlock()
        }

        let urlStr = url.absoluteString
        if let existingIdx = items.firstIndex(where: { $0.kind == .url && $0.urlString == urlStr }) {
            items[existingIdx].dateAdded = Date()
            let updated = items.remove(at: existingIdx)
            items.insert(updated, at: 0)
            return updated
        }

        let name = title ?? url.host ?? urlStr
        let item = ShelfItem(
            kind: .url,
            displayName: name,
            fileSizeBytes: 0,
            dateAdded: Date(),
            sourceAppName: sourceAppName,
            isUnavailable: false,
            urlString: urlStr
        )

        items.insert(item, at: 0)
        pruneExpiredAndOverflowLocked()
        return item
    }

    // MARK: - Decrypt Stored Payload (Text or Image)
    public func retrieveDecryptedPayload(for item: ShelfItem) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let encrypted = item.storedPayloadEncrypted else { return nil }
        return decryptPayload(encrypted)
    }

    // MARK: - Remove & Clear
    @discardableResult
    public func removeItem(byId id: UUID) -> ShelfItem? {
        lock.lock()
        defer {
            saveToDiskLocked()
            lock.unlock()
        }
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: idx)
    }

    public func clear() {
        lock.lock()
        defer {
            saveToDiskLocked()
            lock.unlock()
        }
        items.removeAll()
    }

    // MARK: - Bookmark Resolution & Availability
    public func resolveURL(for item: ShelfItem) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return resolveBookmarkLocked(item)
    }

    private func resolveBookmarkLocked(_ item: ShelfItem) -> URL? {
        if let bookmark = item.bookmarkData {
            var isStale = false
            do {
                let resolved = try URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    // Refresh stale bookmark data
                    if let freshBookmark = try? resolved.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil),
                       let idx = items.firstIndex(where: { $0.id == item.id }) {
                        items[idx].bookmarkData = freshBookmark
                        items[idx].lastKnownPath = resolved.path
                        saveToDiskLocked()
                    }
                }
                if FileManager.default.fileExists(atPath: resolved.path) {
                    if let idx = items.firstIndex(where: { $0.id == item.id }), items[idx].isUnavailable {
                        items[idx].isUnavailable = false
                        items[idx].lastKnownPath = resolved.path
                        saveToDiskLocked()
                    }
                    return resolved
                }
            } catch {
                // Non-security scoped fallback
                var isStale2 = false
                if let resolved2 = try? URL(
                    resolvingBookmarkData: bookmark,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale2
                ) {
                    if FileManager.default.fileExists(atPath: resolved2.path) {
                        return resolved2
                    }
                }
            }
        }

        // Fallback to last known path
        if let path = item.lastKnownPath, FileManager.default.fileExists(atPath: path) {
            let u = URL(fileURLWithPath: path)
            return u
        }

        // Mark item as unavailable
        if let idx = items.firstIndex(where: { $0.id == item.id }), !items[idx].isUnavailable {
            items[idx].isUnavailable = true
            saveToDiskLocked()
        }
        return nil
    }

    // MARK: - Pruning
    private func pruneExpiredAndOverflowLocked() {
        // Expiry
        if settings.autoExpireDays > 0 {
            let cutoff = Date().addingTimeInterval(-Double(settings.autoExpireDays) * 86400.0)
            items.removeAll(where: { $0.dateAdded < cutoff })
        }

        // Capacity
        let limit = max(1, min(settings.maxItemCount, 200))
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
    }

    // MARK: - Persistence
    private func saveToDiskLocked() {
        guard settings.keepItemsAfterRelaunch else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Silently fallback without crashing
        }
    }

    private func loadFromDisk() {
        guard settings.keepItemsAfterRelaunch else { return }
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([ShelfItem].self, from: data)
            lock.lock()
            self.items = loaded
            pruneExpiredAndOverflowLocked()
            lock.unlock()
        } catch {
            // Bad data, reset
        }
    }

    public func handleAppQuit() {
        if settings.clearOnQuit {
            clear()
        }
    }
}

