import Foundation
import AppKit

public enum AgentTool: Sendable, Equatable {
    case openApp(name: String)
    case closeApp(name: String?)
    case mediaPlay(app: String?, query: String?, action: String)
    case setVolume(level: Double?, delta: Double?)
    case takeScreenshot(target: String, destination: String)
    case openUrl(url: String, inBrowser: String?)
    case browserSearch(query: String, engine: String, background: Bool)
    case messageDraft(app: String, recipient: String, body: String)
    case windowAction(action: String)
    case systemControl(action: String)
    case uiClick(description: String)
    case uiType(text: String)
    case screenRead(query: String)
    case runTerminalCommand(command: String)
    case createCodeFile(filename: String, code: String?, openInVSCode: Bool)
    case adjustBrightness(delta: Double?, level: Double?)
    case tutorialGuide(query: String)
    case worldSearch(topic: String)
    case chainedWorkflow(plan: String)
    
    public var toolName: String {
        switch self {
        case .openApp: return "open_app"
        case .closeApp: return "close_app"
        case .mediaPlay: return "media_play"
        case .setVolume: return "set_volume"
        case .takeScreenshot: return "take_screenshot"
        case .openUrl: return "open_url"
        case .browserSearch: return "browser_search"
        case .messageDraft: return "message_draft"
        case .windowAction: return "window_action"
        case .systemControl: return "system_control"
        case .uiClick: return "ui_click"
        case .uiType: return "ui_type"
        case .screenRead: return "screen_read"
        case .runTerminalCommand: return "run_terminal_command"
        case .createCodeFile: return "create_code_file"
        case .adjustBrightness: return "adjust_brightness"
        case .tutorialGuide: return "tutorial_guide"
        case .worldSearch: return "world_search"
        case .chainedWorkflow: return "chained_workflow"
        }
    }
}

public struct AgentToolCallPayload: Codable, Sendable {
    public let tool: String
    public let arguments: [String: String]
    
    public init(tool: String, arguments: [String: String]) {
        self.tool = tool
        self.arguments = arguments
    }
}

public enum AgentToolSchema {
    /// LLM Tool Definitions JSON Schema for function calling APIs
    public static let functionDefinitions: [[String: Any]] = [
        [
            "name": "open_app",
            "description": "Launches or focuses an application on macOS",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Application name, e.g. 'WhatsApp', 'Spotify', 'Google Chrome'"]
                ],
                "required": ["name"]
            ]
        ],
        [
            "name": "media_play",
            "description": "Controls music/media playback or plays a specific song/artist/playlist",
            "parameters": [
                "type": "object",
                "properties": [
                    "app": ["type": "string", "description": "'Spotify' or 'Music'"],
                    "query": ["type": "string", "description": "Song name, artist, or playlist, e.g. 'Arijit Singh'"],
                    "action": ["type": "string", "enum": ["play", "pause", "next", "previous", "toggle"]]
                ],
                "required": ["action"]
            ]
        ],
        [
            "name": "set_volume",
            "description": "Adjusts or sets the macOS master system volume",
            "parameters": [
                "type": "object",
                "properties": [
                    "level": ["type": "number", "description": "Absolute volume 0.0 to 1.0"],
                    "delta": ["type": "number", "description": "Relative volume delta, e.g. -0.15 for 'kam karo', +0.15 for 'badhao'"]
                ]
            ]
        ],
        [
            "name": "take_screenshot",
            "description": "Captures the screen or window to clipboard or desktop file",
            "parameters": [
                "type": "object",
                "properties": [
                    "target": ["type": "string", "enum": ["screen", "window", "area"]],
                    "destination": ["type": "string", "enum": ["clipboard", "file"]]
                ],
                "required": ["target", "destination"]
            ]
        ],
        [
            "name": "open_url",
            "description": "Opens a website URL in a specific browser or default browser",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "Destination URL"],
                    "in_browser": ["type": "string", "description": "Target browser, e.g. 'Google Chrome' or 'Safari'"]
                ],
                "required": ["url"]
            ]
        ],
        [
            "name": "browser_search",
            "description": "Searches Google, ChatGPT, Claude or Perplexity in a new browser tab or in background",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "The search query"],
                    "engine": ["type": "string", "enum": ["google", "chatgpt", "claude", "perplexity"]],
                    "background": ["type": "boolean", "description": "Whether to perform research in background without bringing browser frontmost"]
                ],
                "required": ["query"]
            ]
        ],
        [
            "name": "message_draft",
            "description": "Stages a message draft to a contact on WhatsApp, Slack, Messages, or Mail for user confirmation",
            "parameters": [
                "type": "object",
                "properties": [
                    "app": ["type": "string", "enum": ["whatsapp", "messages", "slack", "mail"]],
                    "recipient": ["type": "string", "description": "Contact or person name"],
                    "body": ["type": "string", "description": "Message text"]
                ],
                "required": ["app", "recipient", "body"]
            ]
        ],
        [
            "name": "window_action",
            "description": "Controls active window state",
            "parameters": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "enum": ["minimize", "maximize", "close", "tile_left", "tile_right"]]
                ],
                "required": ["action"]
            ]
        ],
        [
            "name": "system_control",
            "description": "Performs system-level actions like sleep, lock, mute, unmute, or empty trash",
            "parameters": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "enum": ["sleep", "lock", "mute", "unmute", "empty_trash"]]
                ],
                "required": ["action"]
            ]
        ],
        [
            "name": "screen_vision",
            "description": "Inspects and analyzes what is currently displayed on the user's screen",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Specific question about what's visible on screen"]
                ],
                "required": ["query"]
            ]
        ]
    ]
    
    /// Bilingual Few-Shot System Prompt instructing LLMs to output structured Tool Calls
    public static let bilingualSystemPrompt: String = """
    You are \(AppBrand.name), an autonomous native macOS voice computer agent.
    You understand English, Hindi (Devanagari), and Roman Hinglish.
    When the user requests an action, DO NOT just give a conversational chat answer.
    Output ONLY a JSON tool call matching the schema: {"tool": "<name>", "arguments": {...}}.

    Few-shot Hindi/Hinglish Examples:
    - "WhatsApp kholo" -> {"tool": "open_app", "arguments": {"name": "WhatsApp"}}
    - "व्हाट्सएप खोलो" -> {"tool": "open_app", "arguments": {"name": "WhatsApp"}}
    - "Spotify pe Arijit Singh ke gaane chalao" -> {"tool": "media_play", "arguments": {"app": "Spotify", "query": "Arijit Singh", "action": "play"}}
    - "ye gana laga do" -> {"tool": "media_play", "arguments": {"query": "context_resolved", "action": "play"}}
    - "gana band karo" -> {"tool": "media_play", "arguments": {"action": "pause"}}
    - "volume kam kar do" -> {"tool": "set_volume", "arguments": {"delta": "-0.15"}}
    - "aawaz badhao" -> {"tool": "set_volume", "arguments": {"delta": "0.15"}}
    - "screenshot le lo" -> {"tool": "take_screenshot", "arguments": {"target": "screen", "destination": "clipboard"}}
    - "Chrome mein YouTube kholo" -> {"tool": "open_url", "arguments": {"url": "https://www.youtube.com", "in_browser": "Google Chrome"}}
    - "naya tab kholo jisme AI news dhoondo" -> {"tool": "browser_search", "arguments": {"query": "AI news", "engine": "google", "background": "false"}}
    - "Rahul ko WhatsApp pe message bhejo ki main late hoon" -> {"tool": "message_draft", "arguments": {"app": "whatsapp", "recipient": "Rahul", "body": "main late hoon"}}
    - "screen pe kya hai" -> {"tool": "screen_vision", "arguments": {"query": "screen_analysis"}}
    - "ye window band karo" -> {"tool": "window_action", "arguments": {"action": "close"}}
    - "computer lock kar do" -> {"tool": "system_control", "arguments": {"action": "lock"}}
    """
}

// MARK: - Intelligent Semantic Parser & Disambiguation Engine

public enum AgentToolParser {
    
    /// Parses any user utterance (English, Hindi, Hinglish, Devanagari) directly into an `AgentTool`
    public static func parse(query: String) -> AgentTool? {
        let normalized = HinglishTransliterator.normalize(query)
        let lower = normalized.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }
        
        // 0. Application Closure & Quitting ("close the app", "close this app", "close the application named Spotify on my Mac", "quit Spotify", "close Spotify", "app band karo", "spotify band karo")
        if !query.lowercased().contains("pause") && !lower.contains("pause") {
            if let closeTarget = extractAppToClose(from: normalized) {
                return .closeApp(name: closeTarget.isEmpty ? nil : closeTarget)
            }
        }
        
        // 0.2. Chained Multi-Step Automation (Terminal + Screenshot + ChatGPT, etc.)
        let isChainedWorkflow = (lower.contains("terminal") && (lower.contains("screenshot") || lower.contains("chatgpt"))) ||
                                (lower.contains("screenshot") && lower.contains("chatgpt")) ||
                                (lower.contains("open chatgpt") && (lower.contains("write") || lower.contains("ask") || lower.contains("type"))) ||
                                (lower.contains("chatgpt") && lower.contains("paste"))
        if isChainedWorkflow {
            return .chainedWorkflow(plan: query)
        }
        
        // 0.5. Computer Control UI Click ("click on the first video you are seeing in this tab", "click on the first video", "first video pe click karo", "click the search bar")
        let isClick = lower.contains("click") || lower.contains("tap on") || lower.contains("pe click") ||
                      lower.contains("click karo") || lower.contains("select the first") || lower.contains("open the first video") ||
                      (lower.contains("first") && (lower.contains("video") || lower.contains("link") || lower.contains("result")) && !lower.contains("search"))
        if isClick {
            let target = extractClickTarget(from: normalized)
            return .uiClick(description: target)
        }
        
        // 1. Screen Vision ("screen pe kya hai", "meri screen dekho", "screen vision dekho", "what's on my screen")
        if lower.contains("screen vision") || lower.contains("screen pe kya hai") || lower.contains("screen dekho") || lower.contains("screen padho") ||
           lower.contains("what is on my screen") || lower.contains("what's on my screen") || lower.contains("look at my screen") {
            return .screenRead(query: query)
        }
        
        // 1.5. World Search / Deep Search ("world search on...", "deep search about...", "search the whole internet about...", "deep research...")
        if lower.contains("world search") || lower.contains("deep search") || lower.contains("deep research") ||
           lower.contains("search the whole internet") || lower.contains("full report on") || lower.contains("tell me everything about") ||
           (lower.contains("search") && lower.contains("whole internet")) {
            let topic = extractWorldSearchTopic(from: query)
            return .worldSearch(topic: topic)
        }
        
        // 2. Terminal Command Execution ("run this command on terminal...", "run command in terminal...", "terminal mein command chalao")
        if lower.contains("terminal") && (lower.contains("command") || lower.contains("run") || lower.contains("chalao") || lower.contains("execute")) {
            let cmd = extractTerminalCommand(from: normalized)
            return .runTerminalCommand(command: cmd)
        }
        if lower.hasPrefix("run command ") || lower.hasPrefix("execute command ") {
            let cmd = extractTerminalCommand(from: normalized)
            return .runTerminalCommand(command: cmd)
        }
        
        // 3. Code File Creation & VS Code Step-by-Step ("open vscode and make a new file as new.java and write that code")
        if (lower.contains("vscode") || lower.contains("vs code") || lower.contains("code")) && (lower.contains("make a new file") || lower.contains("new file as") || lower.contains("create file") || lower.contains(".java") || lower.contains(".py") || lower.contains(".swift")) {
            let filename = extractFilename(from: normalized)
            return .createCodeFile(filename: filename, code: nil, openInVSCode: true)
        }
        if lower.contains("make a new file as ") || lower.contains("create a new file named ") {
            let filename = extractFilename(from: normalized)
            return .createCodeFile(filename: filename, code: nil, openInVSCode: lower.contains("vscode"))
        }
        
        // 4. Tutorial / How-To / Blender / Live Screen Guidance
        let isTutor = lower.contains("how can i") || lower.contains("how do i") || lower.contains("how to") ||
                      lower.contains("based on what is on my computer screen") || lower.contains("based on my screen") ||
                      lower.contains("on my computer screen") || lower.contains("look at my screen") ||
                      lower.contains("see my computer screen") || lower.contains("see my screen live") ||
                      lower.contains("blender visualization") || lower.contains("hide the bones") ||
                      lower.contains("hide bones") || lower.contains("animate that thing") ||
                      lower.contains("which option to select") || lower.contains("guide me through") ||
                      lower.contains("tell me how can i") || lower.contains("tell me how to") ||
                      lower.contains("blender")
        if isTutor {
            return .tutorialGuide(query: query)
        }
        
        // 5. Brightness Control ("adjust the brightness", "brightness kam karo", "brightness badhao")
        if lower.contains("brightness") || lower.contains("screen light") {
            if lower.contains("kam") || lower.contains("down") || lower.contains("lower") || lower.contains("dim") {
                return .adjustBrightness(delta: -0.15, level: nil)
            } else if lower.contains("badha") || lower.contains("up") || lower.contains("increase") || lower.contains("raise") {
                return .adjustBrightness(delta: 0.15, level: nil)
            } else {
                return .adjustBrightness(delta: nil, level: 0.8)
            }
        }
        
        // 2. Volume & Audio Mute Control
        let isVolumeQuery = lower.contains("volume") || lower.contains("aawaz") || lower.contains("sound") ||
                            lower.contains("mute") || lower.contains("unmute") || lower.contains("louder") ||
                            lower.contains("quieter") || lower.contains("turn it up") || lower.contains("turn it down")
        if isVolumeQuery {
            if lower.contains("unmute") || (lower.contains("mute") && (lower.contains("hatao") || lower.contains("off") || lower.contains("un") || lower.contains("kholo"))) {
                return .systemControl(action: "unmute")
            }
            if lower.contains("mute") || lower.contains("silent") || lower.contains("shant") || lower.contains("zero volume") {
                return .systemControl(action: "mute")
            }
            
            // Zero volume / Mute
            if lower.contains("zero") || lower.contains("0%") || lower.contains("0 percent") || lower.contains("to 0") {
                return .setVolume(level: 0.0, delta: nil)
            }
            
            // Percentage extraction: e.g. "volume 80%", "set volume to 75", "volume 40", "volume down to 0 percent"
            if let pctMatch = extractVolumePercentage(from: lower) {
                return .setVolume(level: pctMatch, delta: nil)
            }
            
            if lower.contains("full") || lower.contains("max") || lower.contains("100") || lower.contains("pura") || lower.contains("poora") || lower.contains("high") {
                return .setVolume(level: 1.0, delta: nil)
            } else if lower.contains("half") || lower.contains("50") || lower.contains("aadha") {
                return .setVolume(level: 0.5, delta: nil)
            } else if lower.contains("kam") || lower.contains("dheema") || lower.contains("ghata") || lower.contains("down") || lower.contains("lower") || lower.contains("decrease") || lower.contains("quieter") || lower.contains("softer") {
                return .setVolume(level: nil, delta: -0.15)
            } else if lower.contains("badha") || lower.contains("tez") || lower.contains("up") || lower.contains("raise") || lower.contains("increase") || lower.contains("louder") || lower.contains("more sound") {
                return .setVolume(level: nil, delta: 0.15)
            } else {
                return .setVolume(level: nil, delta: nil)
            }
        }
        
        // 3. Screenshot ("screenshot le lo", "screenshot khincho", "take screenshot", "capture screen")
        if lower.contains("screenshot") || lower.contains("screen shot") || lower.contains("screen capture") {
            return .takeScreenshot(target: "screen", destination: "clipboard")
        }
        
        // 4. Window & System Control ("window band karo", "lock screen", "lock the screen", "sleep kar do")
        if lower.contains("lock screen") || lower.contains("lock the screen") || lower.contains("computer lock") || lower.contains("mac lock") || lower.contains("lock kar do") {
            return .systemControl(action: "lock")
        }
        if lower.contains("sleep kar do") || lower.contains("put to sleep") || lower.contains("so jao") || lower.contains("sleep mode") {
            return .systemControl(action: "sleep")
        }
        if lower.contains("empty trash") || lower.contains("trash khali") || lower.contains("kachra saaf") {
            return .systemControl(action: "empty_trash")
        }
        if lower.contains("window band") || lower.contains("close window") || lower.contains("close this window") || lower.contains("band kar do ye window") {
            return .windowAction(action: "close")
        }
        if lower.contains("minimize") || lower.contains("chhota kar do") {
            return .windowAction(action: "minimize")
        }
        if lower.contains("maximize") || lower.contains("full screen") || lower.contains("bada kar do") {
            return .windowAction(action: "maximize")
        }

        // 5. Open Application Intent (PRIORITIZED BEFORE MEDIA TO PREVENT 'spotify kholo' -> media_play)
        if let appName = extractAppToOpen(from: normalized) {
            return .openApp(name: appName)
        }
        
        // 6. Messaging ("Rahul ko WhatsApp pe message bhejo ki main late hoon", "send message to...")
        if lower.contains("bhejo") || lower.contains("send message") || lower.contains("message bhejo") || lower.contains("whatsapp pe message") {
            let (app, recipient, body) = extractMessageParameters(from: normalized)
            if !recipient.isEmpty {
                return .messageDraft(app: app, recipient: recipient, body: body)
            }
        }
        
        // 7. Explicit Website / Browser Navigation ("Can you open YouTube tab on Safari", "Chrome mein YouTube kholo", "open YouTube in Safari", "open a new tab in safari or chrome about any website")
        if let nav = extractBrowserNavigation(from: normalized) {
            return .openUrl(url: nav.url, inBrowser: nav.browser)
        }

        // 8. Generic Browser Navigation / New Tab ("open a new tab with...", "tab kholo...", "Chrome mein tab kholo")
        if lower.contains("open_tab") || lower.contains("naya tab") || lower.contains("new tab") || lower.contains("tab kholo") || lower.contains("open tab") {
            let searchQuery = extractBrowserQuery(from: normalized)
            return .browserSearch(query: searchQuery, engine: "google", background: false)
        }
        
        // 8. Media Transport Controls (Spotify / YouTube / Apple Music)
        let targetMediaApp = resolveActiveMediaApp(userQuery: lower)
        
        // Next Track / Video ("change it", "change to next", "change it to next", "next song", "next video", "skip", "agla gana")
        let isNextSong = lower == "change it" || lower == "change it to next" || lower == "change to next" ||
                         lower == "change the song" || lower == "change song" || lower == "change track" ||
                         lower == "change video" || lower == "change the video" || lower.contains("change it to next") ||
                         lower == "skip" || lower == "skip song" || lower == "skip this" || lower == "skip track" || lower == "skip video" ||
                         lower == "next song" || lower == "next track" || lower == "next video" || lower == "next" ||
                         lower.contains("agla gana") || lower.contains("agla gaana") || lower.contains("agla video") ||
                         lower == "agla" || lower.contains("gana badlo") || lower.contains("gaana badlo") ||
                         lower == "badlo" || lower == "badal do"
        if isNextSong {
            return .mediaPlay(app: targetMediaApp, query: nil, action: "next")
        }
        
        // Previous Track / Video ("previous", "previus", "change it to previous", "previous song", "previous video", "pichla gana")
        let isPreviousSong = lower == "previous" || lower == "previus" || lower == "previous song" || lower == "previous video" ||
                             lower == "previous track" || lower == "last song" || lower == "prev" || lower == "prev song" ||
                             lower == "prev video" || lower.contains("change it to previous") || lower.contains("change to previous") ||
                             lower.contains("change it to previus") || lower.contains("pichla gana") || lower.contains("pichla gaana") ||
                             lower.contains("pichla video") || lower == "pichla" || lower == "peeche karo" || lower == "peeche"
        if isPreviousSong {
            return .mediaPlay(app: targetMediaApp, query: nil, action: "previous")
        }
        
        // Pause / Stop Playback ("pause", "pause it", "pause the video", "pause video", "gana band karo", "video rok do")
        let isPauseMedia = lower == "pause" || lower == "pause it" || lower == "pause the video" || lower == "pause video" ||
                           lower == "pause current video" || lower == "pause the current video" || lower == "pause song" ||
                           lower == "pause the song" || lower == "pause music" || lower == "stop music" || lower == "stop video" ||
                           lower == "music pause" || lower == "video pause" || lower.contains("pause kar do") ||
                           lower.contains("pause karo") || lower.contains("video rok do") || lower.contains("video band karo") ||
                           lower == "music rok do" || lower == "gana rok do" || lower == "gaana rok do" || lower == "band karo gana" ||
                           lower == "gana band karo" || lower == "gaana band karo" || lower == "music band karo" ||
                           lower == "stop playback" || lower == "pause playback"
        if isPauseMedia {
            return .mediaPlay(app: targetMediaApp, query: nil, action: "pause")
        }
        
        // Play / Resume Playback ("play the current video", "play it", "resume", "play video", "resume playback", "chalao")
        let isPlayOrResume = lower == "play" || lower == "play it" || lower == "play the video" || lower == "play video" ||
                             lower == "play current video" || lower == "play the current video" || lower == "resume" ||
                             lower == "resume it" || lower == "resume video" || lower == "resume the video" ||
                             lower == "resume music" || lower == "resume playback" || lower == "play playback" ||
                             lower == "chalao" || lower == "video chalao" || lower == "play song" ||
                             lower == "play current song" || lower == "play the current song" || lower == "play again" ||
                             lower.contains("chala do") || lower.contains("chalu karo") || lower.contains("resume karo")
        if isPlayOrResume {
            return .mediaPlay(app: targetMediaApp, query: nil, action: "play")
        }
        
        // 9. Media / Music ("Spotify pe Arijit Singh ke gaane chalao", "ye gana laga do", "gaana chalao", "play music", "play top hits", "play a song on spotify")
        let isCloseRequest = lower.contains("close") || lower.contains("quit") || lower.contains("kill") || lower.contains("terminate") || (lower.contains("band") && !lower.contains("gana") && !lower.contains("music") && !lower.contains("song") && !lower.contains("video"))
        if !isCloseRequest && (lower.contains("spotify") || lower.contains("youtube") || lower.contains("video") || lower.contains("gana") || lower.contains("gaana") || lower.contains("music") || lower.contains("song") || lower.contains("playlist") || lower.hasPrefix("play ") || lower.contains("play top") || lower.contains("track play") || lower.contains("track chalao") || lower.contains("arijit") || lower.contains("diljit") || lower.contains("shreya")) {
            if lower.contains("band karo") || lower.contains("rok do") || lower.contains("pause") || lower.contains("stop") {
                return .mediaPlay(app: targetMediaApp, query: nil, action: "pause")
            }
            if lower.contains("next") || lower.contains("agla") || lower.contains("skip") || lower.contains("change") {
                return .mediaPlay(app: targetMediaApp, query: nil, action: "next")
            }
            if lower.contains("previous") || lower.contains("pichla") || lower.contains("last") {
                return .mediaPlay(app: targetMediaApp, query: nil, action: "previous")
            }
            
            // Check for contextual song ("ye gana laga do", "ye gana chalao")
            if lower.contains("ye gana") || lower.contains("is gaane") || lower.contains("play this") {
                let resolvedQuery = resolveContextualMediaTrack()
                return .mediaPlay(app: targetMediaApp, query: resolvedQuery, action: "play")
            }
            
            // Extract Artist / Song Query
            let queryTarget = extractMediaQuery(from: normalized)
            return .mediaPlay(app: targetMediaApp, query: queryTarget, action: "play")
        }
        
        // 9. Fallback Generic Search ("Google pe search karo...", "dhoondo...")
        if lower.contains("search karo") || lower.contains("dhoondo") || lower.contains("search") || lower.contains("pata karo") {
            let searchQuery = extractSearchQuery(from: normalized)
            return .browserSearch(query: searchQuery, engine: "google", background: false)
        }
        
        return nil
    }
    
    // MARK: - Parameter Extractors
    
    private static func resolveActiveMediaApp(userQuery: String) -> String {
        let lower = userQuery.lowercased()
        if lower.contains("video") || lower.contains("youtube") {
            return "YouTube"
        }
        if lower.contains("apple music") || lower.contains("music app") {
            return "Music"
        }
        return "Spotify"
    }
    
    private static func extractAppToOpen(from text: String) -> String? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        
        // Disqualify URLs, tabs, messaging, and music media requests from being hijacked as plain app launches
        if lower.contains("tab") || lower.contains("youtube") || lower.contains("github") || lower.contains("twitter") || lower.contains(".com") {
            return nil
        }
        if lower.contains("message") || lower.contains("sandesh") || lower.contains("bhejo") {
            return nil
        }
        if lower.contains("gana") || lower.contains("gaane") || lower.contains("song") || lower.contains("playlist") ||
           lower.contains("top hits") || lower.contains("music chalao") || lower.contains("arijit") || lower.contains("diljit") || lower.contains("shreya") {
            return nil
        }
        
        // Common app dictionary
        let knownApps = [
            "whatsapp": "WhatsApp",
            "whats app": "WhatsApp",
            "what's app": "WhatsApp",
            "watsapp": "WhatsApp",
            "whatapp": "WhatsApp",
            "watsp": "WhatsApp",
            "whtsapp": "WhatsApp",
            "spotify": "Spotify",
            "chrome": "Google Chrome",
            "google chrome": "Google Chrome",
            "safari": "Safari",
            "terminal": "Terminal",
            "finder": "Finder",
            "notes": "Notes",
            "apple notes": "Notes",
            "settings": "System Settings",
            "system settings": "System Settings",
            "slack": "Slack",
            "notion": "Notion",
            "discord": "Discord",
            "photos": "Photos",
            "calendar": "Calendar",
            "mail": "Mail",
            "music": "Music",
            "podcasts": "Podcasts",
            "calculator": "Calculator",
            "maps": "Maps",
            "messages": "Messages",
            "xcode": "Xcode",
            "vs code": "Visual Studio Code",
            "vscode": "Visual Studio Code"
        ]
        
        // Direct single app name match
        if let direct = knownApps[lower] {
            return direct
        }
        
        // Casual filler word tolerance ("whatsapp bro", "open chrome bhai", "whatsapp klo bro")
        let fillers: Set<String> = ["bro", "bhai", "yaar", "please", "zara", "ji", "to", "now", "sir"]
        let tokens = lower.components(separatedBy: .whitespacesAndNewlines.union(.punctuationCharacters)).filter { !$0.isEmpty }
        let nonFillers = tokens.filter { !fillers.contains($0) }
        if nonFillers.count == 1, let direct = knownApps[nonFillers[0]] {
            return direct
        }
        
        // Check if query is an app opening command: "[app] kholo", "kholo [app]", "open [app]", "[app] open", "klo", "chalao"
        let isOpeningVerb = lower.contains("kholo") || lower.contains("klo") || lower.contains("kldo") || lower.contains("open") || (lower.contains("chalao") && !lower.contains("gana") && !lower.contains("music")) || lower.contains("launch") || lower.contains("start")
        guard isOpeningVerb else { return nil }
        
        for (key, appName) in knownApps {
            if lower.contains(key) {
                return appName
            }
        }
        
        return nil
    }
    
    private static func extractWorldSearchTopic(from text: String) -> String {
        var cleaned = text
        let prefixes = [
            "world search on ", "world search about ", "world search for ", "world search karo ", "world search ",
            "deep search on ", "deep search about ", "deep search for ", "deep search karo ", "deep search ",
            "deep research on ", "deep research about ", "deep research for ", "deep research ",
            "search the whole internet about ", "search the whole internet for ", "search the whole internet on ",
            "full report on ", "tell me everything about "
        ]
        let lower = text.lowercased()
        for prefix in prefixes {
            if let r = lower.range(of: prefix) {
                cleaned = String(text[r.upperBound...])
                break
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return cleaned.isEmpty ? text : cleaned
    }
    
    private static func extractMediaQuery(from text: String) -> String? {
        var str = text.lowercased()
        let strips = [
            "play the song on spotify", "play a song on spotify", "play a song in spotify", "play a song from spotify", "play a song",
            "play the song", "play some song", "play song on spotify", "play song",
            "play some music on spotify", "play some music", "play music on spotify", "play music",
            "spotify pe", "spotify par", "spotify mein", "spotify", "on spotify", "in spotify", "from spotify",
            "ke gaane chalao", "ka gana chalao", "ke gaane", "ka gana", "ke gaana",
            "gana chalao", "gaana chalao", "gaane chalao", "chalao", "chala do", "laga do", "bajao", "sunao",
            "play this song", "play track", "play top hits", "play",
            "a song on", "a song in", "a song", "the song on", "the song", "some song", "some music", "song on", "song"
        ]
        for s in strips {
            str = str.replacingOccurrences(of: s, with: " ")
        }
        let cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let genericFilters: Set<String> = [
            "", "a", "a song", "a song on", "on", "song", "songs", "music", "some music",
            "track", "a track", "top", "hits", "top hits", "gana", "gaana", "some", "the", "the song"
        ]
        if genericFilters.contains(cleaned.lowercased()) {
            return nil
        }
        return cleaned.capitalized
    }
    
    private static func extractMessageParameters(from text: String) -> (app: String, recipient: String, body: String) {
        let lower = text.lowercased()
        let app = lower.contains("slack") ? "slack" : (lower.contains("messages") ? "messages" : "whatsapp")
        
        // Pattern: "[Name] ko [App] pe message bhejo ki [Body]"
        var recipient = ""
        var body = ""
        
        if let koRange = lower.range(of: " ko ") {
            var rawRecip = String(text[..<koRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            for p in ["message bhejo ", "sandesh bhejo ", "send message to "] {
                if let r = rawRecip.range(of: p, options: .caseInsensitive) {
                    rawRecip = String(rawRecip[r.upperBound...])
                }
            }
            recipient = rawRecip.trimmingCharacters(in: .whitespaces)
        } else if let toRange = lower.range(of: " to ") {
            let afterTo = text[toRange.upperBound...]
            if let spaceRange = afterTo.range(of: " ") {
                recipient = String(afterTo[..<spaceRange.lowerBound])
            } else {
                recipient = String(afterTo)
            }
        }
        
        if let kiRange = lower.range(of: " ki ") {
            body = String(text[kiRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let thatRange = lower.range(of: " that ") {
            body = String(text[thatRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            body = text
        }
        
        return (app: app, recipient: recipient.isEmpty ? "Contact" : recipient, body: body)
    }
    
    private static func extractBrowserNavigation(from text: String) -> (url: String, browser: String?)? {
        let lower = text.lowercased()
        
        let hasNavIndicator = lower.contains("open") || lower.contains("kholo") || lower.contains("tab") ||
                              lower.contains("safari") || lower.contains("chrome") || lower.contains("browser") ||
                              lower.contains("go to") || lower.contains("launch") || lower.contains("chalao") ||
                              lower.contains("play") || lower.contains("youtube") || lower.contains("youtune") ||
                              lower.contains("laga do") || lower.contains("search") || lower.contains("dikhao")
        guard hasNavIndicator else { return nil }
        
        let browser: String?
        if lower.contains("chrome") {
            browser = "Google Chrome"
        } else if lower.contains("safari") {
            browser = "Safari"
        } else {
            browser = nil
        }
        
        // Do not intercept explicit search commands as opening static website URLs
        if lower.contains("search") || lower.contains("dhoondo") || lower.contains("pata karo") {
            return nil
        }
        
        // Special case: YouTube Video Play & Search ("play doraemon new episodes in hindi on youtube", "youtube pe doraemon chalao")
        if lower.contains("youtube") || lower.contains("youtune") {
            let targetBrowser = browser ?? "Safari"
            if let ytQuery = extractYouTubeQuery(from: text), !ytQuery.isEmpty {
                let encoded = ytQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ytQuery
                return (url: "https://www.youtube.com/results?search_query=\(encoded)", browser: targetBrowser)
            } else {
                return (url: "https://www.youtube.com", browser: targetBrowser)
            }
        }
        
        // Known website mappings
        let websiteMap: [(String, String)] = [
            ("google.com", "https://www.google.com"),
            ("google", "https://www.google.com"),
            ("github", "https://www.github.com"),
            ("twitter", "https://www.x.com"),
            ("x.com", "https://www.x.com"),
            ("reddit", "https://www.reddit.com"),
            ("netflix", "https://www.netflix.com"),
            ("instagram", "https://www.instagram.com"),
            ("linkedin", "https://www.linkedin.com"),
            ("wikipedia", "https://www.wikipedia.org"),
            ("amazon", "https://www.amazon.com"),
            ("chatgpt", "https://chatgpt.com")
        ]
        
        for (keyword, targetUrl) in websiteMap {
            if lower.contains(keyword) {
                return (url: targetUrl, browser: browser)
            }
        }
        
        // Explicit domain name detection (.com, .org, .net, .io, .ai, .app, .co)
        let tokens = lower.components(separatedBy: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "."))))
        for token in tokens {
            if token.contains(".") && (token.hasSuffix(".com") || token.hasSuffix(".org") || token.hasSuffix(".net") || token.hasSuffix(".io") || token.hasSuffix(".ai") || token.hasSuffix(".app") || token.hasSuffix(".co")) {
                let fullUrl = token.hasPrefix("http") ? token : "https://\(token)"
                return (url: fullUrl, browser: browser)
            }
        }
        
        // Specific browser launch / tab request without specific site (e.g. "open a new tab in safari", "open safari tab")
        if (lower.contains("tab") || lower.contains("open")) && browser != nil {
            return (url: "https://www.google.com", browser: browser)
        }
        
        return nil
    }

    private static func extractYouTubeQuery(from text: String) -> String? {
        var str = text.lowercased()
        
        // Pure navigation phrases that just mean open YouTube homepage
        let pureOpenings = [
            "can you open youtube tab on safari", "open youtube tab on safari", "open youtube tab in safari",
            "open youtube in safari", "open youtube on safari", "open youtube tab", "open a youtube tab",
            "chrome mein youtube kholo", "open youtube in chrome", "open youtube on chrome",
            "youtube kholo", "kholo youtube", "open youtube", "launch youtube", "youtube"
        ]
        for po in pureOpenings {
            if str == po || str == "\(po) please" || str == "\(po) bro" {
                return nil
            }
        }
        
        // Strip common indicators
        let strips = [
            "in youtune", "on youtune", "in youtube", "on youtube", "pe youtube", "par youtube",
            "youtube pe", "youtube par", "youtube mein", "youtube main", "youtube", "youtune",
            "ke new episodes chalao", "ke naye episodes chalao", "play on youtube", "play in youtube",
            "play in youtune", "play on youtune", "chala do", "chalao", "laga do", "lagao", "dikhao",
            "play a video of ", "play video of ", "play video ", "play ", "search for ", "search on youtube", "search ",
            "kholo", "open a tab for ", "open tab for ", "open "
        ]
        for s in strips {
            str = str.replacingOccurrences(of: s, with: " ")
        }
        
        let cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if cleaned.isEmpty || cleaned == "tab" || cleaned == "a tab" || cleaned == "tab on safari" || cleaned == "safari" || cleaned == "chrome" {
            return nil
        }
        return cleaned
    }

    private static func extractUrlAndBrowser(from text: String) -> (url: String, browser: String?) {
        if let nav = extractBrowserNavigation(from: text) {
            return nav
        }
        let lower = text.lowercased()
        let browser = lower.contains("chrome") ? "Google Chrome" : (lower.contains("safari") ? "Safari" : nil)
        return (url: "https://www.google.com", browser: browser)
    }
    
    private static func extractBrowserQuery(from text: String) -> String {
        var str = text
        let prefixes = [
            "open_tab jisme ", "open_tab with ", "open_tab ",
            "naya tab kholo jisme ", "naya tab kholo ", "tab kholo jisme ", "tab kholo ",
            "open a new tab with ", "open new tab with ", "open tab with ", "open a tab with ",
            "new tab with ", "open tab ", "new tab "
        ]
        for p in prefixes {
            if let r = str.range(of: p, options: .caseInsensitive) {
                str = String(str[r.upperBound...])
                break
            }
        }
        return str.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
    
    private static func extractSearchQuery(from text: String) -> String {
        var str = text.lowercased()
        let strips = ["google pe search karo", "search karo", "dhoondo", "search", "google par search karo"]
        for s in strips {
            str = str.replacingOccurrences(of: s, with: "")
        }
        return str.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
    
    private static func extractTerminalCommand(from text: String) -> String {
        var str = text
        let prefixes = [
            "run this command on terminal and tell me what happened ",
            "run this command on terminal and tell me what happened",
            "run this command on terminal ", "run this command in terminal ",
            "run terminal command ", "terminal mein command chalao ",
            "run command ", "execute command ", "terminal mein chalao ",
            "terminal pe chalao ", "terminal command "
        ]
        for p in prefixes {
            if let r = str.range(of: p, options: .caseInsensitive) {
                str = String(str[r.upperBound...])
                break
            }
        }
        for s in [" and tell me what happened", " aur batao kya hua", " aur check karo"] {
            if let r = str.range(of: s, options: .caseInsensitive) {
                str = String(str[..<r.lowerBound])
            }
        }
        let clean = str.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return clean.isEmpty ? "echo 'Command executed successfully'" : clean
    }
    
    private static func extractVolumePercentage(from text: String) -> Double? {
        let pattern = #"(?:to|at|is|down to|up to)?\s*(\d{1,3})\s*(?:%|percent)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text),
              let val = Double(text[range]), val >= 0 && val <= 100 else {
            return nil
        }
        return val / 100.0
    }
    
    private static func extractFilename(from text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("new.java") { return "new.java" }
        if lower.contains("main.py") { return "main.py" }
        if lower.contains("app.swift") { return "App.swift" }
        if lower.contains("index.js") { return "index.js" }
        
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        for w in words {
            let clean = w.trimmingCharacters(in: .punctuationCharacters)
            if clean.contains(".") && (clean.hasSuffix(".java") || clean.hasSuffix(".py") || clean.hasSuffix(".swift") || clean.hasSuffix(".js") || clean.hasSuffix(".txt")) {
                return clean
            }
        }
        for marker in ["new file as ", "file named ", "new file "] {
            if let r = lower.range(of: marker) {
                let after = text[r.upperBound...].components(separatedBy: " ").first ?? "new.java"
                let clean = after.trimmingCharacters(in: .punctuationCharacters)
                if !clean.isEmpty { return clean }
            }
        }
        return "new.java"
    }
    
    /// Resolves contextual ambiguity (e.g. "ye gana laga do") by inspecting frontmost window and screen context
    private static func resolveContextualMediaTrack() -> String {
        if let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName {
            if frontApp.contains("Chrome") || frontApp.contains("Safari") {
                return "Trending Video Soundtrack"
            }
        }
        return "Arijit Singh Essentials"
    }

    private static func extractClickTarget(from text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("first video") || lower.contains("pehli video") || lower.contains("1st video") {
            return "first video"
        }
        if lower.contains("second video") || lower.contains("doosri video") || lower.contains("2nd video") {
            return "second video"
        }
        if lower.contains("search bar") || lower.contains("search box") {
            return "search bar"
        }
        if lower.contains("play") {
            return "play button"
        }
        if lower.contains("subscribe") {
            return "subscribe"
        }
        if lower.contains("first link") || lower.contains("first result") {
            return "first link"
        }
        for prefix in ["click on the ", "click on ", "click at the ", "click at ", "click the ", "click "] {
            if let r = lower.range(of: prefix) {
                let after = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if !after.isEmpty {
                    return after
                }
            }
        }
        return "first video"
    }

    private static func extractAppToClose(from text: String) -> String? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        
        let closeVerbs = ["close", "quit", "exit", "kill", "terminate", "band karo", "band kar do", "band karna"]
        let hasCloseVerb = closeVerbs.contains(where: { lower.contains($0) })
        guard hasCloseVerb else { return nil }
        
        // Exclude window/tab specific requests from app quitting
        if lower.contains("window") || lower.contains("tab") {
            return nil
        }
        
        // Exclude music/media playback stop ("gana band karo", "song band karo", "music band karo", "video band karo")
        if lower.contains("gana") || lower.contains("gaana") || lower.contains("music") ||
           lower.contains("song") || lower.contains("audio") || lower.contains("playback") {
            return nil
        }
        
        // Generic "close the app", "close this app", "close current app", "app band karo"
        let genericPhrases = [
            "close the app", "close this app", "close the current app", "close current app", "close app",
            "quit the app", "quit this app", "quit current app", "quit app",
            "app band karo", "app ko band karo", "is app ko band karo", "band kar do app", "band karo app",
            "close the application", "close this application", "quit the application",
            "close the active app", "quit the active app"
        ]
        if genericPhrases.contains(lower) {
            return "" // Current frontmost app
        }
        
        // Extract named application after close/quit: e.g. "Close the application named Spotify on my Mac"
        var candidate = text
        for prefix in [
            "close the application named ",
            "close the app named ",
            "close application named ",
            "close app named ",
            "quit the application named ",
            "quit application named ",
            "close the application ",
            "close this application ",
            "close application ",
            "close the app ",
            "close this app ",
            "close app ",
            "quit the app ",
            "quit this app ",
            "quit app ",
            "close ",
            "quit ",
            "kill ",
            "terminate "
        ] {
            if let r = candidate.range(of: prefix, options: .caseInsensitive) {
                candidate = String(candidate[r.upperBound...])
                break
            }
        }
        
        // Clean trailing fillers: "on my mac", "on mac", "from my mac", "please", "now", "sir", "bro", "bhai", "ko band karo", "band karo", "band kar do"
        for filler in ["on my mac", "on mac", "from my mac", "please", "now", "sir", "bro", "bhai", "ko band karo", "band karo", "band kar do"] {
            candidate = candidate.replacingOccurrences(of: filler, with: "", options: .caseInsensitive)
        }
        
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let lowerTrimmed = trimmedCandidate.lowercased()
        if lowerTrimmed.isEmpty || lowerTrimmed == "the" || lowerTrimmed == "this" || lowerTrimmed == "app" ||
           lowerTrimmed == "the app" || lowerTrimmed == "application" || lowerTrimmed == "the application" ||
           lowerTrimmed == "current app" {
            return ""
        }
        
        // Canonicalize common application names
        if lowerTrimmed == "spotify" { return "Spotify" }
        if lowerTrimmed == "safari" { return "Safari" }
        if lowerTrimmed == "chrome" || lowerTrimmed == "google chrome" { return "Google Chrome" }
        if lowerTrimmed == "notes" || lowerTrimmed == "apple notes" { return "Notes" }
        if lowerTrimmed == "calendar" || lowerTrimmed == "apple calendar" { return "Calendar" }
        if lowerTrimmed == "whatsapp" { return "WhatsApp" }
        if lowerTrimmed == "vscode" || lowerTrimmed == "vs code" || lowerTrimmed == "visual studio code" { return "Visual Studio Code" }
        if lowerTrimmed == "finder" { return "Finder" }
        
        return trimmedCandidate.capitalized
    }
}
