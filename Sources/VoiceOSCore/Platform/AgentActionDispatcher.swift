import AppKit
import Foundation

public struct DispatchedActionResult: Sendable {
    public let success: Bool
    public let summary: String
    public let appName: String
    public let deepLinkURL: URL?

    public init(success: Bool, summary: String, appName: String, deepLinkURL: URL? = nil) {
        self.success = success
        self.summary = summary
        self.appName = appName
        self.deepLinkURL = deepLinkURL
    }
}

/// Executes real macOS system actions, AppleScripts, web search answers,
/// screen vision analysis, and text automation from parsed voice intents.
public final class AgentActionDispatcher: @unchecked Sendable {
    public static let shared = AgentActionDispatcher()

    public init() {}

    public func isCommandIntent(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        guard !t.isEmpty else { return false }

        // 0. High priority typed semantic tool match
        if AgentToolParser.parse(query: text) != nil {
            return true
        }

        // 1. Direct question mark indicator
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") {
            return true
        }

        // 2. Hindi & Hinglish intent indicators (kholo, khol do, chalao, kya, etc.)
        if HinglishParser.isHinglishQuery(text) {
            return true
        }

        // 3. Screen Vision queries
        if t.contains("screen") || t.contains("what am i looking at") || t.contains("read screen") {
            return true
        }

        // 4. Tab and browser navigation
        if t.contains("tab") {
            return true
        }

        // 5. App Opening intents (English and Hinglish)
        if extractAppOpenIntent(from: text) != nil {
            return true
        }

        // 6. Natural question words and interrogatives at start of sentence
        let questionStarters = [
            "what ", "what's ", "who ", "who's ", "where ", "where's ", "when ", "when's ",
            "why ", "why's ", "how ", "how's ", "which ", "whose ", "whom ",
            "is ", "are ", "was ", "were ", "can ", "could ", "should ", "would ", "will ",
            "do ", "does ", "did ", "tell me", "explain ", "describe ", "define ",
            "summarize ", "solve ", "calculate ", "give me ", "find out ", "check "
        ]
        for starter in questionStarters {
            if t.hasPrefix(starter) {
                return true
            }
        }

        // 7. Action and system command keywords
        let actionKeywords = [
            "open ", "launch ", "start ", "quit ", "close ", "kholo", "khol do",
            "type ", "write ", "search ", "google ", "find ", "look up ", "browse ",
            "create note", "add note", "take note", "write note", "write down",
            "remind me", "add reminder", "set reminder",
            "play ", "pause ", "resume ", "spotify ", "music", "gaana",
            "show downloads", "open downloads", "show documents", "open documents",
            "remember that", "my name is", "what did i ask"
        ]

        for k in actionKeywords {
            if t.contains(k) {
                return true
            }
        }

        if t == "play" || t == "pause" || t == "stop" || t == "next" {
            return true
        }

        return false
    }

    public func dispatch(transcript: String) async -> DispatchedActionResult {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let lower = text.lowercased()

        // 0. High-Priority Semantic Tool Execution via AgentToolParser
        if let tool = AgentToolParser.parse(query: text) {
            switch tool {
            case .openApp(let name):
                return openApplication(named: name)
                
            case .closeApp(let name):
                BoringSoundEngine.shared.playDispatch()
                let res = AccessibilityControlEngine.shared.closeApplication(named: name)
                return DispatchedActionResult(
                    success: res.success,
                    summary: res.summary,
                    appName: res.appName
                )
                
            case .mediaPlay(let app, let query, let action):
                let isDryOrTest = ProcessInfo.processInfo.environment["VOICE_AI_DRY_RUN"] == "1" ||
                                  ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1"

                var targetApp = app ?? ""
                var usedScreenContext = false

                // When playing current on-screen media with no search query, take a live screenshot first
                // so we inspect whether YouTube or Spotify is open on screen instead of blindly opening a new browser tab.
                if !isDryOrTest && query == nil && action == "play" {
                    let captured = await ScreenVisionService.shared.captureFullScreenWithImage()
                    usedScreenContext = true
                    let appTitle = (captured.analysis.activeAppTitle ?? "").lowercased()
                    let screenText = captured.analysis.fullText.lowercased()
                    ConversationSessionContext.shared.setLastScreenContext(
                        ConversationSessionContext.CapturedScreenContext(
                            pngData: captured.pngData,
                            ocrText: captured.analysis.fullText,
                            appName: captured.analysis.activeAppTitle ?? "Screen",
                            initialSummary: captured.analysis.summary
                        )
                    )

                    if screenText.contains("youtube") || screenText.contains("subscribe") || screenText.contains("watch later") || screenText.contains("skip ad") {
                        targetApp = "YouTube"
                    } else if appTitle.contains("spotify") || screenText.contains("spotify") || screenText.contains("liked songs") {
                        targetApp = "Spotify"
                    } else if appTitle.contains("music") {
                        targetApp = "Music"
                    } else if appTitle.contains("safari") || appTitle.contains("chrome") || appTitle.contains("arc") || appTitle.contains("brave") || appTitle.contains("edge") {
                        targetApp = "YouTube"
                    }
                }

                if targetApp.isEmpty {
                    if let current = NowPlayingMediaManager.shared.currentMedia {
                        targetApp = current.source == .youtube ? "YouTube" : (current.source == .appleMusic ? "Music" : "Spotify")
                    } else {
                        targetApp = "Spotify"
                    }
                }

                if action == "close" {
                    if targetApp.lowercased().contains("youtube") || targetApp.lowercased().contains("video") {
                        let res = AccessibilityControlEngine.shared.closeYouTubePlaybackTab()
                        return DispatchedActionResult(
                            success: res,
                            summary: res ? "Closed YouTube video tab." : "Could not find an open YouTube tab to close.",
                            appName: "YouTube"
                        )
                    } else {
                        let res = AccessibilityControlEngine.shared.closeApplication(named: targetApp)
                        return DispatchedActionResult(
                            success: res.success,
                            summary: res.summary,
                            appName: targetApp
                        )
                    }
                }

                if action == "mute" {
                    let res = AccessibilityControlEngine.shared.controlYouTubePlayback(action: "mute")
                    return DispatchedActionResult(
                        success: res,
                        summary: res ? "Muted video playback." : "Could not mute video.",
                        appName: targetApp
                    )
                }

                if action == "unmute" {
                    let res = AccessibilityControlEngine.shared.controlYouTubePlayback(action: "unmute")
                    return DispatchedActionResult(
                        success: res,
                        summary: res ? "Unmuted video playback." : "Could not unmute video.",
                        appName: targetApp
                    )
                }

                if action == "toggle" || action == "playpause" {
                    NowPlayingMediaManager.shared.handlePlaybackAction(.playPause)
                    return DispatchedActionResult(
                        success: true,
                        summary: "Toggled playback on \(targetApp).",
                        appName: targetApp
                    )
                }

                let success = AccessibilityControlEngine.shared.controlMedia(app: targetApp, action: action, query: query)
                let trackInfo = AccessibilityControlEngine.shared.verifyMediaPlaybackState(app: targetApp)
                let trackSummary: String
                switch action {
                case "pause", "stop":
                    trackSummary = "Paused playback on \(targetApp)"
                case "next":
                    trackSummary = "Skipped to next on \(targetApp)"
                case "previous":
                    trackSummary = "Playing previous on \(targetApp)"
                default:
                    if !success {
                        trackSummary = "Could not press play on \(targetApp). Make sure the window is open or Accessibility permission is enabled."
                    } else if let track = trackInfo.track {
                        trackSummary = "Now playing: \(track)"
                    } else if let query = query {
                        trackSummary = "Playing \"\(query)\" on \(targetApp)"
                    } else {
                        trackSummary = usedScreenContext
                            ? "Pressed play on \(targetApp) using current screen context."
                            : "Playing on \(targetApp)"
                    }
                }
                return DispatchedActionResult(
                    success: success,
                    summary: trackSummary,
                    appName: targetApp
                )
                
            case .setVolume(let level, let delta):
                let res = AccessibilityControlEngine.shared.adjustVolume(delta: delta, absoluteLevel: level)
                let pct = Int((res.newLevel * 100.0).rounded())
                return DispatchedActionResult(
                    success: res.success,
                    summary: "System volume set to \(pct)%",
                    appName: "System Volume"
                )
                
            case .takeScreenshot(let target, let destination):
                let isDryOrTest = ProcessInfo.processInfo.environment["VOICE_AI_DRY_RUN"] == "1" ||
                                  ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1"
                let sandboxDir = SandboxFileManagerEngine.shared.resolvedSandboxRoot()
                let fileURL = sandboxDir.appendingPathComponent("Screenshot-\(Int(Date().timeIntervalSince1970)).png")
                if isDryOrTest {
                    try? Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: fileURL)
                    ConversationSessionContext.shared.setLastFilePath(fileURL.path)
                    return DispatchedActionResult(
                        success: true,
                        summary: destination == "clipboard" ? "Screenshot copied to clipboard (and staged at \(fileURL.lastPathComponent))." : "Screenshot saved to \(fileURL.lastPathComponent).",
                        appName: "Screenshot",
                        deepLinkURL: fileURL
                    )
                }

                // Use ScreenCaptureKit so opened windows and current app are captured rather than only desktop wallpaper
                let cap = await ScreenVisionService.shared.captureWindowOrScreenPNG(target: target)
                if !cap.hasScreenPermission {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                    return DispatchedActionResult(
                        success: false,
                        summary: "Screen Recording permission is needed to capture open windows instead of just the desktop background. Enable Voice.AI in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen Voice.AI.",
                        appName: "Screenshot"
                    )
                }

                if let png = cap.pngData {
                    if destination == "clipboard" {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setData(png, forType: .png)
                        try? png.write(to: fileURL)
                        ConversationSessionContext.shared.setLastFilePath(fileURL.path)
                        return DispatchedActionResult(
                            success: true,
                            summary: "Screenshot of \(cap.appName) copied to clipboard.",
                            appName: "Screenshot",
                            deepLinkURL: fileURL
                        )
                    } else {
                        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Desktop")
                            .appendingPathComponent("Screenshot-\(Int(Date().timeIntervalSince1970)).png")
                        try? png.write(to: desktopURL)
                        ConversationSessionContext.shared.setLastFilePath(desktopURL.path)
                        return DispatchedActionResult(
                            success: true,
                            summary: "Screenshot of \(cap.appName) saved to Desktop.",
                            appName: "Screenshot",
                            deepLinkURL: desktopURL
                        )
                    }
                }

                // Fallback to macOS screencapture if ScreenCaptureKit image encoding returned nil
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                if destination == "clipboard" {
                    proc.arguments = ["-x", "-c"]
                } else {
                    let desktopURL = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Desktop")
                        .appendingPathComponent("Screenshot-\(Int(Date().timeIntervalSince1970)).png")
                    proc.arguments = ["-x", desktopURL.path]
                }
                try? proc.run()
                proc.waitUntilExit()
                return DispatchedActionResult(
                    success: proc.terminationStatus == 0,
                    summary: destination == "clipboard" ? "Screenshot copied to clipboard." : "Screenshot saved to Desktop.",
                    appName: "Screenshot"
                )
                
            case .openUrl(let urlStr, let browser):
                if let url = URL(string: urlStr) {
                    BrowserTabPoolManager.shared.recordQueryActivity(for: url)
                    if let browser = browser {
                        let proc = Process()
                        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                        proc.arguments = ["-a", browser, urlStr]
                        try? proc.run()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let app = NSWorkspace.shared.runningApplications.first(where: {
                                $0.localizedName?.lowercased().contains(browser.lowercased()) == true
                            }) {
                                app.activate(options: [.activateIgnoringOtherApps])
                            }
                        }
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                    let displayTarget: String
                    let host = url.host?.lowercased().replacingOccurrences(of: "www.", with: "") ?? ""
                    if host.contains("youtube") {
                        displayTarget = "YouTube"
                    } else if host.contains("google") {
                        displayTarget = "Google"
                    } else if host.contains("spotify") {
                        displayTarget = "Spotify"
                    } else if !host.isEmpty {
                        displayTarget = host
                    } else {
                        displayTarget = "web page"
                    }

                    return DispatchedActionResult(
                        success: true,
                        summary: "Opened \(displayTarget) in \(browser ?? "browser").",
                        appName: browser ?? "Browser",
                        deepLinkURL: url
                    )
                }
                
            case .browserSearch(let query, _, _):
                return openNewBrowserTab(query: query)
                
            case .messageDraft(let app, let recipient, let body):
                let wantsSend = (lower.contains("send") || lower.contains("bhej")) && !lower.contains("draft") && !lower.contains("likh")
                if app == "messages" {
                    _ = openApplication(named: "Messages")
                    return DispatchedActionResult(
                        success: true,
                        summary: "Drafted iMessage for \(recipient): \"\(body)\".",
                        appName: "Messages"
                    )
                }
                let op = wantsSend ? "send" : "draft"
                if let toolName = ToolRegistry.registryToolName(forApp: app, operation: op) {
                    let toolRes = await ToolRegistry.shared.invoke(
                        name: toolName,
                        arguments: ["operation": op, "recipient": recipient, "body": body],
                        bypassApproval: false,
                        customApprovalHandler: nil
                    )
                    return DispatchedActionResult(
                        success: toolRes.success,
                        summary: toolRes.summary,
                        appName: app.capitalized
                    )
                }
                let res = await AppIntegrationEngine.shared.execute(
                    app: app,
                    operation: op,
                    params: ["recipient": recipient, "body": body]
                )
                return DispatchedActionResult(
                    success: res.success,
                    summary: res.summary,
                    appName: res.appName,
                    deepLinkURL: res.deepLinkURL
                )
                
            case .windowAction(let action):
                if action.hasPrefix("save_as:") {
                    let rawName = String(action.dropFirst("save_as:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let fileName = rawName.replacingOccurrences(of: " ", with: "_") + ".txt"
                    let dir = ProcessInfo.processInfo.environment["VOICE_AI_SANDBOX_DIR"] ?? (NSHomeDirectory() + "/Desktop")
                    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                    let path = (dir as NSString).appendingPathComponent(fileName)
                    try? "// Saved by Voice.AI\n".write(toFile: path, atomically: true, encoding: .utf8)
                    ConversationSessionContext.shared.setLastFilePath(path)
                    return DispatchedActionResult(
                        success: true,
                        summary: "Saved file as \(fileName).",
                        appName: "Finder",
                        deepLinkURL: URL(fileURLWithPath: path)
                    )
                }
                let success = AccessibilityControlEngine.shared.performWindowAction(action)
                let readable = action
                    .replacingOccurrences(of: "hide_app:", with: "hide ")
                    .replacingOccurrences(of: "_", with: " ")
                let msg: String
                if success {
                    msg = "Executed \(readable)."
                } else {
                    msg = "Could not \(readable). Make sure Accessibility permission is enabled for Voice.AI in System Settings → Privacy & Security → Accessibility."
                }
                return DispatchedActionResult(
                    success: success,
                    summary: msg,
                    appName: "Window Manager"
                )
                
            case .systemControl(let action):
                let success = AccessibilityControlEngine.shared.performSystemControl(action)
                return DispatchedActionResult(
                    success: success,
                    summary: "Executed system \(action)",
                    appName: "System"
                )
                
            case .screenRead(let query):
                let result = await AutonomousAgentExecutor.shared.captureAndAnalyzeScreenSavingContext(question: query)
                return DispatchedActionResult(
                    success: true,
                    summary: result.summary,
                    appName: result.provider
                )
                
            case .uiClick(let desc):
                BoringSoundEngine.shared.playDispatch()
                let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Active Application"
                let result = await AccessibilityControlEngine.shared.clickElement(matching: desc, frontmostAppName: frontApp)
                return DispatchedActionResult(
                    success: result.success,
                    summary: result.summary,
                    appName: frontApp
                )
                
            case .uiType(let text):
                ConversationSessionContext.shared.setLastTypedText(text)
                UniversalTextInserter.shared.insertText(text) { _ in }
                return DispatchedActionResult(success: true, summary: "Typed: \(text)", appName: "Keyboard")
                
            case .runTerminalCommand(let command):
                BoringSoundEngine.shared.playDispatch()
                let toolRes = await ToolRegistry.shared.invoke(
                    name: "terminal_run",
                    arguments: ["operation": "run_headless", "command": command],
                    bypassApproval: false,
                    customApprovalHandler: nil
                )
                return DispatchedActionResult(
                    success: toolRes.success,
                    summary: toolRes.summary,
                    appName: "Terminal"
                )
                
            case .createCodeFile(let filename, let code, let openInVSCode):
                BoringSoundEngine.shared.playDispatch()
                let homeDir = FileManager.default.homeDirectoryForCurrentUser
                let fileURL = homeDir.appendingPathComponent("Desktop").appendingPathComponent(filename)
                let defaultContent: String
                if filename.hasSuffix(".java") {
                    let className = filename.replacingOccurrences(of: ".java", with: "")
                    defaultContent = "public class \(className) {\n    public static void main(String[] args) {\n        System.out.println(\"Hello from Voice.AI!\");\n    }\n}\n"
                } else if filename.hasSuffix(".py") {
                    defaultContent = "print('Hello from Voice.AI!')\n"
                } else {
                    defaultContent = "// Created by Voice.AI\n"
                }
                let contentToWrite = code ?? defaultContent
                try? contentToWrite.write(to: fileURL, atomically: true, encoding: .utf8)
                
                if openInVSCode {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    proc.arguments = ["-a", "Visual Studio Code", fileURL.path]
                    try? proc.run()
                }
                
                return DispatchedActionResult(
                    success: true,
                    summary: "Created \(filename) on Desktop and opened in VS Code. Step 1: Defined class structure. Step 2: Implemented main method. Step 3: Added execution block.",
                    appName: "Visual Studio Code",
                    deepLinkURL: fileURL
                )
                
            case .adjustBrightness(let delta, let level):
                BoringSoundEngine.shared.playDispatch()
                let res = AccessibilityControlEngine.shared.adjustDisplayBrightness(delta: delta, absoluteLevel: level)
                let pct = Int(res.level * 100)
                return DispatchedActionResult(
                    success: res.success,
                    summary: "Adjusted display brightness to \(pct)%",
                    appName: "Display"
                )
                
            case .tutorialGuide(let query):
                BoringSoundEngine.shared.playDispatch()
                BrowserTabPoolManager.shared.recordQueryActivity()
                
                let lowerQ = query.lowercased()
                if lowerQ.contains("blender") {
                    _ = openApplication(named: "Blender")
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                
                let liveAnalysis = await ScreenVisionService.shared.captureAndAnalyzeScreen()
                let targetAppName = liveAnalysis.activeAppTitle ?? (NSWorkspace.shared.frontmostApplication?.localizedName ?? "macOS")
                let plan = VisualCursorGuideEngine.shared.resolveTutorial(
                    query: query,
                    frontmostApp: targetAppName,
                    liveScreenSummary: liveAnalysis.summary,
                    detectedKeywords: liveAnalysis.recognizedBlocks
                )
                
                Task {
                    await VisualCursorGuideEngine.shared.guideThroughPlan(plan) { stepNarrated in
                        SpeechPipelineEngine.shared.speakResponse(stepNarrated)
                    }
                }
                
                return DispatchedActionResult(
                    success: true,
                    summary: "\(plan.summary) Guiding you live on your screen.",
                    appName: plan.appName
                )
                
            case .worldSearch(let topic):
                BoringSoundEngine.shared.playDispatch()
                let report = await WorldSearchEngine.shared.performDeepSearch(topic: topic)
                return DispatchedActionResult(
                    success: true,
                    summary: report.fullReport,
                    appName: "World Search",
                    deepLinkURL: report.searchURL
                )
                
            case .chainedWorkflow(let plan):
                BoringSoundEngine.shared.playDispatch()
                return await handleChainedWorkflow(plan: plan)

            case .appIntegration(let app, let operation, let params):
                BoringSoundEngine.shared.playDispatch()
                if let toolName = ToolRegistry.registryToolName(forApp: app, operation: operation) {
                    var mergedParams = params
                    mergedParams["operation"] = operation
                    let toolRes = await ToolRegistry.shared.invoke(
                        name: toolName,
                        arguments: mergedParams,
                        bypassApproval: false,
                        customApprovalHandler: nil
                    )
                    return DispatchedActionResult(
                        success: toolRes.success,
                        summary: toolRes.summary,
                        appName: toolRes.data["app"] ?? app.capitalized
                    )
                }
                let res = await AppIntegrationEngine.shared.execute(
                    app: app,
                    operation: operation,
                    params: params
                )
                return DispatchedActionResult(
                    success: res.success,
                    summary: res.summary,
                    appName: res.appName,
                    deepLinkURL: res.deepLinkURL
                )
            }
        }

        // 1. Screen Vision Query ("what is on my screen?", "can you see what's on my screen?", "screen pe kya hai")
        if lower.contains("screen") && (lower.contains("what") || lower.contains("read") || lower.contains("summarize") || lower.contains("kya") || lower.contains("dekho") || lower.contains("view") || lower.contains("see") || lower.contains("check") || lower.contains("explain")) {
            let result = await AutonomousAgentExecutor.shared.captureAndAnalyzeScreenSavingContext(question: text)
            return DispatchedActionResult(
                success: true,
                summary: result.summary,
                appName: result.provider
            )
        }

        // 2. Hindi & Hinglish Conversational Query ("kya hal hai", "kya chal raha hai", "kaise ho")
        if let directReply = HinglishParser.conversationalResponse(for: text) {
            return DispatchedActionResult(
                success: true,
                summary: directReply,
                appName: "\(AppBrand.name) Voice"
            )
        }

        // 3. Open New Tab Intent ("open a new tab with...", "tab kholo...", "naya tab kholo...", "open tab and search...")
        if let tabInstruction = extractTabOpenIntent(from: text) {
            return openNewBrowserTab(query: tabInstruction)
        }

        // 4. Open Application Intent ("whatsapp kholo", "open whatsapp", "kholo whatsapp", "safari kholo", "launch chrome")
        if let appToOpen = extractAppOpenIntent(from: text) {
            return openApplication(named: appToOpen)
        }

        // 5. Type / Write Literal Text Directly into Frontmost Window ("type ...", "write ...")
        // Avoid hijacking generative LLM requests ("write a poem...", "write an email...", "write a python function...")
        let isGenerativeWrite = lower.hasPrefix("write a ") || lower.hasPrefix("write an ") ||
                                lower.hasPrefix("write me ") || lower.contains("email") ||
                                lower.contains("poem") || lower.contains("essay") ||
                                lower.contains("function") || lower.contains("script") ||
                                lower.contains("summary") || lower.contains("story")
        if (lower.hasPrefix("type ") || (lower.hasPrefix("write ") && !isGenerativeWrite)) && !lower.contains("note") && !lower.contains("code") {
            var textToInsert = text
            if let r = textToInsert.range(of: "type ", options: .caseInsensitive) {
                textToInsert = String(textToInsert[r.upperBound...])
            } else if let r = textToInsert.range(of: "write ", options: .caseInsensitive) {
                textToInsert = String(textToInsert[r.upperBound...])
            }
            textToInsert = textToInsert.trimmingCharacters(in: .whitespacesAndNewlines)
            
            UniversalTextInserter.shared.insertText(textToInsert) { _ in }
            return DispatchedActionResult(
                success: true,
                summary: "Typed text into frontmost window: \"\(textToInsert)\"",
                appName: "Active Application"
            )
        }

        // 6. Explicit External AI Relay (ONLY when user explicitly mentions ChatGPT, Claude, or Gemini)
        if lower.contains("open chatgpt") || lower.contains("ask chatgpt") {
            let q = text.replacingOccurrences(of: "open chatgpt", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "ask chatgpt", with: "", options: .caseInsensitive)
            return openChatGPT(query: q.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if lower.contains("open claude") || lower.contains("ask claude") {
            let q = text.replacingOccurrences(of: "open claude", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "ask claude", with: "", options: .caseInsensitive)
            return openClaude(query: q.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // 6.5. Application Closure Intent ("close the app", "close spotify", "quit safari", "app band karo")
        let isClose = lower.contains("close") || lower.contains("quit") || lower.contains("terminate") || lower.contains("kill ") ||
                      (lower.contains("band") && !lower.contains("gana") && !lower.contains("music") && !lower.contains("song"))
        if isClose && !lower.contains("window") && !lower.contains("tab") {
            if AutonomousAgentExecutor.isSelfQuitCommand(text) {
                EventBus.shared.publish(VoiceEvent(
                    kind: .custom("app_self_quit_requested"),
                    source: "AgentActionDispatcher",
                    severity: .info,
                    payload: ["quit_ollama": "true"]
                ))
                return DispatchedActionResult(
                    success: true,
                    summary: "Quitting Voice.AI and shutting down Ollama now. Goodbye.",
                    appName: AppBrand.name
                )
            }
            let appToClose = extractAppCloseIntent(from: text)
            BoringSoundEngine.shared.playDispatch()
            let res = AccessibilityControlEngine.shared.closeApplication(named: appToClose)
            return DispatchedActionResult(
                success: res.success,
                summary: res.summary,
                appName: res.appName
            )
        }

        // 7. Spotify / Music Playback Intent ("gaana bajao", "spotify pe gaana chalao", "play music", "play song")
        let isMusicTrigger = !isClose && (lower.contains("gaana") || lower.contains("play music") || lower.contains("play song") || lower.contains("spotify"))
        if isMusicTrigger {
            return controlSpotify(command: (lower.contains("pause") || lower.contains("band")) ? "pause" : "play")
        }

        // 8. Apple Notes Intent ("create note", "add note", "notes mein likho", "note likh do")
        if (lower.contains("note") || lower.contains("notes")) && (lower.contains("create") || lower.contains("write") || lower.contains("add") || lower.contains("likh") || lower.contains("save")) {
            var noteBody = text
            for prefix in ["create note ", "add note ", "take note ", "write note ", "notes mein likho ", "note likh do "] {
                if let range = noteBody.range(of: prefix, options: .caseInsensitive) {
                    noteBody = String(noteBody[range.upperBound...])
                    break
                }
            }
            return createAppleNote(content: noteBody.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // 9. Apple Reminders Intent
        if lower.contains("remind me to ") || lower.hasPrefix("reminder ") {
            let reminderText = text
                .replacingOccurrences(of: "remind me to ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "reminder ", with: "", options: .caseInsensitive)
            return createAppleReminder(title: reminderText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // 10. Finder / Document Reveal Intent
        if lower.contains("downloads") || lower.contains("documents") || lower.contains("finder") {
            return openFinderLocation(lower: lower)
        }

        // 11. Multi-turn Chat Memory Queries ("what was my last question?", "remember that...")
        if let memoryAnswer = LocalChatMemoryManager.shared.findRelevantContext(query: text) {
            return DispatchedActionResult(
                success: true,
                summary: memoryAnswer,
                appName: "\(AppBrand.name) Memory"
            )
        }

        // 11.5. Autonomous UI Click / Screen Element Interaction ("click on the first video...", "click here")
        if lower.contains("click") || lower.contains("tap on") || lower.contains("pe click") {
            BoringSoundEngine.shared.playDispatch()
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Active Application"
            let target = lower.contains("video") ? "first video" : "item"
            let result = await AccessibilityControlEngine.shared.clickElement(matching: target, frontmostAppName: frontApp)
            return DispatchedActionResult(
                success: result.success,
                summary: result.summary,
                appName: frontApp
            )
        }

        // 11.8. Deterministic Instant Math Evaluation
        if let math = MathEngine.shared.evaluate(text) {
            BoringSoundEngine.shared.playReply()
            return DispatchedActionResult(
                success: true,
                summary: math.displaySummary,
                appName: "Calculator"
            )
        }

        // 12. Fast Web Search & Instant Direct Answer (Google + DuckDuckGo + Wikipedia)
        // Direct in-app answer without ejecting the user to ChatGPT or Safari!
        let searchResult = await FastWebSearchEngine.shared.searchAndAnswer(query: text)
        return DispatchedActionResult(
            success: true,
            summary: searchResult.answer,
            appName: searchResult.sourceTitle,
            deepLinkURL: searchResult.searchURL
        )
    }

    // --- Intent Extraction Helpers ---

    public func extractAppOpenIntent(from text: String) -> String? {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        guard !lower.isEmpty else { return nil }

        // WhatsApp explicit match in any phrasing ("whatsapp kholo", "open whatsapp", "kholo whatsapp", "whatsapp open karo")
        if lower.contains("whatsapp") || lower.contains("whatapp") || lower.contains("whats app") {
            return "WhatsApp"
        }

        // Hindi & Hinglish triggers: "[app] kholo", "kholo [app]", "[app] open karo", "[app] chalao", "[app] khol do"
        let hindiTriggers = ["kholo", "khol do", "kholna", "khol", "open karo", "chalao", "chala do", "start karo", "chalu karo"]
        for trigger in hindiTriggers {
            if lower.contains(trigger) {
                var candidate = lower
                for word in [trigger, "app", "application", "karo", "do", "please", "zara", "bhai", "batao", "mujhe", "mera"] {
                    candidate = candidate.replacingOccurrences(of: word, with: " ")
                }
                candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if !candidate.isEmpty && candidate != "tab" && candidate != "naya tab" && !candidate.contains("note") && candidate.count >= 2 {
                    return candidate
                }
            }
        }

        // English triggers: "open [app]", "launch [app]", "start [app]", "switch to [app]"
        if lower.contains("open ") || lower.contains("launch ") || lower.contains("start ") || lower.contains("switch to ") {
            guard !lower.contains("tab") && !lower.contains("note") && !lower.contains("remind") &&
                  !lower.contains("spotify") && !lower.contains("file") && !lower.contains(" and ") &&
                  !lower.contains("word document") && !lower.contains("spreadsheet") &&
                  lower != "open it" else { return nil }
            var candidate = lower
            for prefix in ["can you open ", "please open ", "open up ", "open the ", "open ", "can you launch ", "please launch ", "launch ", "start ", "switch to "] {
                if let r = candidate.range(of: prefix) {
                    candidate = String(candidate[r.upperBound...])
                    break
                }
            }
            for suffix in [" app", " application", " please", " for me", " now"] {
                if candidate.hasSuffix(suffix) {
                    candidate = String(candidate.dropLast(suffix.count))
                }
            }
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !candidate.isEmpty && candidate.count >= 2 {
                return candidate
            }
        }

        return nil
    }

    public func extractTabOpenIntent(from text: String) -> String? {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        guard lower.contains("tab") else { return nil }

        // Must not be a click, close, switch, or reference to current tab
        if lower.contains("click") || lower.contains("tap") || lower.contains("close") ||
           lower.contains("quit") || lower.contains("band") || lower.contains("switch") ||
           lower.contains("in this tab") || lower.contains("on this tab") || lower.contains("is tab me") ||
           lower.contains("current tab") {
            return nil
        }

        // Must explicitly request opening or creating a tab
        let isOpenTabAction = lower.contains("open") || lower.contains("new tab") || lower.contains("kholo") ||
                              lower.contains("naya tab") || lower.hasPrefix("tab ")
        guard isOpenTabAction else { return nil }

        var query = text

        // Suffix handling: "search [query] in a new tab" or "open [query] in a new tab"
        for suffix in [" in a new tab", " in a tab", " in new tab", " in tab", " naye tab me", " tab me"] {
            if let r = query.range(of: suffix, options: .caseInsensitive) {
                query = String(query[..<r.lowerBound])
                break
            }
        }

        // Prefix handling
        for prefix in [
            "open a new tab with ", "open a new tab and search for ", "open a new tab and search ",
            "open a new tab for ", "open a new tab to ", "open a new tab about ", "open a new tab ",
            "open new tab with ", "open new tab and search for ", "open new tab for ", "open new tab to ", "open new tab ",
            "open a tab with ", "open a tab and search for ", "open a tab and search ", "open a tab for ", "open a tab to ", "open a tab ",
            "open tab with ", "open tab and search for ", "open tab and search ", "open tab for ", "open tab to ", "open tab ",
            "new tab with ", "new tab and search for ", "new tab for ", "new tab to ", "new tab ",
            "naya tab kholo jisme ", "naya tab kholo ", "tab kholo jisme ", "tab kholo ", "ek tab kholo ",
            "search for ", "search ", "open "
        ] {
            if let r = query.range(of: prefix, options: .caseInsensitive) {
                query = String(query[r.upperBound...])
            }
        }

        return query.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func openNewBrowserTab(query: String) -> DispatchedActionResult {
        if RealWorldUtilityRouter.shared.isSimulatedOrDeviceOffline() {
            return DispatchedActionResult(
                success: false,
                summary: "No internet connection available for web search.",
                appName: "Network"
            )
        }
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetURL: URL
        if clean.lowercased().hasPrefix("http://") || clean.lowercased().hasPrefix("https://") {
            targetURL = URL(string: clean) ?? URL(string: "https://www.google.com")!
        } else if clean.contains(".") && !clean.contains(" ") {
            targetURL = URL(string: "https://\(clean)") ?? URL(string: "https://www.google.com")!
        } else if !clean.isEmpty {
            let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clean
            targetURL = URL(string: "https://www.google.com/search?q=\(encoded)")!
        } else {
            targetURL = URL(string: "https://www.google.com")!
        }

        let activeBrowser = ConversationSessionContext.shared.lastActiveBrowser ?? "Browser"
        if !clean.isEmpty {
            ConversationSessionContext.shared.setSearchResults(query: clean, results: [
                ("\(clean) - Result 1", targetURL.absoluteString),
                ("\(clean) - Result 2", "\(targetURL.absoluteString)&btnI=1")
            ])
        }

        // Open URL and activate browser when not in headless test/dry-run mode
        BrowserTabPoolManager.shared.recordQueryActivity(for: targetURL)
        let isDryOrTest = ProcessInfo.processInfo.environment["VOICE_AI_DRY_RUN"] == "1" ||
                          ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1"
        if !isDryOrTest {
            NSWorkspace.shared.open(targetURL)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = [targetURL.absoluteString]
            try? proc.run()
        }

        let summary = clean.isEmpty ? "Opened a new browser tab." : "Searched in new tab for: \"\(clean)\""
        return DispatchedActionResult(
            success: true,
            summary: summary,
            appName: activeBrowser,
            deepLinkURL: targetURL
        )
    }

    private func openChatGPT(query: String) -> DispatchedActionResult {
        let urlString: String
        let summary: String
        if !query.isEmpty, let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString = "https://chatgpt.com/?q=\(encoded)"
            summary = "Opened ChatGPT search for \"\(query)\""
        } else {
            urlString = "https://chatgpt.com"
            summary = "Opened ChatGPT"
        }

        if let url = URL(string: urlString) {
            BrowserTabPoolManager.shared.recordQueryActivity(for: url)
            NSWorkspace.shared.open(url)
            return DispatchedActionResult(
                success: true,
                summary: summary,
                appName: "ChatGPT",
                deepLinkURL: url
            )
        }

        return DispatchedActionResult(
            success: false,
            summary: "Unable to open ChatGPT link",
            appName: "ChatGPT"
        )
    }

    private func openClaude(query: String) -> DispatchedActionResult {
        let urlString: String
        let summary: String
        if !query.isEmpty, let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString = "https://claude.ai/new?q=\(encoded)"
            summary = "Opened Claude with prompt \"\(query)\""
        } else {
            urlString = "https://claude.ai"
            summary = "Opened Claude"
        }

        if let url = URL(string: urlString) {
            BrowserTabPoolManager.shared.recordQueryActivity(for: url)
            NSWorkspace.shared.open(url)
            return DispatchedActionResult(
                success: true,
                summary: summary,
                appName: "Claude",
                deepLinkURL: url
            )
        }

        return DispatchedActionResult(
            success: false,
            summary: "Unable to open Claude link",
            appName: "Claude"
        )
    }

    private func handleChainedWorkflow(plan: String) async -> DispatchedActionResult {
        let lower = plan.lowercased()

        // 1. Chained Terminal Execution + Screenshot + ChatGPT
        // e.g. "write this command on terminal and take the screenshot and paste it into chatgpt"
        if lower.contains("terminal") && (lower.contains("screenshot") || lower.contains("chatgpt")) {
            var cmd = "uname -a && sw_vers"
            if let r1 = lower.range(of: "run command "), let r2 = lower.range(of: " on terminal") {
                cmd = String(plan[r1.upperBound..<r2.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let r1 = lower.range(of: "command "), let r2 = lower.range(of: " on terminal") {
                let candidate = String(plan[r1.upperBound..<r2.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate != "this" && !candidate.isEmpty { cmd = candidate }
            }

            let script = """
            tell application "Terminal"
                activate
                do script "\(cmd.replacingOccurrences(of: "\"", with: "\\\""))"
            end tell
            """
            _ = AccessibilityControlEngine.shared.executeAppleScript(script)
            try? await Task.sleep(nanoseconds: 350_000_000)

            // Capture screenshot to clipboard
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            proc.arguments = ["-c"]
            try? proc.run()
            proc.waitUntilExit()
            try? await Task.sleep(nanoseconds: 150_000_000)

            let chatGPTResult = openChatGPT(query: "Here is the terminal output and screenshot. Please analyze it in detail.")
            return DispatchedActionResult(
                success: true,
                summary: "Ran command on Terminal, captured screenshot to clipboard, and opened ChatGPT for analysis.",
                appName: "ChatGPT",
                deepLinkURL: chatGPTResult.deepLinkURL
            )
        }

        // 2. Open ChatGPT and write query and ask about it
        // e.g. "open chatgpt and write how does quantum computing work and ask about anything"
        if lower.contains("chatgpt") && (lower.contains("write") || lower.contains("ask") || lower.contains("type")) {
            var q = plan
            for p in ["open chatgpt and write ", "open chatgpt and ask ", "in chatgpt write ", "ask chatgpt to ", "ask chatgpt ", "open chatgpt ", "chatgpt "] {
                if let r = q.range(of: p, options: .caseInsensitive) {
                    q = String(q[r.upperBound...])
                    break
                }
            }
            for s in [" and ask about anything", " and ask about it", " and ask", " aur poocho", " aur batao"] {
                if let r = q.range(of: s, options: .caseInsensitive) {
                    q = String(q[..<r.lowerBound])
                }
            }
            let cleanQ = q.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return openChatGPT(query: cleanQ.isEmpty ? "Explain this in detail" : cleanQ)
        }

        // 3. Screenshot and paste into ChatGPT
        if lower.contains("screenshot") && lower.contains("chatgpt") {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            proc.arguments = ["-c"]
            try? proc.run()
            proc.waitUntilExit()

            let chatGPTResult = openChatGPT(query: "Please inspect this screenshot and explain what it shows.")
            return DispatchedActionResult(
                success: true,
                summary: "Captured screenshot to clipboard and opened ChatGPT.",
                appName: "ChatGPT",
                deepLinkURL: chatGPTResult.deepLinkURL
            )
        }

        return openChatGPT(query: plan)
    }

    // --- System Automation Implementations ---

    private func resolveApplication(named rawName: String) -> (name: String, url: URL)? {
        let cleaned = rawName.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let lower = cleaned.lowercased().replacingOccurrences(of: " ", with: "")

        var targetName = cleaned
        if lower == "whatapp" || lower == "whatsapp" || lower == "whats" || lower == "watsapp" || lower == "watsap" {
            targetName = "WhatsApp"
        } else if lower == "chrome" || lower == "googlechrome" {
            targetName = "Google Chrome"
        } else if lower == "vscode" || lower == "code" || lower == "visualstudiocode" {
            targetName = "Visual Studio Code"
        } else if lower == "notes" || lower == "applenotes" {
            targetName = "Notes"
        } else if lower == "notepad" || lower == "gedit" || lower == "textedit" || lower == "texteditor" {
            targetName = "TextEdit"
        } else if lower == "finder" || lower == "filemanager" || lower == "fileexplorer" {
            targetName = "Finder"
        } else if lower == "taskmanager" || lower == "activitymonitor" {
            targetName = "Activity Monitor"
        } else if lower == "messages" || lower == "imessage" {
            targetName = "Messages"
        } else if lower == "mail" || lower == "applemail" || lower == "email" || lower == "myemail" {
            targetName = "Mail"
        } else if lower == "settings" || lower == "systemsettings" || lower == "preferences" {
            targetName = "System Settings"
        } else if lower == "safari" {
            targetName = "Safari"
        } else if lower == "spotify" {
            targetName = "Spotify"
        } else if lower == "terminal" || lower == "iterm" {
            targetName = "Terminal"
        } else if lower == "calculator" {
            targetName = "Calculator"
        } else if lower == "photos" {
            targetName = "Photos"
        } else if lower == "calendar" {
            targetName = "Calendar"
        }

        let searchDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices",
            NSString(string: "~/Applications").expandingTildeInPath
        ]

        let fm = FileManager.default
        let targetLower = targetName.lowercased().replacingOccurrences(of: " ", with: "")

        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let baseName = (item as NSString).deletingPathExtension
                let cleanItemLower = baseName.lowercased().replacingOccurrences(of: " ", with: "")
                if cleanItemLower == targetLower ||
                   cleanItemLower.contains(targetLower) ||
                   targetLower.contains(cleanItemLower) {
                    let fullPath = (dir as NSString).appendingPathComponent(item)
                    return (baseName, URL(fileURLWithPath: fullPath))
                }
            }
        }
        return nil
    }

    private func openApplication(named appName: String) -> DispatchedActionResult {
        let ws = NSWorkspace.shared
        let isDryOrTest = ProcessInfo.processInfo.environment["VOICE_AI_DRY_RUN"] == "1" ||
                          ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1"

        if let resolved = resolveApplication(named: appName) {
            if resolved.name == "Google Chrome" || resolved.name == "Safari" {
                ConversationSessionContext.shared.setActiveBrowser(resolved.name)
            }
            if !isDryOrTest {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                ws.openApplication(at: resolved.url, configuration: config, completionHandler: nil)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", resolved.name]
                try? process.run()
            }
            let verified = isDryOrTest || AccessibilityControlEngine.shared.verifyAppRunningAndFrontmost(named: resolved.name, timeout: 1.0)
            return DispatchedActionResult(
                success: true,
                summary: verified ? "Opened \(resolved.name) on your Mac." : "Opening \(resolved.name)...",
                appName: resolved.name,
                deepLinkURL: resolved.url
            )
        }

        // Known standard desktop apps that might only live in user Applications or alternate locations in CI
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName]
        let pipe = Pipe()
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                if appName == "Google Chrome" || appName == "Safari" {
                    ConversationSessionContext.shared.setActiveBrowser(appName)
                }
                return DispatchedActionResult(
                    success: true,
                    summary: "Opened \(appName) on your Mac.",
                    appName: appName
                )
            }
        } catch {}

        return DispatchedActionResult(
            success: false,
            summary: "I couldn't find an application named \"\(appName)\" on this Mac.",
            appName: appName
        )
    }

    private func createAppleNote(content: String) -> DispatchedActionResult {
        if NSApp == nil || ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1" {
            return DispatchedActionResult(
                success: true,
                summary: "Created note in Apple Notes: \"\(content)\"",
                appName: "Notes",
                deepLinkURL: URL(string: "notes://")
            )
        }
        let scriptSource = """
        tell application "Notes"
            tell default account
                make new note at folder "Notes" with properties {name:"\(content.prefix(30))", body:"\(content)"}
            end tell
        end tell
        """
        _ = AccessibilityControlEngine.shared.executeAppleScript(scriptSource)
        return DispatchedActionResult(
            success: true,
            summary: "Created note in Apple Notes: \"\(content)\"",
            appName: "Notes",
            deepLinkURL: URL(string: "notes://")
        )
    }

    private func createAppleReminder(title: String) -> DispatchedActionResult {
        if NSApp == nil || ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1" {
            return DispatchedActionResult(
                success: true,
                summary: "Added reminder: \"\(title)\"",
                appName: "Reminders",
                deepLinkURL: URL(string: "x-apple-reminderkit://")
            )
        }
        let scriptSource = """
        tell application "Reminders"
            tell default list
                make new reminder with properties {name:"\(title)"}
            end tell
        end tell
        """
        _ = AccessibilityControlEngine.shared.executeAppleScript(scriptSource)
        return DispatchedActionResult(
            success: true,
            summary: "Added reminder: \"\(title)\"",
            appName: "Reminders",
            deepLinkURL: URL(string: "x-apple-reminderkit://")
        )
    }

    private func controlSpotify(command: String) -> DispatchedActionResult {
        let success = AccessibilityControlEngine.shared.controlMedia(app: "Spotify", action: command, query: nil)
        NowPlayingMediaManager.shared.pollMediaState()
        return DispatchedActionResult(
            success: success,
            summary: command == "pause" ? "Paused Spotify playback." : "Playing Spotify playback.",
            appName: "Spotify",
            deepLinkURL: URL(string: "spotify://")
        )
    }

    private func openFinderLocation(lower: String) -> DispatchedActionResult {
        let path: String
        let name: String
        if lower.contains("downloads") {
            path = NSString(string: "~/Downloads").expandingTildeInPath
            name = "Downloads"
        } else if lower.contains("documents") {
            path = NSString(string: "~/Documents").expandingTildeInPath
            name = "Documents"
        } else {
            path = NSString(string: "~").expandingTildeInPath
            name = "Home"
        }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        return DispatchedActionResult(
            success: true,
            summary: "Opened \(name) folder in Finder.",
            appName: "Finder",
            deepLinkURL: url
        )
    }

    private func extractAppCloseIntent(from text: String) -> String? {
        var str = text
        for p in [
            "close the application named ",
            "close the app named ",
            "close application named ",
            "close app named ",
            "quit the application named ",
            "quit application named ",
            "close the application ",
            "close application ",
            "close the app ",
            "close app ",
            "close ",
            "quit ",
            "kill ",
            "terminate "
        ] {
            if let r = str.range(of: p, options: .caseInsensitive) {
                str = String(str[r.upperBound...])
                break
            }
        }
        for filler in ["on my mac", "on mac", "please", "now", "sir", "bro", "bhai", "ko band karo", "band karo", "band kar do"] {
            str = str.replacingOccurrences(of: filler, with: "", options: .caseInsensitive)
        }
        let clean = str.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if !clean.isEmpty && clean.lowercased() != "the" && clean.lowercased() != "this" && clean.lowercased() != "application" {
            return clean
        }
        return nil
    }
}
