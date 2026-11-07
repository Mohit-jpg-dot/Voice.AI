import Foundation
import AppKit

public struct ExecutionStep: Codable, Sendable, Identifiable {
    public var id: String { "\(step_number)_\(action)_\(param)" }
    public let step_number: Int
    public let action: String // "focus_application" | "visual_locate_and_click" | "keystroke" | "type_text" | "system_command" | "web_search"
    public let param: String
    
    public init(step_number: Int, action: String, param: String) {
        self.step_number = step_number
        self.action = action
        self.param = param
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
       - "focus_application": param is application name (e.g., "Blender", "Spotify", "Safari", "Terminal", "VS Code")
       - "visual_locate_and_click": param is description of the UI element to locate visually on screen (e.g., "Sculpt Mode dropdown menu", "Play button", "New File icon")
       - "keystroke": param is key combination (e.g., "Shift+A", "Space", "Return", "Command+S", "Control+tilde")
       - "type_text": param is text string to insert
       - "system_command": param is system action (e.g., "volume_level 0", "volume_level 50", "volume_level 100", "volume_up", "volume_down", "mute", "unmute", "play_music <Song Name>", "play_music", "close_application", "screenshot", "lock", "sleep")
       - "web_search": param is web query string
    
    JSON SCHEMA:
    {
      "intent": "software_automation" | "system_control" | "web_search",
      "target_application": "AppName",
      "steps": [
        { "step_number": 1, "action": "focus_application", "param": "Blender" },
        { "step_number": 2, "action": "visual_locate_and_click", "param": "Sculpt Mode dropdown menu" },
        { "step_number": 3, "action": "keystroke", "param": "Shift+A" }
      ]
    }
    
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

    User: "Play the current video" or "video chalao"
    JSON:
    {"intent":"system_control","target_application":"Browser","steps":[{"step_number":1,"action":"focus_application","param":"Safari"},{"step_number":2,"action":"visual_locate_and_click","param":"Video Play button"}]}
    
    User: "weather in Delhi kya hai"
    JSON:
    {"intent":"web_search","target_application":null,"steps":[{"step_number":1,"action":"web_search","param":"weather in Delhi"}]}
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
        
        // Dynamic Context Compaction: Inject bounded sliding-window context
        let compactedContext = SlidingWindowContextCompactor.shared.getCompactedPromptContext()
        if !compactedContext.isEmpty {
            messages.append(LLMChatMessage(role: .system, content: "Context from previous interactions:\n\(compactedContext)"))
        }
        
        messages.append(LLMChatMessage(role: .user, content: cleaned))
        
        var rawResponse = ""
        
        // 1. Resolve active model through ModelRouter
        let chatModel = ModelRouter.shared.resolveChatModel()
        do {
            let res = try await chatModel.sendMessage(messages: messages, tools: nil, jsonMode: true)
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
        
        // Extract outermost { ... }
        if let firstBrace = jsonText.firstIndex(of: "{"),
           let lastBrace = jsonText.lastIndex(of: "}") {
            jsonText = String(jsonText[firstBrace...lastBrace])
        }
        
        guard let data = jsonText.data(using: .utf8) else {
            return try JSONDecoder().decode(OrchestratedPlan.self, from: synthesizeDeterministicPlan(for: fallbackQuery).data(using: .utf8)!)
        }
        
        do {
            return try JSONDecoder().decode(OrchestratedPlan.self, from: data)
        } catch {
            let fallbackJSON = synthesizeDeterministicPlan(for: fallbackQuery)
            return try JSONDecoder().decode(OrchestratedPlan.self, from: fallbackJSON.data(using: .utf8)!)
        }
    }
    
    /// Synthesizes valid schema-conforming JSON for fast deterministic operations (zero token cost)
    public func synthesizeDeterministicPlan(for query: String) -> String {
        let lower = query.lowercased()
        
        // 1. Volume & Audio Control
        if lower.contains("volume") || lower.contains("aawaz") || lower.contains("sound") || lower.contains("mute") || lower.contains("unmute") {
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
        
        // 2. Spotify Playback
        if (lower.contains("spotify") || lower.contains("play") || lower.contains("song") || lower.contains("gana") || lower.contains("gaana") || lower.contains("music")) && (lower.contains("play") || lower.contains("chalao") || lower.contains("chala do") || lower.contains("bajao")) && !lower.contains("close") && !lower.contains("band") && !lower.contains("video") {
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
        
        if lower.contains("video") || lower.contains("play") || lower.contains("chalao") {
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
        
        if lower.contains("whatsapp") {
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
}
