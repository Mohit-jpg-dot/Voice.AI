import Foundation

/// Execution permission tiers governing human-in-the-loop safety across ToolRegistry & Approval Card UI.
public enum PermissionTier: String, Codable, Sendable, Comparable {
    /// Non-mutating reads and pure computation — executes immediately without approval.
    case readOnly = "READ_ONLY"
    /// Local or easily undone state changes — executes with soft confirmation feedback.
    case reversible = "REVERSIBLE"
    /// External communication, destructive shell/file ops, or security actions — requires explicit Approval Card in the notch.
    case consequential = "CONSEQUENTIAL"

    private var sortOrder: Int {
        switch self {
        case .readOnly: return 0
        case .reversible: return 1
        case .consequential: return 2
        }
    }

    public static func < (lhs: PermissionTier, rhs: PermissionTier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    public var agentRiskLevel: AgentAction.RiskLevel {
        switch self {
        case .readOnly: return .low
        case .reversible: return .medium
        case .consequential: return .high
        }
    }

    public var manifestRiskLevel: ManifestAction.ActionRiskLevel {
        switch self {
        case .readOnly: return .readOnly
        case .reversible: return .reversible
        case .consequential: return .consequential
        }
    }

    public init(from manifestRisk: ManifestAction.ActionRiskLevel) {
        switch manifestRisk {
        case .readOnly: self = .readOnly
        case .reversible: self = .reversible
        case .consequential: self = .consequential
        }
    }

    public init(from riskLevel: AgentAction.RiskLevel) {
        switch riskLevel {
        case .low: self = .readOnly
        case .medium: self = .reversible
        case .high: self = .consequential
        }
    }
}

