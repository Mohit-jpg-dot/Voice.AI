import Foundation

public struct ScopedPermissionGrant: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let appName: String
    public let capability: String // e.g. "playback_control", "read_prs", "post_message"
    public let account: String
    public let grantedAt: Date
    public var lastUsedAt: Date
    public let expiryDuration: ExpiryDuration
    public let riskLevel: AgentAction.RiskLevel

    public enum ExpiryDuration: String, Codable, Sendable {
        case once = "Just this once"
        case today = "For today"
        case always = "Always"
    }

    public var isExpired: Bool {
        switch expiryDuration {
        case .once:
            return false // consumed on single use
        case .today:
            let calendar = Calendar.current
            return !calendar.isDateInToday(grantedAt)
        case .always:
            return false
        }
    }

    public init(
        id: UUID = UUID(),
        appName: String,
        capability: String,
        account: String = "primary",
        grantedAt: Date = Date(),
        lastUsedAt: Date = Date(),
        expiryDuration: ExpiryDuration = .always,
        riskLevel: AgentAction.RiskLevel = .low
    ) {
        self.id = id
        self.appName = appName
        self.capability = capability
        self.account = account
        self.grantedAt = grantedAt
        self.lastUsedAt = lastUsedAt
        self.expiryDuration = expiryDuration
        self.riskLevel = riskLevel
    }
}

public final class RememberedPermissionsStore: ObservableObject, @unchecked Sendable {
    public static let shared = RememberedPermissionsStore()

    @Published public var grants: [ScopedPermissionGrant] = [
        ScopedPermissionGrant(
            appName: "Spotify",
            capability: "playback_control",
            account: "jonah@wako.ai",
            expiryDuration: .always,
            riskLevel: .low
        ),
        ScopedPermissionGrant(
            appName: "GitHub",
            capability: "read_prs_and_issues",
            account: "jonahdaian",
            expiryDuration: .always,
            riskLevel: .low
        )
    ]

    public func hasPermission(for app: String, capability: String, risk: AgentAction.RiskLevel) -> Bool {
        guard let grant = grants.first(where: {
            $0.appName.localizedCaseInsensitiveCompare(app) == .orderedSame &&
            $0.capability.localizedCaseInsensitiveCompare(capability) == .orderedSame
        }) else {
            return false
        }

        if grant.isExpired { return false }
        // Rule: A grant never covers a higher-risk action than approved
        if risk == .high && grant.riskLevel != .high { return false }

        return true
    }

    public func grantPermission(app: String, capability: String, duration: ScopedPermissionGrant.ExpiryDuration, risk: AgentAction.RiskLevel) {
        // Remove duplicate if exists
        revokePermission(for: app, capability: capability)
        grants.append(
            ScopedPermissionGrant(
                appName: app,
                capability: capability,
                expiryDuration: duration,
                riskLevel: risk
            )
        )
    }

    public func revokePermission(for app: String, capability: String? = nil) {
        grants.removeAll { grant in
            if let cap = capability {
                return grant.appName.localizedCaseInsensitiveCompare(app) == .orderedSame &&
                       grant.capability.localizedCaseInsensitiveCompare(cap) == .orderedSame
            }
            return grant.appName.localizedCaseInsensitiveCompare(app) == .orderedSame
        }
    }
}

