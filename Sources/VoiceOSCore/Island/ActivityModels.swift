// Ported from islandcn, MIT License, Copyright (c) 2026 Leo. Modified for Swift.
// Pure-logic activity data models for Voice.AI's dynamic notch presentation engine.

import Foundation

public enum IslandPresentationKind: String, Codable, Sendable, Equatable {
    case idle
    case compact
    case split
    case expanded
}

public enum ActivitySlotContent: Codable, Sendable, Equatable {
    case text(String)
    case valueWithUnit(value: String, unit: String)
    case symbol(name: String, tint: String? = nil)
    case timeCountdown(endsAt: Double, pausedRemaining: Double? = nil)
    case progressRing(progress: Double, tint: String? = nil)
    case waveform(levels: [Float], active: Bool)
    case battery(level: Int, state: String)
    case custom(key: String, payload: [String: String])

    public var displayText: String {
        switch self {
        case .text(let str): return str
        case .valueWithUnit(let v, let u): return "\(v) \(u)"
        case .symbol(let name, _): return name
        case .timeCountdown(let endsAt, let remaining):
            if let r = remaining {
                let s = Int(r)
                return String(format: "%d:%02d", s / 60, s % 60)
            }
            let diff = max(0, Int(endsAt - Date().timeIntervalSince1970))
            return String(format: "%d:%02d", diff / 60, diff % 60)
        case .progressRing(let p, _): return "\(Int(p * 100))%"
        case .waveform: return "Audio"
        case .battery(let lvl, _): return "\(lvl)%"
        case .custom(_, let p): return p.values.first ?? ""
        }
    }
}

public struct ActivityCompactSlots: Codable, Sendable, Equatable {
    public var leading: ActivitySlotContent?
    public var trailing: ActivitySlotContent?

    public init(leading: ActivitySlotContent? = nil, trailing: ActivitySlotContent? = nil) {
        self.leading = leading
        self.trailing = trailing
    }
}

public struct ActivityExpandedSlots: Codable, Sendable, Equatable {
    public var leading: ActivitySlotContent?
    public var trailing: ActivitySlotContent?
    public var center: ActivitySlotContent?
    public var bottom: ActivitySlotContent?

    public init(
        leading: ActivitySlotContent? = nil,
        trailing: ActivitySlotContent? = nil,
        center: ActivitySlotContent? = nil,
        bottom: ActivitySlotContent? = nil
    ) {
        self.leading = leading
        self.trailing = trailing
        self.center = center
        self.bottom = bottom
    }
}

public struct ActivityContent: Codable, Sendable, Equatable {
    public var compact: ActivityCompactSlots?
    public var minimal: ActivitySlotContent?
    public var expanded: ActivityExpandedSlots?

    public init(
        compact: ActivityCompactSlots? = nil,
        minimal: ActivitySlotContent? = nil,
        expanded: ActivityExpandedSlots? = nil
    ) {
        self.compact = compact
        self.minimal = minimal
        self.expanded = expanded
    }
}

public enum ExpandReason: String, Codable, Sendable, Equatable {
    case user
    case alert
}

public enum ActivityPriority {
    public static let background: Int = -10
    public static let standard: Int = 0
    public static let media: Int = 10
    public static let timer: Int = 20
    public static let recording: Int = 50
    public static let alert: Int = 80
    /// Consequential approval card ALWAYS has the highest priority and cannot be superseded.
    public static let consequentialApproval: Int = 9999
}

public struct ActivityOptions: Sendable {
    public var id: String
    public var label: String?
    public var priority: Int
    public var alert: Bool
    public var group: String?
    public var isSensitive: Bool
    public var persistsAcrossRestarts: Bool
    public var content: ActivityContent
    public var onPress: (@Sendable () -> Void)?

    public init(
        id: String,
        label: String? = nil,
        priority: Int = ActivityPriority.standard,
        alert: Bool = false,
        group: String? = nil,
        isSensitive: Bool = false,
        persistsAcrossRestarts: Bool = false,
        content: ActivityContent,
        onPress: (@Sendable () -> Void)? = nil
    ) {
        self.id = id
        self.label = label
        self.priority = priority
        self.alert = alert
        self.group = group
        self.isSensitive = isSensitive
        self.persistsAcrossRestarts = persistsAcrossRestarts
        self.content = content
        self.onPress = onPress
    }
}

public struct ActivityUpdate: Sendable {
    public var compact: ActivityCompactSlots?
    public var minimal: ActivitySlotContent?
    public var expanded: ActivityExpandedSlots?
    public var label: String?
    public var priority: Int?
    public var alert: Bool?
    public var transition: String? // "update" or "crossfade"
    public var onPress: (@Sendable () -> Void)?

    public init(
        compact: ActivityCompactSlots? = nil,
        minimal: ActivitySlotContent? = nil,
        expanded: ActivityExpandedSlots? = nil,
        label: String? = nil,
        priority: Int? = nil,
        alert: Bool? = nil,
        transition: String? = nil,
        onPress: (@Sendable () -> Void)? = nil
    ) {
        self.compact = compact
        self.minimal = minimal
        self.expanded = expanded
        self.label = label
        self.priority = priority
        self.alert = alert
        self.transition = transition
        self.onPress = onPress
    }
}

public struct Activity: Identifiable, Sendable {
    public let id: String
    public var label: String
    public var priority: Int
    public var order: Int
    public var content: ActivityContent
    public var revision: Int
    public var group: String?
    public var isSensitive: Bool
    public var persistsAcrossRestarts: Bool
    public var onPress: (@Sendable () -> Void)?

    public init(
        id: String,
        label: String,
        priority: Int,
        order: Int,
        content: ActivityContent,
        revision: Int = 0,
        group: String? = nil,
        isSensitive: Bool = false,
        persistsAcrossRestarts: Bool = false,
        onPress: (@Sendable () -> Void)? = nil
    ) {
        self.id = id
        self.label = label
        self.priority = priority
        self.order = order
        self.content = content
        self.revision = revision
        self.group = group
        self.isSensitive = isSensitive
        self.persistsAcrossRestarts = persistsAcrossRestarts
        self.onPress = onPress
    }
}

public struct SplitSlots: Codable, Sendable, Equatable {
    public var attached: ActivityCompactSlots
    public var detached: ActivityCompactSlots

    public init(attached: ActivityCompactSlots, detached: ActivityCompactSlots) {
        self.attached = attached
        self.detached = detached
    }
}

public enum IslandPresentation: Equatable, Sendable {
    case idle
    case compact(leading: ActivitySlotContent?, trailing: ActivitySlotContent?)
    case minimal(attached: ActivitySlotContent?, detached: ActivitySlotContent?, split: SplitSlots?)
    case expanded(leading: ActivitySlotContent?, trailing: ActivitySlotContent?, center: ActivitySlotContent?, bottom: ActivitySlotContent?)
}

public struct IslandScene: Equatable, Sendable {
    public var presentation: IslandPresentation
    public var contentKey: String
    public var label: String
    public var primaryId: String?
    public var detachedId: String?

    public init(
        presentation: IslandPresentation,
        contentKey: String,
        label: String,
        primaryId: String? = nil,
        detachedId: String? = nil
    ) {
        self.presentation = presentation
        self.contentKey = contentKey
        self.label = label
        self.primaryId = primaryId
        self.detachedId = detachedId
    }

    public static let idle = IslandScene(
        presentation: .idle,
        contentKey: "idle",
        label: ""
    )
}

public struct PersistentActivityRecord: Codable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var priority: Int
    public var content: ActivityContent
    public var group: String?
    public var isSensitive: Bool
    public var metadata: [String: String]

    public init(
        id: String,
        label: String,
        priority: Int,
        content: ActivityContent,
        group: String? = nil,
        isSensitive: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.label = label
        self.priority = priority
        self.content = content
        self.group = group
        self.isSensitive = isSensitive
        self.metadata = metadata
    }
}
