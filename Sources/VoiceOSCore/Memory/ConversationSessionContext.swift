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

    private let lock = NSLock()
    private var _lastReply: String?
    private var _lastCommand: String?
    private var _lastActiveBrowser: String?
    private var _lastCreatedOrModifiedPath: String?
    private var _lastSearchQuery: String?
    private var _lastSearchResults: [(title: String, url: String)] = []
    private var _pendingDeletePath: String?
    private var _undoStack: [UndoOperation] = []
    private var _timers: [(label: String, fireAt: Date)] = []
    private var _alarms: [(label: String, timeDescription: String)] = []

    public init() {}

    public func resetForTesting() {
        lock.withLock {
            _lastReply = nil
            _lastCommand = nil
            _lastActiveBrowser = nil
            _lastCreatedOrModifiedPath = nil
            _lastSearchQuery = nil
            _lastSearchResults = []
            _pendingDeletePath = nil
            _undoStack = []
            _timers = []
            _alarms = []
        }
    }

    public var lastReply: String? { lock.withLock { _lastReply } }
    public var lastCommand: String? { lock.withLock { _lastCommand } }
    public var lastActiveBrowser: String? { lock.withLock { _lastActiveBrowser } }
    public var lastCreatedOrModifiedPath: String? { lock.withLock { _lastCreatedOrModifiedPath } }
    public var lastSearchQuery: String? { lock.withLock { _lastSearchQuery } }
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

