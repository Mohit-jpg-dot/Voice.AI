import Foundation
import AppKit
import UniformTypeIdentifiers

public enum ShelfDropResult: Equatable, Sendable {
    case added(ShelfItem)
    case rejected(reason: String)
}

public protocol FilePromiseReceiving: Sendable {
    var fileNames: [String] { get }
    var fileTypes: [String] { get }
    func receiveFiles(at destinationDir: URL) async throws -> [URL]
}

public final class MockFilePromiseReceiver: FilePromiseReceiving, @unchecked Sendable {
    public let fileNames: [String]
    public let fileTypes: [String]
    private let simulatedFiles: [URL]

    public init(fileNames: [String], fileTypes: [String] = ["public.data"], simulatedFiles: [URL] = []) {
        self.fileNames = fileNames
        self.fileTypes = fileTypes
        self.simulatedFiles = simulatedFiles
    }

    public func receiveFiles(at destinationDir: URL) async throws -> [URL] {
        var createdURLs: [URL] = []
        for name in fileNames {
            let dest = destinationDir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? Data().write(to: dest)
            }
            createdURLs.append(dest)
        }
        return createdURLs.isEmpty ? simulatedFiles : createdURLs
    }
}

public final class NativeFilePromiseAdapter: FilePromiseReceiving, @unchecked Sendable {
    private let receiver: NSFilePromiseReceiver

    public init(receiver: NSFilePromiseReceiver) {
        self.receiver = receiver
    }

    public var fileNames: [String] {
        return receiver.fileNames
    }

    public var fileTypes: [String] {
        return receiver.fileTypes
    }

    public func receiveFiles(at destinationDir: URL) async throws -> [URL] {
        return try await withCheckedThrowingContinuation { continuation in
            let queue = OperationQueue()
            queue.qualityOfService = .userInitiated
            receiver.receivePromisedFiles(atDestination: destinationDir, options: [:], operationQueue: queue) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: [url])
                }
            }
        }
    }
}

public final class ShelfDropController: @unchecked Sendable {
    public static let shared = ShelfDropController()

    private let shelfStore: ShelfStore

    public init(shelfStore: ShelfStore = .shared) {
        self.shelfStore = shelfStore
    }

    // MARK: - Process Direct Pasteboard Items (Async, Off Main Thread)
    public func processPasteboard(_ pasteboard: NSPasteboard, sourceAppName: String? = nil) async -> [ShelfDropResult] {
        var results: [ShelfDropResult] = []

        // 1. Check for File URLs first (covers files and folders)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            for url in urls {
                let res = processFileURL(url, sourceAppName: sourceAppName)
                results.append(res)
            }
            return results
        }

        // 2. Check for File Promises (Mail attachments, Safari images, Photos)
        if let promiseReceivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver], !promiseReceivers.isEmpty {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dropsDir = appSupport.appendingPathComponent("Voice.AI/ShelfDrops", isDirectory: true)
            try? FileManager.default.createDirectory(at: dropsDir, withIntermediateDirectories: true)

            for receiver in promiseReceivers {
                let adapter = NativeFilePromiseAdapter(receiver: receiver)
                let res = await processFilePromise(adapter, destinationDir: dropsDir, sourceAppName: sourceAppName)
                results.append(contentsOf: res)
            }
            return results
        }

        // 3. Check for Images (Pasted screenshot or raw bitmap)
        if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation {
            if let bitmap = NSBitmapImageRep(data: tiff), let pngData = bitmap.representation(using: .png, properties: [:]) {
                let item = shelfStore.addImageData(pngData, sourceAppName: sourceAppName)
                return [.added(item)]
            }
        }

        // 4. Check for Web URLs
        if let urlStrings = pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String] {
            for str in urlStrings {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")), let validURL = URL(string: trimmed) {
                    let item = shelfStore.addWebURL(validURL, sourceAppName: sourceAppName)
                    results.append(.added(item))
                }
            }
            if !results.isEmpty {
                return results
            }
        }

        // 5. Check for Plain String / Text Snippet
        if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let item = shelfStore.addTextSnippet(string, sourceAppName: sourceAppName)
            return [.added(item)]
        }

        // 6. Unsupported / Rejected
        return [.rejected(reason: "Unsupported pasteboard item type. Drop accepts files, folders, images, text, and URLs.")]
    }

    // MARK: - Process File URL
    public func processFileURL(_ url: URL, sourceAppName: String? = nil) -> ShelfDropResult {
        // Enforce: Never load the entire file into memory! Only inspect attributes and bookmark.
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return .rejected(reason: "File not found at path: \(url.path)")
        }

        let item = shelfStore.addFileURL(url, sourceAppName: sourceAppName)
        return .added(item)
    }

    // MARK: - Process File Promise
    public func processFilePromise(_ promise: FilePromiseReceiving, destinationDir: URL, sourceAppName: String? = nil) async -> [ShelfDropResult] {
        do {
            let urls = try await promise.receiveFiles(at: destinationDir)
            var results: [ShelfDropResult] = []
            for url in urls {
                let res = processFileURL(url, sourceAppName: sourceAppName)
                results.append(res)
            }
            return results
        } catch {
            return [.rejected(reason: "Failed to resolve file promise: \(error.localizedDescription)")]
        }
    }

    // MARK: - Process Raw Text Snippet
    public func processTextSnippet(_ text: String, sourceAppName: String? = nil) -> ShelfDropResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .rejected(reason: "Empty text snippet rejected.")
        }
        let item = shelfStore.addTextSnippet(trimmed, sourceAppName: sourceAppName)
        return .added(item)
    }

    // MARK: - Process URL
    public func processURL(_ url: URL, title: String? = nil, sourceAppName: String? = nil) -> ShelfDropResult {
        if url.isFileURL {
            return processFileURL(url, sourceAppName: sourceAppName)
        }
        let item = shelfStore.addWebURL(url, title: title, sourceAppName: sourceAppName)
        return .added(item)
    }
}

