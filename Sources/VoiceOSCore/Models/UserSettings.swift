import Foundation

public struct UserSettings: Codable, Sendable {
    public var dictationHotkey: String
    public var agentHotkey: String
    public var personaName: String
    public var soundFeedbackEnabled: Bool
    public var handsFreeWakeWord: Bool
    public var ultronModeEnabled: Bool
    public var localWhisperModel: String
    public var cloudProviderFallback: String
    public var telemetryEnabled: Bool

    public static let `default` = UserSettings(
        dictationHotkey: "fn",
        agentHotkey: "command",
        personaName: "Boss",
        soundFeedbackEnabled: true,
        handsFreeWakeWord: false,
        ultronModeEnabled: false,
        localWhisperModel: "base.en",
        cloudProviderFallback: "groq",
        telemetryEnabled: false
    )
}

