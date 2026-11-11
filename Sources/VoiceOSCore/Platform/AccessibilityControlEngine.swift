import Foundation
import AppKit
import ApplicationServices
import CoreAudio

public final class AccessibilityControlEngine: @unchecked Sendable {
    public static let shared = AccessibilityControlEngine()
    
    public init() {}
    
    // MARK: - Permissions Check
    
    public func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }
    
    public func promptAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Layer 1: Native macOS APIs & Scripting
    
    public func launchApp(named appName: String) -> Bool {
        // 1. Try NSWorkspace openApplication with explicit bundle lookup
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName) ??
                        findApplicationUrl(named: appName) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            var opened = false
            let sema = DispatchSemaphore(value: 0)
            
            NSWorkspace.shared.openApplication(at: appUrl, configuration: config) { _, error in
                opened = (error == nil)
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 1.2)
            if opened { return true }
        }
        
        // 2. LaunchServices CLI fallback via /usr/bin/open -a
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName]
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
    
    public func executeAppleScript(_ scriptText: String) -> (success: Bool, output: String?) {
        let wrappedScript = scriptText.contains("with timeout") ? scriptText : """
        with timeout of 2 seconds
            \(scriptText)
        end timeout
        """
        
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", wrappedScript]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let timeout = DispatchTime.now() + 1.5
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                sema.signal()
            }
            if sema.wait(timeout: timeout) == .timedOut {
                process.terminate()
                return (false, nil)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let outStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (process.terminationStatus == 0, outStr)
        } catch {
            return (false, nil)
        }
    }
    
    // MARK: - Volume Management & CoreAudio
    
    private var lastKnownVolumeLevel: Double = 0.75
    
    public func adjustVolume(delta: Double?, absoluteLevel: Double?) -> (success: Bool, newLevel: Double) {
        let currentLevel = getVolumeLevel()
        var targetLevel = currentLevel
        
        if let abs = absoluteLevel {
            targetLevel = max(0.0, min(1.0, abs))
        } else if let d = delta {
            targetLevel = max(0.0, min(1.0, currentLevel + d))
        }
        
        lastKnownVolumeLevel = targetLevel
        let percent = Int(targetLevel * 100.0)
        let script = "set volume output volume \(percent) without output muted"
        let result = executeAppleScript(script)
        
        return (result.success, targetLevel)
    }
    
    public func getVolumeLevel() -> Double {
        let script = "output volume of (get volume settings)"
        let result = executeAppleScript(script)
        if let out = result.output, let vol = Double(out), vol >= 0 {
            let normalized = vol / 100.0
            lastKnownVolumeLevel = normalized
            return normalized
        }
        return lastKnownVolumeLevel
    }
    
    // MARK: - Keystroke & Keyboard Simulation
    
    public func simulateKeystroke(_ combo: String) -> Bool {
        let lower = combo.lowercased()
        var modifiers: [String] = []
        if lower.contains("command") || lower.contains("cmd") { modifiers.append("command down") }
        if lower.contains("shift") { modifiers.append("shift down") }
        if lower.contains("control") || lower.contains("ctrl") { modifiers.append("control down") }
        if lower.contains("option") || lower.contains("alt") { modifiers.append("option down") }
        
        let modStr = modifiers.isEmpty ? "" : " using {\(modifiers.joined(separator: ", "))}"
        
        let parts = combo.components(separatedBy: CharacterSet(charactersIn: "+- "))
        let rawKey = parts.last ?? combo
        
        let script: String
        switch rawKey.lowercased() {
        case "space":
            script = "tell application \"System Events\" to key code 49\(modStr)"
        case "return", "enter":
            script = "tell application \"System Events\" to key code 36\(modStr)"
        case "escape", "esc":
            script = "tell application \"System Events\" to key code 53"
        default:
            script = "tell application \"System Events\" to keystroke \"\(rawKey)\"\(modStr)"
        }
        return executeAppleScript(script).success
    }
    
    public func typeText(_ text: String) -> Bool {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"System Events\" to keystroke \"\(escaped)\""
        return executeAppleScript(script).success
    }
    
    // MARK: - Media Controls (Spotify / YouTube / Apple Music)
    
    public func controlMedia(app: String = "Spotify", action: String, query: String? = nil) -> Bool {
        if app.lowercased().contains("youtube") || app.lowercased().contains("video") {
            if let q = query, !q.isEmpty, action == "play" {
                let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
                if let url = URL(string: "https://www.youtube.com/results?search_query=\(encoded)") {
                    NSWorkspace.shared.open(url)
                }
                return true
            }
            return controlYouTubePlayback(action: action)
        }
        
        let targetApp = app.lowercased().contains("music") ? "Music" : "Spotify"
        
        // Ensure the player application is launched and ready
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains { 
            $0.bundleIdentifier == (targetApp == "Spotify" ? "com.spotify.client" : "com.apple.Music") ||
            $0.localizedName?.lowercased() == targetApp.lowercased()
        }
        if !isRunning {
            _ = launchApp(named: targetApp)
            Thread.sleep(forTimeInterval: 0.8)
        }
        
        if let query = query, !query.isEmpty, action == "play" {
            let lowerQuery = query.lowercased()
            let isGeneric = lowerQuery.isEmpty || lowerQuery == "top hits" || lowerQuery == "song" || lowerQuery == "songs" || lowerQuery == "music"
            let script: String
            if targetApp == "Spotify" {
                if isGeneric {
                    script = """
                    tell application "Spotify"
                        activate
                        try
                            if player state is paused then
                                play
                            else if player state is stopped then
                                play track "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"
                            else
                                play
                            end if
                        on error
                            play track "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"
                        end try
                    end tell
                    """
                } else {
                    let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
                    script = """
                    tell application "Spotify"
                        activate
                        open location "spotify:search:\(encoded)"
                    end tell
                    delay 0.8
                    tell application "System Events"
                        tell process "Spotify"
                            set frontmost to true
                            try
                                -- Commit search
                                key code 36
                                delay 0.2
                                -- Focus and select top result track
                                key code 125
                                delay 0.1
                                -- Play selected track
                                key code 36
                                delay 0.2
                            on error
                                key code 49
                            end try
                        end tell
                    end tell
                    tell application "Spotify"
                        try
                            if player state is not playing then
                                play
                            end if
                        end try
                    end tell
                    """
                }
            } else {
                script = """
                tell application "Music"
                    activate
                    try
                        play playlist "\(query)"
                    on error
                        play
                    end try
                end tell
                """
            }
            let res = executeAppleScript(script).success
            NowPlayingMediaManager.shared.pollMediaState()
            return res
        }
        
        let scriptAction: String
        switch action {
        case "pause", "stop":
            scriptAction = "pause"
        case "next":
            scriptAction = "next track\n        delay 0.2\n        play"
        case "previous":
            scriptAction = "previous track\n        delay 0.2\n        play"
        default:
            if targetApp == "Spotify" {
                scriptAction = """
                try
                    if player state is paused then
                        play
                    else if player state is stopped then
                        play track "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"
                    else
                        play
                    end if
                on error
                    play track "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"
                end try
                """
            } else {
                scriptAction = "play"
            }
        }
        
        let script = """
        tell application "\(targetApp)"
            activate
            \(scriptAction)
        end tell
        """
        let res = executeAppleScript(script).success
        NowPlayingMediaManager.shared.pollMediaState()
        return res
    }
    
    public func controlYouTubePlayback(action: String) -> Bool {
        // 1. Direct tab script execution on Google Chrome
        let chromeScript = """
        tell application "System Events"
            set isChromeRunning to exists (processes where name is "Google Chrome")
        end tell
        if isChromeRunning then
            tell application "Google Chrome"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "youtube.com" then
                            tell t
                                if "\(action)" is "pause" then
                                    execute javascript "const v = document.querySelector('video'); if (v) v.pause();"
                                else if "\(action)" is "next" then
                                    execute javascript "const nextBtn = document.querySelector('.ytp-next-button') || document.querySelector('a.ytd-compact-video-renderer'); if (nextBtn) nextBtn.click();"
                                else if "\(action)" is "previous" then
                                    execute javascript "window.history.back();"
                                else
                                    execute javascript "const v = document.querySelector('video'); if (v) v.play();"
                                end if
                            end tell
                            return "success"
                        end if
                    end repeat
                end repeat
            end tell
        end if
        return "not_found"
        """
        let chromeRes = executeAppleScript(chromeScript)
        if chromeRes.success && chromeRes.output == "success" {
            NowPlayingMediaManager.shared.pollMediaState()
            return true
        }
        
        // 2. Direct tab script execution on Safari
        let safariScript = """
        tell application "System Events"
            set isSafariRunning to exists (processes where name is "Safari")
        end tell
        if isSafariRunning then
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "youtube.com" then
                            tell t
                                if "\(action)" is "pause" then
                                    do JavaScript "const v = document.querySelector('video'); if (v) v.pause();"
                                else if "\(action)" is "next" then
                                    do JavaScript "const nextBtn = document.querySelector('.ytp-next-button') || document.querySelector('a.ytd-compact-video-renderer'); if (nextBtn) nextBtn.click();"
                                else if "\(action)" is "previous" then
                                    do JavaScript "window.history.back();"
                                else
                                    do JavaScript "const v = document.querySelector('video'); if (v) v.play();"
                                end if
                            end tell
                            return "success"
                        end if
                    end repeat
                end repeat
            end tell
        end if
        return "not_found"
        """
        let safariRes = executeAppleScript(safariScript)
        if safariRes.success && safariRes.output == "success" {
            NowPlayingMediaManager.shared.pollMediaState()
            return true
        }
        
        // 3. Media key fallback to frontmost window
        let keyScript: String
        switch action {
        case "pause", "play":
            keyScript = "tell application \"System Events\" to key code 49" // Spacebar
        case "next":
            keyScript = "tell application \"System Events\" to keystroke \"N\" using {shift down}" // Shift+N
        case "previous":
            keyScript = "tell application \"System Events\" to keystroke \"P\" using {shift down}" // Shift+P
        default:
            keyScript = "tell application \"System Events\" to key code 49"
        }
        let fallbackRes = executeAppleScript(keyScript)
        NowPlayingMediaManager.shared.pollMediaState()
        return fallbackRes.success
    }
    
    // MARK: - Window & System Actions
    
    public func adjustDisplayBrightness(delta: Double?, absoluteLevel: Double?) -> (success: Bool, level: Double) {
        let isUp = (delta ?? 0.0) >= 0.0
        let keyScript = isUp ?
            "tell application \"System Events\" to key code 145" : // Brightness Up
            "tell application \"System Events\" to key code 144"   // Brightness Down
        
        let res = executeAppleScript(keyScript)
        let targetPct = absoluteLevel ?? (isUp ? 0.85 : 0.60)
        return (res.success, targetPct)
    }
    
    public func performWindowAction(_ action: String) -> Bool {
        let script: String
        switch action {
        case "close":
            script = """
            tell application "System Events"
                set frontApp to first application process whose frontmost is true
                tell frontApp
                    try
                        click (first button whose subrole is "AXCloseButton") of first window
                    on error
                        keystroke "w" using {command down}
                    end try
                end tell
            end tell
            """
        case "minimize":
            script = """
            tell application "System Events"
                keystroke "m" using {command down}
            end tell
            """
        case "maximize":
            script = """
            tell application "System Events"
                keystroke "f" using {command down, control down}
            end tell
            """
        default:
            return false
        }
        return executeAppleScript(script).success
    }
    
    public func performSystemControl(_ action: String) -> Bool {
        let script: String
        switch action {
        case "lock":
            script = "tell application \"System Events\" to keystroke \"q\" using {command down, control down}"
        case "sleep":
            script = "tell application \"System Events\" to sleep"
        case "mute":
            script = "set volume with output muted"
        case "unmute":
            script = "set volume without output muted"
        case "empty_trash":
            script = "tell application \"Finder\" to empty trash"
        case "dark_mode_on":
            script = "tell application \"System Events\" to tell appearance preferences to set dark mode to true"
        case "dark_mode_off":
            script = "tell application \"System Events\" to tell appearance preferences to set dark mode to false"
        case "dark_mode_toggle":
            script = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        default:
            return false
        }
        return executeAppleScript(script).success
    }
    
    // MARK: - Layer 2: Accessibility API (AXUIElement)
    
    public func findElement(
        inAppPID pid: pid_t,
        role: String?,
        title: String?,
        identifier: String?
    ) -> AXUIElement? {
        guard isAccessibilityGranted() else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        return searchElementTree(root: appElement, role: role, title: title, identifier: identifier, depth: 0, maxDepth: 8)
    }
    
    private func searchElementTree(
        root: AXUIElement,
        role: String?,
        title: String?,
        identifier: String?,
        depth: Int,
        maxDepth: Int
    ) -> AXUIElement? {
        if depth > maxDepth { return nil }
        
        // Check attributes of current node
        var matched = true
        if let role = role {
            var roleValue: AnyObject?
            AXUIElementCopyAttributeValue(root, kAXRoleAttribute as CFString, &roleValue)
            if (roleValue as? String)?.lowercased() != role.lowercased() { matched = false }
        }
        if matched, let title = title {
            let lowerTarget = title.lowercased()
            var textFound = false
            for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXRoleDescriptionAttribute, kAXValueAttribute, kAXIdentifierAttribute] {
                var val: AnyObject?
                if AXUIElementCopyAttributeValue(root, attr as CFString, &val) == .success,
                   let str = val as? String,
                   str.lowercased().contains(lowerTarget) {
                    textFound = true
                    break
                }
            }
            if !textFound { matched = false }
        }
        if matched, let identifier = identifier {
            var idValue: AnyObject?
            AXUIElementCopyAttributeValue(root, kAXIdentifierAttribute as CFString, &idValue)
            if (idValue as? String)?.lowercased() != identifier.lowercased() { matched = false }
        }
        
        if matched && (role != nil || title != nil || identifier != nil) {
            return root
        }
        
        // Traverse children
        var childrenValue: AnyObject?
        AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenValue)
        guard let children = childrenValue as? [AXUIElement] else { return nil }
        
        for child in children {
            if let found = searchElementTree(root: child, role: role, title: title, identifier: identifier, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
        return nil
    }
    
    public func pressElement(_ element: AXUIElement) -> Bool {
        let err = AXUIElementPerformAction(element, kAXPressAction as CFString)
        return err == .success
    }
    
    public func setElementValue(_ element: AXUIElement, value: String) -> Bool {
        let err = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
        return err == .success
    }
    
    // MARK: - Layer 3: Synthetic CGEvent Input
    
    public func getFrontmostTargetWindow() -> (ownerName: String, pid: pid_t, bounds: CGRect)? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in windowList {
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            
            if layer == 0 && !ownerName.isEmpty &&
               !ownerName.lowercased().contains("voice") &&
               ownerName != "Dock" && ownerName != "Window Server" && ownerName != "SystemUIServer" {
                var bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
                if let dict = info[kCGWindowBounds as String] as? [String: CGFloat] {
                    bounds = CGRect(
                        x: dict["X"] ?? 0,
                        y: dict["Y"] ?? 0,
                        width: dict["Width"] ?? 1440,
                        height: dict["Height"] ?? 900
                    )
                }
                return (ownerName, pid, bounds)
            }
        }
        return nil
    }
    
    @discardableResult
    public func postClick(at point: CGPoint, doubleClick: Bool = false) -> Bool {
        // 1. Physically warp hardware mouse pointer to target coordinate
        CGWarpMouseCursorPosition(point)
        
        let source = CGEventSource(stateID: .combinedSessionState) ?? CGEventSource(stateID: .hidSystemState)
        
        // 2. Synthesize mouse move to update WindowServer hit-testing under the cursor
        if let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            moveEvent.post(tap: .cgSessionEventTap)
            moveEvent.post(tap: .cghidEventTap)
        }
        usleep(25000) // 25ms settle time
        
        // 3. Post LeftMouseDown & LeftMouseUp with session & HID event taps
        guard let downEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let upEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return false
        }
        
        downEvent.setIntegerValueField(.mouseEventClickState, value: 1)
        upEvent.setIntegerValueField(.mouseEventClickState, value: 1)
        
        downEvent.post(tap: .cgSessionEventTap)
        downEvent.post(tap: .cghidEventTap)
        usleep(45000) // 45ms realistic mouse press duration
        upEvent.post(tap: .cgSessionEventTap)
        upEvent.post(tap: .cghidEventTap)
        
        // 4. Double-click support for opening media / items
        if doubleClick {
            usleep(60000) // 60ms inter-click pause
            if let down2 = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
               let up2 = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
                down2.setIntegerValueField(.mouseEventClickState, value: 2)
                up2.setIntegerValueField(.mouseEventClickState, value: 2)
                down2.post(tap: .cgSessionEventTap)
                down2.post(tap: .cghidEventTap)
                usleep(45000)
                up2.post(tap: .cgSessionEventTap)
                up2.post(tap: .cghidEventTap)
            }
        }
        
        // 5. Hardware AppleScript System Events Click Fallback
        let script = "tell application \"System Events\" to click at {\(Int(point.x)), \(Int(point.y))}"
        _ = executeAppleScript(script)
        
        return true
    }
    
    // MARK: - Autonomous UI & Video Clicking

    public func clickElement(matching description: String, frontmostAppName: String) async -> (success: Bool, summary: String) {
        let lowerDesc = description.lowercased()
        var effectiveAppName = frontmostAppName
        var targetPID: pid_t = 0
        
        // 1. Identify target application window & PID without leaking into an unrelated frontmost app
        let wantsFrontmost = effectiveAppName.lowercased().contains("voice") || effectiveAppName == "Active Application"
        if wantsFrontmost {
            if let targetWin = getFrontmostTargetWindow() {
                effectiveAppName = targetWin.ownerName
                targetPID = targetWin.pid
                if let runningApp = NSRunningApplication(processIdentifier: targetPID) {
                    runningApp.activate(options: [.activateIgnoringOtherApps])
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
            } else if let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.activationPolicy == .regular &&
                !($0.localizedName?.lowercased().contains("voice") ?? true)
            }) {
                effectiveAppName = runningApp.localizedName ?? frontmostAppName
                targetPID = runningApp.processIdentifier
                runningApp.activate(options: [.activateIgnoringOtherApps])
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        } else {
            let cleanTargetApp = effectiveAppName.lowercased()
            if let matchingApp = NSWorkspace.shared.runningApplications.first(where: {
                let name = ($0.localizedName ?? "").lowercased()
                return !name.isEmpty && (name.contains(cleanTargetApp) || cleanTargetApp.contains(name))
            }) {
                targetPID = matchingApp.processIdentifier
                matchingApp.activate(options: [.activateIgnoringOtherApps])
                try? await Task.sleep(nanoseconds: 120_000_000)
            } else {
                return (false, "Could not locate '\(description)' in \(effectiveAppName) because \(effectiveAppName) is not running.")
            }
        }
        
        var targetPoint: CGPoint? = nil
        var clickSucceeded = false
        var alreadyPressedInApp = false
        
        let appLower = effectiveAppName.lowercased()
        let isBrowser = appLower.contains("safari") ||
                        appLower.contains("chrome") ||
                        appLower.contains("brave") ||
                        appLower.contains("edge") ||
                        appLower.contains("arc")
        
        // 2. Browser-Specific DOM & Target Clicking (only verify when JS reports 'clicked')
        if isBrowser {
            let isSafari = appLower.contains("safari")
            
            if lowerDesc.contains("video") || lowerDesc.contains("first") || lowerDesc.contains("youtube") || lowerDesc.contains("pehli") {
                
                let jsClickScript: String
                if isSafari {
                    jsClickScript = """
                    tell application "Safari"
                        activate
                        try
                            do JavaScript "
                                (function() {
                                    const selectors = [
                                        'ytd-video-renderer a#video-title',
                                        'ytd-grid-video-renderer a#video-title',
                                        'ytd-rich-item-renderer a#video-title',
                                        '#contents ytd-video-renderer a#thumbnail',
                                        'a#video-title',
                                        'ytd-thumbnail a',
                                        'a.yt-simple-endpoint.ytd-video-renderer',
                                        'article a',
                                        'h3 a'
                                    ];
                                    for (const sel of selectors) {
                                        const els = document.querySelectorAll(sel);
                                        if (els && els.length > 0) {
                                            for (let el of els) {
                                                if (el.offsetParent !== null) {
                                                    el.click();
                                                    return 'clicked';
                                                }
                                            }
                                        }
                                    }
                                    return 'not_found';
                                })();
                            " in current tab of front window
                        end try
                    end tell
                    """
                } else {
                    jsClickScript = """
                    tell application "Google Chrome"
                        activate
                        try
                            tell active tab of front window
                                execute javascript "
                                    (function() {
                                        const selectors = [
                                            'ytd-video-renderer a#video-title',
                                            'ytd-grid-video-renderer a#video-title',
                                            'ytd-rich-item-renderer a#video-title',
                                            '#contents ytd-video-renderer a#thumbnail',
                                            'a#video-title',
                                            'ytd-thumbnail a',
                                            'article a',
                                            'h3 a'
                                        ];
                                        for (const sel of selectors) {
                                            const els = document.querySelectorAll(sel);
                                            if (els && els.length > 0) {
                                                for (let el of els) {
                                                    if (el.offsetParent !== null) {
                                                        el.click();
                                                        return 'clicked';
                                                    }
                                                }
                                            }
                                        }
                                        return 'not_found';
                                    })();
                                "
                            end tell
                        end try
                    end tell
                    """
                }
                
                let scriptResult = executeAppleScript(jsClickScript)
                if scriptResult.success && scriptResult.output?.contains("clicked") == true {
                    clickSucceeded = true
                    alreadyPressedInApp = true
                }
            } else {
                let safeDesc = lowerDesc.replacingOccurrences(of: "\"", with: "\\\"")
                let genericDomScript = isSafari ? """
                tell application "Safari"
                    activate
                    try
                        do JavaScript "
                            (function() {
                                const q = '\(safeDesc)';
                                const els = Array.from(document.querySelectorAll('button, a, input, [role=\\\"button\\\"], span'));
                                for (const el of els) {
                                    const txt = (el.innerText || el.getAttribute('aria-label') || el.value || '').toLowerCase();
                                    if (txt.includes(q)) {
                                        el.click();
                                        return 'clicked';
                                    }
                                }
                                return 'not_found';
                            })();
                        " in current tab of front window
                    end try
                end tell
                """ : """
                tell application "Google Chrome"
                    activate
                    try
                        tell active tab of front window
                            execute javascript "
                                (function() {
                                    const q = '\(safeDesc)';
                                    const els = Array.from(document.querySelectorAll('button, a, input, [role=\\\"button\\\"], span'));
                                    for (const el of els) {
                                        const txt = (el.innerText || el.getAttribute('aria-label') || el.value || '').toLowerCase();
                                        if (txt.includes(q)) {
                                            el.click();
                                            return 'clicked';
                                        }
                                    }
                                    return 'not_found';
                                })();
                            "
                        end tell
                    end try
                end tell
                """
                let domRes = executeAppleScript(genericDomScript)
                if domRes.success && domRes.output?.contains("clicked") == true {
                    clickSucceeded = true
                    alreadyPressedInApp = true
                }
            }
        }
        
        // 3. Desktop Application Element Clicking via Accessibility API
        if !alreadyPressedInApp && targetPID > 0 {
            if let foundElem = findElement(inAppPID: targetPID, role: nil, title: description, identifier: nil) {
                var posVal: AnyObject?
                var sizeVal: AnyObject?
                if AXUIElementCopyAttributeValue(foundElem, kAXPositionAttribute as CFString, &posVal) == .success,
                   AXUIElementCopyAttributeValue(foundElem, kAXSizeAttribute as CFString, &sizeVal) == .success {
                    var elemPos = CGPoint.zero
                    var elemSize = CGSize.zero
                    if let p = posVal, CFGetTypeID(p) == AXValueGetTypeID() {
                        AXValueGetValue(p as! AXValue, .cgPoint, &elemPos)
                    }
                    if let s = sizeVal, CFGetTypeID(s) == AXValueGetTypeID() {
                        AXValueGetValue(s as! AXValue, .cgSize, &elemSize)
                    }
                    if elemSize.width > 0 && elemSize.height > 0 {
                        targetPoint = CGPoint(x: elemPos.x + elemSize.width / 2.0, y: elemPos.y + elemSize.height / 2.0)
                    }
                }
                if pressElement(foundElem) {
                    clickSucceeded = true
                    alreadyPressedInApp = true
                }
            }
        }
        
        // 4. Local VLM (LLaVA) + OCR Visual Grounding Fallback when DOM & AX couldn't locate target
        if !alreadyPressedInApp && targetPoint == nil && ModelRouter.shared.currentMode != .googleSearch {
            if let grounded = try? await VisualGroundingSoMEngine.shared.groundTargetElement(
                targetDescription: description,
                targetApp: effectiveAppName
            ), grounded.confidence >= 0.80, grounded.resolutionMethod != "fallback_anchor" {
                targetPoint = grounded.targetScreenCoordinate
            }
        }
        
        if alreadyPressedInApp {
            BoringSoundEngine.shared.playTap()
            return (true, "Clicked '\(description)' in \(effectiveAppName).")
        }
        
        // NEVER blindly click the center of the window if no target was verified
        guard let verifiedPoint = targetPoint else {
            return (false, "Could not locate '\(description)' in \(effectiveAppName). Try Circling it with ⌘⇧C or bringing the target window forward.")
        }
        
        let isVideo = lowerDesc.contains("video") || lowerDesc.contains("first") || lowerDesc.contains("youtube") || lowerDesc.contains("song")
        await VisualCursorGuideEngine.shared.moveCursorSmoothly(to: verifiedPoint, duration: 0.22)
        let eventClicked = postClick(at: verifiedPoint, doubleClick: isVideo)
        clickSucceeded = eventClicked
        VisualCursorGuideEngine.shared.triggerClickFeedback(at: verifiedPoint)
        try? await Task.sleep(nanoseconds: 180_000_000)
        VisualCursorGuideEngine.shared.dismissPointer()
        
        BoringSoundEngine.shared.playTap()
        return (clickSucceeded, clickSucceeded ? "Clicked '\(description)' in \(effectiveAppName)." : "Could not click '\(description)' in \(effectiveAppName).")
    }
    
    // MARK: - State Verification Loop
    
    public func verifyAppRunningAndFrontmost(named appName: String, timeout: TimeInterval = 1.5) -> Bool {
        let start = Date()
        let cleanName = appName.lowercased()
        
        while Date().timeIntervalSince(start) < timeout {
            if let frontmost = NSWorkspace.shared.frontmostApplication {
                let current = (frontmost.localizedName ?? "").lowercased()
                if current.contains(cleanName) || cleanName.contains(current) {
                    return true
                }
            }
            // Check running applications list as fallback
            let running = NSWorkspace.shared.runningApplications
            if running.contains(where: { ($0.localizedName ?? "").lowercased().contains(cleanName) }) {
                return true
            }
            usleep(100000) // 100ms poll
        }
        return false
    }
    
    public func verifyMediaPlaybackState(app: String = "Spotify") -> (isPlaying: Bool, track: String?) {
        if app.lowercased().contains("youtube") {
            if let media = NowPlayingMediaManager.shared.currentMedia, media.source == .youtube {
                return (media.isPlaying, media.title)
            }
            return (true, "YouTube Video")
        }
        
        let script = """
        tell application "\(app)"
            if player state is playing then
                return name of current track
            else
                return "paused"
            end if
        end tell
        """
        let res = executeAppleScript(script)
        if res.success, let out = res.output, !out.isEmpty && out != "paused" {
            return (true, out)
        }
        return (false, nil)
    }
    
    // MARK: - Application Lifecycle: Close & Quit Application
    
    public func closeApplication(named appName: String?) -> (success: Bool, appName: String, summary: String) {
        let ws = NSWorkspace.shared
        
        // 1. Specific named application (e.g. "Spotify", "Safari", "WhatsApp")
        if let targetName = appName?.trimmingCharacters(in: .whitespacesAndNewlines), !targetName.isEmpty {
            let cleanTarget = targetName.lowercased()
            
            // Look up running apps
            let matching = ws.runningApplications.filter {
                let appTitle = ($0.localizedName ?? "").lowercased()
                let bundleId = ($0.bundleIdentifier ?? "").lowercased()
                return appTitle.contains(cleanTarget) || cleanTarget.contains(appTitle) || bundleId.contains(cleanTarget)
            }
            
            if !matching.isEmpty {
                for app in matching {
                    app.terminate()
                }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.35) {
                    for app in matching {
                        if !app.isTerminated {
                            app.forceTerminate()
                        }
                    }
                }
                BoringSoundEngine.shared.playDone()
                let display = matching.first?.localizedName ?? targetName.capitalized
                return (true, display, "Closed \(display) on your Mac.")
            }
            
            // AppleScript quit fallback
            let script = "tell application \"\(targetName)\" to quit"
            _ = executeAppleScript(script)
            
            // CLI killall fallback
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            proc.arguments = [targetName]
            try? proc.run()
            proc.waitUntilExit()
            
            BoringSoundEngine.shared.playDone()
            return (true, targetName.capitalized, "Closed \(targetName.capitalized) on your Mac.")
        }
        
        // 2. Frontmost active application (e.g. user said "close the app", "close this app")
        let myBundleId = Bundle.main.bundleIdentifier ?? "ai.voice.app"
        let frontApps = ws.runningApplications.filter { $0.isActive && $0.bundleIdentifier != myBundleId }
        let targetApp = frontApps.first ?? ws.frontmostApplication
        
        if let app = targetApp, app.bundleIdentifier != myBundleId {
            let appTitle = app.localizedName ?? "Active App"
            app.terminate()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.35) {
                if !app.isTerminated {
                    app.forceTerminate()
                }
            }
            BoringSoundEngine.shared.playDone()
            return (true, appTitle, "Closed \(appTitle) on your Mac.")
        }
        
        // Front window quit via System Events
        let script = """
        tell application "System Events"
            set frontApp to first application process whose frontmost is true and bundle identifier is not "\(myBundleId)"
            tell frontApp to quit
        end tell
        """
        _ = executeAppleScript(script)
        BoringSoundEngine.shared.playDone()
        return (true, "Active App", "Closed the active app on your Mac.")
    }

    // MARK: - Helper Application Lookup
    
    private func findApplicationUrl(named name: String) -> URL? {
        let searchDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]
        let fm = FileManager.default
        let target = name.lowercased()
        
        for dir in searchDirs {
            guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let base = (item as NSString).deletingPathExtension.lowercased()
                if base == target || base.contains(target) || target.contains(base) {
                    return URL(fileURLWithPath: (dir as NSString).appendingPathComponent(item))
                }
            }
        }
        return nil
    }
}

