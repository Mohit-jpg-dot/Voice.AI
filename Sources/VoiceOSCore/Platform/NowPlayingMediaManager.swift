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
    public var artworkUrl: String
    
    public init(
        title: String,
        artistOrChannel: String,
        albumOrContext: String = "",
        source: MediaSource,
        isPlaying: Bool = true,
        progress: Double = 0.0,
        positionSeconds: Int = 0,
        durationSeconds: Int = 0,
        artworkUrl: String = ""
    ) {
        self.title = title
        self.artistOrChannel = artistOrChannel
        self.albumOrContext = albumOrContext
        self.source = source
        self.isPlaying = isPlaying
        self.progress = progress
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.artworkUrl = artworkUrl
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
        if ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1" {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.refreshTimer?.invalidate()
            self.pollMediaState()
            self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.pollMediaState()
            }
        }
    }
    
    public func pollMediaState() {
        if ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1" {
            return
        }
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

        // 5. Check macOS System MediaRemote (covers all media playback)
        if let systemItem = querySystemNowPlaying() {
            return systemItem
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
                    set artUrl to ""
                    try
                        set artUrl to artwork url of current track
                    end try
                    return trackName & "|||" & artistName & "|||" & albumName & "|||" & trackPos & "|||" & trackDur & "|||" & artUrl
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
        let art = parts.count > 5 ? parts[5] : ""
        let progress = dur > 0 ? min(1.0, max(0.0, Double(pos) / Double(dur))) : 0.0
        
        return NowPlayingItem(
            title: title,
            artistOrChannel: artist,
            albumOrContext: album,
            source: .spotify,
            isPlaying: true,
            progress: progress,
            positionSeconds: pos,
            durationSeconds: dur,
            artworkUrl: art
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
                        set tURL to URL of t
                        if (tURL contains "youtube.com/watch") or (tURL contains "music.youtube.com") or (tTitle contains "YouTube") then
                            set jsCheck to "NOT_PLAYING"
                            try
                                set jsCheck to (execute t javascript "var v = document.querySelector('video'); (v && !v.paused && !v.ended && v.currentTime > 0) ? (Math.floor(v.currentTime || 0) + '|||' + Math.floor(v.duration || 0) + '|||' + (new URLSearchParams(window.location.search).get('v') || '')) : 'NOT_PLAYING';")
                            end try
                            if jsCheck is not "NOT_PLAYING" and jsCheck contains "|||" then
                                return tTitle & "|||" & jsCheck & "|||" & tURL
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
        
        let rawPayload = runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPayload.isEmpty else {
            return nil
        }
        let metaParts = rawPayload.components(separatedBy: "|||")
        let rawTitle = metaParts.first ?? rawPayload
        
        var pos = metaParts.count > 1 ? (Int(metaParts[1]) ?? 0) : 0
        var dur = metaParts.count > 2 ? (Int(metaParts[2]) ?? 0) : 0
        var ytId = metaParts.count > 3 ? metaParts[3] : ""
        let tabUrl = metaParts.count > 4 ? metaParts[4] : ""
        
        // Extract YouTube ID from URL if JS didn't return it
        if ytId.isEmpty && !tabUrl.isEmpty {
            if let urlComponents = URLComponents(string: tabUrl),
               let vItem = urlComponents.queryItems?.first(where: { $0.name == "v" })?.value {
                ytId = vItem
            }
        }
        
        let artUrl = ytId.isEmpty ? "" : "https://img.youtube.com/vi/\(ytId)/mqdefault.jpg"
        let progress = dur > 0 ? min(1.0, max(0.0, Double(pos) / Double(dur))) : 0.0
        
        // Clean notification counts from title: e.g. "(677) Video Title - YouTube" -> "Video Title"
        var clean = rawTitle
        if let regex = try? NSRegularExpression(pattern: "^\\(\\d+\\)\\s*") {
            clean = regex.stringByReplacingMatches(in: clean, range: NSRange(location: 0, length: clean.utf16.count), withTemplate: "")
        }
        clean = clean
            .replacingOccurrences(of: " - YouTube Music", with: "")
            .replacingOccurrences(of: " - YouTube", with: "")
            .replacingOccurrences(of: "YouTube", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        
        guard !clean.isEmpty else { return nil }
        
        var title = clean
        var channel = "YouTube Video"
        if clean.contains(" - ") {
            let split = clean.components(separatedBy: " - ")
            title = split[0].trimmingCharacters(in: .whitespacesAndNewlines)
            channel = split.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return NowPlayingItem(
            title: title,
            artistOrChannel: channel,
            albumOrContext: "\(appName) Player",
            source: .youtube,
            isPlaying: true,
            progress: progress,
            positionSeconds: pos,
            durationSeconds: dur,
            artworkUrl: artUrl
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
                        set tURL to URL of t
                        if (tURL contains "youtube.com/watch") or (tURL contains "music.youtube.com") or (tName contains "YouTube") then
                            set jsOut to "NOT_PLAYING"
                            try
                                set jsOut to do JavaScript "var v = document.querySelector('video'); (v && !v.paused && !v.ended && v.currentTime > 0) ? (Math.floor(v.currentTime || 0) + '|||' + Math.floor(v.duration || 0) + '|||' + (new URLSearchParams(window.location.search).get('v') || '')) : 'NOT_PLAYING';" in t
                            end try
                            if jsOut is not "NOT_PLAYING" and jsOut contains "|||" then
                                return tName & "|||" & jsOut & "|||" & tURL
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
        
        let rawPayload = runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPayload.isEmpty else {
            return nil
        }
        let metaParts = rawPayload.components(separatedBy: "|||")
        let rawTitle = metaParts.first ?? rawPayload
        
        var pos = metaParts.count > 1 ? (Int(metaParts[1]) ?? 0) : 0
        var dur = metaParts.count > 2 ? (Int(metaParts[2]) ?? 0) : 0
        var ytId = metaParts.count > 3 ? metaParts[3] : ""
        let tabUrl = metaParts.count > 4 ? metaParts[4] : ""
        
        if ytId.isEmpty && !tabUrl.isEmpty {
            if let urlComponents = URLComponents(string: tabUrl),
               let vItem = urlComponents.queryItems?.first(where: { $0.name == "v" })?.value {
                ytId = vItem
            }
        }
        
        let artUrl = ytId.isEmpty ? "" : "https://img.youtube.com/vi/\(ytId)/mqdefault.jpg"
        let progress = dur > 0 ? min(1.0, max(0.0, Double(pos) / Double(dur))) : 0.0
        
        var clean = rawTitle
        if let regex = try? NSRegularExpression(pattern: "^\\(\\d+\\)\\s*") {
            clean = regex.stringByReplacingMatches(in: clean, range: NSRange(location: 0, length: clean.utf16.count), withTemplate: "")
        }
        clean = clean
            .replacingOccurrences(of: " - YouTube Music", with: "")
            .replacingOccurrences(of: " - YouTube", with: "")
            .replacingOccurrences(of: "YouTube", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        
        guard !clean.isEmpty else { return nil }
        
        var title = clean
        var channel = "YouTube on Safari"
        if clean.contains(" - ") {
            let split = clean.components(separatedBy: " - ")
            title = split[0].trimmingCharacters(in: .whitespacesAndNewlines)
            channel = split.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return NowPlayingItem(
            title: title,
            artistOrChannel: channel,
            albumOrContext: "Video Playback",
            source: .youtube,
            isPlaying: true,
            progress: progress,
            positionSeconds: pos,
            durationSeconds: dur,
            artworkUrl: artUrl
        )
    }

    // MARK: - System MediaRemote Dynamic Query (Chrome, Safari, Spotify, YouTube, Podcasts)
    private func querySystemNowPlaying() -> NowPlayingItem? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            return nil
        }
        defer { dlclose(handle) }

        typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
        guard let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
            return nil
        }
        let getInfo = unsafeBitCast(sym, to: GetNowPlayingInfo.self)

        let sema = DispatchSemaphore(value: 0)
        var resultItem: NowPlayingItem?

        getInfo(DispatchQueue.global(qos: .userInitiated)) { dict in
            defer { sema.signal() }
            guard let dict = dict else { return }
            
            let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            guard !title.isEmpty else { return }

            let artist = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            let album = dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            let elapsed = dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0.0
            let duration = dict["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0.0
            let rate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0.0
            guard rate > 0.05 else { return }

            let progress = duration > 0 ? min(1.0, max(0.0, elapsed / duration)) : 0.0

            let source: MediaSource
            let lowerTitle = title.lowercased()
            let lowerArtist = artist.lowercased()
            let lowerAlbum = album.lowercased()

            if lowerTitle.contains("youtube") || lowerArtist.contains("youtube") || lowerAlbum.contains("youtube") {
                source = .youtube
            } else if lowerAlbum.contains("spotify") || lowerArtist.contains("spotify") {
                source = .spotify
            } else {
                source = .youtube
            }

            var clean = title
            if let regex = try? NSRegularExpression(pattern: "^\\(\\d+\\)\\s*") {
                clean = regex.stringByReplacingMatches(in: clean, range: NSRange(location: 0, length: clean.utf16.count), withTemplate: "")
            }

            resultItem = NowPlayingItem(
                title: clean,
                artistOrChannel: artist.isEmpty ? "Now Playing" : artist,
                albumOrContext: album,
                source: source,
                isPlaying: true,
                progress: progress,
                positionSeconds: Int(elapsed),
                durationSeconds: Int(duration),
                artworkUrl: ""
            )
        }

        _ = sema.wait(timeout: .now() + 0.3)
        return resultItem
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
    
    // MARK: - Media Controls & Keyboard Playback Actions

    public enum MediaPlaybackAction: String, Sendable {
        case playPause = "playpause"
        case play = "play"
        case pause = "pause"
        case next = "next"
        case previous = "previous"
        case mute = "mute"
        case unmute = "unmute"
        case close = "close"
    }
    
    @discardableResult
    public func handlePlaybackAction(_ action: MediaPlaybackAction) -> Bool {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let frontName = (frontApp?.localizedName ?? "").lowercased()
        let frontBundle = (frontApp?.bundleIdentifier ?? "").lowercased()
        
        let isBrowserFrontmost = frontName.contains("chrome") || frontName.contains("safari") ||
                                 frontName.contains("arc") || frontName.contains("brave") ||
                                 frontName.contains("edge") || frontBundle.contains("browser")
        let isSpotifyFrontmost = frontName.contains("spotify") || frontBundle.contains("spotify")
        
        // Priority 1: If Spotify window is currently focused/frontmost
        if isSpotifyFrontmost {
            return controlSpotifyAction(action)
        }
        
        // Priority 2: If a browser is frontmost, control the active YouTube tab
        if isBrowserFrontmost {
            let res = AccessibilityControlEngine.shared.controlYouTubePlayback(action: action.rawValue)
            if res {
                pollMediaState()
                return true
            }
        }
        
        // Priority 3: Check currently detected media in the notch
        if let current = currentMedia {
            switch current.source {
            case .youtube:
                let res = AccessibilityControlEngine.shared.controlYouTubePlayback(action: action.rawValue)
                if res { pollMediaState(); return true }
            case .spotify:
                return controlSpotifyAction(action)
            case .appleMusic:
                return controlAppleMusicAction(action)
            }
        }
        
        // Priority 4: If no media was detected as actively playing, try controlling any open YouTube tab first
        let ytRes = AccessibilityControlEngine.shared.controlYouTubePlayback(action: action.rawValue)
        if ytRes {
            pollMediaState()
            return true
        }
        
        let runningApps = NSWorkspace.shared.runningApplications
        let isSpotifyRunning = runningApps.contains { $0.bundleIdentifier == "com.spotify.client" || $0.localizedName?.lowercased() == "spotify" }
        if isSpotifyRunning {
            return controlSpotifyAction(action)
        }
        
        return false
    }

    private func controlSpotifyAction(_ action: MediaPlaybackAction) -> Bool {
        switch action {
        case .playPause:
            _ = runAppleScript("tell application \"Spotify\" to playpause")
        case .play:
            _ = runAppleScript("tell application \"Spotify\" to play")
        case .pause:
            _ = runAppleScript("tell application \"Spotify\" to pause")
        case .next:
            _ = runAppleScript("tell application \"Spotify\" to next track")
        case .previous:
            _ = runAppleScript("tell application \"Spotify\" to previous track")
        case .mute:
            _ = runAppleScript("tell application \"Spotify\" to set sound volume to 0")
        case .unmute:
            _ = runAppleScript("tell application \"Spotify\" to set sound volume to 75")
        case .close:
            _ = AccessibilityControlEngine.shared.closeApplication(named: "Spotify")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pollMediaState()
        }
        return true
    }

    private func controlAppleMusicAction(_ action: MediaPlaybackAction) -> Bool {
        switch action {
        case .playPause:
            _ = runAppleScript("tell application \"Music\" to playpause")
        case .play:
            _ = runAppleScript("tell application \"Music\" to play")
        case .pause:
            _ = runAppleScript("tell application \"Music\" to pause")
        case .next:
            _ = runAppleScript("tell application \"Music\" to next track")
        case .previous:
            _ = runAppleScript("tell application \"Music\" to previous track")
        case .mute:
            _ = runAppleScript("tell application \"Music\" to set sound volume to 0")
        case .unmute:
            _ = runAppleScript("tell application \"Music\" to set sound volume to 75")
        case .close:
            _ = AccessibilityControlEngine.shared.closeApplication(named: "Music")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pollMediaState()
        }
        return true
    }
    
    public func togglePlayPause() {
        handlePlaybackAction(.playPause)
    }
    
    public func play() {
        handlePlaybackAction(.play)
    }
    
    public func pause() {
        handlePlaybackAction(.pause)
    }
    
    public func nextTrack() {
        handlePlaybackAction(.next)
    }
    
    public func previousTrack() {
        handlePlaybackAction(.previous)
    }
    
    public func mute() {
        handlePlaybackAction(.mute)
    }
    
    public func unmute() {
        handlePlaybackAction(.unmute)
    }
    
    public func closeMedia() {
        handlePlaybackAction(.close)
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

