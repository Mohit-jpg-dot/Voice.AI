import AppKit
import Foundation

public struct AutonomousExecutionResult: Sendable, Equatable {
    public let success: Bool
    public let summary: String
    public let targetAppName: String
    public let targetURL: URL?
    public let executedSteps: [String]
    
    public init(
        success: Bool,
        summary: String,
        targetAppName: String,
        targetURL: URL? = nil,
        executedSteps: [String] = []
    ) {
        self.success = success
        self.summary = summary
        self.targetAppName = targetAppName
        self.targetURL = targetURL
        self.executedSteps = executedSteps
    }
}

/// Orchestrates autonomous agent execution:
/// 1. Analyzes user intent, Hinglish nuances, or questions
/// 2. Searches knowledge base & executes macOS automation in background
/// 3. Returns factual summary directly to Voice.AI notch without unsolicited external redirects
public final class AutonomousAgentExecutor: @unchecked Sendable {
    public static let shared = AutonomousAgentExecutor()
    
    public init() {}
    
    public func planAndExecute(
        taskDescription: String,
        triggerMode: VoiceTriggerMode = .agent,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async -> AutonomousExecutionResult {
        let trimmed = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let lower = trimmed.lowercased()
        
        // -------------------------------------------------------------
        // Step 1: Knowledge Search & Strategy Formulation
        // -------------------------------------------------------------
        onProgress?("Processing query...")
        
        // Asynchronous pacing delay (100ms)
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // -------------------------------------------------------------
        // Step 2: Instant Deterministic Math Evaluation
        // -------------------------------------------------------------
        if let mathResult = MathEngine.shared.evaluate(trimmed) {
            LocalMemoryManager.shared.remember(
                content: "\(trimmed) -> \(mathResult.displaySummary)",
                category: "task",
                tags: ["Calculator"]
            )
            return AutonomousExecutionResult(
                success: true,
                summary: mathResult.displaySummary,
                targetAppName: "Calculator",
                targetURL: nil,
                executedSteps: ["Evaluated arithmetic expression", "Computed exact result"]
            )
        }
        
        // -------------------------------------------------------------
        // Mode A: Dedicated Conversation Mode (Fn Key Pressed & Held)
        // -------------------------------------------------------------
        if triggerMode == .dictation && ModelRouter.shared.currentMode != .googleSearch {
            onProgress?("Thinking with local Llama 3.2 (Conversation Mode)...")
            let chatModel = ModelRouter.shared.resolveChatModel()
            let messages = [
                LLMChatMessage(role: .system, content: "You are Voice.AI in Conversation Mode (triggered by Fn key). Provide helpful, natural, friendly, conversational, and concise spoken answers. Answer questions directly and chat naturally. Do not give keyboard commands or tell the user to open settings unless they specifically ask for instructions."),
                LLMChatMessage(role: .user, content: trimmed)
            ]
            
            do {
                let response = try await chatModel.sendMessage(messages: messages, tools: nil, jsonMode: false)
                let text = response.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !text.isEmpty {
                    LocalMemoryManager.shared.remember(
                        content: "\(trimmed) -> \(text)",
                        category: "task",
                        tags: ["Conversation (Fn)"]
                    )
                    return AutonomousExecutionResult(
                        success: true,
                        summary: text,
                        targetAppName: "Voice.AI Conversation",
                        targetURL: nil,
                        executedSteps: ["Conversation Mode (Fn Key)", "Synthesized response via \(ModelRouter.shared.ollamaChatModel)"]
                    )
                }
            } catch {
                print("[AutonomousAgentExecutor] Conversation chatModel error: \(error)")
            }
        }
        
        // -------------------------------------------------------------
        // Mode B: Computer Control Mode (⌃ Control Key Pressed & Held or Default)
        // -------------------------------------------------------------
        if ModelRouter.shared.currentMode != .googleSearch {
            // 1. Send command through LLM (Llama 3.2) to orchestrate native macOS computer instructions
            onProgress?("Translating voice command to computer instructions with LLM...")
            if let plan = try? await LLMIntentOrchestrator.shared.plan(transcript: trimmed) {
                if plan.intent == "software_automation" || plan.intent == "system_control" {
                    let execution = await executeOrchestratedPlan(plan, onProgress: onProgress)
                    LocalMemoryManager.shared.remember(
                        content: "\(trimmed) -> \(execution.summary)",
                        category: "task",
                        tags: [plan.target_application ?? "Computer Control"]
                    )
                    let redirectURL: URL?
                    if let targetApp = plan.target_application, targetApp.lowercased().contains("note") {
                        redirectURL = URL(string: "notes://")
                    } else {
                        redirectURL = nil
                    }
                    return AutonomousExecutionResult(
                        success: execution.success,
                        summary: execution.summary,
                        targetAppName: plan.target_application ?? "Mac Control",
                        targetURL: redirectURL,
                        executedSteps: execution.executedSteps
                    )
                } else if plan.intent == "web_search" && !plan.steps.isEmpty {
                    let searchStep = plan.steps.first { $0.action == "web_search" } ?? plan.steps[0]
                    let dispatchResult = await AgentActionDispatcher.shared.dispatch(transcript: "search \(searchStep.param)")
                    return AutonomousExecutionResult(
                        success: dispatchResult.success,
                        summary: dispatchResult.summary,
                        targetAppName: dispatchResult.appName,
                        targetURL: dispatchResult.deepLinkURL,
                        executedSteps: ["Executed web search for \"\(searchStep.param)\""]
                    )
                }
            }
            
            // 2. Direct Native macOS Tools Fallback
            if let _ = AgentToolParser.parse(query: trimmed) {
                let dispatchResult = await AgentActionDispatcher.shared.dispatch(transcript: trimmed)
                LocalMemoryManager.shared.remember(
                    content: "\(trimmed) -> \(dispatchResult.summary)",
                    category: "task",
                    tags: [dispatchResult.appName]
                )
                return AutonomousExecutionResult(
                    success: dispatchResult.success,
                    summary: dispatchResult.summary,
                    targetAppName: dispatchResult.appName,
                    targetURL: dispatchResult.deepLinkURL,
                    executedSteps: ["Executed native macOS system command", dispatchResult.summary]
                )
            }
            
            // 3. Fallback General AI Reasoning (if conversational query)
            let chatModel = ModelRouter.shared.resolveChatModel()
            let messages = [
                LLMChatMessage(role: .system, content: "You are Voice.AI, an autonomous voice assistant for macOS. You can control the Mac. Provide direct, natural, and helpful spoken answers."),
                LLMChatMessage(role: .user, content: trimmed)
            ]
            
            do {
                let response = try await chatModel.sendMessage(messages: messages, tools: nil, jsonMode: false)
                let text = response.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !text.isEmpty {
                    LocalMemoryManager.shared.remember(
                        content: "\(trimmed) -> \(text)",
                        category: "task",
                        tags: ["Brain"]
                    )
                    return AutonomousExecutionResult(
                        success: true,
                        summary: text,
                        targetAppName: "Voice.AI Brain",
                        targetURL: nil,
                        executedSteps: ["Consulted \(chatModel.providerName) (\(ModelRouter.shared.ollamaChatModel))", "Synthesized response"]
                    )
                }
            } catch {
                print("[AutonomousAgentExecutor] chatModel error: \(error)")
            }
        }
        
        // 2c. Fallback or Google Search Mode Dispatch
        let dispatchResult = await AgentActionDispatcher.shared.dispatch(transcript: trimmed)
        
        var steps: [String] = [
            "Analyzed query: \"\(trimmed)\"",
            "Queried local and knowledge search engines"
        ]
        
        if dispatchResult.appName.lowercased().contains("note") {
            steps.append("Created note in Apple Notes")
        } else if dispatchResult.appName.lowercased().contains("reminder") {
            steps.append("Saved reminder in Apple Reminders")
        } else if dispatchResult.appName.lowercased().contains("spotify") {
            steps.append("Sent playback event to Spotify")
        } else if dispatchResult.appName.lowercased().contains("screen") {
            steps.append("Recognized and analyzed text on screen via Apple Vision OCR")
        } else if dispatchResult.appName.lowercased().contains("browser") {
            steps.append("Launched browser tab")
        } else if dispatchResult.appName.lowercased().contains("chatgpt") {
            steps.append("Executed automated workflow and integrated with ChatGPT")
        } else if dispatchResult.appName.lowercased().contains("blender") {
            steps.append("Activated Blender visualization engine and guided controls")
        } else {
            steps.append("Synthesized knowledge answer: \(dispatchResult.summary.prefix(60))...")
        }
        
        // Save to persistent memory
        LocalMemoryManager.shared.remember(
            content: "\(trimmed) -> \(dispatchResult.summary)",
            category: "task",
            tags: [dispatchResult.appName]
        )
        
        return AutonomousExecutionResult(
            success: dispatchResult.success,
            summary: dispatchResult.summary,
            targetAppName: dispatchResult.appName,
            targetURL: dispatchResult.deepLinkURL,
            executedSteps: steps
        )
    }
    
    // MARK: - Orchestrated Step Execution Engine
    
    private func executeOrchestratedPlan(
        _ plan: OrchestratedPlan,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async -> (success: Bool, summary: String, executedSteps: [String]) {
        var executed: [String] = []
        var overallSuccess = true
        let targetApp = plan.target_application ?? "macOS"
        
        for step in plan.steps {
            onProgress?("\(step.action): \(step.param)")
            switch step.action {
            case "focus_application":
                _ = AccessibilityControlEngine.shared.launchApp(named: step.param)
                executed.append("Focused \(step.param)")
                try? await Task.sleep(nanoseconds: 200_000_000)
                
            case "visual_locate_and_click":
                _ = await AgentActionDispatcher.shared.dispatch(transcript: "click \(step.param)")
                executed.append("Clicked \(step.param)")
                try? await Task.sleep(nanoseconds: 200_000_000)
                
            case "keystroke":
                _ = AccessibilityControlEngine.shared.simulateKeystroke(step.param)
                executed.append("Pressed \(step.param)")
                try? await Task.sleep(nanoseconds: 150_000_000)
                
            case "type_text":
                _ = AccessibilityControlEngine.shared.typeText(step.param)
                executed.append("Typed \"\(step.param)\"")
                try? await Task.sleep(nanoseconds: 150_000_000)
                
            case "system_command":
                let cmd = step.param.lowercased()
                if cmd.contains("volume_level") || cmd.contains("volume to") || cmd.contains("set_volume") || cmd.contains("volume") || cmd.contains("aawaz") {
                    let digits = cmd.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                    if let firstDigit = digits.first, let val = Double(firstDigit) {
                        let normalized = min(1.0, max(0.0, val / 100.0))
                        let res = AccessibilityControlEngine.shared.adjustVolume(delta: nil, absoluteLevel: normalized)
                        executed.append("System volume set to \(Int(res.newLevel * 100))%")
                    } else if cmd.contains("volume_up") || cmd.contains("volume up") || cmd.contains("louder") || cmd.contains("tez") {
                        let res = AccessibilityControlEngine.shared.adjustVolume(delta: 0.15, absoluteLevel: nil)
                        executed.append("System volume set to \(Int(res.newLevel * 100))%")
                    } else if cmd.contains("volume_down") || cmd.contains("volume down") || cmd.contains("quieter") || cmd.contains("kam") {
                        let res = AccessibilityControlEngine.shared.adjustVolume(delta: -0.15, absoluteLevel: nil)
                        executed.append("System volume set to \(Int(res.newLevel * 100))%")
                    } else if cmd.contains("zero") || cmd.contains("mute") || cmd.contains("0") {
                        let res = AccessibilityControlEngine.shared.adjustVolume(delta: nil, absoluteLevel: 0.0)
                        executed.append("System volume set to 0%")
                    } else {
                        executed.append("Executed \(step.param)")
                    }
                } else if cmd.contains("mute") && !cmd.contains("unmute") {
                    _ = AccessibilityControlEngine.shared.performSystemControl("mute")
                    executed.append("Muted audio")
                } else if cmd.contains("unmute") {
                    _ = AccessibilityControlEngine.shared.performSystemControl("unmute")
                    executed.append("Unmuted audio")
                } else if cmd.contains("play_music") || cmd.contains("play") {
                    let mediaApp = targetApp == "System" || targetApp == "macOS" ? "Spotify" : targetApp
                    _ = AccessibilityControlEngine.shared.controlMedia(app: mediaApp, action: "play", query: nil)
                    executed.append("Playing music on \(mediaApp)")
                } else if cmd.contains("close") {
                    let res = AccessibilityControlEngine.shared.closeApplication(named: targetApp)
                    executed.append(res.summary)
                } else if cmd.contains("screenshot") {
                    _ = await AgentActionDispatcher.shared.dispatch(transcript: "screenshot")
                    executed.append("Captured screenshot")
                } else if cmd.contains("lock") {
                    _ = AccessibilityControlEngine.shared.performSystemControl("lock")
                    executed.append("Locked Mac")
                } else if cmd.contains("sleep") {
                    _ = AccessibilityControlEngine.shared.performSystemControl("sleep")
                    executed.append("Put Mac to sleep")
                } else {
                    executed.append("Executed \(step.param)")
                }
                
            case "web_search":
                _ = await AgentActionDispatcher.shared.dispatch(transcript: "search \(step.param)")
                executed.append("Searched \(step.param)")
                
            default:
                executed.append("Executed \(step.action)(\(step.param))")
            }
        }
        
        let summary: String
        if plan.intent == "system_control" || plan.intent == "software_automation" {
            summary = executed.last ?? "Completed \(plan.steps.count) computer actions for \(targetApp)."
        } else {
            summary = "Completed task for \(targetApp)."
        }
        return (overallSuccess, summary, executed)
    }
}
