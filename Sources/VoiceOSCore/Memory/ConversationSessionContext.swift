import Foundation

/// Tracks conversational continuity, active browser/app context, pending file confirmations, and undo history.
public final class ConversationSessionContext: @unchecked Sendable {
    public static let shared = ConversationSessionContext()

    public enum UndoOperation: Sendable, Equatable {
        case createdFile(path: String)
        case createdFolder(path: String)
        case renamedFile(fromPath: String, toPath: String)
        case movedFile(fromPath: String, toPath: String)
        case copiedFile(createdPath: String)
    }

    public struct CapturedScreenContext: Sendable {
        public let pngData: Data?
        public let ocrText: String
        public let appName: String
        public let initialSummary: String
        public let capturedAt: Date

        public init(
            pngData: Data?,
            ocrText: String,
            appName: String,
            initialSummary: String,
            capturedAt: Date = Date()
        ) {
            self.pngData = pngData
            self.ocrText = ocrText
            self.appName = appName
            self.initialSummary = initialSummary
            self.capturedAt = capturedAt
        }
    }

    private let lock = NSLock()
    private var _lastReply: String?
    private var _lastCommand: String?
    private var _lastActiveBrowser: String?
    private var _lastCreatedOrModifiedPath: String?
    private var _lastTypedText: String?
    private var _lastSearchQuery: String?
    private var _lastSearchResults: [(title: String, url: String)] = []
    private var _pendingDeletePath: String?
    private var _undoStack: [UndoOperation] = []
    private var _timers: [(label: String, fireAt: Date)] = []
    private var _alarms: [(label: String, timeDescription: String)] = []
    private var _lastScreenContext: CapturedScreenContext?

    public init() {}

    public func resetForTesting() {
        lock.withLock {
            _lastReply = nil
            _lastCommand = nil
            _lastActiveBrowser = nil
            _lastCreatedOrModifiedPath = nil
            _lastTypedText = nil
            _lastSearchQuery = nil
            _lastSearchResults = []
            _pendingDeletePath = nil
            _undoStack = []
            _timers = []
            _alarms = []
            _lastScreenContext = nil
        }
    }

    public func setLastScreenContext(_ ctx: CapturedScreenContext) {
        lock.withLock { _lastScreenContext = ctx }
    }

    public func lastScreenContext(maxAgeSeconds: TimeInterval = 900) -> CapturedScreenContext? {
        lock.withLock {
            guard let ctx = _lastScreenContext else { return nil }
            if Date().timeIntervalSince(ctx.capturedAt) > maxAgeSeconds {
                _lastScreenContext = nil
                return nil
            }
            return ctx
        }
    }

    public func clearLastScreenContext() {
        lock.withLock { _lastScreenContext = nil }
    }

    public var lastReply: String? { lock.withLock { _lastReply } }
    public var lastCommand: String? { lock.withLock { _lastCommand } }
    public var lastActiveBrowser: String? { lock.withLock { _lastActiveBrowser } }
    public var lastCreatedOrModifiedPath: String? { lock.withLock { _lastCreatedOrModifiedPath } }
    public var lastTypedText: String? { lock.withLock { _lastTypedText } }
    public var lastSearchQuery: String? { lock.withLock { _lastSearchQuery } }

    public func setLastTypedText(_ text: String) {
        lock.withLock { _lastTypedText = text }
    }

    public func clearLastFilePathIfMatching(_ path: String) {
        lock.withLock {
            if _lastCreatedOrModifiedPath == path {
                _lastCreatedOrModifiedPath = nil
            }
        }
    }
    public var pendingDeletePath: String? { lock.withLock { _pendingDeletePath } }

    public func recordReply(_ reply: String, forCommand cmd: String) {
        lock.withLock {
            _lastReply = reply
            let lower = cmd.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lower != "do that again" && lower != "repeat that" {
                _lastCommand = cmd
            }
        }
    }

    public func setActiveBrowser(_ browser: String) {
        lock.withLock { _lastActiveBrowser = browser }
    }

    public func setLastFilePath(_ path: String) {
        lock.withLock { _lastCreatedOrModifiedPath = path }
    }

    public func setSearchResults(query: String, results: [(title: String, url: String)]) {
        lock.withLock {
            _lastSearchQuery = query
            _lastSearchResults = results
        }
    }

    public func searchResult(atOneBasedIndex idx: Int) -> (title: String, url: String)? {
        lock.withLock {
            let zero = idx - 1
            guard zero >= 0 && zero < _lastSearchResults.count else { return nil }
            return _lastSearchResults[zero]
        }
    }

    public func setPendingDeletePath(_ path: String?) {
        lock.withLock { _pendingDeletePath = path }
    }

    public func pushUndo(_ op: UndoOperation) {
        lock.withLock {
            _undoStack.append(op)
            if _undoStack.count > 25 { _undoStack.removeFirst() }
        }
    }

    public func popUndo() -> UndoOperation? {
        lock.withLock {
            _undoStack.isEmpty ? nil : _undoStack.removeLast()
        }
    }

    public func addTimer(label: String, seconds: TimeInterval) {
        lock.withLock {
            _timers.append((label: label, fireAt: Date().addingTimeInterval(seconds)))
        }
    }

    public func addAlarm(label: String, timeDescription: String) {
        lock.withLock {
            _alarms.append((label: label, timeDescription: timeDescription))
        }
    }
}

