import Foundation
import AppKit
import QuickLookThumbnailing

public final class ShelfThumbnailCache: @unchecked Sendable {
    public static let shared = ShelfThumbnailCache()

    private let lock = NSLock()
    private var cache: [String: (image: NSImage, modDate: Date?, accessOrder: Int)] = [:]
    private var currentAccessCounter: Int = 0
    private let capacity: Int

    public init(capacity: Int = 250) {
        self.capacity = capacity
    }

    public func cachedThumbnail(for key: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if var entry = cache[key] {
            currentAccessCounter += 1
            entry.accessOrder = currentAccessCounter
            cache[key] = entry
            return entry.image
        }
        return nil
    }

    public func storeThumbnail(_ image: NSImage, for key: String, modDate: Date? = nil) {
        lock.lock()
        defer { lock.unlock() }

        currentAccessCounter += 1
        cache[key] = (image: image, modDate: modDate, accessOrder: currentAccessCounter)

        // LRU Eviction if over capacity
        if cache.count > capacity {
            let sortedKeys = cache.sorted(by: { $0.value.accessOrder < $1.value.accessOrder })
            let excess = cache.count - capacity
            for (k, _) in sortedKeys.prefix(excess) {
                cache.removeValue(forKey: k)
            }
        }
    }

    public func invalidate(for key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: key)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }

    // MARK: - Asynchronous QuickLook Thumbnail Generation
    public func requestThumbnail(for fileURL: URL, size: CGSize = CGSize(width: 64, height: 64)) async -> NSImage {
        let key = "\(fileURL.path)_\(Int(size.width))x\(Int(size.height))"
        let modDate = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date

        lock.lock()
        if let entry = cache[key] {
            if entry.modDate == modDate {
                currentAccessCounter += 1
                cache[key]?.accessOrder = currentAccessCounter
                let img = entry.image
                lock.unlock()
                return img
            } else {
                cache.removeValue(forKey: key)
            }
        }
        lock.unlock()

        // Generate via QLThumbnailGenerator off the main thread
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: size,
            scale: scale,
            representationTypes: [.thumbnail, .icon]
        )

        do {
            let thumbnail = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            let nsImage = thumbnail.nsImage
            storeThumbnail(nsImage, for: key, modDate: modDate)
            return nsImage
        } catch {
            // Fallback to system icon for file type
            let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
            storeThumbnail(icon, for: key, modDate: modDate)
            return icon
        }
    }
}

