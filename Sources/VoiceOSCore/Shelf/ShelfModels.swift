import Foundation

public enum ShelfItemKind: String, Codable, Sendable, CaseIterable {
    case file = "file"
    case folder = "folder"
    case image = "image"
    case textSnippet = "text"
    case url = "url"
    
    public var iconName: String {
        switch self {
        case .file: return "doc.fill"
        case .folder: return "folder.fill"
        case .image: return "photo.fill"
        case .textSnippet: return "text.quote"
        case .url: return "link"
        }
    }
}

public enum ShelfDragOutAction: String, Codable, Sendable, CaseIterable {
    case copy = "Copy"
    case move = "Move"
}

public struct ShelfSettings: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var autoOpenOnDragNearNotch: Bool
    public var closeAfterDrop: Bool
    public var defaultDragOutAction: ShelfDragOutAction
    public var removeAfterDragOut: Bool
    public var keepItemsAfterRelaunch: Bool
    public var clearOnQuit: Bool
    public var autoExpireDays: Int // 0 = never
    public var maxItemCount: Int
    public var showCountBadgeOnCollapsedNotch: Bool

    public init(
        isEnabled: Bool = true,
        autoOpenOnDragNearNotch: Bool = true,
        closeAfterDrop: Bool = false,
        defaultDragOutAction: ShelfDragOutAction = .copy,
        removeAfterDragOut: Bool = true,
        keepItemsAfterRelaunch: Bool = true,
        clearOnQuit: Bool = false,
        autoExpireDays: Int = 7,
        maxItemCount: Int = 50,
        showCountBadgeOnCollapsedNotch: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.autoOpenOnDragNearNotch = autoOpenOnDragNearNotch
        self.closeAfterDrop = closeAfterDrop
        self.defaultDragOutAction = defaultDragOutAction
        self.removeAfterDragOut = removeAfterDragOut
        self.keepItemsAfterRelaunch = keepItemsAfterRelaunch
        self.clearOnQuit = clearOnQuit
        self.autoExpireDays = autoExpireDays
        self.maxItemCount = maxItemCount
        self.showCountBadgeOnCollapsedNotch = showCountBadgeOnCollapsedNotch
    }
}

public struct ShelfItem: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var kind: ShelfItemKind
    public var displayName: String
    public var bookmarkData: Data?
    public var lastKnownPath: String?
    public var storedPayloadEncrypted: Data?
    public var fileSizeBytes: Int64
    public var dateAdded: Date
    public var sourceAppName: String?
    public var isUnavailable: Bool
    public var textContent: String?
    public var urlString: String?

    public init(
        id: UUID = UUID(),
        kind: ShelfItemKind,
        displayName: String,
        bookmarkData: Data? = nil,
        lastKnownPath: String? = nil,
        storedPayloadEncrypted: Data? = nil,
        fileSizeBytes: Int64 = 0,
        dateAdded: Date = Date(),
        sourceAppName: String? = nil,
        isUnavailable: Bool = false,
        textContent: String? = nil,
        urlString: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.bookmarkData = bookmarkData
        self.lastKnownPath = lastKnownPath
        self.storedPayloadEncrypted = storedPayloadEncrypted
        self.fileSizeBytes = fileSizeBytes
        self.dateAdded = dateAdded
        self.sourceAppName = sourceAppName
        self.isUnavailable = isUnavailable
        self.textContent = textContent
        self.urlString = urlString
    }
    
    public var formattedSize: String {
        if kind == .textSnippet {
            return "\(textContent?.count ?? 0) chars"
        }
        if kind == .url {
            return "Web Link"
        }
        if fileSizeBytes <= 0 {
            return kind == .folder ? "Folder" : "--"
        }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: fileSizeBytes)
    }
}

