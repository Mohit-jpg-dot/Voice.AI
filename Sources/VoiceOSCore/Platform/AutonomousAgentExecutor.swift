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
private final class StreamingTokenAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func append(_ chunk: String) -> String {
        lock.lock()
        buffer += chunk
        let snapshot = buffer
        lock.unlock()
        return snapshot
    }
}

public final class AutonomousAgentExecutor: @unchecked Sendable {
    public static let shared = AutonomousAgentExecutor()
    
    public init() {}
    
    /// Shared Vision + OCR reasoning helper (LLaVA -> Llama OCR fallback) for full-screen and region captures.
    public func analyzeScreenWithActiveModel(
        pngData: Data?,
        ocrText: String,
        appName: String,
        sourceLabel: String,
        question: String
    ) async -> (summary: String, usedProvider: String)? {
        guard ModelRouter.shared.currentMode != .googleSearch else { return nil }
        let cleanedOCR = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = """
        The user asked about their screen (\(appName) via \(sourceLabel)).
        Extracted OCR text:
        \"\"\"
        \(cleanedOCR.isEmpty ? "(No readable text detected)" : cleanedOCR)
        \"\"\"

        User question: \(question.isEmpty ? "Explain what is shown on the screen." : question)
        Answer clearly, concisely, and directly based on what is shown.
        """
        
        if let pngData = pngData,
           let image = NSImage(data: pngData),
           let visionModel = try? ModelRouter.shared.resolveVisionModel() {
            do {
                let visionResp = try await visionModel.analyzeImage(image: image, prompt: prompt, tools: nil)
                let reply = visionResp.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !reply.isEmpty {
                    return (reply, "\(visionModel.providerName) (\(visionModel.modelIdentifier))")
                }
            } catch {
                print("[AutonomousAgentExecutor] Vision analysis failed, falling back to chat+OCR: \(error)")
            }
        }
        
        let chatModel = ModelRouter.shared.resolveChatModel()
        let messages = [
            LLMChatMessage(role: .system, content: "You are Voice.AI. Answer questions accurately about the user's screen content."),
            LLMChatMessage(role: .user, content: prompt)
        ]
        if let resp = try? await chatModel.sendMessage(messages: messages, tools: nil, jsonMode: false) {
            let text = resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return (text, "\(chatModel.providerName) (\(chatModel.modelIdentifier))")
            }
        }
        return nil
    }

    private func generateChatResponse(
        model: ChatModel,
        systemPrompt: String,
        userPrompt: String,
        onPartialReply: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let messages = [
            LLMChatMessage(role: .system, content: systemPrompt),
            LLMChatMessage(role: .user, content: userPrompt)
        ]
        if let onPartialReply = onPartialReply {
            let accumulator = StreamingTokenAccumulator()
            let resp = try await model.streamMessage(messages: messages, tools: nil) { chunk in
                let current = accumulator.append(chunk)
                onPartialReply(current)
            }
            return resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let resp = try await model.sendMessage(messages: messages, tools: nil, jsonMode: false)
        return resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isLikelyPureConversation(raw: String, trimmed: String) -> Bool {
        let lower = trimmed.lowercased()
        let actionKeywords = [
            "open ", "launch ", "close ", "quit ", "click ", "type ", "note", "reminder",
            "screenshot", "volume", "mute", "spotify", "youtube", "tab", "terminal",
            "vscode", "vs code", "weather", "mausam", "temperature", "forecast", "news",
            "score", "stock", "kholo", "band", "chalao", "bhejo", "whatsapp", "slack",
            "discord", "notion", "draft", "reply", "inbox", "unread", "chatgpt",
            "claude", "gemini", "blender", "brightness", "mail", "email",
            "battery", "disk", "storage", "ram", "memory", "wifi", "wi-fi", "dark mode", "folder"
        ]
        if actionKeywords.contains(where: { lower.contains($0) }) {
            return false
        }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") {
            return true
        }
        let questionStarters = [
            "what ", "what's ", "who ", "who's ", "why ", "how ", "when ", "where ",
            "explain ", "define ", "compare ", "summarize ", "translate ",
            "write a ", "write an ", "write me ", "tell me ", "give me ", "can you explain"
        ]
        return questionStarters.contains(where: { lower.hasPrefix($0) })
    }

    private func isPlanGroundedInUserQuery(_ plan: OrchestratedPlan, query: String) -> Bool {
        let lower = query.lowercased()
        let focusedApps = [plan.target_application].compactMap { $0 } +
            plan.steps.filter { $0.action == "focus_application" }.map { $0.param }

        for rawApp in focusedApps {
            let app = rawApp.lowercased()
            if app.contains("safari") || app.contains("browser") || app.contains("chrome") {
                let webRequested = lower.contains("safari") || lower.contains("chrome") || lower.contains("browser") ||
                                   lower.contains("tab") || lower.contains("youtube") || lower.contains("website") ||
                                   lower.contains(".com") || lower.contains("http") || lower.contains("google") ||
                                   lower.hasPrefix("search ") || lower.contains("search karo") || lower.contains("dhoondo") ||
                                   (lower.contains("video") && (lower.range(of: "\\bplay\\b", options: .regularExpression) != nil || lower.contains("chalao")))
                if !webRequested { return false }
            } else if app.contains("spotify") || app == "music" {
                let musicRequested = lower.contains("spotify") || lower.contains("music") || lower.contains("song") ||
                                     lower.contains("gaana") || lower.contains("gana") || lower.contains("playlist") ||
                                     lower.contains("track") || lower.contains("arijit") || lower.contains("diljit") || lower.contains("shreya")
                if !musicRequested { return false }
            }
        }

        // Also ensure no play_music system command executes unless user asked for music
        for step in plan.steps where step.action == "system_command" {
            let p = step.param.lowercased()
            if p == "play" || p.hasPrefix("play_music") || p.hasPrefix("play ") {
                let mediaRequested = lower.contains("spotify") || lower.contains("music") || lower.contains("song") ||
                                     lower.contains("gaana") || lower.contains("gana") || lower.contains("playlist") ||
                                     lower.contains("video") || lower.contains("youtube") ||
                                     lower.range(of: "\\bplay\\b", options: .regularExpression) != nil ||
                                     lower.contains("chalao") || lower.contains("bajao")
                if !mediaRequested { return false }
            }
        }
        return true
    }

    public func planAndExecute(
        taskDescription: String,
        triggerMode: VoiceTriggerMode = .agent,
        screenCrop: ScreenCropResult? = nil,
        onPartialReply: (@Sendable (String) -> Void)? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async -> AutonomousExecutionResult {
        let trimmed = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        let stopCheck = trimmed.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if (stopCheck == "stop" || stopCheck == "stop agent" || stopCheck == "ruko" || stopCheck == "ruk jao") &&
           ComputerUseOperator.shared.isRunning {
            ComputerUseOperator.shared.stopActiveRun()
            return AutonomousExecutionResult(
                success: true,
                summary: "Stopped.",
                targetAppName: "Computer Use",
                targetURL: nil,
                executedSteps: ["Spoken stop keyword halted active computer-use loop"]
            )
        }

        if PersonaManager.shared.evaluateSafetyGuardrail(userInput: trimmed) {
            return AutonomousExecutionResult(
                success: true,
                summary: "Understood — switching to calm assistant mode.",
                targetAppName: "Persona",
                targetURL: nil,
                executedSteps: ["Adjusted tone via persona safety guardrail"]
            )
        }

        // -------------------------------------------------------------
        // Step -1: Remember / Forget / Recall Long-Term Memory Voice Commands
        // -------------------------------------------------------------
        if let memoryResult = await handleMemoryVoiceCommandIfPresent(trimmed) {
            return memoryResult
        }

        // -------------------------------------------------------------
        // Step -0.5: User & Built-in Routines / Macros ("good morning", "focus mode", "house party protocol")
        // -------------------------------------------------------------
        if let matchedRoutine = RoutineManager.shared.matchRoutine(for: trimmed) {
            onProgress?("Running routine: \(matchedRoutine.name)...")
            let routineRes = await RoutineManager.shared.runRoutine(matchedRoutine, onProgress: onProgress)
            await MemoryStore.shared.remember(content: "Ran routine '\(matchedRoutine.name)'", scope: .shortTerm, kind: .turn, tags: ["routine"])
            return routineRes
        }

        // -------------------------------------------------------------
        // Step -0.4: Voice-Controlled Automatic AI Model / Tier Switching
        // -------------------------------------------------------------
        if let modelSwitch = await ModelRouter.shared.switchModelByVoice(trimmed) {
            let lang = PersonaManager.shared.detectedLanguageCode(for: trimmed)
            let reply = PersonaManager.shared.formatResponse(modelSwitch.summary, language: lang)
            await MemoryStore.shared.remember(content: "Switched AI brain: \(modelSwitch.summary)", scope: .shortTerm, kind: .turn, tags: ["model_switch"])
            return AutonomousExecutionResult(
                success: true,
                summary: reply,
                targetAppName: "AI Brain",
                targetURL: nil,
                executedSteps: ["Switched to \(modelSwitch.mode.rawValue): \(modelSwitch.selectedModelId)"]
            )
        }
        
        // -------------------------------------------------------------
        // Step -0.25: Phase 2 Voice Commands (Proactive, Calendar/Mail/Messages, RAG, Smart Home, Health)
        // -------------------------------------------------------------
        if let phase2Result = await handlePhase2VoiceCommandIfPresent(trimmed) {
            await MemoryStore.shared.remember(content: "Q: \(trimmed) | A: \(phase2Result.summary.prefix(160))", scope: .shortTerm, kind: .turn, tags: [phase2Result.targetAppName])
            return phase2Result
        }

        // -------------------------------------------------------------
        // Step 0: Circle-to-Ask Visual (VLM + OCR) Region Analysis
        // -------------------------------------------------------------
        if let crop = screenCrop, ModelRouter.shared.currentMode != .googleSearch {
            onProgress?("Analyzing selected screen region...")
            let visionResult = await ScreenVisionService.shared.understandScreenQuestion(
                pngData: crop.capturedImagePNGData,
                ocrText: crop.extractedOCRText,
                appName: crop.sourceAppName ?? "Screen",
                question: trimmed
            )
            let formattedSummary: String
            if let btn = visionResult.targetButtonLabel, !visionResult.answer.localizedCaseInsensitiveContains(btn) {
                formattedSummary = "\(visionResult.answer) (Suggested control: \(btn)) [\(visionResult.privacyBadge)]"
            } else {
                formattedSummary = "\(visionResult.answer) [\(visionResult.privacyBadge)]"
            }
            LocalMemoryManager.shared.remember(content: "[Circle to Ask] \(trimmed) -> \(formattedSummary)", category: "task", tags: ["Circle to Ask"])
            return AutonomousExecutionResult(
                success: true,
                summary: PersonaManager.shared.formatResponse(baseResponse: formattedSummary),
                targetAppName: crop.sourceAppName ?? "Circle to Ask",
                targetURL: nil,
                executedSteps: ["Captured \(crop.toolUsed.rawValue) region", "Analyzed via \(visionResult.providerLabel)"]
            )
        }
        
        // -------------------------------------------------------------
        // Step 1: Instant Deterministic Math Evaluation
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
            onProgress?("Thinking...")
            let chatModel = ModelRouter.shared.resolveChatModel()
            let fnSystem = await buildPersonaAndMemorySystemPrompt(
                basePrompt: "You are Voice.AI in Conversation Mode (triggered by Fn key). Be helpful, natural, and concise.",
                forQuery: trimmed
            )
            do {
                let text = try await generateChatResponse(
                    model: chatModel,
                    systemPrompt: fnSystem,
                    userPrompt: trimmed,
                    onPartialReply: onPartialReply
                )
                if !text.isEmpty {
                    let styled = PersonaManager.shared.formatResponse(text, language: PersonaManager.shared.detectedLanguageCode(for: trimmed))
                    await MemoryStore.shared.remember(content: "Q: \(trimmed) | A: \(styled.prefix(180))", scope: .shortTerm, kind: .turn, tags: ["fn_conversation"])
                    LocalMemoryManager.shared.remember(
                        content: "\(trimmed) -> \(styled)",
                        category: "task",
                        tags: ["Conversation (Fn)"]
                    )
                    return AutonomousExecutionResult(
                        success: true,
                        summary: styled,
                        targetAppName: "Voice.AI Conversation",
                        targetURL: nil,
                        executedSteps: ["Conversation Mode (Fn Key)", "Synthesized response via \(chatModel.providerName) (\(chatModel.modelIdentifier))"]
                    )
                }
            } catch {
                print("[AutonomousAgentExecutor] Conversation chatModel error: \(error)")
            }
        }
        
        // -------------------------------------------------------------
        // Mode B: Fast Native Tool -> Pure Q&A Stream -> Orchestrated Plan
        // -------------------------------------------------------------
        if ModelRouter.shared.currentMode != .googleSearch {
            // 1. Direct Native macOS Tools (<1ms, zero LLM round-trip for explicit commands)
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

            // 1b. Direct local Apple Notes / Reminders / Finder tasks (reliable without risking LLM app hallucination)
            let qLower = trimmed.lowercased()
            let isDirectLocalUtilityTask =
                ((qLower.contains("note") || qLower.contains("notes")) && (qLower.contains("create") || qLower.contains("add") || qLower.contains("write") || qLower.contains("take") || qLower.contains("likh") || qLower.contains("save"))) ||
                qLower.contains("remind me to ") || qLower.hasPrefix("reminder ") ||
                qLower.contains("open downloads") || qLower.contains("show downloads") ||
                qLower.contains("open documents") || qLower.contains("show documents")
            if isDirectLocalUtilityTask {
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
                    executedSteps: ["Executed native macOS task", dispatchResult.summary]
                )
            }

            // 1c. Open-Ended Screen / Vision Computer-Use Operator Loop (Control key Agent Mode)
            if triggerMode == .agent && Self.isLikelyOpenEndedComputerUseGoal(trimmed) {
                onProgress?("Starting visual computer-use loop...")
                return await ComputerUseOperator.shared.runAgentTask(
                    goal: trimmed,
                    maxSteps: 15,
                    onProgress: onProgress
                )
            }

            // 2. Skip slow JSON classifier on clear questions/chat/writing prompts and stream directly
            if !isLikelyPureConversation(raw: taskDescription, trimmed: trimmed) {
                onProgress?("Planning task...")
                if let plan = try? await LLMIntentOrchestrator.shared.plan(transcript: trimmed),
                   isPlanGroundedInUserQuery(plan, query: trimmed) {
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
                        let lower = trimmed.lowercased()
                        let isExplicitBrowserSearch = lower.hasPrefix("search ") || lower.hasPrefix("google ") ||
                                                      lower.contains("open tab") || lower.contains("in browser") ||
                                                      lower.contains("in safari") || lower.contains("in chrome")
                        let isLiveRealtimeInfo = lower.contains("weather") || lower.contains("mausam") ||
                                                 lower.contains("temperature") || lower.contains("forecast") ||
                                                 lower.contains("news") || lower.contains("stock price") ||
                                                 lower.contains("live score")
                        if isExplicitBrowserSearch {
                            let dispatchResult = await AgentActionDispatcher.shared.dispatch(transcript: "search \(searchStep.param)")
                            return AutonomousExecutionResult(
                                success: dispatchResult.success,
                                summary: dispatchResult.summary,
                                targetAppName: dispatchResult.appName,
                                targetURL: dispatchResult.deepLinkURL,
                                executedSteps: ["Executed web search for \"\(searchStep.param)\""]
                            )
                        } else if isLiveRealtimeInfo {
                            let card = await GoogleSearchEngine.shared.answerQuestion(query: searchStep.param)
                            if !card.answerText.contains("is a recognized subject with detailed encyclopedic documentation") {
                                return AutonomousExecutionResult(
                                    success: true,
                                    summary: card.answerText,
                                    targetAppName: card.sourceTitle,
                                    targetURL: card.sourceURL,
                                    executedSteps: ["Fetched live info for \"\(searchStep.param)\"", card.methodLabel]
                                )
                            }
                        }
                    }
                }
            }
            
            // 3. Direct General AI Reasoning with live token streaming + Persona & Long-Term Memory Recall
            onProgress?("Thinking...")
            let chatModel = ModelRouter.shared.resolveChatModel()
            let chatSystem = await buildPersonaAndMemorySystemPrompt(
                basePrompt: "You are Voice.AI, a fast, capable personal assistant for macOS.",
                forQuery: trimmed
            )
            do {
                let text = try await generateChatResponse(
                    model: chatModel,
                    systemPrompt: chatSystem,
                    userPrompt: trimmed,
                    onPartialReply: onPartialReply
                )
                if !text.isEmpty {
                    let styled = PersonaManager.shared.formatResponse(text, language: PersonaManager.shared.detectedLanguageCode(for: trimmed))
                    await MemoryStore.shared.remember(content: "Q: \(trimmed) | A: \(styled.prefix(180))", scope: .shortTerm, kind: .turn, tags: ["brain"])
                    LocalMemoryManager.shared.remember(
                        content: "\(trimmed) -> \(styled)",
                        category: "task",
                        tags: ["Brain"]
                    )
                    return AutonomousExecutionResult(
                        success: true,
                        summary: styled,
                        targetAppName: "Voice.AI Brain",
                        targetURL: nil,
                        executedSteps: ["Consulted \(chatModel.providerName) (\(chatModel.modelIdentifier))", "Recalled memory & applied persona"]
                    )
                }
            } catch {
                print("[AutonomousAgentExecutor] chatModel error: \(error)")
                if ModelRouter.shared.currentMode == .local {
                    let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    return AutonomousExecutionResult(
                        success: false,
                        summary: msg,
                        targetAppName: "Ollama Local",
                        targetURL: nil,
                        executedSteps: ["Local LLM error: \(msg)"]
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
    
    private func executeSafeShellCommand(_ rawCommand: String) -> (success: Bool, output: String) {
        let lower = rawCommand.lowercased()
        let dangerousPatterns = [
            "rm -rf", "rm -fr", "sudo ", "mkfs", "dd if=", "shutdown", "reboot",
            "halt", ":(){", "chmod -r 777 /", "diskutil erase", "> /dev/"
        ]
        if dangerousPatterns.contains(where: { lower.contains($0) }) {
            return (false, "Blocked for safety: destructive shell command '\(rawCommand)' requires manual Terminal confirmation.")
        }
        let proc = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", rawCommand]
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
            let deadline = DispatchTime.now() + 8.0
            let sema = DispatchSemaphore(value: 0)
            proc.terminationHandler = { _ in sema.signal() }
            if sema.wait(timeout: deadline) == .timedOut {
                proc.terminate()
                return (false, "Command timed out after 8s.")
            }
            let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if proc.terminationStatus == 0 {
                return (true, out.isEmpty ? "Done." : String(out.prefix(600)))
            } else {
                let msg = err.isEmpty ? out : err
                return (false, msg.isEmpty ? "Command failed with exit code \(proc.terminationStatus)." : String(msg.prefix(400)))
            }
        } catch {
            return (false, "Failed to run command: \(error.localizedDescription)")
        }
    }

    // MARK: - Orchestrated Step Execution Engine
    
    private func executeOrchestratedPlan(
        _ plan: OrchestratedPlan,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async -> (success: Bool, summary: String, executedSteps: [String]) {
        var executed: [String] = []
        var overallSuccess = true
        let targetApp = plan.target_application ?? "macOS"
        
        stepLoop: for step in plan.steps {
            onProgress?("\(step.action): \(step.param)")
            switch step.action {
            case "focus_application":
                _ = AccessibilityControlEngine.shared.launchApp(named: step.param)
                executed.append("Focused \(step.param)")
                try? await Task.sleep(nanoseconds: 200_000_000)
                
            case "visual_locate_and_click":
                let clickRes = await AccessibilityControlEngine.shared.clickElement(
                    matching: step.param,
                    frontmostAppName: targetApp == "macOS" ? (NSWorkspace.shared.frontmostApplication?.localizedName ?? "Active Application") : targetApp
                )
                executed.append(clickRes.summary)
                if !clickRes.success {
                    overallSuccess = false
                    break stepLoop
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
                
            case "keystroke":
                _ = AccessibilityControlEngine.shared.simulateKeystroke(step.param)
                executed.append("Pressed \(step.param)")
                try? await Task.sleep(nanoseconds: 150_000_000)
                
            case "type_text":
                _ = AccessibilityControlEngine.shared.typeText(step.param)
                executed.append("Typed \"\(step.param)\"")
                try? await Task.sleep(nanoseconds: 150_000_000)
                
            case "run_shell":
                let shellRes = executeSafeShellCommand(step.param)
                executed.append(shellRes.output)
                if !shellRes.success {
                    overallSuccess = false
                    break stepLoop
                }
                
            case "system_command":
                let cmd = step.param.lowercased()
                if cmd.contains("dark_mode_on") {
                    _ = AccessibilityControlEngine.shared.performSystemControl("dark_mode_on")
                    executed.append("Enabled macOS Dark Mode.")
                } else if cmd.contains("dark_mode_off") {
                    _ = AccessibilityControlEngine.shared.performSystemControl("dark_mode_off")
                    executed.append("Disabled macOS Dark Mode.")
                } else if cmd.contains("dark_mode") {
                    _ = AccessibilityControlEngine.shared.performSystemControl("dark_mode_toggle")
                    executed.append("Toggled macOS Dark Mode.")
                } else if cmd.contains("brightness_up") {
                    let res = AccessibilityControlEngine.shared.adjustDisplayBrightness(delta: 0.15, absoluteLevel: nil)
                    executed.append("Increased display brightness to \(Int(res.level * 100))%.")
                } else if cmd.contains("brightness_down") {
                    let res = AccessibilityControlEngine.shared.adjustDisplayBrightness(delta: -0.15, absoluteLevel: nil)
                    executed.append("Decreased display brightness to \(Int(res.level * 100))%.")
                } else if cmd.contains("battery") {
                    let res = executeSafeShellCommand("pmset -g batt | tail -n 1")
                    executed.append(res.output)
                    overallSuccess = res.success
                } else if cmd.contains("disk") {
                    let res = executeSafeShellCommand("df -h / | awk 'NR==2 {print \"Disk free: \"$4\" of \"$2\" (\"$5\" used)\"}'")
                    executed.append(res.output)
                    overallSuccess = res.success
                } else if cmd.contains("ram") || cmd.contains("memory") {
                    let res = executeSafeShellCommand("top -l 1 -n 0 | grep -E 'PhysMem'")
                    executed.append(res.output)
                    overallSuccess = res.success
                } else if cmd.contains("volume_level") || cmd.contains("volume to") || cmd.contains("set_volume") || cmd.contains("volume") || cmd.contains("aawaz") {
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
                } else if cmd == "play" || cmd.hasPrefix("play_music") || cmd.hasPrefix("play ") {
                    let mediaApp = targetApp == "System" || targetApp == "macOS" ? "Spotify" : targetApp
                    let songQuery: String?
                    if cmd.hasPrefix("play_music ") {
                        songQuery = String(step.param.dropFirst("play_music ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if cmd.hasPrefix("play ") {
                        songQuery = String(step.param.dropFirst("play ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        songQuery = AgentToolParser.extractMediaQuery(from: step.param)
                    }
                    _ = AccessibilityControlEngine.shared.controlMedia(app: mediaApp, action: "play", query: songQuery)
                    if let sq = songQuery, !sq.isEmpty {
                        executed.append("Playing \"\(sq)\" on \(mediaApp)")
                    } else {
                        executed.append("Playing music on \(mediaApp)")
                    }
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
                    overallSuccess = false
                    executed.append("Unsupported system action: \(step.param)")
                }
                
            case "web_search":
                _ = await AgentActionDispatcher.shared.dispatch(transcript: "search \(step.param)")
                executed.append("Searched \(step.param)")

            case "app_integration":
                if let data = step.param.data(using: .utf8),
                   let rawDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let app = (rawDict["app"] as? String) ?? targetApp
                    let operation = (rawDict["operation"] as? String) ?? "open"
                    var params: [String: String] = ["operation": operation]
                    for (k, v) in rawDict {
                        if let str = v as? String { params[k] = str }
                    }

                    if let toolName = ToolRegistry.registryToolName(forApp: app, operation: operation) {
                        let toolResult = await ToolRegistry.shared.invoke(
                            name: toolName,
                            arguments: params,
                            bypassApproval: false,
                            customApprovalHandler: nil
                        )
                        executed.append(toolResult.summary)
                        if !toolResult.success {
                            overallSuccess = false
                            break stepLoop
                        }
                    } else {
                        let res = await AppIntegrationEngine.shared.execute(app: app, operation: operation, params: params)
                        executed.append(res.summary)
                        if !res.success {
                            overallSuccess = false
                            break stepLoop
                        }
                    }
                } else {
                    overallSuccess = false
                    executed.append("Invalid app integration payload: \(step.param)")
                }
                
            default:
                overallSuccess = false
                executed.append("Unsupported action: \(step.action)(\(step.param))")
            }
            if !overallSuccess { break }
        }
        
        let summary: String
        if plan.intent == "system_control" || plan.intent == "software_automation" {
            summary = executed.last ?? (overallSuccess ? "Completed \(plan.steps.count) computer actions for \(targetApp)." : "Could not complete task for \(targetApp).")
        } else {
            summary = "Completed task for \(targetApp)."
        }
        return (overallSuccess, summary, executed)
    }

    // MARK: - Proactive Local LLM Brain Suggestions

    public func generateBrainSuggestions(
        forQuery query: String,
        reply: String,
        screenContext: String? = nil
    ) async -> [BrainSuggestion] {
        guard ModelRouter.shared.currentMode != .googleSearch else { return [] }
        let chatModel = ModelRouter.shared.resolveChatModel()
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Desktop"

        let prompt = """
        You are Voice.AI's thinking Brain running locally. Based on this interaction, suggest 3 short, smart, practical next things the user might want to ask or do on their Mac.
        Frontmost App: \(frontApp)
        User asked: "\(String(query.prefix(240)))"
        Assistant replied: "\(String(reply.prefix(350)))"
        \(screenContext.map { "Screen context: \(String($0.prefix(300)))" } ?? "")

        Return ONLY valid JSON:
        {"suggestions":[{"title":"2-4 words","prompt":"clear actionable prompt or follow-up question","is_action":false}]}
        """

        let messages = [
            LLMChatMessage(role: .system, content: "Return ONLY a JSON object matching {\"suggestions\":[{\"title\":...,\"prompt\":...,\"is_action\":true|false}]} with 3 concise suggestions."),
            LLMChatMessage(role: .user, content: prompt)
        ]

        do {
            let res = try await withThrowingTaskGroup(of: ChatResponse.self) { group in
                group.addTask {
                    try await chatModel.sendMessage(messages: messages, tools: nil, jsonMode: true)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 8_000_000_000)
                    throw CancellationError()
                }
                guard let first = try await group.next() else { throw CancellationError() }
                group.cancelAll()
                return first
            }
            return parseSuggestionsJSON(res.text)
        } catch {
            return []
        }
    }

    public func thinkAndSuggestForCurrentContext() async -> (insight: String, suggestions: [BrainSuggestion]) {
        guard ModelRouter.shared.currentMode != .googleSearch else {
            return ("Switch from Google Search Only mode to Local or Hybrid Mode to let the Ollama LLM Brain analyze context and think of suggestions.", [])
        }
        let analysis = await ScreenVisionService.shared.captureAndAnalyzeScreen()
        let frontApp = analysis.activeAppTitle ?? (NSWorkspace.shared.frontmostApplication?.localizedName ?? "Desktop")
        let chatModel = ModelRouter.shared.resolveChatModel()

        let prompt = """
        Look at what the user is currently working on and think like a proactive AI co-pilot:
        Frontmost App: \(frontApp)
        Visible Screen Text (OCR):
        \"\"\"
        \(String(analysis.fullText.prefix(900)))
        \"\"\"

        Return ONLY valid JSON:
        {
          "insight": "1-2 helpful, specific sentences noticing what they are working on and your best recommendation",
          "suggestions": [
            {"title": "2-4 word label", "prompt": "exact prompt or task for Voice.AI to execute", "is_action": true},
            {"title": "2-4 word label", "prompt": "exact follow-up question", "is_action": false},
            {"title": "2-4 word label", "prompt": "exact follow-up prompt or task", "is_action": true}
          ]
        }
        """

        let messages = [
            LLMChatMessage(role: .system, content: "You are Voice.AI's local LLM Brain. Think thoughtfully and return ONLY valid JSON."),
            LLMChatMessage(role: .user, content: prompt)
        ]

        do {
            let res = try await chatModel.sendMessage(messages: messages, tools: nil, jsonMode: true)
            let cleaned = extractJSONObjectString(res.text)
            if let data = cleaned.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let insight = (obj["insight"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Analyzed your active context in \(frontApp)."
                let parsed = parseSuggestionsArray(obj["suggestions"] as? [[String: Any]] ?? [])
                return (insight, parsed)
            }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return ("Local LLM Brain unavailable: \(msg)", [])
        }
        return ("Working in \(frontApp). Ask me anything or tell me a task to automate.", [])
    }

    private func extractJSONObjectString(_ raw: String) -> String {
        var jsonText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = jsonText.range(of: "```json") { jsonText = String(jsonText[start.upperBound...]) }
        else if let start = jsonText.range(of: "```") { jsonText = String(jsonText[start.upperBound...]) }
        if let end = jsonText.range(of: "```", options: .backwards) { jsonText = String(jsonText[..<end.lowerBound]) }
        if let first = jsonText.firstIndex(of: "{"), let last = jsonText.lastIndex(of: "}") {
            return String(jsonText[first...last])
        }
        return jsonText
    }

    private func parseSuggestionsJSON(_ raw: String) -> [BrainSuggestion] {
        let jsonText = extractJSONObjectString(raw)
        guard let data = jsonText.data(using: .utf8) else { return [] }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = dict["suggestions"] as? [[String: Any]] {
            return parseSuggestionsArray(arr)
        }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return parseSuggestionsArray(arr)
        }
        return []
    }

    private func parseSuggestionsArray(_ arr: [[String: Any]]) -> [BrainSuggestion] {
        return arr.prefix(3).compactMap { item in
            guard let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let prompt = (item["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty, !prompt.isEmpty else { return nil }
            let isAction = item["is_action"] as? Bool ?? false
            return BrainSuggestion(title: title, prompt: prompt, isAction: isAction)
        }
    }

    // MARK: - Phase 1 Long-Term Memory Voice Commands & Persona Prompt Context

    private func handleMemoryVoiceCommandIfPresent(_ trimmed: String) async -> AutonomousExecutionResult? {
        let lower = trimmed.lowercased()

        // 1. "Remember this ..." / "Remember that ..." / "Yaad rakhna ..."
        let rememberPrefixes = [
            "remember this:", "remember this ", "remember that ", "remember ",
            "yaad rakhna ki ", "yaad rakhna ", "ise yaad rakho ", "yaad rakho "
        ]
        for prefix in rememberPrefixes {
            if lower.hasPrefix(prefix) {
                let fact = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !fact.isEmpty else { break }
                let kind: MemoryFactKind
                let fLower = fact.lowercased()
                if fLower.contains("prefer") || fLower.contains("favorite") || fLower.contains("pasand") {
                    kind = .preference
                } else if fLower.contains("project") || fLower.contains("working on") || fLower.contains("repo") {
                    kind = .project
                } else if fLower.contains("friend") || fLower.contains("boss") || fLower.contains("manager") || fLower.contains("email") {
                    kind = .person
                } else {
                    kind = .fact
                }
                let saved = await MemoryStore.shared.remember(content: fact, scope: .longTerm, kind: kind, tags: ["voice"])
                let reply = PersonaManager.shared.formatResponse(
                    "Remembered: \"\(saved.content)\"",
                    language: PersonaManager.shared.detectedLanguageCode(for: trimmed)
                )
                return AutonomousExecutionResult(
                    success: true,
                    summary: reply,
                    targetAppName: "Memory",
                    targetURL: nil,
                    executedSteps: ["Stored encrypted \(kind.rawValue) in MemoryStore"]
                )
            }
        }

        // 2. "Forget this ..." / "Forget about ..." / "Bhool jao ..."
        let forgetPrefixes = [
            "forget about ", "forget that ", "forget this ", "forget ",
            "bhool jao ", "ise bhool jao ", "yaad mat rakhna "
        ]
        for prefix in forgetPrefixes {
            if lower.hasPrefix(prefix) {
                let target = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                let removed: Int
                if target.isEmpty || target.lowercased() == "it" || target.lowercased() == "this" || target.lowercased() == "that" {
                    if let latest = MemoryStore.shared.allItems(scope: .longTerm).first {
                        let ok = await MemoryStore.shared.forget(id: latest.id)
                        removed = ok ? 1 : 0
                    } else {
                        removed = 0
                    }
                } else {
                    removed = await MemoryStore.shared.forget(matching: target)
                }
                let msg = removed > 0
                    ? "Removed \(removed) matching item(s) from your memory."
                    : "No saved memory matched '\(target)'."
                return AutonomousExecutionResult(
                    success: true,
                    summary: PersonaManager.shared.formatResponse(msg, language: PersonaManager.shared.detectedLanguageCode(for: trimmed)),
                    targetAppName: "Memory",
                    targetURL: nil,
                    executedSteps: ["Updated encrypted MemoryStore (removed \(removed))"]
                )
            }
        }

        // 3. "What do you remember about ..." / "Show my memories ..."
        if lower.hasPrefix("what do you remember") || lower.contains("kya yaad hai") || lower == "my memories" || lower == "list my memories" {
            let query = trimmed
                .replacingOccurrences(of: "what do you remember about", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "what do you remember", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let items: [StructuredMemoryItem]
            if query.isEmpty {
                items = Array(MemoryStore.shared.allItems(scope: .longTerm).prefix(5))
            } else {
                items = await MemoryStore.shared.searchSemantic(query: query, scope: .longTerm, limit: 5).map { $0.item }
            }
            let summary = items.isEmpty
                ? "I don't have any saved long-term memories matching that yet."
                : "Here is what I remember:\n" + items.map { "• [\($0.kind.rawValue)] \($0.content)" }.joined(separator: "\n")
            return AutonomousExecutionResult(
                success: true,
                summary: summary,
                targetAppName: "Memory",
                targetURL: nil,
                executedSteps: ["Queried encrypted MemoryStore (\(items.count) result(s))"]
            )
        }

        return nil
    }

    private func buildPersonaAndMemorySystemPrompt(basePrompt: String, forQuery query: String) async -> String {
        let personaDirectives = PersonaManager.shared.systemPromptDirectives(forUserQuery: query)
        let profile = MemoryStore.shared.userProfile()
        let hits = await MemoryStore.shared.searchSemantic(query: query, scope: .longTerm, limit: 3)

        var parts = [basePrompt, personaDirectives]
        if !profile.displayName.isEmpty && profile.displayName != "User" {
            parts.append("User display name: \(profile.displayName).")
        }
        if !hits.isEmpty {
            let bullets = hits.map { "- \($0.item.content)" }.joined(separator: "\n")
            parts.append("Relevant recalled user memory:\n\(bullets)")
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Phase 2 Proactive, Calendar, RAG, Smart Home & Health Routing

    private func handlePhase2VoiceCommandIfPresent(_ trimmed: String) async -> AutonomousExecutionResult? {
        let lower = HinglishTransliterator.normalize(trimmed)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lang = PersonaManager.shared.detectedLanguageCode(for: trimmed)

        // 1. Proactive Alerts Status
        if lower.contains("proactive alert") || lower.contains("system alert") || lower.contains("any alert") || lower.contains("kya alert") {
            let res = await ToolRegistry.shared.invoke(name: "proactive_alerts_status", arguments: [:])
            return AutonomousExecutionResult(
                success: res.success,
                summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                targetAppName: "Proactive Engine",
                targetURL: nil,
                executedSteps: ["Checked EventBus proactive alerts"]
            )
        }

        // 2. Smart Home (Locks/Security -> CONSEQUENTIAL, Lights/Thermostat/Scenes -> REVERSIBLE)
        if lower.contains("smart home") || lower.contains("home status") ||
           lower.contains("door lock") || lower.contains("front door") || lower.contains("security alarm") ||
           lower.contains("darwaza") || lower.contains("thermostat") ||
           lower.contains("living room light") || lower.contains("bedroom light") ||
           lower.contains("movie night scene") || lower.contains("kamre ki light") {
            if lower.contains("status") || lower.contains("check") || lower.contains("dikhao") {
                let res = await ToolRegistry.shared.invoke(name: "smarthome_status", arguments: [:])
                return AutonomousExecutionResult(
                    success: res.success,
                    summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                    targetAppName: "Smart Home",
                    targetURL: nil,
                    executedSteps: ["Queried smart home device status"]
                )
            }

            let isSecurity = lower.contains("lock") || lower.contains("door") || lower.contains("darwaza") || lower.contains("alarm") || lower.contains("security")
            let deviceQuery: String
            if lower.contains("front") || lower.contains("door") || lower.contains("lock") || lower.contains("darwaza") {
                deviceQuery = "Front Door Lock"
            } else if lower.contains("alarm") || lower.contains("security") {
                deviceQuery = "Home Security Alarm"
            } else if lower.contains("thermostat") {
                deviceQuery = "Main Thermostat"
            } else if lower.contains("bedroom") {
                deviceQuery = "Bedroom Lights"
            } else if lower.contains("movie") || lower.contains("scene") {
                deviceQuery = "Movie Night Scene"
            } else {
                deviceQuery = "Living Room Lights"
            }

            var action = "on"
            var value = ""
            if lower.contains("unlock") || (isSecurity && lower.contains("kholo")) {
                action = "unlock"
            } else if isSecurity && (lower.contains("disarm") || lower.contains("band") || lower.contains("off")) {
                action = "disarm"
            } else if isSecurity && lower.contains("arm") {
                action = "arm"
            } else if isSecurity {
                action = "lock"
            } else if lower.contains("thermostat") {
                action = "set_temperature"
                let digits = lower.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                value = digits.first ?? "22"
            } else if lower.contains("scene") {
                action = "activate"
            } else if lower.contains("off") || lower.contains("band") || lower.contains("bujhao") {
                action = "off"
            }

            let toolName = isSecurity ? "smarthome_control_security" : "smarthome_control_comfort"
            var args: [String: String] = ["device": deviceQuery, "action": action]
            if !value.isEmpty { args["value"] = value }
            let res = await ToolRegistry.shared.invoke(name: toolName, arguments: args)
            return AutonomousExecutionResult(
                success: res.success,
                summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                targetAppName: isSecurity ? "Smart Home Security" : "Smart Home",
                targetURL: nil,
                executedSteps: ["Smart Home [\(isSecurity ? "CONSEQUENTIAL" : "REVERSIBLE")]: \(deviceQuery) -> \(action)"]
            )
        }

        // 3. Calendar Summarize / Create Event
        if lower.contains("calendar") || lower.contains("meeting schedule") || lower.contains("aaj ki meeting") {
            if lower.contains("schedule ") || lower.contains("create ") || lower.contains("add ") {
                let title = trimmed
                    .replacingOccurrences(of: "schedule calendar event", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "create calendar event", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "add to calendar", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let res = await ToolRegistry.shared.invoke(name: "calendar_create_event", arguments: ["title": title.isEmpty ? "New Event" : title])
                return AutonomousExecutionResult(
                    success: res.success,
                    summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                    targetAppName: "Apple Calendar",
                    targetURL: nil,
                    executedSteps: ["Calendar [REVERSIBLE]: created event"]
                )
            }
            let range = lower.contains("week") || lower.contains("hafte") ? "week" : "today"
            let res = await ToolRegistry.shared.invoke(name: "calendar_summarize", arguments: ["range": range])
            return AutonomousExecutionResult(
                success: res.success,
                summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                targetAppName: "Apple Calendar",
                targetURL: nil,
                executedSteps: ["Calendar [READ_ONLY]: summarized \(range) events"]
            )
        }

        // 4. Email Summary & Messages Read/Draft/Send
        if lower.contains("summarize") && (lower.contains("mail") || lower.contains("email") || lower.contains("inbox")) {
            let res = await ToolRegistry.shared.invoke(name: "mail_summarize", arguments: [:])
            return AutonomousExecutionResult(
                success: res.success,
                summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                targetAppName: "Apple Mail",
                targetURL: nil,
                executedSteps: ["Mail [READ_ONLY]: summarized recent inbox"]
            )
        }

        if lower.contains("read messages") || lower.contains("summarize messages") || lower.contains("messages padho") || lower.contains("check imessage") {
            let res = await ToolRegistry.shared.invoke(name: "messages_read", arguments: [:])
            return AutonomousExecutionResult(
                success: res.success,
                summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                targetAppName: "Messages",
                targetURL: nil,
                executedSteps: ["Messages [READ_ONLY]: read threads"]
            )
        }

        // 5. Local File & Knowledge Search (On-Device RAG)
        let ragPrefixes = ["search local files for ", "search files for ", "local search ", "search knowledge ", "rag search ", "file dhoondo "]
        for prefix in ragPrefixes {
            if lower.hasPrefix(prefix) {
                let query = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                let res = await ToolRegistry.shared.invoke(name: "rag_search_files", arguments: ["query": query])
                return AutonomousExecutionResult(
                    success: res.success,
                    summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                    targetAppName: "Local Knowledge",
                    targetURL: nil,
                    executedSteps: ["RAG [READ_ONLY]: searched on-device indexed folders"]
                )
            }
        }

        // 6. Opt-In Apple Health Summary & Wellness Reminders
        if lower.contains("health summary") || lower.contains("check my health") || lower.contains("meri health") || lower.contains("fitness summary") || lower.contains("resting heart rate") {
            let res = await ToolRegistry.shared.invoke(name: "health_summary", arguments: [:])
            return AutonomousExecutionResult(
                success: res.success,
                summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                targetAppName: "Apple Health",
                targetURL: nil,
                executedSteps: ["Apple Health [READ_ONLY]: computed opt-in on-device digest"]
            )
        }
        if lower.hasPrefix("add health reminder ") || lower.hasPrefix("remind me to ") && (lower.contains("water") || lower.contains("medicine") || lower.contains("stretch") || lower.contains("walk")) {
            let title = trimmed.replacingOccurrences(of: "add health reminder", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
            let res = await ToolRegistry.shared.invoke(name: "health_add_reminder", arguments: ["title": title, "schedule": "Daily"])
            return AutonomousExecutionResult(
                success: res.success,
                summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                targetAppName: "Apple Health",
                targetURL: nil,
                executedSteps: ["Apple Health [REVERSIBLE]: added reminder"]
            )
        }

        // 7. Phase 3: Iron Legion Parallel Subagents, CAD/Physics, Security & Lockdown
        if lower.contains("iron legion") || lower.contains("parallel agent") || lower.contains("agents chala") {
            let goal = trimmed
                .replacingOccurrences(of: "iron legion", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "parallel agents", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let res = await ToolRegistry.shared.invoke(name: "iron_legion_dispatch", arguments: ["goal": goal.isEmpty ? trimmed : goal])
            return AutonomousExecutionResult(
                success: res.success,
                summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                targetAppName: "Iron Legion",
                targetURL: nil,
                executedSteps: ["Spawned parallel Research, Code & Summarize subagents"]
            )
        }

        if lower.contains("generate cad") || lower.contains("openscad") || lower.contains("cadquery") || lower.contains("cad banao") || lower.contains("hologram") {
            let backend = lower.contains("cadquery") ? "cadquery" : "openscad"
            let res = await ToolRegistry.shared.invoke(name: "engineering_generate_cad", arguments: ["shape": trimmed, "backend": backend])
            return AutonomousExecutionResult(
                success: res.success,
                summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                targetAppName: "Engineering Studio",
                targetURL: nil,
                executedSteps: ["Generated parametric \(backend) model & 3D Hologram"]
            )
        }

        if lower.contains("physics sim") || lower.contains("projectile") || lower.contains("harmonic oscillator") || lower.contains("thermal sim") {
            let simType = lower.contains("spring") || lower.contains("harmonic") ? "spring" : (lower.contains("thermal") ? "thermal" : "projectile")
            let res = await ToolRegistry.shared.invoke(name: "engineering_physics_sim", arguments: ["type": simType])
            return AutonomousExecutionResult(
                success: res.success,
                summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                targetAppName: "Engineering Studio",
                targetURL: nil,
                executedSteps: ["Executed deterministic physics simulation"]
            )
        }

        if lower.contains("lockdown") || lower.contains("suraksha lockdown") {
            let res = await ToolRegistry.shared.invoke(name: "security_lockdown", arguments: ["reason": trimmed])
            return AutonomousExecutionResult(
                success: res.success,
                summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                targetAppName: "Cyber Defense",
                targetURL: nil,
                executedSteps: ["Security Lockdown [CONSEQUENTIAL]: Approval Gate"]
            )
        }

        if lower.contains("security scan") || lower.contains("network anomal") || lower.contains("suraksha scan") {
            let res = await ToolRegistry.shared.invoke(name: "security_anomaly_scan", arguments: [:])
            return AutonomousExecutionResult(
                success: res.success,
                summary: PersonaManager.shared.formatResponse(res.summary, language: lang),
                targetAppName: "Cyber Defense",
                targetURL: nil,
                executedSteps: ["Scanned local ports & LAN ARP baseline"]
            )
        }

        return nil
    }

    public static func isLikelyOpenEndedComputerUseGoal(_ utterance: String) -> Bool {
        let lower = utterance.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return false }
        let markers = [
            "click the ", "click on ", "press the ", "on screen", "operate the screen",
            "computer use", "find the cheapest", "scroll down and", "fill out", "select the button",
            "complete this form", "open settings button", "click start"
        ]
        return markers.contains { lower.contains($0) }
    }
}
