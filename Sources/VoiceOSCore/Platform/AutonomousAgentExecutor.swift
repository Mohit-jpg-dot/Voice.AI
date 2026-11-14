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

    /// Captures the full display, analyzes it via active VLM/OCR, and stores the screenshot context
    /// in `ConversationSessionContext.shared` so the user can ask hands-free follow-up questions by voice.
    public func captureAndAnalyzeScreenSavingContext(
        question: String,
        sourceLabel: String = "Full Screen"
    ) async -> (summary: String, provider: String, appName: String) {
        let captured = await ScreenVisionService.shared.captureFullScreenWithImage()
        let appName = captured.analysis.activeAppTitle ?? "Active App"
        let llmResult = await analyzeScreenWithActiveModel(
            pngData: captured.pngData,
            ocrText: captured.analysis.fullText,
            appName: appName,
            sourceLabel: sourceLabel,
            question: question
        )
        let summary = llmResult?.summary ?? captured.analysis.summary
        let provider = llmResult?.usedProvider ?? "Screen Vision"

        ConversationSessionContext.shared.setLastScreenContext(
            ConversationSessionContext.CapturedScreenContext(
                pngData: captured.pngData,
                ocrText: captured.analysis.fullText,
                appName: appName,
                initialSummary: summary,
                capturedAt: Date()
            )
        )
        ConversationSessionContext.shared.recordReply(summary, forCommand: question)
        return (summary, provider, appName)
    }

    private func isScreenFollowUpQuery(_ lower: String) -> Bool {
        let explicitRefs = [
            "on it", "in it", "on the screen", "on my screen", "the screenshot", "from the screenshot",
            "in the screenshot", "that screenshot", "that image", "this image", "from that image",
            "what does it say", "what is it saying", "what's it saying", "whats it saying",
            "read that", "explain this", "explain that", "summarize this", "summarize that",
            "what's wrong", "whats wrong", "that error", "the error", "this error",
            "what should i do", "what button", "based on that", "based on what you see", "tell me more about"
        ]
        if explicitRefs.contains(where: { lower.contains($0) }) {
            return true
        }
        return false
    }

    private func handleScreenContextFollowUpIfRelevant(_ query: String) async -> AutonomousExecutionResult? {
        let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower == "forget the screen" || lower == "clear screen context" || lower == "forget screenshot" {
            ConversationSessionContext.shared.clearLastScreenContext()
            return AutonomousExecutionResult(
                success: true,
                summary: "Cleared the stored screenshot context.",
                targetAppName: "Screen Vision",
                executedSteps: ["Cleared stored screen context"]
            )
        }
        if lower == "refresh screen" || lower == "take another screenshot" || lower == "look at my screen again" || lower == "check my screen again" {
            let captured = await captureAndAnalyzeScreenSavingContext(question: "Summarize what is currently visible on the screen.")
            return AutonomousExecutionResult(
                success: true,
                summary: captured.summary,
                targetAppName: captured.provider,
                executedSteps: ["Re-captured screen and updated stored context"]
            )
        }

        guard let saved = ConversationSessionContext.shared.lastScreenContext() else { return nil }

        // Allow explicit references anywhere within 15 minutes, OR short conversational follow-up questions within 90s
        let age = Date().timeIntervalSince(saved.capturedAt)
        let isQuestion = lower.hasSuffix("?") || ["what", "why", "how", "which", "where", "who", "explain", "summarize", "is there", "does it", "can i", "should i", "tell me"].contains(where: { lower.hasPrefix($0 + " ") })
        let unrelatedExternal = lower.contains("weather") || lower.contains("capital of") || lower.contains("google ") ||
                                lower.contains("youtube") || lower.contains("spotify") || lower.contains("timer") ||
                                lower.contains("alarm") || lower.contains("volume") || lower.hasPrefix("open ")
        let shouldUseSavedScreen = isScreenFollowUpQuery(lower) || (age <= 90 && isQuestion && !unrelatedExternal)
        guard shouldUseSavedScreen else { return nil }

        let llm = await analyzeScreenWithActiveModel(
            pngData: saved.pngData,
            ocrText: saved.ocrText,
            appName: saved.appName,
            sourceLabel: "Stored Screenshot Context",
            question: query
        )
        let answer: String
        if let text = llm?.summary, !text.isEmpty {
            answer = text
        } else if !saved.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let excerpt = saved.ocrText.split(separator: "\n").prefix(6).joined(separator: " • ")
            answer = "From the saved \(saved.appName) screenshot: \(excerpt)"
        } else {
            answer = "From the saved \(saved.appName) screenshot: \(saved.initialSummary)"
        }
        ConversationSessionContext.shared.recordReply(answer, forCommand: query)
        return AutonomousExecutionResult(
            success: true,
            summary: answer,
            targetAppName: llm?.usedProvider ?? "Saved Screen Context",
            executedSteps: ["Answered voice follow-up from stored screenshot context (\(saved.appName))"]
        )
    }

    public static func isSelfQuitCommand(_ query: String) -> Bool {
        let lower = query
            .replacingOccurrences(of: "[,.!?'\"]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return false }
        if lower.contains("named ") || lower.contains("called ") { return false }

        // Specific targeted external app exclusions (e.g. "quit Chrome", "close Safari")
        let externalApps = ["chrome", "safari", "spotify", "slack", "discord", "whatsapp", "mail", "terminal", "finder", "notes", "reminders", "calendar", "contacts", "youtube"]
        for app in externalApps {
            if lower.contains(app) && !lower.contains("voice") {
                return false
            }
        }

        let phrases = [
            "quit yourself",
            "quit urself",
            "shut yourself down",
            "shutdown yourself",
            "close yourself",
            "exit yourself",
            "turn yourself off",
            "power off yourself",
            "terminate yourself",
            "kill yourself",
            "quit voice ai",
            "quit voiceai",
            "quit voice.ai",
            "exit voice ai",
            "exit voice.ai",
            "close voice ai",
            "close voice.ai",
            "quit jarvis",
            "exit jarvis",
            "close jarvis",
            "band ho jao",
            "apne aap ko band kar do",
            "apne aap ko band karo",
            "tum band ho jao",
            "voice ai band kar do",
            "voiceai band kar do",
            "die",
            "just die",
            "please die",
            "app ko maar do",
            "mar jao",
            "mar ja",
            "khud ko khatam karo"
        ]
        return phrases.contains(where: { lower.contains($0) })
    }

    public static func parseIntegrationSetupVoiceCommand(_ query: String) -> (appId: String, appName: String, statusResponse: String)? {
        let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let isConnectOrSetup = lower.contains("connect ") || lower.contains("set up ") || lower.contains("setup ") ||
                              lower.contains("connected hai") || lower.contains("ko connect") || lower.contains("ka setup")
        guard isConnectOrSetup else { return nil }

        let apps: [(id: String, name: String, keys: [String])] = [
            ("mail", "Gmail", ["gmail", "email", "mail"]),
            ("slack", "Slack", ["slack"]),
            ("discord", "Discord", ["discord"]),
            ("whatsapp", "WhatsApp", ["whatsapp"]),
            ("spotify", "Spotify", ["spotify"]),
            ("notion", "Notion", ["notion"]),
            ("calendar", "Calendar", ["calendar", "google meet"])
        ]

        for app in apps {
            if app.keys.contains(where: { lower.contains($0) }) {
                let desc = IntegrationRegistry.shared.descriptor(for: app.id)
                let isConnected = desc?.status.isConnected ?? false
                let statusMsg: String
                if lower.contains("connected hai") || lower.contains("is connected") {
                    statusMsg = isConnected
                        ? "\(app.name) is currently connected and active."
                        : "\(app.name) is not connected yet. Opening setup screen so you can connect your account."
                } else {
                    statusMsg = isConnected
                        ? "Opening \(app.name) setup. Your account is already connected."
                        : "Opening \(app.name) setup so you can connect your account."
                }
                return (app.id, app.name, statusMsg)
            }
        }
        return nil
    }

    private func handleComputerAudioQuestion(_ query: String) async -> AutonomousExecutionResult {
        let enabled = ComputerAudioListenerService.shared.isEnabled
        let context = ComputerAudioListenerService.shared.capturedContext(maxAgeSeconds: 600)
        let mediaSummary: String = {
            if let item = context.nowPlaying {
                let channel = item.artistOrChannel.isEmpty ? "" : " (\(item.artistOrChannel))"
                return "Currently playing via \(item.source.rawValue): \(item.title)\(channel)."
            }
            return ""
        }()

        if !enabled && context.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let prefix = mediaSummary.isEmpty ? "" : "\(mediaSummary) "
            let msg = "\(prefix)Computer audio listening is off so I ignore background videos. Say 'listen to the things my computer is making' first, and I'll listen and summarize what's playing."
            ConversationSessionContext.shared.recordReply(msg, forCommand: query)
            return AutonomousExecutionResult(
                success: true,
                summary: msg,
                targetAppName: "Computer Audio",
                executedSteps: ["Explained how to enable on-demand computer audio listening"]
            )
        }

        let cleanTranscript = context.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTranscript.isEmpty {
            let permNote = (Bundle.main.bundleIdentifier != nil && !CGPreflightScreenCaptureAccess())
                ? " Make sure Screen & System Audio Recording permission is enabled for Voice.AI in System Settings."
                : ""
            let msg = mediaSummary.isEmpty
                ? "I'm listening to your computer audio, but haven't heard clear speech from playback yet.\(permNote)"
                : "\(mediaSummary) I'm listening to your computer audio, though no spoken dialogue has been transcribed yet.\(permNote)"
            ConversationSessionContext.shared.recordReply(msg, forCommand: query)
            return AutonomousExecutionResult(
                success: true,
                summary: msg,
                targetAppName: "Computer Audio",
                executedSteps: ["Checked captured computer audio buffer"]
            )
        }

        if ModelRouter.shared.currentMode != .googleSearch,
           let model = try? ModelRouter.shared.resolveChatModel() {
            let sysPrompt = "You are Voice.AI. Answer concisely in 1-3 clear spoken sentences based ONLY on the captured computer audio transcript and active media info below."
            let userPrompt = """
            \(mediaSummary)
            Recent captured computer audio transcript:
            \(cleanTranscript.suffix(2400))

            User question: \(query)
            """
            if let answer = try? await generateChatResponse(
                model: model,
                systemPrompt: sysPrompt,
                userPrompt: userPrompt,
                onPartialReply: nil
            ), !answer.isEmpty {
                ConversationSessionContext.shared.recordReply(answer, forCommand: query)
                return AutonomousExecutionResult(
                    success: true,
                    summary: answer,
                    targetAppName: "Computer Audio",
                    executedSteps: ["Summarized captured computer audio via \(model.providerName)"]
                )
            }
        }

        let excerpt = String(cleanTranscript.suffix(420))
        let fallback = mediaSummary.isEmpty
            ? "Here's what your computer recently said: \(excerpt)"
            : "\(mediaSummary) Recent audio: \(excerpt)"
        ConversationSessionContext.shared.recordReply(fallback, forCommand: query)
        return AutonomousExecutionResult(
            success: true,
            summary: fallback,
            targetAppName: "Computer Audio",
            executedSteps: ["Returned captured computer audio transcript"]
        )
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

        // Also ensure no play_music or dark_mode system command executes ungrounded
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
            if p.contains("dark_mode") {
                let themeRequested = lower.contains("dark") || lower.contains("light mode") ||
                                     lower.contains("night mode") || lower.contains("appearance") ||
                                     lower.contains("theme")
                if !themeRequested { return false }
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
        let result = await executePlanCore(
            taskDescription: taskDescription,
            triggerMode: triggerMode,
            screenCrop: screenCrop,
            onPartialReply: onPartialReply,
            onProgress: onProgress
        )
        let cleanedInput = AgentToolParser.stripCasualPrefix(taskDescription)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedInput.isEmpty && !result.summary.isEmpty && !Self.isSelfQuitCommand(cleanedInput) {
            await MemoryStore.shared.recordConversationExchange(
                userText: cleanedInput,
                assistantText: result.summary,
                timestamp: Date(),
                sourceTag: result.targetAppName
            )
        }
        return result
    }

    private func executePlanCore(
        taskDescription: String,
        triggerMode: VoiceTriggerMode = .agent,
        screenCrop: ScreenCropResult? = nil,
        onPartialReply: (@Sendable (String) -> Void)? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async -> AutonomousExecutionResult {
        let strippedCasual = AgentToolParser.stripCasualPrefix(taskDescription)
        let trimmed = strippedCasual.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        let stopCheck = trimmed.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if (stopCheck == "stop" || stopCheck == "stop agent" || stopCheck == "ruko" || stopCheck == "ruk jao") {
            SafeTerminalEngine.shared.stopActiveCommand()
            if ComputerUseOperator.shared.isRunning {
                ComputerUseOperator.shared.stopActiveRun()
                return AutonomousExecutionResult(
                    success: true,
                    summary: "Stopped.",
                    targetAppName: "Computer Use",
                    targetURL: nil,
                    executedSteps: ["Spoken stop keyword halted active computer-use & terminal tasks"]
                )
            }
        }

        if triggerMode == .agent,
           let firewallResult = await CommandSafetyFirewall.shared.enforce(command: taskDescription) {
            return firewallResult
        }

        // -------------------------------------------------------------
        // Step -1.5: Section 1 Conversation Controls (Greeting, Stop Listening, Cancel, Repeat)
        // -------------------------------------------------------------
        if triggerMode == .agent {
            let cleanLower = trimmed.lowercased()
            if cleanLower == "hello" || cleanLower == "hi" || cleanLower == "hey" || cleanLower == "namaste" {
                let greet = "Hello! How can I help you today?"
                ConversationSessionContext.shared.recordReply(greet, forCommand: trimmed)
                return AutonomousExecutionResult(success: true, summary: greet, targetAppName: AppBrand.name)
            }
            if cleanLower == "stop listening" || cleanLower == "pause listening" {
                TheVoiceAmbientListener.shared.isTheVoiceModeEnabled = false
                let msg = "Stopped listening. Press Fn or say your wake word when you need me."
                ConversationSessionContext.shared.recordReply(msg, forCommand: trimmed)
                return AutonomousExecutionResult(success: true, summary: msg, targetAppName: AppBrand.name)
            }
            if cleanLower == "cancel" || cleanLower == "never mind" || cleanLower == "nevermind" || cleanLower == "abort" {
                SpeechPipelineEngine.shared.bargeIn()
                ConversationSessionContext.shared.setPendingDeletePath(nil)
                let msg = "Cancelled."
                ConversationSessionContext.shared.recordReply(msg, forCommand: trimmed)
                return AutonomousExecutionResult(success: false, summary: msg, targetAppName: AppBrand.name)
            }
            if cleanLower == "repeat that" || cleanLower == "say that again" || cleanLower == "repeat" {
                let prev = ConversationSessionContext.shared.lastReply ?? "I haven't said anything yet."
                return AutonomousExecutionResult(
                    success: ConversationSessionContext.shared.lastReply != nil,
                    summary: prev,
                    targetAppName: AppBrand.name,
                    executedSteps: ["Repeated previous spoken response"]
                )
            }
            // Multi-app fast launch ("Open Chrome and Notepad")
            if cleanLower.hasPrefix("open ") && cleanLower.contains(" and ") && !cleanLower.contains("search") && !cleanLower.contains("note:") && !cleanLower.contains("a note") && !cleanLower.contains("type") {
                let body = String(trimmed.dropFirst(5))
                let parts = body.components(separatedBy: " and ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if parts.count >= 2 && parts.allSatisfy({ $0.split(separator: " ").count <= 3 }) {
                    var openedNames: [String] = []
                    for appPart in parts {
                        let res = await AgentActionDispatcher.shared.dispatch(transcript: "open \(appPart)")
                        if res.success {
                            openedNames.append(res.appName)
                        }
                    }
                    if !openedNames.isEmpty {
                        let summary = "Opened \(openedNames.joined(separator: " and "))."
                        ConversationSessionContext.shared.recordReply(summary, forCommand: trimmed)
                        return AutonomousExecutionResult(
                            success: true,
                            summary: summary,
                            targetAppName: openedNames.joined(separator: ", "),
                            executedSteps: openedNames.map { "Opened \($0)" }
                        )
                    }
                }
            }
        }

        if AppState.isSilenceAndCollapseCommand(trimmed) {
            SpeechPipelineEngine.shared.bargeIn()
            if ComputerUseOperator.shared.isRunning {
                ComputerUseOperator.shared.stopActiveRun()
            }
            _ = PersonaManager.shared.evaluateSafetyGuardrail(userInput: "shut up")
            EventBus.shared.publish(VoiceEvent(
                kind: .custom("notch_collapse_requested"),
                source: "AutonomousAgentExecutor",
                severity: .info,
                payload: ["reason": "silence_collapse"]
            ))
            return AutonomousExecutionResult(
                success: true,
                summary: "Silenced and collapsed notch.",
                targetAppName: "System",
                targetURL: nil,
                executedSteps: ["Silenced TTS and collapsed open hover pill"]
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
        // Step -1.45: Self-Quit Voice.AI & Automatically Shut Down Ollama
        // -------------------------------------------------------------
        if Self.isSelfQuitCommand(trimmed) {
            EventBus.shared.publish(VoiceEvent(
                kind: .custom("app_self_quit_requested"),
                source: "AutonomousAgentExecutor",
                severity: .info,
                payload: ["quit_ollama": "true"]
            ))
            let msg = "Quitting Voice.AI and shutting down Ollama now. Goodbye."
            ConversationSessionContext.shared.recordReply(msg, forCommand: trimmed)
            return AutonomousExecutionResult(
                success: true,
                summary: msg,
                targetAppName: AppBrand.name,
                targetURL: nil,
                executedSteps: ["Triggered self-quit", "Scheduled Ollama shutdown"]
            )
        }

        // -------------------------------------------------------------
        // Step -1.42: Voice Command for Integration Setup ("connect Gmail", "Slack connected hai?", "set up WhatsApp")
        // -------------------------------------------------------------
        if let setupTarget = Self.parseIntegrationSetupVoiceCommand(trimmed) {
            EventBus.shared.publish(VoiceEvent(
                kind: .custom("open_integration_setup"),
                source: "AutonomousAgentExecutor",
                severity: .info,
                payload: ["app_id": setupTarget.appId]
            ))
            let msg = setupTarget.statusResponse
            ConversationSessionContext.shared.recordReply(msg, forCommand: trimmed)
            return AutonomousExecutionResult(
                success: true,
                summary: msg,
                targetAppName: setupTarget.appName,
                targetURL: nil,
                executedSteps: ["Opened integration setup screen for \(setupTarget.appName)"]
            )
        }

        // -------------------------------------------------------------
        // Step -1.4: Voice Toggle for 24/7 Continuous Listening Mode & Computer Audio Mode
        // -------------------------------------------------------------
        if triggerMode == .agent {
            if let toggleComputerAudio = ComputerAudioListenerService.parseListeningToggleCommand(trimmed) {
                ComputerAudioListenerService.shared.isEnabled = toggleComputerAudio
                if toggleComputerAudio && !TheVoiceAmbientListener.shared.isTheVoiceModeEnabled {
                    TheVoiceAmbientListener.shared.isTheVoiceModeEnabled = true
                }
                let msg: String
                if toggleComputerAudio {
                    let needsPerm = (Bundle.main.bundleIdentifier != nil && !CGPreflightScreenCaptureAccess())
                    msg = needsPerm
                        ? "Computer audio listening is on. Allow Screen and System Audio Recording for Voice.AI in System Settings so I can capture internal playback."
                        : "Got it, I'm now listening to what your computer is playing. Ask me anytime to summarize or explain it."
                } else {
                    msg = "Stopped listening to computer audio. I will ignore background videos and system playback now."
                }
                ConversationSessionContext.shared.recordReply(msg, forCommand: trimmed)
                return AutonomousExecutionResult(
                    success: true,
                    summary: msg,
                    targetAppName: "Computer Audio",
                    executedSteps: [toggleComputerAudio ? "Enabled computer audio listening mode" : "Disabled computer audio listening mode"]
                )
            }

            if ComputerAudioListenerService.isComputerAudioQuestion(trimmed) {
                return await handleComputerAudioQuestion(trimmed)
            }

            let lm = trimmed.lowercased()
            let mentions24x7OrBroMode =
                lm.contains("24/7") || lm.contains("24 7") || lm.contains("24x7") || lm.contains("24-7") ||
                lm.contains("24 by 7") || lm.contains("twenty four seven") || lm.contains("twenty-four seven") ||
                lm.contains("24 hours") || lm.contains("always listen") || lm.contains("always-on listen") ||
                lm.contains("continuous listen") || lm.contains("listening mode") ||
                lm.contains("bro mode") || lm.contains("bro-mode") || lm.contains("bro's mode") ||
                lm.contains("pro mode") || lm.contains("pro-mode") || lm.contains("brow mode") || lm.contains("grow mode") ||
                lm.contains("free talk") || lm.contains("keep listening")
            let wantsModeOff =
                lm.contains("turn off") || lm.contains("switch off") || lm.contains("disable") ||
                lm.contains("stop ") || lm.contains("exit ") || lm.contains("deactivate") ||
                lm.contains("mode off") || lm.hasSuffix(" off") || lm.contains(" off ") ||
                lm.contains("band") || lm.contains("wake word only") || lm.contains("wake-word only")
            if lm.contains("wake word only") || lm.contains("wake-word only") || (mentions24x7OrBroMode && wantsModeOff) {
                TheVoiceAmbientListener.shared.isAlwaysOn24x7Mode = false
                EventBus.shared.publish(VoiceEvent(kind: .custom("listening_mode_changed"), source: "AutonomousAgentExecutor", severity: .info, payload: ["always_on": "false"]))
                let msg = "Switched back to wake-word mode."
                ConversationSessionContext.shared.recordReply(msg, forCommand: trimmed)
                return AutonomousExecutionResult(success: true, summary: msg, targetAppName: AppBrand.name, executedSteps: ["Switched to wake-word-only listening mode"])
            }
            if mentions24x7OrBroMode {
                TheVoiceAmbientListener.shared.isTheVoiceModeEnabled = true
                TheVoiceAmbientListener.shared.isAlwaysOn24x7Mode = true
                EventBus.shared.publish(VoiceEvent(kind: .custom("listening_mode_changed"), source: "AutonomousAgentExecutor", severity: .info, payload: ["always_on": "true"]))
                let msg = "24/7 continuous listening (Bro mode) is on. Speak anytime when you need me."
                ConversationSessionContext.shared.recordReply(msg, forCommand: trimmed)
                return AutonomousExecutionResult(success: true, summary: msg, targetAppName: AppBrand.name, executedSteps: ["Enabled 24/7 always-on listening mode"])
            }
        }

        // -------------------------------------------------------------
        // Step -1.25: Safe Terminal Audit ("What commands did you run today?") & Terminal Undo ("Undo that")
        // -------------------------------------------------------------
        if triggerMode == .agent {
            let auditLower = trimmed.lowercased()
            if auditLower.contains("what commands did you run") || auditLower.contains("commands did i run") || auditLower.contains("terminal history") || auditLower.contains("audit log") {
                let logs = EncryptedChatHistoryManager.shared.commandAuditLogs(forDay: Date())
                if logs.isEmpty {
                    let msg = "No terminal commands have been attempted today."
                    return AutonomousExecutionResult(success: true, summary: msg, targetAppName: "Terminal", executedSteps: ["Checked encrypted terminal audit log (0 entries today)"])
                }
                let tf = DateFormatter()
                tf.timeStyle = .short
                let lines = logs.prefix(10).map { "• [\(tf.string(from: $0.timestamp))] `\($0.command)` (\($0.decision), exit \($0.exitCode))" }
                let msg = "Commands attempted today:\n" + lines.joined(separator: "\n")
                return AutonomousExecutionResult(success: true, summary: msg, targetAppName: "Terminal", executedSteps: ["Listed \(logs.count) encrypted terminal audit record(s)"])
            }
            if (auditLower == "undo that" || auditLower == "undo last command" || auditLower == "undo terminal command"),
               SafeTerminalEngine.shared.lastUndoOperation() != nil {
                let undoRes = await SafeTerminalEngine.shared.undoLastCommand()
                return AutonomousExecutionResult(
                    success: undoRes.success,
                    summary: undoRes.plainSummary,
                    targetAppName: "Terminal",
                    executedSteps: ["Executed policy-checked terminal undo (\(undoRes.decision))"]
                )
            }
        }

        // -------------------------------------------------------------
        // Step -1.2: System Utilities, Multi-Step Chains, Context Follow-ups & Error Guards
        // (Must run before single-step file/tool parsers so chains like "Create X, then create Y" split cleanly)
        // -------------------------------------------------------------
        if triggerMode == .agent,
           let utilResult = await RealWorldUtilityRouter.shared.handleUtilityOrFollowUp(taskDescription) {
            ConversationSessionContext.shared.recordReply(utilResult.summary, forCommand: trimmed)
            return utilResult
        }

        // -------------------------------------------------------------
        // Step -1.1: Section 5 Sandboxed File & Folder Operations (+ Undo / Confirmed Delete)
        // -------------------------------------------------------------
        if triggerMode == .agent,
           let fileResult = await SandboxFileManagerEngine.shared.handleFileCommand(trimmed) {
            ConversationSessionContext.shared.recordReply(fileResult.summary, forCommand: trimmed)
            return fileResult
        }

        // -------------------------------------------------------------
        // Step -1: Remember / Forget / Recall Long-Term Memory Voice Commands
        // -------------------------------------------------------------
        if let memoryResult = await handleMemoryVoiceCommandIfPresent(trimmed) {
            return memoryResult
        }

        if let emailResult = await handleVoiceEmailCommandIfPresent(trimmed) {
            return emailResult
        }

        if let eventResult = await handleVoiceEventAndReminderCommandIfPresent(trimmed) {
            return eventResult
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
            ConversationSessionContext.shared.recordReply(mathResult.displaySummary, forCommand: trimmed)
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
                // Preserve dictated speech cleanly rather than falling back to Wikipedia lookup
                let polished = DictationPolishEngine.shared.polish(
                    rawText: taskDescription,
                    profile: .general
                ).polishedText.trimmingCharacters(in: .whitespacesAndNewlines)
                let output = polished.isEmpty ? taskDescription : polished
                ConversationSessionContext.shared.recordReply(output, forCommand: taskDescription)
                return AutonomousExecutionResult(
                    success: true,
                    summary: output,
                    targetAppName: "Dictation",
                    executedSteps: ["Polished dictated speech locally"]
                )
            }
        }
        
        // -------------------------------------------------------------
        // Mode B: Fast Native Tool -> Pure Q&A Stream -> Orchestrated Plan
        // -------------------------------------------------------------
        if ModelRouter.shared.currentMode != .googleSearch {
            // 1. Direct Native macOS Tools (<1ms, zero LLM round-trip for explicit commands)
            if let _ = AgentToolParser.parse(query: trimmed) {
                let dispatchResult = await AgentActionDispatcher.shared.dispatch(transcript: trimmed)
                ConversationSessionContext.shared.recordReply(dispatchResult.summary, forCommand: trimmed)
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

            // 1b. Direct local Apple Notes / Reminders / Finder tasks (never hijack explicit file/folder commands)
            let qLower = trimmed.lowercased()
            let mentionsFileSystem = qLower.contains("file") || qLower.contains("folder") || qLower.contains(".txt") || qLower.contains("rename ") || qLower.contains("move ") || qLower.contains("copy ") || qLower.contains("delete ")
            let isDirectLocalUtilityTask =
                (!mentionsFileSystem && (qLower.contains("note") || qLower.contains("notes")) && (qLower.contains("create") || qLower.contains("add") || qLower.contains("write") || qLower.contains("take") || qLower.contains("likh") || qLower.contains("save"))) ||
                qLower.contains("remind me to ") || qLower.hasPrefix("reminder ") ||
                qLower.contains("open downloads") || qLower.contains("show downloads") || qLower.contains("downloads folder") ||
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

            // 1b. Direct Voice Follow-up on Stored Screenshot Context (NO pill click required)
            if let screenFollowUp = await handleScreenContextFollowUpIfRelevant(trimmed) {
                LocalMemoryManager.shared.remember(content: "\(trimmed) -> \(screenFollowUp.summary)", category: "task", tags: ["Screen Context"])
                return screenFollowUp
            }

            // 1c. Casual Demonstrative Action ("open this up", "do this") -> resolve active screen/file/link or Computer-Use
            if qLower == "open this up" || qLower == "open this" || qLower == "do this" {
                if let savedItem = ConversationSessionContext.shared.searchResult(atOneBasedIndex: 1) {
                    return AutonomousExecutionResult(
                        success: true,
                        summary: "Opening \(savedItem.title).",
                        targetAppName: ConversationSessionContext.shared.lastActiveBrowser ?? "Browser",
                        targetURL: URL(string: savedItem.url),
                        executedSteps: ["Opened active contextual link: \(savedItem.title)"]
                    )
                }
                if let lastPath = ConversationSessionContext.shared.lastCreatedOrModifiedPath {
                    return await SandboxFileManagerEngine.shared.handleFileCommand("open file \(URL(fileURLWithPath: lastPath).lastPathComponent)")
                        ?? AutonomousExecutionResult(success: true, summary: "Opened \(lastPath).", targetAppName: "Finder")
                }
                let screenCap = await captureAndAnalyzeScreenSavingContext(question: "What item or control is highlighted or should be opened/acted on?")
                return AutonomousExecutionResult(
                    success: true,
                    summary: screenCap.summary,
                    targetAppName: screenCap.provider,
                    executedSteps: ["Analyzed current screen context for action"]
                )
            }

            // 1d. Open-Ended Screen / Vision Computer-Use Operator Loop (Control key Agent Mode)
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
    
    private func executeSafeShellCommand(_ rawCommand: String) async -> (success: Bool, output: String) {
        let outcome = await SafeTerminalEngine.shared.execute(
            command: rawCommand,
            purpose: "Execute terminal command: \(rawCommand)",
            approvalSource: .liveMicrophone
        )
        return (outcome.success, outcome.plainSummary)
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
                let shellRes = await executeSafeShellCommand(step.param)
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
                    let snap = LiveHostTelemetrySnapshot.capture()
                    if let pct = snap.batteryPercent {
                        executed.append("Battery: \(pct)% (\(snap.isCharging ? "Charging" : "On Battery"))")
                    } else {
                        executed.append("Battery telemetry unavailable")
                    }
                } else if cmd.contains("disk") {
                    let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
                    let freeBytes = (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
                    let totalBytes = (attrs?[.systemSize] as? NSNumber)?.int64Value ?? 0
                    let freeGB = String(format: "%.1f", Double(freeBytes) / 1_073_741_824.0)
                    let totalGB = String(format: "%.1f", Double(totalBytes) / 1_073_741_824.0)
                    executed.append("Disk free: \(freeGB) GB of \(totalGB) GB")
                } else if cmd.contains("ram") || cmd.contains("memory") {
                    let snap = LiveHostTelemetrySnapshot.capture()
                    executed.append("Memory used: \(snap.ramUsagePercent)%")
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
                } else if cmd == "copy" || cmd == "copy_selection" || cmd == "copy_text" {
                    _ = AccessibilityControlEngine.shared.performWindowAction("copy")
                    executed.append("Copied selection to clipboard")
                } else if cmd == "paste" || cmd == "paste_text" {
                    _ = AccessibilityControlEngine.shared.performWindowAction("paste")
                    executed.append("Pasted from clipboard")
                } else if cmd == "undo" || cmd == "redo" || cmd == "select_all" || cmd == "scroll_down" || cmd == "scroll_up" {
                    _ = AccessibilityControlEngine.shared.performWindowAction(cmd)
                    executed.append("Executed editor action: \(cmd)")
                } else if cmd.contains("&&") || cmd.contains("osascript") || cmd.contains("json;") || cmd.contains("{") || cmd.contains("open /") {
                    // Reject malformed shell/JSON strings emitted by small local models instead of leaking raw artifacts to HUD
                    overallSuccess = false
                    executed.append("I couldn't map that directly — try rephrasing a specific action.")
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
        if lower == "forget the screen" || lower == "clear screen context" || lower == "forget screenshot" {
            return nil
        }

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
                if MemoryStore.isInstructionLikeMemory(fact) {
                    return AutonomousExecutionResult(
                        success: false,
                        summary: "Rejected: I cannot store instructions that disable approvals or alter safety rules.",
                        targetAppName: "Memory",
                        targetURL: nil,
                        executedSteps: ["Rejected instruction-like memory override attempt"]
                    )
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

        // 2b. Session Management & Working-Context Terminal Recall ("start a new session", "continue where we left off", "open the session about ...", "rename this session to ...", "run that again", "what was the last command")
        if lower == "start a new session" || lower == "new session" || lower == "start new session" || lower == "new chat" {
            EventBus.shared.publish(VoiceEvent(kind: .custom("session_control"), source: "AutonomousAgentExecutor", severity: .info, payload: ["action": "new_session"]))
            return AutonomousExecutionResult(success: true, summary: "Started a new conversation session.", targetAppName: "Sessions", executedSteps: ["Started new encrypted session"])
        }
        if lower.contains("continue where we left off") || lower.contains("resume my last session") || lower.contains("resume last session") {
            let latest = EncryptedChatHistoryManager.shared.listConversations().first
            if let conv = latest {
                EventBus.shared.publish(VoiceEvent(kind: .custom("session_control"), source: "AutonomousAgentExecutor", severity: .info, payload: ["action": "select_session", "id": conv.id]))
                return AutonomousExecutionResult(success: true, summary: "Resumed session \"\(conv.title)\" (\(conv.messages.count) messages).", targetAppName: "Sessions", executedSteps: ["Resumed session \(conv.id)"])
            }
            return AutonomousExecutionResult(success: false, summary: "No previous session found to resume.", targetAppName: "Sessions")
        }
        if lower.hasPrefix("open the session about ") || lower.hasPrefix("open session about ") || lower.hasPrefix("find session ") {
            let topic = trimmed.replacingOccurrences(of: #"(?i)^(?:open\s+(?:the\s+)?session\s+about|find\s+session)\s+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = EncryptedChatHistoryManager.shared.listConversations(query: topic).first {
                EventBus.shared.publish(VoiceEvent(kind: .custom("session_control"), source: "AutonomousAgentExecutor", severity: .info, payload: ["action": "select_session", "id": match.id]))
                return AutonomousExecutionResult(success: true, summary: "Opened session \"\(match.title)\".", targetAppName: "Sessions", executedSteps: ["Opened matching session \(match.id)"])
            }
            return AutonomousExecutionResult(success: false, summary: "No session matching '\(topic)' found.", targetAppName: "Sessions")
        }
        if lower.hasPrefix("rename this session to ") || lower.hasPrefix("rename session to ") {
            let newTitle = trimmed.replacingOccurrences(of: #"(?i)^rename\s+(?:this\s+)?session\s+to\s+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if !newTitle.isEmpty {
                EventBus.shared.publish(VoiceEvent(kind: .custom("session_control"), source: "AutonomousAgentExecutor", severity: .info, payload: ["action": "rename_session", "title": newTitle]))
                return AutonomousExecutionResult(success: true, summary: "Renamed current session to \"\(newTitle)\".", targetAppName: "Sessions", executedSteps: ["Renamed session to \(newTitle)"])
            }
        }
        if lower == "run that again" || lower == "run it again" || lower == "repeat last command" {
            if let lastCmd = MemoryStore.shared.workingContext().lastCommands.first {
                let rerun = await SafeTerminalEngine.shared.execute(
                    command: lastCmd.command,
                    workingDirectory: lastCmd.workingDirectory,
                    purpose: "Re-run previous command: \(lastCmd.command)",
                    approvalSource: .liveMicrophone
                )
                return AutonomousExecutionResult(success: rerun.success, summary: rerun.plainSummary, targetAppName: "Terminal", executedSteps: ["Re-evaluated & ran '\(lastCmd.command)' (\(rerun.decision))"])
            }
        }
        if lower.contains("what was the last command") || lower.contains("last command you ran") || lower == "last command" {
            if let lastCmd = MemoryStore.shared.workingContext().lastCommands.first {
                return AutonomousExecutionResult(
                    success: true,
                    summary: "The last command was `\(lastCmd.command)` in \(lastCmd.workingDirectory) (\(lastCmd.success ? "succeeded" : "failed")).",
                    targetAppName: "Memory",
                    executedSteps: ["Read working context last command"]
                )
            }
        }

        // 3. Episodic / Temporal / Profile / Semantic Memory Recall:
        // ("What did we do yesterday?", "What did we talk about?", "What do you remember about me?", "What is my name?")
        let isTemporalOrEpisodicRecall =
            lower.contains("what did we do") ||
            lower.contains("what did we talk") ||
            lower.contains("what did we discuss") ||
            lower.contains("what happened yesterday") ||
            lower.contains("what did i ask yesterday") ||
            lower.contains("what did i say yesterday") ||
            lower.contains("kal kya") ||
            lower.contains("kal humne") ||
            lower.contains("yesterday") && (lower.contains("talk") || lower.contains("chat") || lower.contains("ask") || lower.contains("conversation") || lower.contains("remember") || lower.contains("do")) ||
            lower.contains("previous conversation") ||
            lower.contains("past conversation") ||
            lower.contains("previous command") ||
            lower.contains("last command") ||
            lower.contains("previous question") ||
            lower.contains("last question") ||
            lower.contains("previous result") ||
            lower.contains("last result") ||
            lower.contains("last response") ||
            lower.contains("previous response") ||
            lower.contains("what did i just ask") ||
            lower.contains("what did i just say") ||
            lower.contains("what did we just do") ||
            lower.contains("what did you just say") ||
            lower.contains("do you remember") ||
            lower == "who am i" ||
            lower.contains("what is my name") ||
            lower.contains("what's my name")

        if lower.hasPrefix("what do you remember") || lower.contains("kya yaad hai") || lower == "my memories" || lower == "list my memories" || isTemporalOrEpisodicRecall {
            let recall = await MemoryStore.shared.recallByTimeOrTopic(query: trimmed)
            ConversationSessionContext.shared.recordReply(recall.answer, forCommand: trimmed)
            return AutonomousExecutionResult(
                success: true,
                summary: PersonaManager.shared.formatResponse(recall.answer, language: PersonaManager.shared.detectedLanguageCode(for: trimmed)),
                targetAppName: "Memory",
                targetURL: nil,
                executedSteps: ["Queried local memory & conversation history (\(recall.matchedCount) match(es))"]
            )
        }

        return nil
    }

    private func buildPersonaAndMemorySystemPrompt(basePrompt: String, forQuery query: String) async -> String {
        let personaDirectives = PersonaManager.shared.systemPromptDirectives(forUserQuery: query)
        let profile = MemoryStore.shared.userProfile()
        let activeSessionId = UserDefaults.standard.string(forKey: "VoiceAI_ActiveConversationId")
        let retrieved = await MemoryStore.shared.retrievePromptContext(
            forQuery: query,
            activeSessionId: activeSessionId,
            maxTokenBudget: 400
        )

        var parts = [basePrompt, personaDirectives]
        if !profile.displayName.isEmpty && profile.displayName != "User" {
            parts.append("User display name: \(profile.displayName).")
        }
        if !retrieved.untrustedPromptBlock.isEmpty {
            parts.append(retrieved.untrustedPromptBlock)
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

    // MARK: - Voice Email Commands (Draft, Send, Reply, Watch)

    private func handleVoiceEmailCommandIfPresent(_ trimmed: String) async -> AutonomousExecutionResult? {
        var cleanInput = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        var lower = cleanInput.lowercased()

        // Strip conversational openers so natural queries like "Can you draft me an email for Rahul" route cleanly
        let conversationalOpeners = [
            "can you please ", "could you please ", "can u please ", "will you please ", "would you please ",
            "can you ", "could you ", "can u ", "will you ", "would you ", "please ",
            "help me ", "i want you to ", "i want to ", "i need you to ", "i need to ",
            "hey jarvis ", "jarvis ", "bro "
        ]
        for opener in conversationalOpeners {
            if lower.hasPrefix(opener) {
                cleanInput = String(cleanInput.dropFirst(opener.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                lower = cleanInput.lowercased()
                break
            }
        }

        let manager = VoiceEmailManager.shared

        func emailResult(_ summary: String, success: Bool = true, step: String = "Voice Email") -> AutonomousExecutionResult {
            AutonomousExecutionResult(
                success: success,
                summary: summary,
                targetAppName: "VoiceAI",
                targetURL: nil,
                executedSteps: [step]
            )
        }

        // 0. Direct Voice Dismiss / Delete for active or focused draft
        let isDiscardCommand = lower == "discard" || lower == "discard draft" || lower == "discard this draft" ||
                               lower == "discard email" || lower == "discard this email" ||
                               lower == "dismiss" || lower == "dismiss draft" || lower == "dismiss this draft" ||
                               lower == "dismiss email" || lower == "dismiss this email" ||
                               lower == "dismiss this drafted email" || lower == "dismiss drafted email" ||
                               lower == "delete draft" || lower == "delete this draft" || lower == "delete email" ||
                               lower == "cancel draft" || lower == "cancel this draft" || lower == "cancel email" ||
                               lower == "cancel this email" || lower == "don't send" || lower == "dont send" ||
                               lower.contains("draft hatao") || lower.contains("email band karo") ||
                               lower.contains("draft delete") || lower.contains("draft dismiss")
        if isDiscardCommand {
            _ = manager.discardFocusedDraft()
            EventBus.shared.publish(VoiceEvent(
                kind: .custom("email_draft_dismiss_requested"),
                source: "AutonomousAgentExecutor",
                severity: .info,
                payload: [:]
            ))
            return emailResult("Draft dismissed and deleted.", success: true, step: "Dismissed and deleted email draft")
        }

        // 1. Capability check
        if lower == "can you send emails?" || lower == "can you send emails" || lower == "can you send email" || lower == "can you send email?" {
            let rep = await manager.capabilitiesReport()
            return emailResult(rep.spokenSummary, success: rep.status == .canSendAndRead || rep.status == .canSendOnly, step: "Checked email backend capabilities")
        }

        // 2. Undo pending send during undo window
        if lower == "undo" || lower == "undo send" {
            if manager.cancelPendingSend() {
                return emailResult("Send undone. Your email draft was kept.", step: "Cancelled pending send")
            }
        }

        // 3. Watch queries & controls
        if lower.contains("what am i watching") || lower == "list watches" {
            let watches = manager.activeWatchRules()
            if watches.isEmpty {
                return emailResult("You are not watching any email threads or senders right now.")
            }
            let desc = watches.map { "• \($0.displayLabel)\($0.subjectHint.map { " (\($0))" } ?? "") [\($0.type.rawValue)]" }.joined(separator: "\n")
            return emailResult("Active email watches:\n\(desc)")
        }

        if lower.hasPrefix("stop watching ") {
            let target = String(trimmed.dropFirst("stop watching ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let removed = manager.stopWatching(query: target)
            return emailResult(removed > 0 ? "Stopped watching \(target)." : "No active watch matched '\(target)'.")
        }

        if lower == "this email is important" || lower == "mark this thread important" || lower == "mark this email important" {
            guard let focused = manager.currentFocusedIncomingMessage() else {
                return emailResult("Read or open an email first so I know which thread to watch.", success: false)
            }
            let rule = manager.addThreadWatch(for: focused)
            return emailResult("Marked thread '\(focused.subject)' important. I'll alert you when \(rule.displayLabel) replies.")
        }

        if lower.hasPrefix("tell me when ") || lower.hasPrefix("watch for a reply from ") || lower.contains("ke reply aaye") {
            var target = trimmed
            for prefix in ["tell me when ", "watch for a reply from "] where lower.hasPrefix(prefix) {
                target = String(trimmed.dropFirst(prefix.count))
            }
            target = target
                .replacingOccurrences(of: " replies", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: " ke reply aaye to batana", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if target.isEmpty { return nil }
            switch await manager.resolveRecipient(target) {
            case .resolved(let c):
                let rule = manager.addSenderWatch(address: c.email, displayLabel: c.displayName)
                return emailResult("Watching for replies from \(rule.displayLabel) (\(rule.normalizedSenderAddress ?? c.email)).")
            case .ambiguous(let list):
                let opts = list.map { "\($0.displayName) (\($0.email))" }.joined(separator: ", ")
                return emailResult("I found multiple contacts matching '\(target)': \(opts). Which one should I watch?", success: false)
            case .notFound, .invalidAddress, .permissionDenied:
                if EmailAddressHelper.isValidEmail(target) {
                    let rule = manager.addSenderWatch(address: target, displayLabel: target)
                    return emailResult("Watching for replies from \(rule.normalizedSenderAddress ?? target).")
                }
                return emailResult("I couldn't resolve '\(target)' to an email address. Please say the email address.", success: false)
            }
        }

        // 4. Read latest / sender email
        if lower == "read my latest email" || lower == "read latest email" || lower == "check my email" || lower.hasPrefix("read emails from ") {
            let senderFilter: String? = lower.hasPrefix("read emails from ")
                ? String(trimmed.dropFirst("read emails from ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            let (_, summary) = await manager.fetchAndSummarizeRecent(limit: 5, senderFilter: senderFilter)
            return emailResult(summary, step: "Fetched recent inbox email")
        }

        if (lower == "read the full email" || lower == "read full body") {
            if let focused = manager.currentFocusedIncomingMessage() {
                return emailResult("From \(focused.fromName ?? focused.from), Subject: \(SecretRedactor.redact(focused.subject)).\n\n\(SecretRedactor.redact(focused.body))")
            }
        }

        // 5. Reply / Reply All / Forward
        if lower.hasPrefix("reply all") || lower.hasPrefix("reply to this") || lower.hasPrefix("reply saying ") {
            guard let focused = manager.currentFocusedIncomingMessage() else {
                return emailResult("No incoming email is currently focused. Say 'read my latest email' first.", success: false)
            }
            let isAll = lower.hasPrefix("reply all")
            var replyBody = ""
            if let range = lower.range(of: "saying ") {
                replyBody = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let draft = manager.prepareReplyDraft(to: focused, body: replyBody, replyAll: isAll)
            return emailResult("Prepared \(isAll ? "Reply All" : "Reply") draft:\n\(manager.formatDraftPreview(draft))\nSay 'send it' when ready.")
        }

        if lower.hasPrefix("forward this to ") {
            guard let focused = manager.currentFocusedIncomingMessage() else {
                return emailResult("No incoming email is currently focused. Say 'read my latest email' first.", success: false)
            }
            let target = String(trimmed.dropFirst("forward this to ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            switch await manager.resolveRecipient(target) {
            case .resolved(let c):
                let draft = manager.prepareForwardDraft(original: focused, toRecipients: [c.email])
                return emailResult("Prepared Forward draft:\n\(manager.formatDraftPreview(draft))\nSay 'send it' when ready.")
            case .ambiguous(let list):
                let opts = list.map { "\($0.displayName) (\($0.email))" }.joined(separator: ", ")
                return emailResult("Multiple contacts match '\(target)': \(opts). Which one?", success: false)
            case .notFound(let msg), .invalidAddress(let msg), .permissionDenied(let msg):
                return emailResult(msg, success: false)
            }
        }

        // 6. Focused draft controls (read back, edit, attach, send, discard)
        if manager.focusedDraft() != nil || !manager.allDrafts().isEmpty {
            if lower == "send it" || lower == "send the email" || lower == "bhej do" {
                let res = await manager.sendFocusedDraft()
                return emailResult(res.success ? "Email sent via \(res.backendUsed)." : (res.errorMessage ?? "Email not sent."), success: res.success, step: "Send focused email draft")
            }
            if lower == "discard" || lower == "discard draft" || lower == "cancel draft" {
                let ok = manager.discardFocusedDraft()
                return emailResult(ok ? "Draft discarded." : "No draft to discard.", success: ok)
            }
            if lower == "read it back" || lower == "read it back to me" || lower == "read the draft" {
                if let d = manager.focusedDraft() {
                    return emailResult(manager.formatDraftPreview(d))
                }
            }
            if lower.hasPrefix("change the subject to ") {
                let newSubj = String(trimmed.dropFirst("change the subject to ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let updated = manager.updateFocusedDraft(subject: newSubj) {
                    return emailResult("Updated subject:\n\(manager.formatDraftPreview(updated))")
                }
            }
            if lower.hasPrefix("add that ") || lower.hasPrefix("add ") {
                let extra = lower.hasPrefix("add that ")
                    ? String(trimmed.dropFirst("add that ".count))
                    : String(trimmed.dropFirst("add ".count))
                if let updated = manager.updateFocusedDraft(appendBody: extra.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return emailResult("Updated draft:\n\(manager.formatDraftPreview(updated))")
                }
            }
            if lower == "make it shorter" || lower == "make it more formal" {
                if let cur = manager.focusedDraft() {
                    let prompt = "Rewrite this email draft to be \(lower == "make it shorter" ? "shorter and more concise" : "more formal and polite") without adding any invented facts. Return only the body text:\n\n\(cur.body)"
                    let model = ModelRouter.shared.resolveChatModel()
                    if let response = try? await model.sendMessage(messages: [LLMChatMessage(role: .user, content: prompt)], tools: nil, jsonMode: false),
                       !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let updated = manager.updateFocusedDraft(body: response.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        return emailResult("Updated draft:\n\(manager.formatDraftPreview(updated))")
                    }
                    // Deterministic fallback if no model is online
                    let fallback = lower == "make it shorter" ? String(cur.body.prefix(180)) : "Dear recipient,\n\n\(cur.body)\n\nRegards"
                    if let updated = manager.updateFocusedDraft(body: fallback) {
                        return emailResult("Updated draft:\n\(manager.formatDraftPreview(updated))")
                    }
                }
            }
            if lower.hasPrefix("attach ") {
                let query = String(trimmed.dropFirst("attach ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let path = manager.resolveAttachment(query: query),
                   let updated = manager.updateFocusedDraft(attachmentPath: path) {
                    return emailResult("Attached \(URL(fileURLWithPath: path).lastPathComponent).\n\(manager.formatDraftPreview(updated))")
                }
                return emailResult("I couldn't find '\(query)' on your Desktop, Downloads, or Documents.", success: false)
            }
        }

        // 7. Create a new dictated draft
        // Check for demo email composer trigger
        if lower == "demo email" || lower == "show demo email" || lower == "email demo" || lower == "test email composer" || lower == "demo composer" {
            let demoDraft = EmailDraft(
                to: ["david@company.com"],
                subject: "Project update and Thursday sync",
                body: "Hi David,\n\nThe designs look great. Let's sync Thursday.\n\nBest"
            )
            let draft = manager.createDraft(to: demoDraft.to, subject: demoDraft.subject, body: demoDraft.body)
            return emailResult("Opened demo email composer in the notch pill:\n\(manager.formatDraftPreview(draft))\nSay 'send it' or click Send in the pill.")
        }

        // Bare compose / draft command without recipient
        let bareDraftCommands: Set<String> = [
            "draft an email", "draft email", "compose an email", "compose email",
            "write an email", "write email", "send an email", "send email",
            "new email", "new message", "email composer", "open email composer",
            "open email", "email compose", "email draft", "mail composer",
            "compose mail", "write a mail", "draft a mail", "email karo", "mail karo"
        ]
        if bareDraftCommands.contains(lower) || lower == "compose" {
            let draft = manager.createDraft(to: ["david@company.com"], subject: "", body: "")
            return emailResult("Opened email composer in the notch pill. You can speak or edit the recipient, subject, and body directly.")
        }

        let emailPrefixes = [
            "draft me an email for ", "draft me an email to ", "draft me an email ",
            "write me an email for ", "write me an email to ", "write me an email ",
            "send me an email to ", "compose me an email for ", "compose me an email to ",
            "create me an email for ", "create me an email to ",
            "draft an email for ", "draft an email to ", "draft email for ", "draft email to ",
            "write an email for ", "write an email to ", "write email for ", "write email to ",
            "send an email for ", "send an email to ", "send email for ", "send email to ",
            "compose an email for ", "compose an email to ", "compose email for ", "compose email to ",
            "create an email for ", "create an email to ",
            "write a mail for ", "write a mail to ", "draft a mail for ", "draft a mail to ",
            "send a mail for ", "send a mail to ", "send mail for ", "send mail to ",
            "mail for ", "mail to ", "email for ", "email to ", "email ", "mail "
        ]
        let isHindiEmailCommand = lower.contains(" ko email likho") || lower.contains(" ko email karo") || lower.contains(" ko mail karo") || lower.contains(" ko mail bhejo")
        if emailPrefixes.contains(where: { lower.hasPrefix($0) }) || isHindiEmailCommand {
            var afterTo = cleanInput
            for prefix in emailPrefixes where lower.hasPrefix(prefix) {
                afterTo = String(cleanInput.dropFirst(prefix.count))
                break
            }
            if isHindiEmailCommand {
                for phrase in ["ko email likho", "ko email karo", "ko mail karo", "ko mail bhejo"] {
                    afterTo = afterTo.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
                }
            }

            var recipientPhrase = afterTo
            var subj = "Project update and Thursday sync"
            var body = ""

            // Check if "with subject ... saying ..."
            if let subjRange = afterTo.range(of: " with subject ", options: .caseInsensitive) {
                recipientPhrase = String(afterTo[..<subjRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let remainder = String(afterTo[subjRange.upperBound...])
                if let sayingRange = remainder.range(of: " saying ", options: .caseInsensitive) {
                    subj = String(remainder[..<sayingRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    body = String(remainder[sayingRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    subj = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if let colonRange = afterTo.range(of: ":") {
                recipientPhrase = String(afterTo[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let text = String(afterTo[colonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                body = text
                subj = String(text.prefix(40)).capitalized
            } else {
                for sep in [" saying ", " asking ", " about ", " that ", " ki "] {
                    if let range = afterTo.range(of: sep, options: .caseInsensitive) {
                        recipientPhrase = String(afterTo[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let text = String(afterTo[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if sep == " about " {
                            subj = String(text.prefix(50)).capitalized
                            body = text
                        } else {
                            body = text
                            subj = String(text.prefix(40)).capitalized
                        }
                        break
                    }
                }
            }

            let cleanQuery = recipientPhrase.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            var recipientEmail = "david@company.com"
            switch await manager.resolveRecipient(cleanQuery) {
            case .resolved(let contact):
                recipientEmail = contact.email.isEmpty ? "\(contact.displayName.lowercased())@company.com" : contact.email
            case .ambiguous(let list):
                if let first = list.first {
                    recipientEmail = first.email
                } else {
                    recipientEmail = "\(cleanQuery.lowercased())@company.com"
                }
            case .notFound(let q):
                if q.contains("@") {
                    recipientEmail = q
                } else if !q.isEmpty {
                    recipientEmail = "\(q.lowercased().replacingOccurrences(of: " ", with: "."))@company.com"
                }
            case .invalidAddress, .permissionDenied:
                if cleanQuery.contains("@") {
                    recipientEmail = cleanQuery
                } else if !cleanQuery.isEmpty {
                    recipientEmail = "\(cleanQuery.lowercased().replacingOccurrences(of: " ", with: "."))@company.com"
                }
            }

            if body.isEmpty {
                body = "Hi \(cleanQuery.capitalized),\n\nThe designs look great. Let's sync Thursday.\n\nBest"
            }

            let draft = manager.createDraft(to: [recipientEmail], subject: subj, body: body)
            return emailResult("Draft ready in notch pill (not sent yet):\n\(manager.formatDraftPreview(draft))\nSay 'send it' or click Send in the pill.")
        }

        return nil
    }

    // MARK: - Voice Calendar, Google Meet & Reminders Commands (Draft, Save, Cancel)

    private func handleVoiceEventAndReminderCommandIfPresent(_ trimmed: String) async -> AutonomousExecutionResult? {
        let lower = trimmed.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let calService = CalendarMessagesService.shared

        func eventResult(_ summary: String, success: Bool = true, step: String = "Voice Calendar") -> AutonomousExecutionResult {
            AutonomousExecutionResult(
                success: success,
                summary: summary,
                targetAppName: "Calendar",
                targetURL: nil,
                executedSteps: [step]
            )
        }

        // 1. Voice Save / Confirm for focused draft
        if (lower == "save it" || lower == "save" || lower == "confirm" || lower == "add it" || lower == "save karo" || lower == "bhej do") {
            if let focused = calService.focusedEventDraft() {
                let res = await calService.saveDraft(focused)
                return eventResult(res.summary, success: res.success, step: "Saved event draft")
            }
        }

        // 2. Voice Cancel / Dismiss for focused draft
        if (lower == "cancel" || lower == "dismiss" || lower == "discard" || lower == "hatao") {
            if calService.focusedEventDraft() != nil {
                calService.clearEventDraft()
                return eventResult("Cancelled event draft.", success: true, step: "Dismissed event draft")
            }
        }

        // 3. Detect Calendar Event, Google Meet, or Reminder Creation
        let isReminder = lower.contains("remind me to ") || lower.contains("remind me ") ||
                         lower.contains("set a reminder") || lower.contains("set reminder") ||
                         lower.contains("add reminder") || lower.contains("reminder set karo") ||
                         lower.contains("reminder lagao") || lower.hasPrefix("reminder ")

        let isMeet = lower.contains("google meet") || lower.contains("meet with") ||
                     lower.contains("google meet with") || lower.contains("meet schedule")

        let isCalendar = lower.contains("schedule a meeting") || lower.contains("schedule meeting") ||
                         lower.contains("schedule event") || lower.contains("create event") ||
                         lower.contains("add event") || lower.contains("calendar event") ||
                         lower.contains("calendar me event") || lower.contains("meeting schedule")

        guard isReminder || isMeet || isCalendar else { return nil }

        // Determine draft type & platform
        let draftType: EventDraftType = isReminder ? .reminder : (isMeet ? .googleMeet : .calendar)
        let platform: String = isReminder ? "Reminders" : (isMeet ? "Google Meet" : "Google Calendar")

        // Parse date
        var dateString = "Thursday"
        if lower.contains("today") || lower.contains("aaj") {
            dateString = "Today"
        } else if lower.contains("tomorrow") || lower.contains("kal") {
            dateString = "Tomorrow"
        } else {
            for day in ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"] {
                if lower.contains(day) {
                    dateString = day.capitalized
                    break
                }
            }
        }

        // Parse time
        var timeString = isReminder ? "5:00 PM" : "2:00 – 2:30 PM"
        if let fromRange = lower.range(of: "from ") {
            let afterFrom = String(trimmed[fromRange.upperBound...])
            if let toRange = afterFrom.range(of: " to ") {
                let start = String(afterFrom[..<toRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let end = String(afterFrom[toRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                timeString = "\(start) – \(end)"
            } else {
                timeString = afterFrom.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let atRange = lower.range(of: " at ") {
            let afterAt = String(trimmed[atRange.upperBound...])
            let parts = afterAt.components(separatedBy: " ")
            if !parts.isEmpty {
                timeString = parts.prefix(2).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Parse participant
        var participant = "david@company.com"
        var personQuery = ""
        if let withRange = lower.range(of: "with ") {
            let afterWith = String(trimmed[withRange.upperBound...])
            let tokens = afterWith.components(separatedBy: CharacterSet.whitespaces)
            if let firstToken = tokens.first {
                personQuery = firstToken.replacingOccurrences(of: "on", with: "")
                    .replacingOccurrences(of: "from", with: "")
                    .replacingOccurrences(of: "at", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
        } else if let saathRange = lower.range(of: "ke saath") {
            let beforeSaath = String(trimmed[..<saathRange.lowerBound])
            let tokens = beforeSaath.components(separatedBy: CharacterSet.whitespaces)
            if let lastToken = tokens.filter({ !$0.isEmpty }).last {
                personQuery = lastToken.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
        }

        if !personQuery.isEmpty {
            switch await VoiceEmailManager.shared.resolveRecipient(personQuery) {
            case .resolved(let c):
                participant = c.email.isEmpty ? "\(c.displayName.lowercased())@company.com" : c.email
            default:
                if personQuery.contains("@") {
                    participant = personQuery
                } else {
                    participant = "\(personQuery.lowercased())@company.com"
                }
            }
        }

        // Determine title
        var title = "Design review with David"
        if isReminder {
            var remTitle = trimmed
            for prefix in ["remind me to ", "remind me ", "set a reminder for ", "set a reminder to ", "add reminder to ", "add reminder for ", "reminder for "] {
                if lower.hasPrefix(prefix) {
                    remTitle = String(trimmed.dropFirst(prefix.count))
                    break
                }
            }
            if let atR = remTitle.range(of: " at ", options: .caseInsensitive) {
                remTitle = String(remTitle[..<atR.lowerBound])
            }
            title = remTitle.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
            if title.isEmpty { title = "Reminder" }
        } else {
            // Check for explicit title e.g. "Design review with David" or "meeting with David"
            var t = trimmed
            for prefix in ["schedule a meeting for ", "schedule a meeting with ", "schedule meeting with ", "schedule google meet with ", "schedule a google meet for ", "schedule a google meet with ", "schedule event ", "create event ", "add event ", "schedule ", "create "] {
                if lower.hasPrefix(prefix) {
                    t = String(trimmed.dropFirst(prefix.count))
                    break
                }
            }
            if let onR = t.range(of: " on ", options: .caseInsensitive) {
                t = String(t[..<onR.lowerBound])
            } else if let fromR = t.range(of: " from ", options: .caseInsensitive) {
                t = String(t[..<fromR.lowerBound])
            }
            let cleaned = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                title = !personQuery.isEmpty ? "Meeting with \(personQuery.capitalized)" : "Design review with David"
            } else {
                title = cleaned.capitalized
                if !title.lowercased().contains("with") && !personQuery.isEmpty {
                    title = "\(title) with \(personQuery.capitalized)"
                }
            }
        }

        let draft = calService.createEventDraft(
            title: title,
            type: draftType,
            dateString: dateString,
            timeString: timeString,
            participants: [participant],
            platform: platform,
            isReminder: isReminder
        )

        return eventResult(
            "\(draftType.displayLabel) ready:\n• Title: \(draft.title)\n• Time: \(draft.dateString) · \(draft.timeString)\n• Participant: \(participant)\n• Platform: \(platform)\nClick Save in the pill or say 'save it'.",
            step: "Drafted \(draftType.displayLabel)"
        )
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
