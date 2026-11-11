import Foundation
import AppKit

public struct ExecutionStep: Codable, Sendable, Identifiable {
    public var id: String { "\(step_number)_\(action)_\(param)" }
    public let step_number: Int
    public let action: String // "focus_application" | "visual_locate_and_click" | "keystroke" | "type_text" | "system_command" | "web_search" | "run_shell" | "app_integration"
    public let param: String
    
    public init(step_number: Int, action: String, param: String) {
        self.step_number = step_number
        self.action = action
        self.param = param
    }

    private enum CodingKeys: String, CodingKey {
        case step_number, action, param
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.step_number = (try? container.decode(Int.self, forKey: .step_number)) ?? 1
        self.action = try container.decode(String.self, forKey: .action)
        if let str = try? container.decode(String.self, forKey: .param) {
            self.param = str
        } else if let obj = try? container.decode([String: String].self, forKey: .param),
                  let data = try? JSONSerialization.data(withJSONObject: obj),
                  let encoded = String(data: data, encoding: .utf8) {
            self.param = encoded
        } else {
            self.param = ""
        }
    }
}

public struct OrchestratedPlan: Codable, Sendable {
    public let intent: String // "software_automation" | "system_control" | "web_search"
    public let target_application: String?
    public let steps: [ExecutionStep]
    
    public var targetApplication: String {
        return target_application ?? ""
    }
    
    public init(intent: String, target_application: String?, steps: [ExecutionStep]) {
        self.intent = intent
        self.target_application = target_application
        self.steps = steps
    }
}

/// Structured JSON LLM Orchestrator
/// Eliminates fragile string-matching by converting natural Hindi, Hinglish, and English commands
/// into strictly valid, multi-step structured JSON plans executed by the vision and input engines.
public final class LLMIntentOrchestrator: @unchecked Sendable {
    public static let shared = LLMIntentOrchestrator()
    
    public static let systemPrompt = """
    You are the central OS orchestrator for Voice.AI.
    Your task is to convert colloquial Hindi, Hinglish, and English user voice transcripts into a strictly valid, structured JSON execution plan.
    
    CRITICAL CONSTRAINTS:
    1. Output MUST be ONLY valid JSON matching the exact schema below.
    2. Do NOT output markdown code fences, explanations, notes, or any conversational text.
    3. Allowable actions:
       - "focus_application": param is application name (e.g., "Notes", "Terminal", "Finder", "Calculator", "System Settings", "VS Code")
       - "visual_locate_and_click": param is exact visible label of the UI element on screen (ONLY use when user explicitly asks to click a button/link)
       - "keystroke": param is key combination (e.g., "Shift+A", "Space", "Return", "Command+S", "Command+N")
       - "type_text": param is text string to insert
       - "system_command": param is system action ("volume_level 0..100", "volume_up", "volume_down", "mute", "unmute", "brightness_up", "brightness_down", "dark_mode_on", "dark_mode_off", "dark_mode_toggle", "battery", "disk_space", "ram_status", "play_music <Song Name>", "close_application", "screenshot", "lock", "sleep")
       - "run_shell": safe zsh command to inspect system state or manage user folders/files in ~/Desktop, ~/Documents, or ~/Downloads (e.g., "mkdir -p ~/Desktop/Projects", "ls -la ~/Desktop", "open ~/Downloads")
       - "app_integration": param is JSON string with keys {"app":"mail|whatsapp|slack|discord|youtube|notion|notes|terminal","operation":"draft|send|reply|reply_and_send|check_inbox|search|open_chat|open_channel|read|play|pause|next|previous|mute|unmute|fullscreen|forward|rewind|like|subscribe|summarize|create_page|append|create|list|run_headless|run_in_window|read_output","recipient":"","subject":"","body":"","title":"","query":"","command":""}
       - "web_search": param is web query string
    
    JSON SCHEMA:
    {
      "intent": "software_automation" | "system_control" | "web_search" | "conversation",
      "target_application": "AppName" | null,
      "steps": [
        { "step_number": 1, "action": "focus_application", "param": "Blender" },
        { "step_number": 2, "action": "visual_locate_and_click", "param": "Sculpt Mode dropdown menu" },
        { "step_number": 3, "action": "keystroke", "param": "Shift+A" }
      ]
    }
    
    INTENT RULES:
    - Use "software_automation" or "system_control" ONLY when the user explicitly wants to control macOS or an application.
    - CRITICAL RULE: NEVER output "Safari", "Browser", "Chrome", or "Spotify" unless the user explicitly mentions Safari, Chrome, opening a browser/tab, searching Google, Spotify, music, or playing a song.
    - Use "web_search" ONLY when the user explicitly says "search", "google", "open tab", or asks for live real-time info (today's weather, current news, stock price, live score).
    - Use "conversation" (with empty steps: []) for ALL general knowledge questions, science/history/geography questions (e.g. capitals, constants, speed of sound), explanations, coding help, summaries, writing emails/essays, or casual chat.
    
    FEW-SHOT EXAMPLES:
    User: "put the volume down to 0 percent" or "volume zero kar do"
    JSON:
    {"intent":"system_control","target_application":"System","steps":[{"step_number":1,"action":"system_command","param":"volume_level 0"}]}

    User: "set volume to 80 percent" or "volume 80 kar do"
    JSON:
    {"intent":"system_control","target_application":"System","steps":[{"step_number":1,"action":"system_command","param":"volume_level 80"}]}

    User: "Blender mein cube sculpt karo"
    JSON:
    {"intent":"software_automation","target_application":"Blender","steps":[{"step_number":1,"action":"focus_application","param":"Blender"},{"step_number":2,"action":"visual_locate_and_click","param":"Sculpt Mode dropdown menu"},{"step_number":3,"action":"keystroke","param":"Shift+A"}]}
    
    User: "Spotify band kar do"
    JSON:
    {"intent":"system_control","target_application":"Spotify","steps":[{"step_number":1,"action":"focus_application","param":"Spotify"},{"step_number":2,"action":"system_command","param":"close_application"}]}
    
    User: "play the song on spotify" or "spotify pe gaana chalao"
    JSON:
    {"intent":"software_automation","target_application":"Spotify","steps":[{"step_number":1,"action":"focus_application","param":"Spotify"},{"step_number":2,"action":"system_command","param":"play_music"}]}

    User: "play the song Starboy on spotify" or "Voice play this song Starboy" or "Spotify pe Starboy chalao"
    JSON:
    {"intent":"software_automation","target_application":"Spotify","steps":[{"step_number":1,"action":"focus_application","param":"Spotify"},{"step_number":2,"action":"system_command","param":"play_music Starboy"}]}

    User: "turn on dark mode" or "dark mode on karo"
    JSON:
    {"intent":"system_control","target_application":"System","steps":[{"step_number":1,"action":"system_command","param":"dark_mode_on"}]}

    User: "create a folder named Work on desktop" or "desktop pe Work folder banao"
    JSON:
    {"intent":"software_automation","target_application":"Finder","steps":[{"step_number":1,"action":"run_shell","param":"mkdir -p ~/Desktop/Work && open ~/Desktop/Work"}]}

    User: "check my battery percentage" or "disk space kitni bachi hai"
    JSON:
    {"intent":"system_control","target_application":"System","steps":[{"step_number":1,"action":"system_command","param":"battery"}]}

    User: "open Calculator" or "Terminal kholo"
    JSON:
    {"intent":"software_automation","target_application":"Calculator","steps":[{"step_number":1,"action":"focus_application","param":"Calculator"}]}

    User: "create a note saying buy milk" or "take a note about meeting"
    JSON:
    {"intent":"software_automation","target_application":"Apple Notes","steps":[{"step_number":1,"action":"app_integration","param":"{\"app\":\"notes\",\"operation\":\"create\",\"title\":\"Meeting Note\",\"body\":\"buy milk\"}"}]}

    User: "draft an email to sara@acme.com about Q4 launch" or "send email to John saying I will join at 3"
    JSON:
    {"intent":"software_automation","target_application":"Email","steps":[{"step_number":1,"action":"app_integration","param":"{\"app\":\"mail\",\"operation\":\"draft\",\"recipient\":\"sara@acme.com\",\"subject\":\"Q4 Launch\",\"query\":\"Q4 launch update\"}"}]}

    User: "reply to this email saying thanks I received it" or "check my unread emails"
    JSON:
    {"intent":"software_automation","target_application":"Email","steps":[{"step_number":1,"action":"app_integration","param":"{\"app\":\"mail\",\"operation\":\"reply\",\"body\":\"Thanks, I received it.\"}"}]}

    User: "send a slack message to #engineering saying release is live" or "draft a discord message to #general saying hi"
    JSON:
    {"intent":"software_automation","target_application":"Slack","steps":[{"step_number":1,"action":"app_integration","param":"{\"app\":\"slack\",\"operation\":\"send\",\"recipient\":\"#engineering\",\"body\":\"release is live\"}"}]}

    User: "create a notion page titled Sprint Plan with test voice control"
    JSON:
    {"intent":"software_automation","target_application":"Notion","steps":[{"step_number":1,"action":"app_integration","param":"{\"app\":\"notion\",\"operation\":\"create_page\",\"title\":\"Sprint Plan\",\"body\":\"test voice control\"}"}]}

    User: "summarize this youtube video" or "mute youtube"
    JSON:
    {"intent":"software_automation","target_application":"YouTube","steps":[{"step_number":1,"action":"app_integration","param":"{\"app\":\"youtube\",\"operation\":\"summarize\"}"}]}

    User: "explain how neural networks work" or "what is Swift" or "how do I learn Python?"
    JSON:
    {"intent":"conversation","target_application":null,"steps":[]}
    """
    
    private init() {}
    
    /// Parses speech transcript into structured JSON plan using active model (Local Llama 3.2 or Cloud)
    public func plan(transcript: String) async throws -> OrchestratedPlan {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            throw NSError(domain: "LLMIntentOrchestrator", code: 400, userInfo: [NSLocalizedDescriptionKey: "Empty transcript"])
        }
        
        var messages: [LLMChatMessage] = [
            LLMChatMessage(role: .system, content: LLMIntentOrchestrator.systemPrompt)
        ]
        
        // Inject live macOS desktop context so the local LLM Brain knows active & open apps
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Desktop"
        let runningAppNames = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
            .prefix(8)
            .joined(separator: ", ")
        let enabledIntegrations = ["mail", "whatsapp", "slack", "discord", "youtube", "notion", "notes", "terminal"]
            .filter { AppIntegrationEngine.shared.isAppIntegrated($0) }
            .joined(separator: ", ")
        let desktopContext = "Live Mac Context — Frontmost App: \(frontApp) | Running Apps: \(runningAppNames) | Integrated Apps: \(enabledIntegrations)"
        
        // Dynamic Context Compaction: Inject bounded sliding-window context
        let compactedContext = SlidingWindowContextCompactor.shared.getCompactedPromptContext()
        let combinedContext = compactedContext.isEmpty ? desktopContext : "\(desktopContext)\nRecent history:\n\(compactedContext)"
        messages.append(LLMChatMessage(role: .system, content: combinedContext))
        
        messages.append(LLMChatMessage(role: .user, content: cleaned))
        
        var rawResponse = ""
        
        // 1. Resolve active model through ModelRouter (bounded 12s routing classification budget)
        let chatModel = ModelRouter.shared.resolveChatModel()
        do {
            let res = try await withThrowingTaskGroup(of: ChatResponse.self) { group in
                group.addTask {
                    try await chatModel.sendMessage(messages: messages, tools: nil, jsonMode: true)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 12_000_000_000)
                    throw CancellationError()
                }
                guard let first = try await group.next() else {
                    throw CancellationError()
                }
                group.cancelAll()
                return first
            }
            rawResponse = res.text
        } catch {
            rawResponse = synthesizeDeterministicPlan(for: cleaned)
        }
        
        let plan = try parseOrchestratedPlan(from: rawResponse, fallbackQuery: cleaned)
        
        // Record turn in sliding window compactor
        let actionSummaries = plan.steps.map { "\($0.action)(\($0.param))" }
        SlidingWindowContextCompactor.shared.recordTurn(
            userIntent: cleaned,
            targetApplication: plan.targetApplication,
            actions: actionSummaries
        )
        
        return plan
    }
    
    /// Robust JSON extractor ensuring clean parsing even if model wraps output in markdown or text
    public func parseOrchestratedPlan(from text: String, fallbackQuery: String) throws -> OrchestratedPlan {
        var jsonText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strip ```json ... ``` blocks
        if let startRange = jsonText.range(of: "```json") {
            jsonText = String(jsonText[startRange.upperBound...])
        } else if let startRange = jsonText.range(of: "```") {
            jsonText = String(jsonText[startRange.upperBound...])
        }
        if let endRange = jsonText.range(of: "```", options: .backwards) {
            jsonText = String(jsonText[..<endRange.lowerBound])
        }
        
        // Extract first balanced { ... } so trailing "} JSON; {" hallucinations do not corrupt decoding
        if let balanced = extractFirstBalancedJSONObject(from: jsonText) {
            jsonText = balanced
        } else if let firstBrace = jsonText.firstIndex(of: "{"),
                  let lastBrace = jsonText.lastIndex(of: "}") {
            jsonText = String(jsonText[firstBrace...lastBrace])
        }
        
        guard let data = jsonText.data(using: .utf8) else {
            return try JSONDecoder().decode(OrchestratedPlan.self, from: synthesizeDeterministicPlan(for: fallbackQuery).data(using: .utf8)!)
        }
        
        do {
            let decoded = try JSONDecoder().decode(OrchestratedPlan.self, from: data)
            if Self.containsMalformedShellArtifact(decoded) {
                let fallbackJSON = synthesizeDeterministicPlan(for: fallbackQuery)
                return try JSONDecoder().decode(OrchestratedPlan.self, from: fallbackJSON.data(using: .utf8)!)
            }
            return decoded
        } catch {
            let fallbackJSON = synthesizeDeterministicPlan(for: fallbackQuery)
            return try JSONDecoder().decode(OrchestratedPlan.self, from: fallbackJSON.data(using: .utf8)!)
        }
    }

    private static func containsMalformedShellArtifact(_ plan: OrchestratedPlan) -> Bool {
        for step in plan.steps where step.action == "system_command" {
            let p = step.param.lowercased()
            if p.contains("&&") || p.contains("||") || p.contains("osascript") ||
               p.contains("tell application") || p.contains("open /") ||
               p.contains("json;") || p.contains("{") || p.contains("}") {
                return true
            }
        }
        return false
    }

    private func extractFirstBalancedJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var idx = start
        while idx < text.endIndex {
            let ch = text[idx]
            if escaped {
                escaped = false
            } else if ch == "\\" && inString {
                escaped = true
            } else if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...idx])
                    }
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }
    
    /// Synthesizes valid schema-conforming JSON for fast deterministic operations (zero token cost)
    public func synthesizeDeterministicPlan(for query: String) -> String {
        let lower = query.lowercased()
        
        // 1. Volume & Audio Control
        if !AgentToolParser.isConceptualAudioQuery(lower) &&
           (lower.contains("volume") || lower.contains("aawaz") || lower.contains("sound") || lower.contains("mute") || lower.contains("unmute")) {
            let param: String
            if lower.contains("unmute") {
                param = "unmute"
            } else if lower.contains("mute") || lower.contains("zero") || lower.contains("0%") || lower.contains("0 percent") || lower.contains("to 0") {
                param = "volume_level 0"
            } else if lower.contains("100") || lower.contains("full") || lower.contains("max") {
                param = "volume_level 100"
            } else if lower.contains("50") || lower.contains("half") {
                param = "volume_level 50"
            } else {
                let digits = lower.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                if let d = digits.first {
                    param = "volume_level \(d)"
                } else if lower.contains("down") || lower.contains("kam") || lower.contains("lower") || lower.contains("decrease") || lower.contains("quieter") {
                    param = "volume_down"
                } else if lower.contains("up") || lower.contains("tez") || lower.contains("raise") || lower.contains("increase") || lower.contains("louder") {
                    param = "volume_up"
                } else {
                    param = "volume_down"
                }
            }
            return """
            {
              "intent": "system_control",
              "target_application": "System",
              "steps": [
                { "step_number": 1, "action": "system_command", "param": "\(param)" }
              ]
            }
            """
        }
        
        // 2. Spotify Playback (require explicit music/song/spotify target AND whole-word play/chalao verb)
        let hasMusicWord = lower.contains("spotify") || lower.contains("song") || lower.contains("gana") || lower.contains("gaana") || lower.contains("music")
        let hasWholePlay = lower.range(of: "\\bplay\\b", options: .regularExpression) != nil
        if hasMusicWord && (hasWholePlay || lower.contains("chalao") || lower.contains("chala do") || lower.contains("bajao")) && !lower.contains("close") && !lower.contains("band") && !lower.contains("video") {
            let extracted = AgentToolParser.extractMediaQuery(from: query)
            let cmdParam = extracted != nil && !extracted!.isEmpty ? "play_music \(extracted!)" : "play_music"
            return """
            {
              "intent": "software_automation",
              "target_application": "Spotify",
              "steps": [
                { "step_number": 1, "action": "focus_application", "param": "Spotify" },
                { "step_number": 2, "action": "system_command", "param": "\(cmdParam)" }
              ]
            }
            """
        }
        
        if lower.contains("blender") {
            return """
            {
              "intent": "software_automation",
              "target_application": "Blender",
              "steps": [
                { "step_number": 1, "action": "focus_application", "param": "Blender" },
                { "step_number": 2, "action": "visual_locate_and_click", "param": "Sculpt Mode dropdown menu" },
                { "step_number": 3, "action": "keystroke", "param": "Shift+A" }
              ]
            }
            """
        }
        
        if lower.contains("spotify") && (lower.contains("band") || lower.contains("close")) {
            return """
            {
              "intent": "system_control",
              "target_application": "Spotify",
              "steps": [
                { "step_number": 1, "action": "focus_application", "param": "Spotify" },
                { "step_number": 2, "action": "system_command", "param": "close_application" }
              ]
            }
            """
        }
        
        let isGeneralQuestion = query.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") ||
                                lower.hasPrefix("what ") || lower.hasPrefix("who ") || lower.hasPrefix("why ") ||
                                lower.hasPrefix("how ") || lower.hasPrefix("explain ")

        if !isGeneralQuestion && lower.contains("video") && (lower.range(of: "\\bplay\\b", options: .regularExpression) != nil || lower.contains("chalao")) {
            return """
            {
              "intent": "system_control",
              "target_application": "Browser",
              "steps": [
                { "step_number": 1, "action": "focus_application", "param": "Safari" },
                { "step_number": 2, "action": "visual_locate_and_click", "param": "Video Play button" }
              ]
            }
            """
        }
        
        if !isGeneralQuestion && lower.contains("whatsapp") {
            return """
            {
              "intent": "software_automation",
              "target_application": "WhatsApp",
              "steps": [
                { "step_number": 1, "action": "focus_application", "param": "WhatsApp" }
              ]
            }
            """
        }
        
        if lower.contains("note") {
            return """
            {
              "intent": "software_automation",
              "target_application": "Apple Notes",
              "steps": [
                { "step_number": 1, "action": "focus_application", "param": "Notes" },
                { "step_number": 2, "action": "keystroke", "param": "Command+N" },
                { "step_number": 3, "action": "type_text", "param": "\(query.replacingOccurrences(of: "\"", with: "\\\""))" }
              ]
            }
            """
        }
        
        if lower.contains("search") || lower.contains("google") || lower.contains("weather") || lower.contains("news") {
            return """
            {
              "intent": "web_search",
              "target_application": null,
              "steps": [
                { "step_number": 1, "action": "web_search", "param": "\(query.replacingOccurrences(of: "\"", with: "\\\""))" }
              ]
            }
            """
        }
        
        return """
        {
          "intent": "conversation",
          "target_application": null,
          "steps": []
        }
        """
    }
}
