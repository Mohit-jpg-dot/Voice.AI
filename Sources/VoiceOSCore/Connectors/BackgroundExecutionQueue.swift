import Foundation

public struct BackgroundExecutionResult: Sendable {
    public let appName: String
    public let actionSummary: String
    public let deepLinkURL: String
    public let elapsedSeconds: Double
    public let spokenReport: String
    public let isSuccess: Bool

    public init(
        appName: String,
        actionSummary: String,
        deepLinkURL: String,
        elapsedSeconds: Double,
        spokenReport: String,
        isSuccess: Bool = true
    ) {
        self.appName = appName
        self.actionSummary = actionSummary
        self.deepLinkURL = deepLinkURL
        self.elapsedSeconds = elapsedSeconds
        self.spokenReport = spokenReport
        self.isSuccess = isSuccess
    }
}

public final class BackgroundExecutionQueue: Sendable {
    public static let shared = BackgroundExecutionQueue()

    public func executeTask(intent: ParsedIntent, completion: @escaping @Sendable (BackgroundExecutionResult) -> Void) {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Background worker thread execution (no main actor blocking)
        DispatchQueue.global(qos: .userInitiated).async {
            // Realistic API latency simulation (1.2s - 2.4s)
            Thread.sleep(forTimeInterval: 1.4)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let formattedElapsed = String(format: "%.1f", elapsed)

            var summary = ""
            var deepLink = ""
            var spoken = ""

            switch intent.app.lowercased() {
            case "spotify":
                summary = "Playing Chill Vibes Playlist on Spotify"
                deepLink = "spotify:playlist:chill"
                spoken = "Ho gaya, Boss. Spotify pe playlist laga di hai. \(formattedElapsed) seconds."
            case "slack":
                summary = "Sent update to #team on Slack: \"meeting late hai\""
                deepLink = "slack://channel?team=T01&id=C01"
                spoken = "Ho gaya, Boss. Team ko message bhej diya hai. \(formattedElapsed) seconds."
            case "github":
                summary = "Fetched 3 open pull requests on \(AppBrand.name)"
                deepLink = "https://github.com/voiceai/agent/pulls"
                spoken = "Boss, 3 open PRs hain. Review ke liye ready hain. \(formattedElapsed) seconds."
            case "apple notes":
                summary = "Appended quick note to Apple Notes"
                deepLink = "notes://notes"
                spoken = "Notes mein save kar diya, Boss. \(formattedElapsed) seconds."
            case "search":
                summary = "Searched web with live sources for: \"\(intent.target)\""
                deepLink = "https://google.com/search?q=\(intent.target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                spoken = "Boss, search complete. Top verified sources loaded. \(formattedElapsed) seconds."
            default:
                summary = "Task executed: \(intent.rawQuery)"
                deepLink = "voiceos://task/completed"
                spoken = "Ho gaya, Boss. Task completed in \(formattedElapsed) seconds."
            }

            let result = BackgroundExecutionResult(
                appName: intent.app,
                actionSummary: summary,
                deepLinkURL: deepLink,
                elapsedSeconds: elapsed,
                spokenReport: spoken,
                isSuccess: true
            )

            completion(result)
        }
    }
}

