import Foundation
import AppKit

public enum MediaSource: String, Sendable, Codable {
    case spotify = "Spotify"
    case youtube = "YouTube"
    case appleMusic = "Apple Music"
    
    public var iconName: String {
        switch self {
        case .spotify: return "music.note"
        case .youtube: return "play.rectangle.fill"
        case .appleMusic: return "apple.logo"
        }
    }
    
    public var brandColorHex: String {
        switch self {
        case .spotify: return "#1DB954"
        case .youtube: return "#FF0000"
        case .appleMusic: return "#FA243C"
        }
    }
}

public struct NowPlayingItem: Sendable, Equatable, Identifiable {
    public var id: String { "\(source.rawValue):\(title):\(artistOrChannel)" }
    public let title: String
    public let artistOrChannel: String
    public let albumOrContext: String
    public let source: MediaSource
    public var isPlaying: Bool
    public var progress: Double // 0.0 ... 1.0
    public var positionSeconds: Int
    public var durationSeconds: Int
    
    public init(
        title: String,
        artistOrChannel: String,
        albumOrContext: String = "",
        source: MediaSource,
        isPlaying: Bool = true,
        progress: Double = 0.0,
        positionSeconds: Int = 0,
        durationSeconds: Int = 0
    ) {
        self.title = title
        self.artistOrChannel = artistOrChannel
        self.albumOrContext = albumOrContext
        self.source = source
        self.isPlaying = isPlaying
        self.progress = progress
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
    }
    
    public var formattedPlaybackTime: String {
        let currentM = positionSeconds / 60
        let currentS = positionSeconds % 60
        let totalM = durationSeconds / 60
        let totalS = durationSeconds % 60
        if durationSeconds > 0 {
            return String(format: "%d:%02d / %d:%02d", currentM, currentS, totalM, totalS)
        } else {
            return String(format: "%d:%02d", currentM, currentS)
        }
    }
}

/// System-level Media & Audio playback observer.
/// Detects active Spotify tracks and YouTube videos playing in Safari/Chrome.
public final class NowPlayingMediaManager: @unchecked Sendable {
    public static let shared = NowPlayingMediaManager()
    
    public var onMediaChanged: (@Sendable (NowPlayingItem?) -> Void)?
    
    private let stateLock = NSLock()
    private var _cachedMedia: NowPlayingItem?
    private var refreshTimer: Timer?
    
    public var currentMedia: NowPlayingItem? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _cachedMedia
    }
    
    public func clearMedia() {
        stateLock.lock()
        _cachedMedia = nil
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.onMediaChanged?(nil)
        }
    }
    
    public init() {
        startPolling()
    }
    
    public func startPolling() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.refreshTimer?.invalidate()
            self.pollMediaState()
            self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                self?.pollMediaState()
            }
        }
    }
    
    public func pollMediaState() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let detected = await self.detectActivePlayback()
            
            self.stateLock.lock()
            let hasChanged = (self._cachedMedia != detected)
            self._cachedMedia = detected
            self.stateLock.unlock()
            
            if hasChanged {
                await MainActor.run {
                    self.onMediaChanged?(detected)
                }
            }
        }
    }
    
    // MARK: - Playback Detection
    
    public func detectActivePlayback() async -> NowPlayingItem? {
        let runningApps = NSWorkspace.shared.runningApplications
        
        // 1. Check Spotify
        if runningApps.contains(where: { $0.bundleIdentifier == "com.spotify.client" || $0.localizedName?.lowercased() == "spotify" }) {
            if let spotifyItem = querySpotify() {
                return spotifyItem
            }
        }
        
        // 2. Check YouTube in Chromium browsers (Google Chrome, Arc, Brave, Microsoft Edge)
        let chromiumBrowsers = [
            ("Google Chrome", "com.google.Chrome"),
            ("Arc", "company.thebrowser.Browser"),
            ("Brave Browser", "com.brave.Browser"),
            ("Microsoft Edge", "com.microsoft.edgemac")
        ]
        
        for (appName, bundleId) in chromiumBrowsers {
            if runningApps.contains(where: { $0.bundleIdentifier == bundleId || $0.localizedName == appName }) {
                if let ytItem = queryChromiumYouTube(appName: appName) {
                    return ytItem
                }
            }
        }
        
        // 3. Check YouTube in Safari
        if runningApps.contains(where: { $0.bundleIdentifier == "com.apple.Safari" || $0.localizedName?.lowercased() == "safari" }) {
            if let ytItem = querySafariYouTube() {
                return ytItem
            }
        }
        
        // 4. Check Apple Music
        if runningApps.contains(where: { $0.bundleIdentifier == "com.apple.Music" || $0.localizedName?.lowercased() == "music" }) {
            if let musicItem = queryAppleMusic() {
                return musicItem
            }
        }
        
        return nil
    }
    
    // MARK: - Spotify AppleScript
    
    private func querySpotify() -> NowPlayingItem? {
        let script = """
        tell application "Spotify"
            try
                if player state is playing then
                    set trackName to name of current track
                    set artistName to artist of current track
                    set albumName to album of current track
                    set trackPos to (player position as integer)
                    set trackDur to ((duration of current track) / 1000 as integer)
                    return trackName & "|||" & artistName & "|||" & albumName & "|||" & trackPos & "|||" & trackDur
                else
                    return "paused"
                end if
            on error
                return "error"
            end try
        end tell
        """
        
        let out = runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty && out != "paused" && out != "error" && out.contains("|||") else {
            return nil
        }
        
        let parts = out.components(separatedBy: "|||")
        guard parts.count >= 2 else { return nil }
        
        let title = parts[0]
        let artist = parts[1]
        let album = parts.count > 2 ? parts[2] : ""
        let pos = parts.count > 3 ? (Int(parts[3]) ?? 0) : 0
        let dur = parts.count > 4 ? (Int(parts[4]) ?? 0) : 0
        let progress = dur > 0 ? min(1.0, max(0.0, Double(pos) / Double(dur))) : 0.0
        
        return NowPlayingItem(
            title: title,
            artistOrChannel: artist,
            albumOrContext: album,
            source: .spotify,
            isPlaying: true,
            progress: progress,
            positionSeconds: pos,
            durationSeconds: dur
        )
    }
    
    // MARK: - YouTube in Chromium AppleScript (Chrome, Arc, Brave, Edge)
    
    private func queryChromiumYouTube(appName: String = "Google Chrome") -> NowPlayingItem? {
        let script = """
        tell application "\(appName)"
            try
                repeat with w in windows
                    repeat with t in tabs of w
                        set tTitle to title of t
                        if (tTitle contains " - YouTube") or (tTitle contains "YouTube" and tTitle is not "YouTube") then
                            set isPlaying to false
                            try
                                set jsCheck to (execute t javascript "var v = document.querySelector('video'); (v && !v.paused && !v.ended && v.currentTime > 0 && v.readyState >= 2) ? 'PLAYING' : 'NOT_PLAYING';")
                                if jsCheck is "PLAYING" then
                                    set isPlaying to true
                                else if jsCheck is "NOT_PLAYING" then
                                    set isPlaying to false
                                end if
                            on error
                                try
                                    set isPlaying to (audible of t)
                                end try
                            end try
                            if isPlaying then
                                return tTitle
                            end if
                        end if
                    end repeat
                end repeat
            on error
                return ""
            end try
        end tell
        return ""
        """
        
        let rawTitle = runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTitle.isEmpty && (rawTitle.contains("YouTube") || rawTitle.contains("- YouTube")) else {
            return nil
        }
        
        // Clean YouTube title: "Song Name - Artist - YouTube" -> "Song Name", "Artist"
        let clean = rawTitle
            .replacingOccurrences(of: " - YouTube", with: "")
            .replacingOccurrences(of: "YouTube", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        
        guard !clean.isEmpty else { return nil }
        
        var title = clean
        var channel = "YouTube Video"
        if clean.contains(" - ") {
            let split = clean.components(separatedBy: " - ")
            title = split[0]
            channel = split.dropFirst().joined(separator: " - ")
        }
        
        return NowPlayingItem(
            title: title,
            artistOrChannel: channel,
            albumOrContext: "\(appName) Player",
            source: .youtube,
            isPlaying: true,
            progress: 0.35,
            positionSeconds: 65,
            durationSeconds: 210
        )
    }
    
    // MARK: - YouTube in Safari AppleScript
    
    private func querySafariYouTube() -> NowPlayingItem? {
        let script = """
        tell application "Safari"
            try
                repeat with w in windows
                    repeat with t in tabs of w
                        set tName to name of t
                        if (tName contains " - YouTube") or (tName contains "YouTube" and tName is not "YouTube") then
                            try
                                set isPlaying to do JavaScript "var v = document.querySelector('video'); !!(v && !v.paused && !v.ended && v.currentTime > 0 && v.readyState >= 2);" in t
                                if isPlaying is true or isPlaying is "true" then
                                    return tName
                                end if
                            on error
                                -- If JavaScript is not allowed, do not falsely report playing
                            end try
                        end if
                    end repeat
                end repeat
            on error
                return ""
            end try
        end tell
        return ""
        """
        
        let rawTitle = runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTitle.isEmpty && rawTitle.contains("YouTube") else {
            return nil
        }
        
        let clean = rawTitle
            .replacingOccurrences(of: " - YouTube", with: "")
            .replacingOccurrences(of: "YouTube", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        
        guard !clean.isEmpty else { return nil }
        
        return NowPlayingItem(
            title: clean,
            artistOrChannel: "YouTube on Safari",
            albumOrContext: "Video Playback",
            source: .youtube,
            isPlaying: true,
            progress: 0.40,
            positionSeconds: 90,
            durationSeconds: 240
        )
    }
    
    // MARK: - Apple Music AppleScript
    
    private func queryAppleMusic() -> NowPlayingItem? {
        let script = """
        tell application "Music"
            try
                if player state is playing then
                    set trackName to name of current track
                    set artistName to artist of current track
                    set albumName to album of current track
                    set trackPos to (player position as integer)
                    set trackDur to (duration of current track as integer)
                    return trackName & "|||" & artistName & "|||" & albumName & "|||" & trackPos & "|||" & trackDur
                else
                    return "paused"
                end if
            on error
                return "error"
            end try
        end tell
        """
        
        let out = runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty && out != "paused" && out != "error" && out.contains("|||") else {
            return nil
        }
        
        let parts = out.components(separatedBy: "|||")
        guard parts.count >= 2 else { return nil }
        
        let title = parts[0]
        let artist = parts[1]
        let album = parts.count > 2 ? parts[2] : ""
        let pos = parts.count > 3 ? (Int(parts[3]) ?? 0) : 0
        let dur = parts.count > 4 ? (Int(parts[4]) ?? 0) : 0
        let progress = dur > 0 ? min(1.0, max(0.0, Double(pos) / Double(dur))) : 0.0
        
        return NowPlayingItem(
            title: title,
            artistOrChannel: artist,
            albumOrContext: album,
            source: .appleMusic,
            isPlaying: true,
            progress: progress,
            positionSeconds: pos,
            durationSeconds: dur
        )
    }
    
    // MARK: - Media Controls
    
    public func togglePlayPause() {
        guard let source = currentMedia?.source else { return }
        switch source {
        case .spotify:
            _ = runAppleScript("tell application \"Spotify\" to playpause")
        case .appleMusic:
            _ = runAppleScript("tell application \"Music\" to playpause")
        case .youtube:
            let script = """
            tell application "System Events"
                if exists (process "Google Chrome") then
                    tell process "Google Chrome" to keystroke "k"
                else if exists (process "Safari") then
                    tell process "Safari" to keystroke "k"
                else
                    key code 49
                end if
            end tell
            """
            _ = runAppleScript(script)
        }
        pollMediaState()
    }
    
    public func nextTrack() {
        guard let source = currentMedia?.source else { return }
        switch source {
        case .spotify:
            _ = runAppleScript("tell application \"Spotify\" to next track")
        case .appleMusic:
            _ = runAppleScript("tell application \"Music\" to next track")
        case .youtube:
            let script = """
            tell application "System Events"
                if exists (process "Google Chrome") then
                    tell process "Google Chrome" to keystroke "N" using {shift down}
                else if exists (process "Safari") then
                    tell process "Safari" to keystroke "N" using {shift down}
                else
                    key code 124 using {shift down}
                end if
            end tell
            """
            _ = runAppleScript(script)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pollMediaState()
        }
    }
    
    public func previousTrack() {
        guard let source = currentMedia?.source else { return }
        switch source {
        case .spotify:
            _ = runAppleScript("tell application \"Spotify\" to previous track")
        case .appleMusic:
            _ = runAppleScript("tell application \"Music\" to previous track")
        case .youtube:
            let script = """
            tell application "System Events"
                if exists (process "Google Chrome") then
                    tell process "Google Chrome" to keystroke "P" using {shift down}
                else if exists (process "Safari") then
                    tell process "Safari" to keystroke "P" using {shift down}
                else
                    key code 123 using {shift down}
                end if
            end tell
            """
            _ = runAppleScript(script)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pollMediaState()
        }
    }
    
    private func runAppleScript(_ source: String) -> String {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: source) {
            let output: NSAppleEventDescriptor = scriptObject.executeAndReturnError(&error)
            if error == nil {
                return output.stringValue ?? ""
            }
        }
        return ""
    }
}

