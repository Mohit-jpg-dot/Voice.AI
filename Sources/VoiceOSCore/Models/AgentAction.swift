import Foundation
import Combine

public enum VoiceTriggerMode: String, Codable, Sendable {
    case dictation = "Dictation Mode"
    case clipboardDictation = "Clipboard Dictation"
    case agent = "Agent Mode"
    case ask = "Ask Mode"
}

public enum AgentExecutionState: Equatable, Sendable {
    case idle
    case listening(VoiceTriggerMode)
    case transcribing
    case thinking(String)
    case awaitingApproval(AgentAction)
    case executing(String)
    case speaking(String)
    case completed(String)
    case error(String)
}

public struct AgentAction: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let appName: String
    public let appIcon: String
    public let title: String
    public let subtitle: String?
    public var payload: [String: String]
    public let riskLevel: RiskLevel
    public var isApproved: Bool

    public enum RiskLevel: String, Codable, Sendable {
        case low
        case medium
        case high
    }

    public init(
        id: UUID = UUID(),
        appName: String,
        appIcon: String,
        title: String,
        subtitle: String? = nil,
        payload: [String: String] = [:],
        riskLevel: RiskLevel = .medium,
        isApproved: Bool = false
    ) {
        self.id = id
        self.appName = appName
        self.appIcon = appIcon
        self.title = title
        self.subtitle = subtitle
        self.payload = payload
        self.riskLevel = riskLevel
        self.isApproved = isApproved
    }
}

public struct SessionRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let mode: VoiceTriggerMode
    public let prompt: String
    public let response: String
    public let appName: String
    public let appIcon: String
    public let action: AgentAction?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        mode: VoiceTriggerMode,
        prompt: String,
        response: String,
        appName: String = AppBrand.name,
        appIcon: String = "globe",
        action: AgentAction? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mode = mode
        self.prompt = prompt
        self.response = response
        self.appName = appName
        self.appIcon = appIcon
        self.action = action
    }
}

public struct ConnectedApp: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let iconName: String
    public let iconColor: String
    public var isConnected: Bool
    public var category: String

    public init(
        id: String,
        name: String,
        description: String,
        iconName: String,
        iconColor: String,
        isConnected: Bool,
        category: String = "Connected Apps"
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.iconColor = iconColor
        self.isConnected = isConnected
        self.category = category
    }
}

public struct AppUsageStat: Identifiable, Codable, Sendable, Equatable {
    public var id: String { appName }
    public let appName: String
    public let iconName: String
    public let count: Int
    public let percentage: Double

    public init(appName: String, iconName: String, count: Int, percentage: Double) {
        self.appName = appName
        self.iconName = iconName
        self.count = count
        self.percentage = percentage
    }
}

