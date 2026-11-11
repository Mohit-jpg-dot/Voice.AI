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
        
        // -------------------------------------------------------------
        // Step 0: Circle-to-Ask Visual + OCR Region Analysis
        // -------------------------------------------------------------
        if let crop = screenCrop, ModelRouter.shared.currentMode != .googleSearch {
            onProgress?("Analyzing selected screen region...")
            if let analysis = await analyzeScreenWithActiveModel(
                pngData: crop.capturedImagePNGData,
                ocrText: crop.extractedOCRText,
                appName: crop.sourceAppName ?? "Screen",
                sourceLabel: crop.toolUsed.rawValue,
                question: trimmed
            ) {
                LocalMemoryManager.shared.remember(content: "[Circle to Ask] \(trimmed) -> \(analysis.summary)", category: "task", tags: ["Circle to Ask"])
                return AutonomousExecutionResult(
                    success: true,
                    summary: analysis.summary,
                    targetAppName: crop.sourceAppName ?? "Circle to Ask",
                    targetURL: nil,
                    executedSteps: ["Captured \(crop.toolUsed.rawValue) region", "Analyzed via \(analysis.usedProvider)"]
                )
            }
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
            do {
                let text = try await generateChatResponse(
                    model: chatModel,
                    systemPrompt: "You are Voice.AI in Conversation Mode (triggered by Fn key). Provide helpful, natural, friendly, concise answers. Be direct and avoid fluff.",
                    userPrompt: trimmed,
                    onPartialReply: onPartialReply
                )
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
            
            // 3. Direct General AI Reasoning with live token streaming
            onProgress?("Thinking...")
            let chatModel = ModelRouter.shared.resolveChatModel()
            do {
                let text = try await generateChatResponse(
                    model: chatModel,
                    systemPrompt: "You are Voice.AI, a fast, helpful voice assistant for macOS. Provide clear, accurate, concise answers.",
                    userPrompt: trimmed,
                    onPartialReply: onPartialReply
                )
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
                        executedSteps: ["Consulted \(chatModel.providerName) (\(chatModel.modelIdentifier))", "Synthesized response"]
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
}
