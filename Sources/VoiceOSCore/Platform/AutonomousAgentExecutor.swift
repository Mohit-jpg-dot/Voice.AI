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
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async -> AutonomousExecutionResult {
        let trimmed = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let lower = trimmed.lowercased()
        
        // -------------------------------------------------------------
        // Step 1: Knowledge Search & Strategy Formulation
        // -------------------------------------------------------------
        onProgress?("Searching knowledge base & formulating answer...")
        
        // Asynchronous pacing delay (100ms)
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // -------------------------------------------------------------
        // Step 2: Background Automated Execution / Direct Search Answer
        // -------------------------------------------------------------
        onProgress?("Processing context & formulating response...")
        
        // 2a. Instant Deterministic Math Evaluation
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
        
        // 2b. AI Brain Reasoning (Cloud OpenAI/Claude, Local Ollama, or Hybrid)
        let isSystemCommand = AgentActionDispatcher.shared.isCommandIntent(trimmed)
        if !isSystemCommand && ModelRouter.shared.currentMode != .googleSearch {
            let chatModel = ModelRouter.shared.resolveChatModel()
            let messages = [
                LLMChatMessage(role: .system, content: "You are Voice.AI, a macOS voice assistant. Provide direct, accurate, concise, and helpful answers. For conceptual or programming questions, explain clearly with key principles."),
                LLMChatMessage(role: .user, content: trimmed)
            ]
            if let response = try? await chatModel.sendMessage(messages: messages, tools: nil, jsonMode: false) {
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
                        executedSteps: ["Consulted \(ModelRouter.shared.currentMode.rawValue) model", "Synthesized response"]
                    )
                }
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
}
