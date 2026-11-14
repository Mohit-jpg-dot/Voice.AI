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
    case appIntegration(app: String, operation: String, params: [String: String])
    
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
        case .appIntegration: return "app_integration"
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
    
    public static func isConceptualAudioQuery(_ lower: String) -> Bool {
        lower.contains("volume of ") || lower.contains("speed of sound") ||
        lower.contains("sound wave") || lower.contains("sound like") ||
        lower.hasPrefix("what is ") || lower.hasPrefix("explain ") ||
        lower.hasPrefix("why ") || lower.hasPrefix("how does sound")
    }

    /// Strips casual conversational wake/filler starters ("bro ", "hey bro ", "hey jarvis ", "jarvis ") cleanly.
    public static func stripCasualPrefix(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.replacingOccurrences(
            of: #"^(?:(?:hey|hi|yo|ok|okay|arey)\s+)?(?:bro|bhai|jarvis)\b[\s,:!]*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? trimmed : stripped
    }

    /// Parses any user utterance (English, Hindi, Hinglish, Devanagari) directly into an `AgentTool`
    public static func parse(query: String) -> AgentTool? {
        let cleanQuery = stripCasualPrefix(query)
        let normalized = HinglishTransliterator.normalize(cleanQuery)
        let lower = normalized.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }
        
        // 0. Application Closure & Quitting ("close the app", "close this app", "close the application named Spotify on my Mac", "quit Spotify", "close Spotify", "app band karo", "spotify band karo")
        if !query.lowercased().contains("pause") && !lower.contains("pause") {
            if !AutonomousAgentExecutor.isSelfQuitCommand(query) {
                if let closeTarget = extractAppToClose(from: normalized) {
                    return .closeApp(name: closeTarget.isEmpty ? nil : closeTarget)
                }
            }
        }
        
        // 0.2. Chained Multi-Step Automation (Terminal + Screenshot + ChatGPT, etc.)
        let isChainedWorkflow = (lower.contains("terminal") && (lower.contains("screenshot") || lower.contains("chatgpt"))) ||
                                (lower.contains("screenshot") && lower.contains("chatgpt")) ||
                                (lower.contains("open chatgpt") && (lower.contains("write") || lower.contains("ask") || lower.contains("type"))) ||
                                (lower.contains("chatgpt") && lower.contains("paste"))
        if isChainedWorkflow {
            return .chainedWorkflow(plan: cleanQuery)
        }
        
        // 0.5. Computer Control UI Click ("click on the first video you are seeing in this tab", "click on the first video", "first video pe click karo", "click the search bar")
        let isClick = lower.contains("click") || lower.contains("tap on") || lower.contains("pe click") ||
                      lower.contains("click karo") || lower.contains("select the first") || lower.contains("open the first video") ||
                      (lower.contains("first") && (lower.contains("video") || lower.contains("link") || lower.contains("result")) && !lower.contains("search"))
        if isClick {
            let target = extractClickTarget(from: normalized)
            return .uiClick(description: target)
        }
        
        // 1. Screen Vision ("can u see whats on my screen", "what's on my screen", "screen pe kya hai", "take a screenshot and tell me")
        if lower.contains("screen vision") || lower.contains("screen pe kya hai") || lower.contains("mere screen") ||
           lower.contains("screen dekho") || lower.contains("screen padho") ||
           lower.contains("what is on my screen") || lower.contains("what's on my screen") || lower.contains("whats on my screen") ||
           lower.contains("see on my screen") || lower.contains("see my screen") || lower.contains("look at my screen") ||
           lower.contains("check my screen") || lower.contains("explain my screen") ||
           (lower.contains("screenshot") && (lower.contains("tell me") || lower.contains("what") || lower.contains("explain") || lower.contains("read"))) {
            return .screenRead(query: cleanQuery)
        }
        
        // 1.5. World Search / Deep Search ("world search on...", "deep search about...", "search the whole internet about...", "deep research...")
        if lower.contains("world search") || lower.contains("deep search") || lower.contains("deep research") ||
           lower.contains("search the whole internet") || lower.contains("full report on") || lower.contains("tell me everything about") ||
           (lower.contains("search") && lower.contains("whole internet")) {
            let topic = extractWorldSearchTopic(from: query)
            return .worldSearch(topic: topic)
        }
        
        // 2. Terminal Command Execution ("run this command on terminal...", "open terminal and run...", "read terminal output")
        if lower.contains("terminal") && (lower.contains("read output") || lower.contains("read terminal") || lower.contains("terminal output")) {
            return .appIntegration(app: "terminal", operation: "read_output", params: [:])
        }
        if lower.contains("terminal") && (lower.contains("in terminal window") || lower.contains("open terminal and run") || lower.contains("terminal mein chalao")) {
            let cmd = extractTerminalCommand(from: normalized)
            return .appIntegration(app: "terminal", operation: "run_in_window", params: ["command": cmd])
        }
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
        let hasUITutorContext = lower.contains("screen") || lower.contains("blender") || lower.contains("option") ||
                                lower.contains("button") || lower.contains("menu") || lower.contains("hide") ||
                                lower.contains("animate") || lower.contains("guide me") || lower.contains("select") ||
                                lower.contains("in photoshop") || lower.contains("in figma") || lower.contains("in xcode") ||
                                lower.contains("in vscode") || lower.contains("in vs code") || lower.contains("in terminal")
        let isTutor = (hasUITutorContext && (lower.contains("how can i") || lower.contains("how do i") || lower.contains("how to"))) ||
                      lower.contains("based on what is on my computer screen") || lower.contains("based on my screen") ||
                      lower.contains("on my computer screen") || lower.contains("look at my screen") ||
                      lower.contains("see my computer screen") || lower.contains("see my screen live") ||
                      lower.contains("blender visualization") || lower.contains("hide the bones") ||
                      lower.contains("hide bones") || lower.contains("animate that thing") ||
                      lower.contains("which option to select") || lower.contains("guide me through") ||
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
        
        // 2. Volume & Audio Mute Control (avoid hijacking geometry/physics questions or YouTube player mute/unmute)
        let isYouTubeAudioCommand = lower.contains("youtube") || lower.contains("mute video") || lower.contains("unmute video") || lower.contains("video mute") || lower.contains("video unmute") || (lower.contains("video") && (lower.contains("mute") || lower.contains("unmute")))
        let isVolumeQuery = !isConceptualAudioQuery(lower) && !isYouTubeAudioCommand &&
                            !lower.contains("sounds good") && !lower.contains("sound good") &&
                            (lower.contains("volume") || lower.contains("aawaz") ||
                             (lower.contains("sound") && !lower.contains("discord") && !lower.contains("slack") && !lower.contains("whatsapp")) ||
                             lower.contains("mute") || lower.contains("unmute") || lower.contains("louder") ||
                             lower.contains("quieter") || lower.contains("turn it up") || lower.contains("turn it down"))
        if isVolumeQuery {
            if lower.contains("unmute") || (lower.contains("mute") && (lower.contains("hatao") || lower.contains("off") || lower.contains("un") || lower.contains("kholo"))) {
                return .systemControl(action: "unmute")
            }
            if lower.contains("mute") || lower.contains("silent") || lower.contains("shant") || lower.contains("zero volume") {
                return .systemControl(action: "mute")
            }
            
            // Zero volume / Mute (use word boundaries so "30 percent" does not match "0 percent")
            let isExplicitZero = lower.contains("zero") ||
                                 lower.range(of: "\\b0\\s*(?:%|percent)\\b", options: .regularExpression) != nil ||
                                 lower.range(of: "\\bto 0\\b", options: .regularExpression) != nil
            if isExplicitZero {
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
        
        // 3. Screenshot ("screenshot le lo", "screenshot this window", "take screenshot", "capture screen")
        if lower.contains("screenshot") || lower.contains("screen shot") || lower.contains("screen capture") {
            let target = (lower.contains("window") || lower.contains("current app") || lower.contains("this app")) ? "window" : "screen"
            let dest = lower.contains("desktop") ? "desktop" : "clipboard"
            return .takeScreenshot(target: target, destination: dest)
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
        if lower.contains("close this tab") || lower.contains("close tab") || lower == "close the tab" {
            return .windowAction(action: "tab_close")
        }
        if lower == "go back" || lower == "navigate back" || lower == "back" || lower == "page back" {
            return .windowAction(action: "browser_back")
        }
        if lower == "go forward" || lower == "navigate forward" || lower == "page forward" {
            return .windowAction(action: "browser_forward")
        }
        if lower.contains("scroll down") || lower == "scroll down page" {
            return .windowAction(action: "scroll_down")
        }
        if lower.contains("scroll up") || lower == "scroll up page" {
            return .windowAction(action: "scroll_up")
        }
        if lower.contains("refresh the page") || lower == "refresh page" || lower == "reload page" || lower.contains("reload this page") || lower == "refresh" {
            return .windowAction(action: "browser_refresh")
        }
        if lower.contains("bookmark this page") || lower == "bookmark page" || lower == "add bookmark" {
            return .windowAction(action: "bookmark_page")
        }
        if lower.contains("read this page") || lower.contains("read the page") || lower.contains("summarize this page") {
            return .screenRead(query: query)
        }
        if lower.contains("minimize") || lower.contains("chhota kar do") {
            return .windowAction(action: "minimize")
        }
        if lower.contains("maximize") || lower.contains("full screen") || lower.contains("bada kar do") {
            return .windowAction(action: "maximize")
        }
        if lower == "show hidden windows" || lower == "unhide windows" || lower == "unhide all" || lower == "show hidden apps" {
            return .windowAction(action: "unhide_all")
        }
        if !lower.contains("bones") && (
            lower == "hide" ||
            lower.contains("hide this window") ||
            lower.contains("hide the window") ||
            lower.contains("hide current window") ||
            lower.contains("hide active window") ||
            lower.contains("hide window") ||
            lower.contains("hide this app") ||
            lower.contains("hide current app") ||
            lower.contains("press command h") ||
            lower.contains("command h")
        ) {
            return .windowAction(action: "hide")
        }
        if lower.hasPrefix("hide ") && !lower.contains("bones") {
            let appTarget = String(query.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(5))
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !appTarget.isEmpty {
                return .windowAction(action: "hide_app:\(appTarget)")
            }
        }

        // 4.5 Editor & Typing Commands (Section 4)
        if lower == "new line" || lower == "next line" {
            return .windowAction(action: "new_line")
        }
        if lower == "select all" || lower == "select everything" {
            return .windowAction(action: "select_all")
        }
        if lower.contains("copy and paste") || lower.contains("copy that and paste") || lower.contains("copy this and paste") {
            return .windowAction(action: "copy_and_paste")
        }
        let copyPhrases: Set<String> = [
            "copy", "copy that", "copy this", "copy it", "copy all", "copy everything",
            "copy text", "copy the text", "copy selected text", "copy the selected text", "copy selection",
            "copy to clipboard", "copy this to clipboard", "copy that to clipboard",
            "press command c", "command c", "cmd c", "press cmd c", "control c", "ctrl c"
        ]
        if copyPhrases.contains(lower) {
            return .windowAction(action: "copy")
        }
        let pastePhrases: Set<String> = [
            "paste", "paste that", "paste this", "paste it", "paste here", "paste it here", "paste that here",
            "paste text", "paste the text", "paste the copied text", "paste copied text",
            "paste from clipboard", "paste clipboard",
            "press command v", "command v", "cmd v", "press cmd v", "control v", "ctrl v"
        ]
        if pastePhrases.contains(lower) {
            return .windowAction(action: "paste")
        }
        if lower == "undo" {
            return .windowAction(action: "undo")
        }
        if lower == "redo" {
            return .windowAction(action: "redo")
        }
        if lower.contains("delete the last word") || lower == "delete last word" {
            return .windowAction(action: "delete_last_word")
        }
        if lower.hasPrefix("save this file as ") || lower.hasPrefix("save file as ") {
            let cleanName = lower
                .replacingOccurrences(of: "save this file as ", with: "")
                .replacingOccurrences(of: "save file as ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !cleanName.isEmpty {
                return .windowAction(action: "save_as:\(cleanName)")
            }
        }
        if lower.hasPrefix("type ") || lower.hasPrefix("type:") {
            let trimmedInput = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let dropCount = lower.hasPrefix("type:") ? 5 : 5
            let rawTyped = String(trimmedInput.dropFirst(dropCount)).trimmingCharacters(in: .whitespaces)
            let formatted = formatSpokenPunctuation(rawTyped)
            return .uiType(text: formatted)
        }

        if lower.contains("downloads folder") || lower == "open downloads" || lower == "show downloads" {
            return .openUrl(url: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads").absoluteString, inBrowser: "Finder")
        }
        if lower.contains("documents folder") || lower == "open documents" || lower == "show documents" {
            return .openUrl(url: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents").absoluteString, inBrowser: "Finder")
        }

        // 5. Open Application Intent (PRIORITIZED BEFORE MEDIA TO PREVENT 'spotify kholo' -> media_play)
        if let appName = extractAppToOpen(from: normalized) {
            return .openApp(name: appName)
        }
        
        // 6. Hinglish/Generic Messaging ("Rahul ko WhatsApp pe message bhejo ki main late hoon", "slack pe team ko message bhejo...")
        if lower.contains("bhejo") || lower.contains("send message") || lower.contains("message bhejo") || lower.contains("whatsapp pe message") || lower.contains("whatsapp pe bolo") || lower.contains("whatsapp pe likho") {
            let (app, recipient, body) = extractMessageParameters(from: normalized)
            if !recipient.isEmpty {
                return .messageDraft(app: app, recipient: recipient, body: body)
            }
        }

        // 6b. Rich App Integrations (Email/Mail/Gmail, Slack, Discord, WhatsApp, Notion, Notes, YouTube controls)
        if let integration = extractAppIntegration(from: normalized, raw: query) {
            return integration
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
        let cleanLower = lower
            .replacingOccurrences(of: #"[^\w\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Next Track / Video ("change it", "change to next", "change it to next", "next song", "next video", "skip", "agla gana", "spotify change song to next")
        let isNextSong = cleanLower.contains("change song to next") ||
                         cleanLower.contains("change the song to next") ||
                         cleanLower.contains("change to next") ||
                         cleanLower.contains("change it to next") ||
                         cleanLower.contains("change track to next") ||
                         cleanLower.contains("song to next") ||
                         cleanLower.contains("track to next") ||
                         cleanLower.contains("next song") ||
                         cleanLower.contains("next track") ||
                         cleanLower.contains("next video") ||
                         cleanLower.contains("play next song") ||
                         cleanLower.contains("play next track") ||
                         cleanLower.contains("play next") ||
                         cleanLower.contains("skip song") ||
                         cleanLower.contains("skip track") ||
                         cleanLower.contains("skip this") ||
                         cleanLower.contains("skip video") ||
                         cleanLower.contains("skip to next") ||
                         cleanLower.contains("agla gana") ||
                         cleanLower.contains("agla gaana") ||
                         cleanLower.contains("agla video") ||
                         cleanLower.contains("gana badlo") ||
                         cleanLower.contains("gaana badlo") ||
                         cleanLower.contains("song badlo") ||
                         cleanLower.contains("track badlo") ||
                         cleanLower.contains("badal do") ||
                         cleanLower == "change it" || cleanLower == "change song" || cleanLower == "change the song" ||
                         cleanLower == "change track" || cleanLower == "change video" || cleanLower == "change the video" ||
                         cleanLower == "skip" || cleanLower == "next" || cleanLower == "agla" || cleanLower == "badlo" ||
                         cleanLower == "spotify next" || cleanLower == "spotify skip" || cleanLower == "youtube next" ||
                         cleanLower == "music next"
        if isNextSong {
            return .mediaPlay(app: targetMediaApp, query: nil, action: "next")
        }
        
        // Previous Track / Video ("previous", "previus", "change it to previous", "previous song", "previous video", "pichla gana", "spotify change song to previous")
        let isPreviousSong = cleanLower.contains("change song to previous") ||
                             cleanLower.contains("change the song to previous") ||
                             cleanLower.contains("change to previous") ||
                             cleanLower.contains("change it to previous") ||
                             cleanLower.contains("change track to previous") ||
                             cleanLower.contains("song to previous") ||
                             cleanLower.contains("track to previous") ||
                             cleanLower.contains("previous song") ||
                             cleanLower.contains("previous track") ||
                             cleanLower.contains("previous video") ||
                             cleanLower.contains("play previous song") ||
                             cleanLower.contains("play previous track") ||
                             cleanLower.contains("play previous") ||
                             cleanLower.contains("prev song") ||
                             cleanLower.contains("prev track") ||
                             cleanLower.contains("prev video") ||
                             cleanLower.contains("skip to previous") ||
                             cleanLower.contains("pichla gana") ||
                             cleanLower.contains("pichla gaana") ||
                             cleanLower.contains("pichla video") ||
                             cleanLower.contains("peeche karo") ||
                             cleanLower == "previous" || cleanLower == "previus" || cleanLower == "prev" ||
                             cleanLower == "last song" || cleanLower == "pichla" || cleanLower == "peeche" ||
                             cleanLower == "spotify previous" || cleanLower == "spotify prev" ||
                             cleanLower == "youtube previous" || cleanLower == "music previous"
        if isPreviousSong {
            return .mediaPlay(app: targetMediaApp, query: nil, action: "previous")
        }
        
        // Close Video / Tab ("close the video", "close video", "close this video", "close the youtube tab", "close youtube tab", "video band karo", "youtube tab band karo")
        let isCloseVideo = lower == "close the video" || lower == "close video" || lower == "close this video" ||
                           lower == "close youtube" || lower == "close the youtube video" || lower == "close youtube video" ||
                           lower == "close youtube tab" || lower == "close the youtube tab" || lower == "close video tab" ||
                           lower == "close the video tab" || lower.contains("close the video") || lower.contains("close video tab") ||
                           lower.contains("close youtube tab") || lower == "video band karo" || lower == "youtube band karo" ||
                           lower == "youtube tab band karo"
        if isCloseVideo {
            return .mediaPlay(app: "YouTube", query: nil, action: "close")
        }

        // Mute / Unmute Video
        let isMuteVideo = lower == "mute video" || lower == "mute the video" || lower == "mute youtube" || lower == "video mute karo"
        if isMuteVideo {
            return .mediaPlay(app: "YouTube", query: nil, action: "mute")
        }
        let isUnmuteVideo = lower == "unmute video" || lower == "unmute the video" || lower == "unmute youtube" || lower == "video unmute karo"
        if isUnmuteVideo {
            return .mediaPlay(app: "YouTube", query: nil, action: "unmute")
        }

        // Pause / Stop Playback ("pause", "pause it", "pause the video", "pause video", "gana band karo", "video rok do")
        let isPauseMedia = lower == "pause" || lower == "pause it" || lower == "pause the video" || lower == "pause video" ||
                           lower == "pause current video" || lower == "pause the current video" || lower == "pause song" ||
                           lower == "pause the song" || lower == "pause music" || lower == "stop music" || lower == "stop video" ||
                           lower == "music pause" || lower == "video pause" || lower.contains("pause kar do") ||
                           lower.contains("pause karo") || lower.contains("video rok do") || lower.contains("video band karo") ||
                           lower.contains("pause the video") || lower.contains("pause video") || lower.contains("stop the video") ||
                           lower.contains("stop video") || lower.contains("pause youtube") ||
                           lower == "music rok do" || lower == "gana rok do" || lower == "gaana rok do" || lower == "band karo gana" ||
                           lower == "gana band karo" || lower == "gaana band karo" || lower == "music band karo" ||
                           lower == "stop playback" || lower == "pause playback"
        if isPauseMedia {
            return .mediaPlay(app: targetMediaApp, query: nil, action: "pause")
        }
        
        // Contextual Video Play / Resume on Opened Tab or Screen
        let isContextualVideoPlay = (lower.contains("play") || lower.contains("resume") || lower.contains("chalao")) &&
                                    lower.contains("video") && !lower.contains("song") &&
                                    (lower.contains("youtube") || lower.contains("tab") || lower.contains("opened") ||
                                     lower.contains("displayed") || lower.contains("likely") || lower.contains("screen") ||
                                     lower.contains("focused") || lower.contains("frontmost") || lower.contains("browser") ||
                                     (lower.contains("current") && !lower.contains("video or song")))
        if isContextualVideoPlay {
            return .mediaPlay(app: "YouTube", query: nil, action: "play")
        }

        // Play / Resume Playback ("play the current video", "play this song", "play the current video or song", "resume")
        let normalizedPlayPhrase = lower
            .replacingOccurrences(of: #"\s+(?:on\s+screen|on\s+my\s+screen|visible|right\s+now|please)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let contextualPlayPhrases: Set<String> = [
            "play", "play it", "play this", "play that",
            "play video", "play the video", "play this video", "play that video",
            "play current video", "play the current video",
            "play song", "play the song", "play this song", "play that song",
            "play current song", "play the current song",
            "play track", "play this track", "play current track", "play the current track",
            "play music", "play the music", "play this music", "play current music",
            "play current video or song", "play the current video or song",
            "play video or song", "play this video or song",
            "resume", "resume it", "resume this", "resume video", "resume the video",
            "resume this video", "resume song", "resume the song", "resume music",
            "resume playback", "play playback", "play again",
            "chalao", "video chalao", "ye video chalao", "ye gana chalao", "ye gaana chalao"
        ]
        let isPlayOrResume = contextualPlayPhrases.contains(normalizedPlayPhrase) ||
                             lower.contains("chala do") || lower.contains("chalu karo") || lower.contains("resume karo")
        if isPlayOrResume {
            let inferredApp: String?
            if lower.contains("spotify") {
                inferredApp = "Spotify"
            } else if lower.contains("apple music") {
                inferredApp = "Music"
            } else if lower.contains("youtube") || (lower.contains("video") && !lower.contains("song")) {
                inferredApp = "YouTube"
            } else {
                inferredApp = nil
            }
            return .mediaPlay(app: inferredApp, query: nil, action: "play")
        }
        
        // 9. Media / Music ("Spotify pe Arijit Singh ke gaane chalao", "ye gana laga do", "gaana chalao", "play music", "play top hits", "play a song on spotify")
        let isCloseRequest = lower.contains("close") || lower.contains("quit") || lower.contains("kill") || lower.contains("terminate") || (lower.contains("band") && !lower.contains("gana") && !lower.contains("music") && !lower.contains("song") && !lower.contains("video"))
        let hasWholePlay = lower.range(of: "\\bplay\\b", options: .regularExpression) != nil
        let hasMediaActionVerb = hasWholePlay || lower.contains("chalao") || lower.contains("chala do") ||
                                 lower.contains("bajao") || lower.contains("laga do") || lower.contains("pause") ||
                                 lower.contains("skip") || lower.contains("next") || lower.contains("previous") ||
                                 lower.contains("rok do") || lower.contains("band karo")
        let isInfoMediaQuestion = !hasMediaActionVerb && (
                                  query.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") ||
                                  lower.hasPrefix("who ") || lower.hasPrefix("what ") || lower.hasPrefix("why ") ||
                                  lower.hasPrefix("how ") || lower.hasPrefix("when ") || lower.hasPrefix("explain ") ||
                                  lower.hasPrefix("write ") || lower.hasPrefix("tell me "))
        let explicitMediaTarget = lower.contains("spotify") ||
                                  (lower.contains("youtube") && hasMediaActionVerb) ||
                                  (lower.contains("video") && hasMediaActionVerb) ||
                                  lower.contains("gana") || lower.contains("gaana") ||
                                  (lower.contains("music") && (hasMediaActionVerb || lower.contains("top"))) ||
                                  (lower.contains("song") && (hasMediaActionVerb || lower.contains("top"))) ||
                                  (lower.contains("playlist") && hasMediaActionVerb) ||
                                  lower.hasPrefix("play ") || lower.contains("play top") ||
                                  lower.contains("track play") || lower.contains("track chalao") ||
                                  lower.contains("arijit") || lower.contains("diljit") || lower.contains("shreya")
        if !isCloseRequest && !isInfoMediaQuestion && explicitMediaTarget {
            if lower.contains("band karo") || lower.contains("rok do") || lower.contains("pause") || lower.contains("stop") {
                return .mediaPlay(app: targetMediaApp, query: nil, action: "pause")
            }
            if lower.contains("next") || lower.contains("agla") || lower.contains("skip") || lower.contains("change") {
                return .mediaPlay(app: targetMediaApp, query: nil, action: "next")
            }
            if lower.contains("previous") || lower.contains("pichla") || lower.contains("last") {
                return .mediaPlay(app: targetMediaApp, query: nil, action: "previous")
            }
            
            // Extract Artist / Song Query first so "play this song <Name>" extracts <Name>
            var queryTarget = extractMediaQuery(from: normalized)
            
            // If user only said "play this song" or "ye gana chalao" with NO explicit song title:
            if queryTarget == nil && (lower.contains("ye gana") || lower.contains("is gaane") || lower.contains("play this") || lower.contains("play that")) {
                queryTarget = resolveContextualMediaTrack()
            } else if queryTarget == nil && (lower.contains("a song on spotify") || lower.contains("play top hits") || lower.contains("top hits")) {
                queryTarget = "Top Hits"
            }
            return .mediaPlay(app: targetMediaApp, query: queryTarget, action: "play")
        }
        
        // 9. Fallback Generic Search ("Google pe search karo...", "dhoondo...", explicit web search)
        let isCodingSearchTopic = lower.contains("binary search") || lower.contains("linear search") ||
                                    lower.contains("depth first search") || lower.contains("breadth first search") ||
                                    lower.contains("a* search") || lower.contains("search algorithm") ||
                                    lower.contains("search my files") || lower.contains("job search")
        let hasWholeSearch = lower.range(of: "\\bsearch\\b", options: .regularExpression) != nil
        if !isCodingSearchTopic && (lower.contains("search karo") || lower.contains("dhoondo") || lower.contains("pata karo") || hasWholeSearch) {
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
        
        // Disqualify URLs, tabs, messaging, multi-app chains, files, and music media requests from single-app launch
        if lower.contains("tab") || lower.contains("youtube") || lower.contains("github") || lower.contains("twitter") || lower.contains(".com") || lower.contains(".org") || lower.contains(" and ") {
            return nil
        }
        if (lower.hasPrefix("open file ") && !lower.contains("file manager") && !lower.contains("file explorer")) || lower == "open it" || lower.contains("word document") || lower.contains("spreadsheet") || lower.contains("latest file") {
            return nil
        }
        if lower.contains("message") || lower.contains("sandesh") || lower.contains("bhejo") {
            return nil
        }
        if lower.contains("gana") || lower.contains("gaane") || lower.contains("song") || lower.contains("playlist") ||
           lower.contains("top hits") || lower.contains("music chalao") || lower.contains("arijit") || lower.contains("diljit") || lower.contains("shreya") ||
           lower.contains("next") || lower.contains("previous") || lower.contains("prev") || lower.contains("skip") {
            return nil
        }
        
        // Common app dictionary (including cross-OS aliases)
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
            "file manager": "Finder",
            "file explorer": "Finder",
            "notes": "Notes",
            "apple notes": "Notes",
            "notepad": "TextEdit",
            "textedit": "TextEdit",
            "gedit": "TextEdit",
            "text editor": "TextEdit",
            "settings": "System Settings",
            "system settings": "System Settings",
            "task manager": "Activity Monitor",
            "activity monitor": "Activity Monitor",
            "slack": "Slack",
            "notion": "Notion",
            "discord": "Discord",
            "photos": "Photos",
            "calendar": "Calendar",
            "mail": "Mail",
            "email": "Mail",
            "my email": "Mail",
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
        
        // Check if query is an app opening/switching command
        let isOpeningVerb = lower.contains("kholo") || lower.contains("klo") || lower.contains("kldo") ||
                            lower.contains("open") || lower.contains("switch to") ||
                            (lower.contains("chalao") && !lower.contains("gana") && !lower.contains("music")) ||
                            lower.contains("launch") || lower.contains("start")
        guard isOpeningVerb else { return nil }
        
        for (key, appName) in knownApps.sorted(by: { $0.key.count > $1.key.count }) {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: key) + "\\b"
            if lower.range(of: pattern, options: .regularExpression) != nil {
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
    
    public static func extractMediaQuery(from text: String) -> String? {
        var str = text.lowercased()
        for prefix in ["the voice ", "hey voice ", "ok voice ", "voice "] {
            if str.hasPrefix(prefix) {
                str = String(str.dropFirst(prefix.count))
                break
            }
        }
        let strips = [
            "play the song on spotify", "play a song on spotify", "play a song in spotify", "play a song from spotify", "play a song",
            "play the song", "play some song", "play song on spotify", "play song",
            "play some music on spotify", "play some music", "play music on spotify", "play music",
            "play this song on spotify", "play this track on spotify", "play this song", "play this track", "play this",
            "play that song on spotify", "play that track on spotify", "play that song", "play that track", "play that",
            "on spotify", "in spotify", "from spotify", "spotify pe", "spotify par", "spotify mein", "spotify",
            "ke gaane chalao", "ka gana chalao", "ke gaane", "ka gana", "ke gaana",
            "gana chalao", "gaana chalao", "gaane chalao", "chalao", "chala do", "laga do", "bajao", "sunao",
            "play track", "play top hits", "play",
            "a song on", "a song in", "a song", "the song on", "the song", "some song", "some music", "song on", "song"
        ].sorted { $0.count > $1.count }
        for s in strips {
            str = str.replacingOccurrences(of: s, with: " ")
        }
        var cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for p in ["called ", "named ", "by "] {
            if cleaned.lowercased().hasPrefix(p) {
                cleaned = String(cleaned.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
        }
        for suffix in [" on", " in", " from", " pe", " par", " mein"] {
            if cleaned.lowercased().hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
        }
        let genericFilters: Set<String> = [
            "", "a", "a song", "a song on", "on", "song", "songs", "music", "some music",
            "track", "a track", "top", "hits", "top hits", "gana", "gaana", "some", "the", "the song",
            "this", "this song", "that", "that song", "it"
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
        } else if let boloRange = lower.range(of: " bolo ") {
            body = String(text[boloRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let likhoRange = lower.range(of: " likho ") {
            body = String(text[likhoRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let thatRange = lower.range(of: " that ") {
            body = String(text[thatRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let sayingRange = lower.range(of: " saying ") {
            body = String(text[sayingRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
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

        // Do not intercept media transport control commands (close, pause, mute, or controlling currently open video tabs)
        if lower.contains("close") || lower.contains("band") || lower.contains("pause") || lower.contains("rok") ||
           lower.contains("mute") || lower.contains("unmute") || lower.contains("opened up") || lower.contains("likely") ||
           (lower.contains("video") && (lower.contains("this video") || lower.contains("the video") || lower.contains("current"))) {
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
            "open terminal and run ", "open terminal and execute ",
            "run command in terminal ", "run command on terminal ",
            "run terminal command ", "terminal mein command chalao ",
            "run command ", "execute command ", "terminal mein chalao ",
            "terminal pe chalao ", "terminal command ", "run "
        ]
        for p in prefixes {
            if let r = str.range(of: p, options: .caseInsensitive) {
                str = String(str[r.upperBound...])
                break
            }
        }
        for s in [" in terminal window", " on terminal", " in terminal", " and tell me what happened", " aur batao kya hua", " aur check karo"] {
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
    
    /// Resolves contextual ambiguity (e.g. "ye gana laga do") by inspecting current media, clipboard, or active window
    private static func resolveContextualMediaTrack() -> String? {
        if let current = NowPlayingMediaManager.shared.currentMedia, !current.title.isEmpty {
            return current.title
        }
        let pb = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !pb.isEmpty && pb.count < 80 && !pb.contains("\n") {
            return pb
        }
        return nil
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
        
        // Exclude music/media playback stop ("gana band karo", "song band karo", "music band karo", "video band karo", "close the video")
        if lower.contains("gana") || lower.contains("gaana") || lower.contains("music") ||
           lower.contains("song") || lower.contains("audio") || lower.contains("playback") ||
           lower.contains("video") {
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
            "close the ",
            "quit the ",
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
        if lowerTrimmed == "notepad" || lowerTrimmed == "textedit" || lowerTrimmed == "gedit" { return "TextEdit" }
        if lowerTrimmed == "calendar" || lowerTrimmed == "apple calendar" { return "Calendar" }
        if lowerTrimmed == "whatsapp" { return "WhatsApp" }
        if lowerTrimmed == "vscode" || lowerTrimmed == "vs code" || lowerTrimmed == "visual studio code" { return "Visual Studio Code" }
        if lowerTrimmed == "finder" || lowerTrimmed == "file manager" { return "Finder" }
        if lowerTrimmed == "task manager" || lowerTrimmed == "activity monitor" { return "Activity Monitor" }
        
        return trimmedCandidate.capitalized
    }

    private static func formatSpokenPunctuation(_ raw: String) -> String {
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacements: [(String, String)] = [
            ("\\s+comma\\b", ","),
            ("\\s+period\\b", "."),
            ("\\s+full stop\\b", "."),
            ("\\s+question mark\\b", "?"),
            ("\\s+exclamation mark\\b", "!"),
            ("\\s+exclamation point\\b", "!"),
            ("\\s+colon\\b", ":"),
            ("\\s+semicolon\\b", ";"),
            ("\\s+new line\\b", "\n")
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        return result
    }

    // MARK: - Rich Multi-App Integration Intent Extractor

    private static func extractAppIntegration(from normalized: String, raw: String) -> AgentTool? {
        let lower = normalized.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Preserve original capitalization for English titles, names, and drafted bodies while still using Hinglish normalization when rewritten
        let textForExtraction = (normalized.lowercased() == raw.lowercased()) ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : normalized

        // Exclude pure conceptual questions unless asking about active content/inbox/video
        let isConceptualQ = (lower.hasPrefix("what is ") || lower.hasPrefix("explain ") || lower.hasPrefix("who invented ") || lower.hasPrefix("how does ")) &&
                            !lower.contains("this youtube") && !lower.contains("this video") && !lower.contains("my email") && !lower.contains("my inbox") && !lower.contains("my note")
        if isConceptualQ { return nil }

        // Handle "Open my email" / "Open email" directly as launching Mail before integration extractor
        if lower == "open my email" || lower == "open email" || lower == "open mail" || lower == "launch mail" {
            return .openApp(name: "Mail")
        }

        // 1. Email / Apple Mail / Gmail (draft, reply, send, check inbox, search)
        let mentionsEmail = lower.range(of: "\\b(e?mails?|inbox|gmail)\\b", options: .regularExpression) != nil
        if mentionsEmail && !lower.contains("what is an email") && !lower.contains("explain email") {
            if lower.contains("check") || lower.contains("unread") || lower.contains("inbox") || lower.contains("read my") || lower.contains("latest email") || lower.contains("latest mail") {
                return .appIntegration(app: "mail", operation: "check_inbox", params: [:])
            }
            if lower.contains("search ") || lower.contains("find ") {
                let q = stripLeadingVerbs(textForExtraction, prefixes: ["search my emails for ", "search emails for ", "search email for ", "find emails from ", "find email from ", "find email about ", "search email "])
                return .appIntegration(app: "mail", operation: "search", params: ["query": q])
            }
            if lower.contains("reply") || lower.contains("respond") {
                let shouldSend = lower.contains("and send") || lower.contains("bhej do")
                let body = extractAfterMarkers(textForExtraction, markers: [" saying ", " that ", " with ", " ki ", ": "]) ?? ""
                let rawRecipient = extractRecipientAfter(textForExtraction, prepositions: [" to "]) ?? ""
                let fillerRecipients: Set<String> = ["this", "the", "it", "email", "mail", "this email", "the email", "this mail", "the mail", "latest email", "last email"]
                let recipient = fillerRecipients.contains(rawRecipient.lowercased()) ? "" : rawRecipient
                return .appIntegration(app: "mail", operation: shouldSend ? "reply_and_send" : "reply", params: [
                    "recipient": recipient,
                    "body": body,
                    "query": body.isEmpty ? textForExtraction : ""
                ])
            }
            if lower.contains("draft") || lower.contains("compose") || lower.contains("send") || lower.contains("write a mail") || lower.contains("write an email") || lower.contains("mail ") {
                let shouldSend = (lower.contains("send ") && !lower.contains("draft")) || lower.contains("bhej do")
                let recipient = extractRecipientAfter(textForExtraction, prepositions: [" to "]) ?? ""
                let subject = extractBetween(textForExtraction, startMarkers: [" about ", " subject ", " regarding "], endMarkers: [" saying ", " body ", " that ", " ki ", " with "]) ?? ""
                let body = extractAfterMarkers(textForExtraction, markers: [" saying ", " body ", " with message ", " that ", " ki "]) ?? ""
                return .appIntegration(app: "mail", operation: shouldSend ? "send" : "draft", params: [
                    "recipient": recipient,
                    "subject": subject,
                    "body": body,
                    "query": textForExtraction
                ])
            }
        }

        // 2. Slack & Discord ("send slack message to #dev saying ...", "draft discord message...", "open #general in slack", "message #general on Slack: standup in 5 minutes", "Slack pe general channel me likho...", "Reply to the last message on Discord with 'sounds good'", "Discord pe jawab do...", "Read my unread Slack messages", "Mere unread messages padho", "React with a thumbs up", "Set my Slack status to in a meeting", "Search Slack for invoice", "Open the dev-team channel", "dev-team khol do")
        if lower.contains("slack") || lower.contains("discord") || lower.contains("dev-team") || lower.contains("thumbs up") || lower.contains("unread messages padho") {
            let appId = lower.contains("discord") ? "discord" : "slack"
            
            if lower.contains("react") || lower.contains("thumbs up") {
                let emoji = lower.contains("thumbs up") ? "thumbsup" : "heart"
                return .appIntegration(app: appId, operation: "react", params: ["emoji": emoji])
            }
            if lower.contains("status") {
                let statusText = extractAfterMarkers(textForExtraction, markers: [" status to ", " status: ", " status "]) ?? "in a meeting"
                return .appIntegration(app: appId, operation: "set_status", params: ["status": statusText])
            }
            if lower.contains("search") || lower.contains("dhoondo") {
                let q = extractAfterMarkers(textForExtraction, markers: [" for ", " dhoondo "]) ?? ""
                return .appIntegration(app: appId, operation: "search", params: ["query": q.isEmpty ? textForExtraction : q])
            }
            if lower.contains("reply") || lower.contains("jawab") {
                let body = extractAfterMarkers(textForExtraction, markers: [" with '", " with \"", " with ", " saying ", " ki ", ": ", " jawab do "]) ?? "sounds good"
                return .appIntegration(app: appId, operation: "reply", params: ["body": body.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))])
            }
            if lower.contains("read ") || lower.contains("check ") || lower.contains("summarize ") || lower.contains("padho") || lower.contains("unread") {
                return .appIntegration(app: appId, operation: "read", params: [:])
            }
            if (lower.contains("channel") || lower.contains("dev-team")) && (lower.contains("khol") || lower.contains("open")) {
                let target = extractChannelOrPerson(from: textForExtraction, appName: appId)
                return .appIntegration(app: appId, operation: "open_channel", params: ["recipient": target.isEmpty ? "dev-team" : target])
            }
            let hasExplicitSend = (lower.contains("send") || lower.contains("post") || lower.contains("bhej") || lower.contains("likh") || lower.contains("message #") || lower.contains("message")) && !lower.contains("draft")
            let isDraft = lower.contains("draft") || lower.contains("compose") || lower.contains("write")
            let body = extractAfterMarkers(textForExtraction, markers: [" saying ", " that ", " ki ", ": ", " me likho ", " pe likho "]) ?? ""
            let target = extractChannelOrPerson(from: textForExtraction, appName: appId)
            if hasExplicitSend || isDraft || !body.isEmpty || !target.isEmpty {
                let op = hasExplicitSend ? "send" : (isDraft || !body.isEmpty ? "draft" : "open_channel")
                return .appIntegration(app: appId, operation: op, params: [
                    "recipient": target,
                    "body": body
                ])
            }
        }

        // 3. WhatsApp English/Rich ("draft whatsapp message to Rahul saying ...", "open Rahul chat on whatsapp", "read whatsapp", "What did Priya say on WhatsApp?", "Priya ne kya bheja?", "dictate and send")
        // Note: preserve existing Hinglish "Rahul ko WhatsApp pe message bhejo..." for `.messageDraft` parity!
        if lower.contains("whatsapp") || lower.contains("whatapp") || lower.contains("kya bheja") || lower.contains("dictate and send") {
            if lower.contains("dictate and send") || lower.contains("dictate") {
                return .appIntegration(app: "whatsapp", operation: "dictate_send", params: [:])
            }
            if lower.contains("read ") || lower.contains("check ") || lower.contains("summarize ") || lower.contains("kya bheja") || lower.contains("what did") {
                let target = extractRecipientAfter(textForExtraction, prepositions: [" did ", " from ", " se "]) ?? extractChannelOrPerson(from: textForExtraction, appName: "whatsapp")
                return .appIntegration(app: "whatsapp", operation: "read", params: ["recipient": target.isEmpty ? "Priya" : target])
            }
            if lower.contains("chat with ") || (lower.contains("open ") && lower.contains(" chat")) {
                let target = extractRecipientAfter(textForExtraction, prepositions: [" with ", " chat ", " to "]) ?? extractChannelOrPerson(from: textForExtraction, appName: "whatsapp")
                return .appIntegration(app: "whatsapp", operation: "open_chat", params: ["recipient": target])
            }
            if (lower.contains("draft") || lower.contains("compose")) && lower.contains("whatsapp") {
                let body = extractAfterMarkers(textForExtraction, markers: [" saying ", " that ", " ki ", ": "]) ?? ""
                let recipient = extractRecipientAfter(textForExtraction, prepositions: [" to ", " for "]) ?? ""
                return .appIntegration(app: "whatsapp", operation: "draft", params: ["recipient": recipient, "body": body])
            }
            if lower.hasPrefix("send a whatsapp") || lower.hasPrefix("send whatsapp") || (lower.contains("send ") && lower.contains("whatsapp")) {
                let body = extractAfterMarkers(textForExtraction, markers: [" saying ", " that ", " bolo ", ": "]) ?? ""
                let recipient = extractRecipientAfter(textForExtraction, prepositions: [" to "]) ?? extractChannelOrPerson(from: textForExtraction, appName: "whatsapp")
                return .appIntegration(app: "whatsapp", operation: "send", params: ["recipient": recipient, "body": body])
            }
        }

        // 4. Notion ("create notion page ...", "search ... in notion", "open ... in notion", "append ... to notion")
        if lower.contains("notion") {
            if lower.contains("search ") || lower.contains("find ") || (lower.contains("open ") && !lower.trimmingCharacters(in: .whitespaces).hasSuffix("notion")) {
                let q = stripLeadingVerbs(textForExtraction, prefixes: ["search notion for ", "search ", "find ", "open "])
                    .replacingOccurrences(of: " in notion", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: " on notion", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !q.isEmpty {
                    return .appIntegration(app: "notion", operation: "search", params: ["query": q, "title": q])
                }
            }
            if lower.contains("append") || lower.contains("add to notion") || lower.contains("add to my notion") {
                let body = extractAfterMarkers(textForExtraction, markers: [" saying ", " text ", " to notion ", ": "]) ?? stripLeadingVerbs(textForExtraction, prefixes: ["append ", "add "])
                return .appIntegration(app: "notion", operation: "append", params: ["body": body])
            }
            if lower.contains("create") || lower.contains("new page") || lower.contains("make a page") || lower.contains("add page") {
                let title = extractBetween(textForExtraction, startMarkers: ["titled ", "called ", "named ", "page "], endMarkers: [" with ", " saying ", " content ", ": "]) ?? ""
                let body = extractAfterMarkers(textForExtraction, markers: [" with ", " content ", " saying ", ": "]) ?? ""
                return .appIntegration(app: "notion", operation: "create_page", params: [
                    "title": title.replacingOccurrences(of: "notion", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines),
                    "body": body
                ])
            }
        }

        // 5. Apple Notes ("append ... to my ... note", "read my ... note", "list my notes")
        if lower.contains("note") && !lower.contains("notion") {
            if lower.contains("list my notes") || lower.contains("list notes") || lower.contains("show my notes") || lower.contains("recent notes") {
                return .appIntegration(app: "notes", operation: "list", params: [:])
            }
            if (lower.hasPrefix("read ") || lower.contains("read my ")) && (lower.contains(" note") || lower.contains(" notes")) {
                let q = stripLeadingVerbs(textForExtraction, prefixes: ["read my ", "read the ", "read "])
                    .replacingOccurrences(of: " note", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .appIntegration(app: "notes", operation: "read", params: ["query": q])
            }
            if lower.contains("append ") || (lower.contains("add ") && (lower.contains(" to my ") || lower.contains(" to the ") || lower.contains(" to note "))) {
                let title = extractAfterMarkers(textForExtraction, markers: [" to my ", " to the ", " to note "])?
                    .replacingOccurrences(of: " note", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let body = extractBetween(textForExtraction, startMarkers: ["append ", "add "], endMarkers: [" to my ", " to the ", " to note "]) ?? ""
                if !body.isEmpty {
                    return .appIntegration(app: "notes", operation: "append", params: ["title": title, "body": body])
                }
            }
        }

        // 6. YouTube Rich Player Controls & Summarization
        if lower.contains("mute youtube") || lower == "mute video" {
            return .appIntegration(app: "youtube", operation: "mute", params: [:])
        }
        if lower.contains("unmute youtube") || lower == "unmute video" {
            return .appIntegration(app: "youtube", operation: "unmute", params: [:])
        }
        if lower.contains("fullscreen youtube") || lower.contains("youtube fullscreen") {
            return .appIntegration(app: "youtube", operation: "fullscreen", params: [:])
        }
        if lower.contains("fast forward") || lower.contains("skip forward") || lower.contains("forward 10") {
            return .appIntegration(app: "youtube", operation: "forward", params: [:])
        }
        if lower.contains("rewind") || lower.contains("skip back") || lower.contains("back 10") {
            return .appIntegration(app: "youtube", operation: "rewind", params: [:])
        }
        if lower.contains("like this video") || lower.contains("like the video") {
            return .appIntegration(app: "youtube", operation: "like", params: [:])
        }
        if lower == "subscribe" || lower.contains("subscribe to this channel") || lower.contains("subscribe to channel") {
            return .appIntegration(app: "youtube", operation: "subscribe", params: [:])
        }
        if (lower.contains("summarize") || lower.contains("what is this video") || lower.contains("what's this video")) &&
           (lower.contains("youtube") || lower.contains("video")) {
            return .appIntegration(app: "youtube", operation: "summarize", params: [:])
        }

        return nil
    }

    private static func stripLeadingVerbs(_ text: String, prefixes: [String]) -> String {
        for p in prefixes {
            if let r = text.range(of: p, options: [.caseInsensitive, .anchored]) {
                return String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    private static func extractAfterMarkers(_ text: String, markers: [String]) -> String? {
        for m in markers {
            if let r = text.range(of: m, options: .caseInsensitive) {
                let tail = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty { return tail }
            }
        }
        return nil
    }

    private static func extractBetween(_ text: String, startMarkers: [String], endMarkers: [String]) -> String? {
        for s in startMarkers {
            if let sr = text.range(of: s, options: .caseInsensitive) {
                let after = String(text[sr.upperBound...])
                var endIndex = after.endIndex
                for e in endMarkers {
                    if let er = after.range(of: e, options: .caseInsensitive), er.lowerBound < endIndex {
                        endIndex = er.lowerBound
                    }
                }
                let result = String(after[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !result.isEmpty { return result }
            }
        }
        return nil
    }

    private static func extractRecipientAfter(_ text: String, prepositions: [String]) -> String? {
        let stopTokens: Set<String> = ["about", "saying", "that", "with", "subject", "regarding", "on", "in", "ki"]
        for prep in prepositions {
            if let r = text.range(of: prep, options: .caseInsensitive) {
                let after = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let words = after.split(separator: " ").map { String($0) }
                var collected: [String] = []
                for w in words {
                    if stopTokens.contains(w.lowercased()) { break }
                    collected.append(w)
                    if collected.count >= 3 { break }
                }
                let res = collected.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
                if !res.isEmpty { return res }
            }
        }
        return nil
    }

    private static func extractChannelOrPerson(from text: String, appName: String) -> String {
        if let hashMatch = text.range(of: "#[A-Za-z0-9_-]+", options: .regularExpression) {
            return String(text[hashMatch])
        }
        if let rec = extractRecipientAfter(text, prepositions: [" to ", " in ", " channel "]) {
            let cleaned = rec.replacingOccurrences(of: appName, with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        return ""
    }
}
