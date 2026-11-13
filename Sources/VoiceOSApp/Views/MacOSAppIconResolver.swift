import AppKit
import Foundation
import SwiftUI

// MARK: - Native macOS App Icon & Resolution Engine

public enum MacOSAppIconResolver {
    /// Canonical local paths for macOS native applications
    private static let knownAppPathsByKey: [String: [String]] = [
        "mail": [
            "/System/Applications/Mail.app"
        ],
        "apple mail": [
            "/System/Applications/Mail.app"
        ],
        "email": [
            "/System/Applications/Mail.app"
        ],
        "whatsapp": [
            "/Applications/WhatsApp.app"
        ],
        "messages": [
            "/System/Applications/Messages.app"
        ],
        "imessage": [
            "/System/Applications/Messages.app"
        ],
        "notes": [
            "/System/Applications/Notes.app"
        ],
        "apple notes": [
            "/System/Applications/Notes.app"
        ],
        "reminders": [
            "/System/Applications/Reminders.app"
        ],
        "calendar": [
            "/System/Applications/Calendar.app"
        ],
        "apple calendar": [
            "/System/Applications/Calendar.app"
        ],
        "music": [
            "/System/Applications/Music.app"
        ],
        "apple music": [
            "/System/Applications/Music.app"
        ],
        "finder": [
            "/System/Library/CoreServices/Finder.app"
        ],
        "terminal": [
            "/System/Applications/Utilities/Terminal.app"
        ],
        "safari": [
            "/Applications/Safari.app",
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"
        ],
        "chrome": [
            "/Applications/Google Chrome.app"
        ],
        "google chrome": [
            "/Applications/Google Chrome.app"
        ],
        "spotify": [
            "/Applications/Spotify.app"
        ],
        "vscode": [
            "/Applications/Visual Studio Code.app"
        ],
        "vs code": [
            "/Applications/Visual Studio Code.app"
        ],
        "visual studio code": [
            "/Applications/Visual Studio Code.app"
        ],
        "codex": [
            "/Applications/Visual Studio Code.app"
        ],
        "slack": [
            "/Applications/Slack.app"
        ],
        "discord": [
            "/Applications/Discord.app"
        ],
        "notion": [
            "/Applications/Notion.app"
        ],
        "linear": [
            "/Applications/Linear.app"
        ],
        "jira": [
            "/Applications/Jira.app"
        ],
        "outlook": [
            "/Applications/Microsoft Outlook.app"
        ],
        "obsidian": [
            "/Applications/Obsidian.app"
        ]
    ]

    private static let bundleIdsByAppKey: [String: [String]] = [
        "mail": ["com.apple.mail"],
        "apple mail": ["com.apple.mail"],
        "whatsapp": ["net.whatsapp.WhatsApp"],
        "slack": ["com.tinyspeck.slackmacgap"],
        "discord": ["com.hnc.Discord"],
        "notion": ["notion.id"],
        "spotify": ["com.spotify.client"],
        "apple music": ["com.apple.Music"],
        "music": ["com.apple.Music"],
        "imessage": ["com.apple.MobileSMS"],
        "messages": ["com.apple.MobileSMS"],
        "reminders": ["com.apple.reminders"],
        "finder": ["com.apple.finder"],
        "notes": ["com.apple.Notes"],
        "apple notes": ["com.apple.Notes"],
        "apple calendar": ["com.apple.iCal"],
        "calendar": ["com.apple.iCal"],
        "safari": ["com.apple.Safari"],
        "chrome": ["com.google.Chrome"],
        "google chrome": ["com.google.Chrome"],
        "terminal": ["com.apple.Terminal"],
        "vscode": ["com.microsoft.VSCode"],
        "vs code": ["com.microsoft.VSCode"],
        "codex": ["com.openai.codex", "com.microsoft.VSCode"],
        "outlook": ["com.microsoft.Outlook"],
        "linear": ["com.linear"],
        "youtube": ["com.google.Chrome.app.youtube"]
    ]

    public static func applicationURL(for nameOrKey: String) -> URL? {
        let lower = nameOrKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 1. Direct check against known canonical file paths
        if let paths = knownAppPathsByKey[lower] {
            for path in paths where FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // 2. Candidate paths in macOS application directories
        let cleanName = nameOrKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            cleanName,
            cleanName.capitalized,
            lower.capitalized
        ]
        
        let searchRoots = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices",
            "\(NSHomeDirectory())/Applications"
        ]

        for root in searchRoots {
            for cand in candidates {
                let fullPath = "\(root)/\(cand).app"
                if FileManager.default.fileExists(atPath: fullPath) {
                    return URL(fileURLWithPath: fullPath)
                }
            }
        }

        // 3. Fallback to NSWorkspace bundle identifier lookup if accessible
        if let ids = bundleIdsByAppKey[lower] {
            for bid in ids {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                    return url
                }
            }
        }

        return nil
    }

    public static func icon(for nameOrKey: String) -> NSImage? {
        guard let url = applicationURL(for: nameOrKey) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    public static func isInstalled(nameOrKey: String) -> Bool {
        applicationURL(for: nameOrKey) != nil
    }
}

// MARK: - Authentic App Icon & Brand Artwork View

public struct AppTileIconView: View {
    public let appKey: String
    public let appName: String
    public let size: CGFloat
    
    public init(appKey: String, appName: String, size: CGFloat = 38) {
        self.appKey = appKey
        self.appName = appName
        self.size = size
    }
    
    private var normalizedKey: String {
        let key = appKey.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if key.contains("mail") || key.contains("email") { return "mail" }
        if key.contains("whatsapp") { return "whatsapp" }
        if key.contains("slack") { return "slack" }
        if key.contains("discord") { return "discord" }
        if key.contains("youtube") { return "youtube" }
        if key.contains("notion") { return "notion" }
        if key.contains("spotify") { return "spotify" }
        if key.contains("notes") { return "notes" }
        if key.contains("music") { return "music" }
        if key.contains("messages") || key.contains("imessage") { return "messages" }
        if key.contains("calendar") { return key.contains("google") ? "google_cal" : "calendar" }
        if key.contains("maps") { return "google_maps" }
        if key.contains("drive") { return "google_drive" }
        if key.contains("linear") { return "linear" }
        if key.contains("jira") { return "jira" }
        if key.contains("outlook") { return "outlook" }
        if key.contains("terminal") { return "terminal" }
        if key.contains("vscode") || key.contains("codex") { return "vscode" }
        if key.contains("reminders") { return "reminders" }
        if key.contains("finder") { return "finder" }
        return key
    }

    public var body: some View {
        Group {
            // 1. If native macOS application is installed, display its authentic OS icon
            if let nsIcon = MacOSAppIconResolver.icon(for: appKey) ?? MacOSAppIconResolver.icon(for: appName) {
                Image(nsImage: nsIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .shadow(color: Color.black.opacity(0.20), radius: 3, x: 0, y: 1.5)
            } else {
                // 2. High-fidelity authentic brand vector tile for cloud/web services
                authenticBrandTile(for: normalizedKey)
            }
        }
    }

    @ViewBuilder
    private func authenticBrandTile(for key: String) -> some View {
        let cornerRadius = size * 0.22
        switch key {
        case "slack":
            // Slack authentic 4-color petals on aubergine
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.29, green: 0.08, blue: 0.31))
                    .frame(width: size, height: size)
                
                // 4-color Slack hashtag emblem
                VStack(spacing: size * 0.06) {
                    HStack(spacing: size * 0.06) {
                        Capsule().fill(Color(red: 0.22, green: 0.72, blue: 0.58)).frame(width: size * 0.20, height: size * 0.10)
                        Capsule().fill(Color(red: 0.94, green: 0.69, blue: 0.16)).frame(width: size * 0.10, height: size * 0.20)
                    }
                    HStack(spacing: size * 0.06) {
                        Capsule().fill(Color(red: 0.89, green: 0.15, blue: 0.38)).frame(width: size * 0.10, height: size * 0.20)
                        Capsule().fill(Color(red: 0.21, green: 0.66, blue: 0.94)).frame(width: size * 0.20, height: size * 0.10)
                    }
                }
            }
            .shadow(color: Color(red: 0.29, green: 0.08, blue: 0.31).opacity(0.4), radius: 3, x: 0, y: 1.5)

        case "discord":
            // Discord Blurple (#5865F2) with white game controller face
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.35, green: 0.40, blue: 0.95))
                    .frame(width: size, height: size)
                
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(color: Color(red: 0.35, green: 0.40, blue: 0.95).opacity(0.35), radius: 3, x: 0, y: 1.5)

        case "notion":
            // Notion clean white tile with black border and bold 'N'
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white)
                    .frame(width: size, height: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                
                Text("N")
                    .font(.system(size: size * 0.56, weight: .black, design: .serif))
                    .foregroundColor(Color.black)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1.5)

        case "youtube":
            // YouTube vibrant red (#FF0000) tile with white play button
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.0, blue: 0.0))
                    .frame(width: size, height: size)
                
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundColor(.white)
            }
            .shadow(color: Color.red.opacity(0.35), radius: 3, x: 0, y: 1.5)

        case "google_drive", "drive":
            // Google Drive authentic tri-color geometric triangle
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white)
                    .frame(width: size, height: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                    )
                
                Image(systemName: "triangle.fill")
                    .font(.system(size: size * 0.50, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.95, green: 0.75, blue: 0.15), Color(red: 0.22, green: 0.72, blue: 0.38), Color(red: 0.16, green: 0.54, blue: 0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1.5)

        case "google_cal":
            // Google Calendar white tile with blue header and '31'
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white)
                    .frame(width: size, height: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                    )
                
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.16, green: 0.54, blue: 0.95))
                        .frame(width: size * 0.65, height: size * 0.18)
                    
                    Text("\(Calendar.current.component(.day, from: Date()))")
                        .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.18))
                        .offset(y: -1)
                }
            }
            .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1.5)

        case "google_maps":
            // Google Maps clean location marker tile
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white)
                    .frame(width: size, height: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                    )
                
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: size * 0.56, weight: .bold))
                    .foregroundStyle(Color(red: 0.92, green: 0.26, blue: 0.21))
            }
            .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1.5)

        case "linear":
            // Linear deep indigo tile with concentric circle logo
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.37, green: 0.42, blue: 0.88))
                    .frame(width: size, height: size)
                
                Image(systemName: "circle.circle")
                    .font(.system(size: size * 0.50, weight: .bold))
                    .foregroundColor(.white)
            }
            .shadow(color: Color(red: 0.37, green: 0.42, blue: 0.88).opacity(0.35), radius: 3, x: 0, y: 1.5)

        case "jira":
            // Jira Atlassian blue tile with diamond wings
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.00, green: 0.32, blue: 0.80))
                    .frame(width: size, height: size)
                
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: size * 0.50, weight: .bold))
                    .foregroundColor(.white)
            }
            .shadow(color: Color(red: 0.00, green: 0.32, blue: 0.80).opacity(0.35), radius: 3, x: 0, y: 1.5)

        case "outlook":
            // Microsoft Outlook clean blue tile
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.00, green: 0.47, blue: 0.83))
                    .frame(width: size, height: size)
                
                Image(systemName: "envelope.fill")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundColor(.white)
            }
            .shadow(color: Color(red: 0.00, green: 0.47, blue: 0.83).opacity(0.35), radius: 3, x: 0, y: 1.5)

        case "whatsapp":
            // WhatsApp vibrant green with white phone receiver
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.15, green: 0.83, blue: 0.40))
                    .frame(width: size, height: size)
                
                Image(systemName: "phone.fill")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundColor(.white)
            }
            .shadow(color: Color(red: 0.15, green: 0.83, blue: 0.40).opacity(0.35), radius: 3, x: 0, y: 1.5)

        default:
            // High-quality fallback tile with rounded gradient
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.16, green: 0.18, blue: 0.22))
                    .frame(width: size, height: size)
                
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            .shadow(color: Color.black.opacity(0.20), radius: 3, x: 0, y: 1.5)
        }
    }
}
