import Foundation

public enum VoiceEventSeverity: String, Codable, Sendable {
    case info
    case notice
    case warning
    case critical
}

public enum SystemEventKind: Hashable, Codable, Sendable {
    case batteryChanged
    case cpuMemoryPressure
    case calendarUpcoming
    case buildStatusChanged
    case toolInvoked
    case approvalRequested
    case approvalResolved
    case memoryUpdated
    case emailDraftCreated
    case calendarDraftCreated
    case custom(String)

    public var rawKey: String {
        switch self {
        case .batteryChanged: return "battery_changed"
        case .cpuMemoryPressure: return "cpu_memory_pressure"
        case .calendarUpcoming: return "calendar_upcoming"
        case .buildStatusChanged: return "build_status_changed"
        case .toolInvoked: return "tool_invoked"
        case .approvalRequested: return "approval_requested"
        case .approvalResolved: return "approval_resolved"
        case .memoryUpdated: return "memory_updated"
        case .emailDraftCreated: return "email_draft_created"
        case .calendarDraftCreated: return "calendar_draft_created"
        case .custom(let name): return name
        }
    }
}

public struct VoiceEvent: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let kind: SystemEventKind
    public let source: String
    public let timestamp: Date
    public let severity: VoiceEventSeverity
    public let payload: [String: String]

    public init(
        id: UUID = UUID(),
        kind: SystemEventKind,
        source: String,
        timestamp: Date = Date(),
        severity: VoiceEventSeverity = .info,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.timestamp = timestamp
        self.severity = severity
        self.payload = SecretRedactor.redactDictionary(payload)
    }
}

public protocol EventBusProtocol: Sendable {
    func publish(_ event: VoiceEvent)
    @discardableResult
    func subscribe(
        matching kind: SystemEventKind?,
        handler: @escaping @Sendable (VoiceEvent) -> Void
    ) -> UUID
    func unsubscribe(_ subscriptionId: UUID)
    func recentEvents(limit: Int) -> [VoiceEvent]
    func stream(matching kind: SystemEventKind?) -> AsyncStream<VoiceEvent>
}

/// Thread-safe pub/sub system bus decouple system monitors, tool execution, safety approvals, and memory updates.
public final class EventBus: EventBusProtocol, @unchecked Sendable {
    public static let shared = EventBus()

    private struct Subscription {
        let id: UUID
        let filter: SystemEventKind?
        let handler: @Sendable (VoiceEvent) -> Void
    }

    private struct StreamSubscriber {
        let id: UUID
        let filter: SystemEventKind?
        let continuation: AsyncStream<VoiceEvent>.Continuation
    }

    private let lock = NSLock()
    private var subscriptions: [UUID: Subscription] = [:]
    private var streamSubscribers: [UUID: StreamSubscriber] = [:]
    private var historyBuffer: [VoiceEvent] = []
    private let maxHistoryCapacity = 200

    public init() {}

    public func publish(_ event: VoiceEvent) {
        let matchedHandlers: [@Sendable (VoiceEvent) -> Void]
        let matchedStreams: [AsyncStream<VoiceEvent>.Continuation]

        lock.lock()
        historyBuffer.append(event)
        if historyBuffer.count > maxHistoryCapacity {
            historyBuffer.removeFirst(historyBuffer.count - maxHistoryCapacity)
        }
        matchedHandlers = subscriptions.values.compactMap { sub in
            (sub.filter == nil || sub.filter == event.kind) ? sub.handler : nil
        }
        matchedStreams = streamSubscribers.values.compactMap { sub in
            (sub.filter == nil || sub.filter == event.kind) ? sub.continuation : nil
        }
        lock.unlock()

        for handler in matchedHandlers {
            handler(event)
        }
        for continuation in matchedStreams {
            continuation.yield(event)
        }
    }

    @discardableResult
    public func subscribe(
        matching kind: SystemEventKind? = nil,
        handler: @escaping @Sendable (VoiceEvent) -> Void
    ) -> UUID {
        let id = UUID()
        lock.lock()
        subscriptions[id] = Subscription(id: id, filter: kind, handler: handler)
        lock.unlock()
        return id
    }

    public func unsubscribe(_ subscriptionId: UUID) {
        lock.lock()
        subscriptions.removeValue(forKey: subscriptionId)
        if let streamSub = streamSubscribers.removeValue(forKey: subscriptionId) {
            streamSub.continuation.finish()
        }
        lock.unlock()
    }

    public func recentEvents(limit: Int = 50) -> [VoiceEvent] {
        guard limit > 0 else { return [] }
        lock.lock()
        let snapshot = Array(historyBuffer.suffix(limit))
        lock.unlock()
        return snapshot
    }

    public func stream(matching kind: SystemEventKind? = nil) -> AsyncStream<VoiceEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.lock.lock()
            self.streamSubscribers[id] = StreamSubscriber(id: id, filter: kind, continuation: continuation)
            self.lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.streamSubscribers.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    public func clearHistory() {
        lock.lock()
        historyBuffer.removeAll()
        lock.unlock()
    }
}

