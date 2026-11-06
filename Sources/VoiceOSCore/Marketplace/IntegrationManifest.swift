import Foundation

/// Authentication mechanism used by an integration
public enum IntegrationAuthType: String, Codable, Sendable {
    case oauth2 = "oauth2"
    case apiKey = "api_key"
    case appIntent = "app_intent"
    case appleScript = "apple_script"
    case mcp = "mcp"
    case custom = "custom"
}

/// Verification badge indicating security and testing tier
public enum VerificationBadge: String, Codable, Sendable {
    case verifiedByVoiceAI = "Verified by Voice.AI"
    case community = "Community"
    case customMCP = "Custom MCP"
}

/// Category classification
public enum IntegrationCategory: String, Codable, Sendable, CaseIterable {
    case productivity = "Productivity"
    case developer = "Developer"
    case communication = "Communication"
    case ai = "AI"
    case musicAndMedia = "Music & Media"
    case notesAndKnowledge = "Notes & Knowledge"
    case utilities = "Utilities"
}

/// Supported operating systems
public enum IntegrationPlatform: String, Codable, Sendable {
    case macOS = "macOS"
    case windows = "Windows"
    case web = "Web"
}

/// Minimal permission scope requested by an integration
public struct PermissionScope: Codable, Sendable, Equatable {
    public let scope: String
    public let justification: String

    public init(scope: String, justification: String) {
        self.scope = scope
        self.justification = justification
    }
}

/// Action declared in an integration manifest
public struct ManifestAction: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let riskLevel: ActionRiskLevel
    public let parameters: [String: String]
    public let returnType: String

    public enum ActionRiskLevel: String, Codable, Sendable {
        case readOnly = "Read-Only"
        case reversible = "Reversible"
        case consequential = "Consequential (Requires Approval)"
    }

    public init(
        id: String,
        name: String,
        description: String,
        riskLevel: ActionRiskLevel,
        parameters: [String: String] = [:],
        returnType: String = "Void"
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.riskLevel = riskLevel
        self.parameters = parameters
        self.returnType = returnType
    }
}

/// Strongly-typed integration manifest conforming to VoiceOS App Store specifications
public struct IntegrationManifest: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let publisher: String
    public let version: String
    public let icon: String
    public let summary: String
    public let categories: [IntegrationCategory]
    public let authType: IntegrationAuthType
    public let permissionsRequired: [PermissionScope]
    public let actions: [ManifestAction]
    public let verificationBadge: VerificationBadge
    public let deepLinkTemplate: String
    public let platformSupport: [IntegrationPlatform]

    public init(
        id: String,
        name: String,
        publisher: String,
        version: String,
        icon: String,
        summary: String,
        categories: [IntegrationCategory],
        authType: IntegrationAuthType,
        permissionsRequired: [PermissionScope],
        actions: [ManifestAction],
        verificationBadge: VerificationBadge,
        deepLinkTemplate: String,
        platformSupport: [IntegrationPlatform]
    ) {
        self.id = id
        self.name = name
        self.publisher = publisher
        self.version = version
        self.icon = icon
        self.summary = summary
        self.categories = categories
        self.authType = authType
        self.permissionsRequired = permissionsRequired
        self.actions = actions
        self.verificationBadge = verificationBadge
        self.deepLinkTemplate = deepLinkTemplate
        self.platformSupport = platformSupport
    }
}

