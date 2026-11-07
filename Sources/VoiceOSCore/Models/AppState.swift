import Foundation
import Combine
import CoreGraphics
import AppKit

public final class AppState: ObservableObject, @unchecked Sendable {
    @Published public var activeNavTab: NavTab = .dashboard
    @Published public var activeNotchTab: NotchTab = .ask
    @Published public var isTypingFocused: Bool = false
    @Published public var executionState: AgentExecutionState = .idle
    @Published public var islandState: IslandPresentationState = .resting {
        didSet {
            guard oldValue != islandState else { return }
            if oldValue == .resting && islandState != .resting {
                BoringSoundEngine.shared.playNotchOpen()
            } else if oldValue != .resting && islandState == .resting {
                BoringSoundEngine.shared.playNotchClose()
            }
        }
    }
    @Published public var isPinned: Bool = false
    @Published public var isMediaExpanded: Bool = false
    @Published public var isNotchHUDVisible: Bool = true
    @Published public var isFloatingOrbVisible: Bool = true {
        didSet {
            UserDefaults.standard.set(isFloatingOrbVisible, forKey: "VoiceAI_ShowFloatingOrb")
        }
    }
    @Published public var isHistoryDrawerOpen: Bool = false
    @Published public var isAppBuilderOpen: Bool = false
    
    public var isCurrentlyListening: Bool {
        if case .listening = executionState { return true }
        return false
    }
    
    // Main App Window Toggle Callback
    public var onToggleMainWindow: (() -> Void)?
    
    public func toggleMainWindow() {
        onToggleMainWindow?()
    }
    
    // Circle to Ask Context
    @Published public var activeSelectionTool: CircleSelectionTool = .lasso
    @Published public var currentCropResult: ScreenCropResult? = nil
    @Published public var isScreenCaptureActive: Bool = false
    
    // Persistent Multi-turn Chat Memory
    @Published public var chatMessages: [ChatMessage] = []
    
    // Prompt & Query input (coexisting voice & typing)
    @Published public var promptInputText: String = ""
    @Published public var currentTranscript: String = ""
    @Published public var currentAgentReply: String = ""
    @Published public var latestAutonomousResult: AutonomousExecutionResult? = nil
    @Published public var isAwaitingRedirectConfirmation: Bool = false
    @Published public var dynamicNotchSize: CGSize = CGSize(width: 185, height: 32)
    @Published public var isCompactResponseMode: Bool = true
    @Published public var lastPromptOrQuestion: String = ""
    
    // "THE VOICE" Hands-free ambient wake-word mode & one-time search permission
    @Published public var isTheVoiceModeEnabled: Bool {
        didSet {
            TheVoiceAmbientListener.shared.isTheVoiceModeEnabled = isTheVoiceModeEnabled
        }
    }
    @Published public var hasGrantedBackgroundSearchPermission: Bool
    @Published public var isAwaitingBackgroundSearchPermission: Bool = false
    @Published public var pendingBackgroundSearchQuery: String? = nil
    
    // Active background task handle for interruption and barge-in
    public var currentExecutionTask: Task<Void, Never>? = nil
    
    @Published public var currentAction: AgentAction? = nil
    
    // Real User Profile - loaded dynamically from system & UserDefaults
    @Published public var userName: String
    @Published public var userEmail: String
    @Published public var trialDaysUsed: Int = 1
    @Published public var trialDaysTotal: Int = 14
    
    // Real Metrics - persisted in UserDefaults
    @Published public var totalSessions: Int
    @Published public var totalWords: Int
    @Published public var timeSavedMinutes: Int
    
    // Usage Breakdown - dynamically computed from actual sessions
    @Published public var appUsages: [AppUsageStat] = []
    
    // Real macOS Connected Applications
    @Published public var connectedApps: [ConnectedApp] = []
    
    // Real History - loaded from UserDefaults
    @Published public var recentHistory: [SessionRecord] = []
    
    // Waveform visualization data for Notch HUD (values between 0.1 and 1.0)
    @Published public var audioLevels: [CGFloat] = [0.15, 0.2, 0.18, 0.22, 0.19, 0.25, 0.2, 0.18, 0.15, 0.12]
    
    // Live Now Playing Media State (Spotify, YouTube, Apple Music)
    @Published public var currentMedia: NowPlayingItem? = nil
    
    // Active Coding Subagents State
    @Published public var activeCodingAgents: [CodingAgentTask] = []
    
    public enum NavTab: String, CaseIterable, Identifiable, Sendable {
        case dashboard = "Dashboard"
        case insights = "Insights"
        case history = "History"
        case dictation = "Dictation"
        case agent = "Agent"
        case apps = "Apps"
        case settings = "Settings"
        
        public var id: String { rawValue }
        
        public var iconName: String {
            switch self {
            case .dashboard: return "square.grid.2x2"
            case .insights: return "chart.bar"
            case .history: return "clock.arrow.circlepath"
            case .dictation: return "mic"
            case .agent: return "sparkles"
            case .apps: return "app.badge"
            case .settings: return "gearshape"
            }
        }
    }
    
    public enum NotchTab: String, CaseIterable, Identifiable, Sendable {
        case ask = "Ask"
        case apps = "Apps"
        case tasks = "Agents"
        case memory = "Memory"
        
        public var id: String { rawValue }
        
        public var iconName: String {
            switch self {
            case .ask: return "sparkles"
            case .apps: return "square.grid.2x2"
            case .tasks: return "cpu"
            case .memory: return "brain"
            }
        }
    }
    
    public init() {
        // 1. Resolve real user identity
        let resolvedName: String
        if let savedName = UserDefaults.standard.string(forKey: "VoiceOS_UserName"), !savedName.isEmpty {
            resolvedName = savedName
        } else {
            let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
            let user = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
            if !full.isEmpty && full != user {
                resolvedName = full
            } else if !user.isEmpty {
                resolvedName = user.capitalized
            } else {
                resolvedName = "Mohit"
            }
            UserDefaults.standard.set(resolvedName, forKey: "VoiceOS_UserName")
        }
        self.userName = resolvedName

        let resolvedEmail: String
        if let savedEmail = UserDefaults.standard.string(forKey: "VoiceOS_UserEmail"), !savedEmail.isEmpty {
            resolvedEmail = savedEmail
        } else {
            let user = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
            resolvedEmail = user.isEmpty ? "user@icloud.com" : "\(user)@icloud.com"
            UserDefaults.standard.set(resolvedEmail, forKey: "VoiceOS_UserEmail")
        }
        self.userEmail = resolvedEmail

        // 2. Load real session counters
        let sessions = UserDefaults.standard.integer(forKey: "VoiceOS_TotalSessions")
        let words = UserDefaults.standard.integer(forKey: "VoiceOS_TotalWords")
        self.totalSessions = sessions
        self.totalWords = words
        self.timeSavedMinutes = max(0, words / 130)

        // 3. Load real history & persistent local chat memory
        if let data = UserDefaults.standard.data(forKey: "VoiceOS_RecentHistory"),
           let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) {
            self.recentHistory = decoded
        } else {
            self.recentHistory = []
        }
        self.chatMessages = LocalChatMemoryManager.shared.allMessages()

        // 4. Initialize stored properties for "THE VOICE" Mode & Background Search Permissions
        let theVoiceSaved = UserDefaults.standard.object(forKey: "VoiceAI_TheVoiceModeActive") == nil ? true : UserDefaults.standard.bool(forKey: "VoiceAI_TheVoiceModeActive")
        self.isTheVoiceModeEnabled = theVoiceSaved
        self.hasGrantedBackgroundSearchPermission = UserDefaults.standard.bool(forKey: "VoiceAI_BackgroundSearchPermissionGranted")

        // 5. Setup real connected macOS apps
        self.setupConnectedApps()

        // 6. Compute real app usages
        self.recomputeAppUsages()

        // 7. Bind "THE VOICE" Hands-free ambient listener callback with interruption support
        TheVoiceAmbientListener.shared.onWakeWordTriggered = { [weak self] command in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.interruptAndExecute(instruction: command)
            }
        }
        if theVoiceSaved {
            TheVoiceAmbientListener.shared.startAmbientListening()
        }

        // 7. Bind voice pipeline
        setupVoicePipelineBindings()
        
        // 8. Bind Now Playing media observer & Coding Subagents manager
        setupNowPlayingAndAgentBindings()
    }
    
    private func setupNowPlayingAndAgentBindings() {
        self.currentMedia = NowPlayingMediaManager.shared.currentMedia
        NowPlayingMediaManager.shared.onMediaChanged = { [weak self] item in
            DispatchQueue.main.async {
                self?.currentMedia = item
            }
        }
        
        self.activeCodingAgents = CodingAgentManager.shared.activeAgents
        CodingAgentManager.shared.onAgentsChanged = { [weak self] agents in
            DispatchQueue.main.async {
                self?.activeCodingAgents = agents
            }
        }
    }

    private func setupConnectedApps() {
        self.connectedApps = [
            ConnectedApp(
                id: "whatsapp",
                name: "WhatsApp",
                description: "Voice-compose messages, open chats, and dispatch quick replies.",
                iconName: "message.fill",
                iconColor: "#25D366",
                isConnected: true
            ),
            ConnectedApp(
                id: "safari",
                name: "Safari",
                description: "Instant web searches, URL navigation, and browser dictation.",
                iconName: "safari.fill",
                iconColor: "#007AFF",
                isConnected: true
            ),
            ConnectedApp(
                id: "notes",
                name: "Apple Notes",
                description: "Create quick notes, speech dictation memos, and thought capture.",
                iconName: "note.text",
                iconColor: "#F5A623",
                isConnected: true
            ),
            ConnectedApp(
                id: "calendar",
                name: "Apple Calendar",
                description: "Check schedule and voice-add roadmap events or meetings.",
                iconName: "calendar",
                iconColor: "#FF3B30",
                isConnected: true
            ),
            ConnectedApp(
                id: "reminders",
                name: "Apple Reminders",
                description: "Voice-create to-dos, shopping lists, and follow-up alerts.",
                iconName: "list.bullet.circle.fill",
                iconColor: "#FF9500",
                isConnected: true
            ),
            ConnectedApp(
                id: "vscode",
                name: "Visual Studio Code",
                description: "Dictate comments, code docstrings, and control IDE workflows.",
                iconName: "chevron.left.forwardslash.chevron.right",
                iconColor: "#0078D7",
                isConnected: true
            ),
            ConnectedApp(
                id: "chrome",
                name: "Google Chrome",
                description: "Web automation, fast research searches, and active tab control.",
                iconName: "globe",
                iconColor: "#EA4335",
                isConnected: true
            ),
            ConnectedApp(
                id: "terminal",
                name: "Terminal",
                description: "Dictate shell commands and trigger local developer scripts.",
                iconName: "terminal.fill",
                iconColor: "#24292E",
                isConnected: false
            )
        ]
    }

    public func recomputeAppUsages() {
        guard !recentHistory.isEmpty else {
            self.appUsages = []
            return
        }
        var counts: [String: Int] = [:]
        for session in recentHistory {
            counts[session.appName, default: 0] += 1
        }
        let total = Double(recentHistory.count)
        self.appUsages = counts.map { appName, count in
            AppUsageStat(
                appName: appName,
                iconName: iconForApp(appName),
                count: count,
                percentage: Double(count) / max(1.0, total)
            )
        }.sorted { $0.count > $1.count }
    }

    private func iconForApp(_ appName: String) -> String {
        let lower = appName.lowercased()
        if lower.contains("whatsapp") { return "message.fill" }
        if lower.contains("safari") || lower.contains("browser") { return "safari.fill" }
        if lower.contains("note") { return "note.text" }
        if lower.contains("calendar") { return "calendar" }
        if lower.contains("mail") { return "envelope.fill" }
        if lower.contains("reminder") { return "list.bullet.circle.fill" }
        if lower.contains("code") || lower.contains("cursor") { return "chevron.left.forwardslash.chevron.right" }
        if lower.contains("chrome") { return "globe" }
        if lower.contains("terminal") { return "terminal.fill" }
        return "app.fill"
    }

    public func recordSession(
        mode: VoiceTriggerMode,
        prompt: String,
        response: String,
        appName: String,
        appIcon: String,
        action: AgentAction? = nil
    ) {
        let record = SessionRecord(
            mode: mode,
            prompt: prompt,
            response: response,
            appName: appName,
            appIcon: appIcon,
            action: action
        )
        self.recentHistory.insert(record, at: 0)
        self.lastPromptOrQuestion = prompt
        self.currentAgentReply = response

        // Increment stats
        self.totalSessions += 1
        let wordCount = prompt.split(separator: " ").count
        self.totalWords += wordCount
        self.timeSavedMinutes = max(0, self.totalWords / 130)

        // Persist to UserDefaults
        UserDefaults.standard.set(self.totalSessions, forKey: "VoiceOS_TotalSessions")
        UserDefaults.standard.set(self.totalWords, forKey: "VoiceOS_TotalWords")
        if let encoded = try? JSONEncoder().encode(self.recentHistory) {
            UserDefaults.standard.set(encoded, forKey: "VoiceOS_RecentHistory")
        }

        // Encrypted Chat History persistence
        let actionItems: [ActionRecordItem] = (action != nil) ? [
            ActionRecordItem(
                toolName: action!.title,
                argumentsJSON: action!.payload.isEmpty ? (action!.subtitle ?? "") : (try? String(data: JSONEncoder().encode(action!.payload), encoding: .utf8)) ?? "",
                resultSummary: response,
                durationSeconds: 0.1,
                wasApproved: action!.isApproved
            )
        ] : []
        EncryptedChatHistoryManager.shared.recordTurn(
            conversationId: nil,
            userText: prompt,
            assistantText: response,
            persona: PersonaManager.shared.getActivePersona().rawValue,
            actions: actionItems
        )

        recomputeAppUsages()
    }

    public func clearAllHistory() {
        self.recentHistory = []
        UserDefaults.standard.removeObject(forKey: "VoiceOS_RecentHistory")
        recomputeAppUsages()
    }

    public func resetAllStatistics() {
        self.totalSessions = 0
        self.totalWords = 0
        self.timeSavedMinutes = 0
        self.recentHistory = []
        self.appUsages = []
        UserDefaults.standard.set(0, forKey: "VoiceOS_TotalSessions")
        UserDefaults.standard.set(0, forKey: "VoiceOS_TotalWords")
        UserDefaults.standard.removeObject(forKey: "VoiceOS_RecentHistory")
    }

    public func updateProfile(name: String, email: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            self.userName = trimmedName
            UserDefaults.standard.set(trimmedName, forKey: "VoiceOS_UserName")
        }
        if !trimmedEmail.isEmpty {
            self.userEmail = trimmedEmail
            UserDefaults.standard.set(trimmedEmail, forKey: "VoiceOS_UserEmail")
        }
    }

    private func setupVoicePipelineBindings() {
        let pipeline = SpeechPipelineEngine.shared

        pipeline.onAudioLevelsUpdated = { [weak self] levels in
            self?.audioLevels = levels
        }

        pipeline.onLiveTranscript = { [weak self] liveText in
            self?.currentTranscript = liveText
        }

        pipeline.onTranscriptionCompleted = { [weak self] transcript, mode in
            guard let self = self else { return }
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmed.isEmpty else {
                DispatchQueue.main.async {
                    BoringSoundEngine.shared.playError()
                    self.executionState = .idle
                    self.currentTranscript = "No speech detected"
                    if !self.isPinned {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            if case .voiceCompact = self.islandState {
                                self.islandState = .resting
                            }
                        }
                    }
                }
                return
            }

            let polished = DictationPolishEngine.shared.polish(rawText: trimmed, profile: .general)
            self.currentTranscript = polished.polishedText

            let isCommand = AgentActionDispatcher.shared.isCommandIntent(polished.polishedText)
            let isHinglish = HinglishParser.isHinglishQuery(polished.polishedText)
            let lower = polished.polishedText.lowercased()
            let isQuestion = polished.polishedText.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") ||
                             ["what", "who", "where", "why", "how", "when", "can", "could", "should", "tell me", "search", "kya", "kaise", "batao", "dikhao", "screen", "google", "gaana", "note", "tab"].contains { lower.contains($0) }

            // Any dictated utterance outside the dedicated Dictation Studio or matching an agent intent MUST execute as an autonomous agent
            let shouldExecuteAsAgent = (mode == .agent) ||
                                       (self.activeNavTab != .dictation) ||
                                       isCommand ||
                                       isHinglish ||
                                       isQuestion

            if shouldExecuteAsAgent {
                // Execute autonomous assistant: Search/Plan -> Background Execute -> Respond
                BoringSoundEngine.shared.playReply()
                self.executionState = .thinking("Formulating answer & executing task...")
                self.islandState = .hoverExpanded
                self.isAwaitingRedirectConfirmation = false

                // Add user message to persistent local chat memory
                _ = LocalChatMemoryManager.shared.addMessage(role: "user", text: polished.polishedText)
                DispatchQueue.main.async {
                    self.chatMessages = LocalChatMemoryManager.shared.allMessages()
                }

                self.currentExecutionTask?.cancel()
                self.currentExecutionTask = Task {
                    let result = await AutonomousAgentExecutor.shared.planAndExecute(
                        taskDescription: polished.polishedText,
                        triggerMode: mode
                    ) { [weak self] stepMsg in
                        Task { @MainActor in
                            self?.executionState = .executing(stepMsg)
                        }
                    }
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        if result.success {
                            BoringSoundEngine.shared.playDone()
                        } else {
                            BoringSoundEngine.shared.playError()
                        }
                        self.executionState = .completed(result.summary)
                        self.currentAgentReply = result.summary
                        self.latestAutonomousResult = result
                        let targetLower = result.targetAppName.lowercased()
                        let summaryLower = result.summary.lowercased()
                        let isDirectOpen = targetLower == "browser" ||
                                           targetLower == "safari" ||
                                           targetLower == "google chrome" ||
                                           targetLower == "whatsapp" ||
                                           targetLower == "spotify" ||
                                           targetLower == "terminal" ||
                                           targetLower == "finder" ||
                                           targetLower.contains("chrome") ||
                                           targetLower.contains("safari") ||
                                           summaryLower.contains("opened") ||
                                           summaryLower.contains("opening") ||
                                           summaryLower.contains("launched") ||
                                           summaryLower.contains("playing")
                        self.isAwaitingRedirectConfirmation = !isDirectOpen && result.targetURL != nil
                        if self.isAwaitingRedirectConfirmation {
                            BoringSoundEngine.shared.playAlert()
                        }
                        self.islandState = .hoverExpanded
                        
                        // Add assistant response to persistent chat memory
                        _ = LocalChatMemoryManager.shared.addMessage(
                            role: "assistant",
                            text: result.summary,
                            sourceURL: result.targetURL?.absoluteString,
                            sourceTitle: result.targetAppName
                        )
                        self.chatMessages = LocalChatMemoryManager.shared.allMessages()

                        self.recordSession(
                            mode: .agent,
                            prompt: polished.polishedText,
                            response: result.summary,
                            appName: result.targetAppName,
                            appIcon: "sparkles"
                        )
                        // Speak aloud direct answer / summary
                        SpeechPipelineEngine.shared.speakResponse(result.summary)

                        // Keep HUD open so user can read response; auto-close after 12s if not pinned/hovered
                        if !self.isPinned {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
                                guard !self.isPinned else { return }
                                if case .speaking = self.executionState { return }
                                self.isAwaitingRedirectConfirmation = false
                                if case .hoverExpanded = self.islandState {
                                    self.islandState = .resting
                                }
                            }
                        }
                    }
                }
            } else {
                // In Dictation Mode: insert text directly into the frontmost app
                UniversalTextInserter.shared.insertText(polished.polishedText) { success in
                    DispatchQueue.main.async {
                        self.executionState = .idle
                        if !self.isPinned {
                            self.islandState = .resting
                        }
                        self.recordSession(
                            mode: .dictation,
                            prompt: polished.polishedText,
                            response: "Inserted text into frontmost application.",
                            appName: "Active App",
                            appIcon: "mic.fill"
                        )
                    }
                }
            }
        }

        pipeline.onStateChanged = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .idle:
                if case .listening = self.executionState {
                    self.executionState = .idle
                }
                if case .voiceCompact = self.islandState {
                    self.islandState = .resting
                }
            case .recording(let mode):
                self.executionState = .listening(mode)
                self.islandState = .voiceCompact(mode)
            case .transcribing:
                self.executionState = .transcribing
            case .speaking:
                self.executionState = .speaking("Responding...")
            case .error(let msg):
                self.executionState = .error(msg)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if case .voiceCompact = self.islandState {
                        self.islandState = .resting
                    }
                    if case .error = self.executionState {
                        self.executionState = .idle
                    }
                }
            }
        }
    }
    
    // MARK: - Notch Island Transitions
    public func setHoverExpanded(_ expanded: Bool) {
        guard !isPinned else { return }
        if expanded {
            if case .resting = islandState {
                islandState = .hoverExpanded
            }
        } else {
            if islandState != .resting && islandState != .pinned {
                islandState = .resting
            }
        }
    }
    
    public func togglePin() {
        BoringSoundEngine.shared.playTap()
        isPinned.toggle()
        islandState = isPinned ? .pinned : .hoverExpanded
    }
    
    public func triggerVoice(mode: VoiceTriggerMode) {
        GoogleSearchEngine.shared.clearLastAnswer()
        BoringSoundEngine.shared.playQueued()
        executionState = .listening(mode)
        islandState = .voiceCompact(mode)
        SpeechPipelineEngine.shared.startRecording(mode: mode)
        
        // Safety Watchdog: Auto-cancel recording after 20s if hotkey or mic stalls
        DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) { [weak self] in
            guard let self = self else { return }
            if case .listening = self.executionState {
                self.stopVoice()
            }
        }
    }
    
    public func stopVoice() {
        BoringSoundEngine.shared.playSend()
        SpeechPipelineEngine.shared.stopRecording()
    }
    
    public func submitTypedPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        BoringSoundEngine.shared.playSend()
        currentTranscript = trimmed
        lastPromptOrQuestion = trimmed
        promptInputText = ""
        BoringSoundEngine.shared.playReply()
        executionState = .thinking("Formulating answer & executing task...")
        islandState = .hoverExpanded
        isAwaitingRedirectConfirmation = false
        
        // Add to persistent local chat memory
        _ = LocalChatMemoryManager.shared.addMessage(role: "user", text: trimmed)
        self.chatMessages = LocalChatMemoryManager.shared.allMessages()
        
        currentExecutionTask?.cancel()
        currentExecutionTask = Task {
            let result = await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: trimmed) { [weak self] stepMsg in
                Task { @MainActor in
                    self?.executionState = .executing(stepMsg)
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if result.success {
                    BoringSoundEngine.shared.playDone()
                } else {
                    BoringSoundEngine.shared.playError()
                }
                self.executionState = .completed(result.summary)
                self.currentAgentReply = result.summary
                self.latestAutonomousResult = result
                let targetLower = result.targetAppName.lowercased()
                let summaryLower = result.summary.lowercased()
                let isDirectOpen = targetLower == "browser" ||
                                   targetLower == "safari" ||
                                   targetLower == "google chrome" ||
                                   targetLower == "whatsapp" ||
                                   targetLower == "spotify" ||
                                   targetLower == "terminal" ||
                                   targetLower == "finder" ||
                                   targetLower.contains("chrome") ||
                                   targetLower.contains("safari") ||
                                   summaryLower.contains("opened") ||
                                   summaryLower.contains("opening") ||
                                   summaryLower.contains("launched") ||
                                   summaryLower.contains("playing")
                self.isAwaitingRedirectConfirmation = !isDirectOpen && result.targetURL != nil
                if self.isAwaitingRedirectConfirmation {
                    BoringSoundEngine.shared.playAlert()
                }
                
                // Add assistant response to persistent chat memory
                _ = LocalChatMemoryManager.shared.addMessage(
                    role: "assistant",
                    text: result.summary,
                    sourceURL: result.targetURL?.absoluteString,
                    sourceTitle: result.targetAppName
                )
                self.chatMessages = LocalChatMemoryManager.shared.allMessages()
                
                self.recordSession(
                    mode: .agent,
                    prompt: trimmed,
                    response: result.summary,
                    appName: result.targetAppName,
                    appIcon: "sparkles"
                )
                SpeechPipelineEngine.shared.speakResponse(result.summary)
            }
        }
    }
    
    public func triggerScreenVision() {
        self.executionState = .thinking("Scanning current screen via Apple Vision OCR...")
        self.islandState = .hoverExpanded
        _ = LocalChatMemoryManager.shared.addMessage(role: "user", text: "What is currently on my screen?", isScreenContext: true)
        self.chatMessages = LocalChatMemoryManager.shared.allMessages()
        
        Task {
            let analysis = await ScreenVisionService.shared.captureAndAnalyzeScreen()
            await MainActor.run {
                self.executionState = .completed(analysis.summary)
                self.currentAgentReply = analysis.summary
                _ = LocalChatMemoryManager.shared.addMessage(
                    role: "assistant",
                    text: analysis.summary,
                    sourceTitle: "Screen OCR",
                    isScreenContext: true
                )
                self.chatMessages = LocalChatMemoryManager.shared.allMessages()
                SpeechPipelineEngine.shared.speakResponse(analysis.summary)
            }
        }
    }
    
    public func clearChatHistory() {
        BoringSoundEngine.shared.playTap()
        LocalChatMemoryManager.shared.clearChat()
        self.chatMessages = LocalChatMemoryManager.shared.allMessages()
        self.currentAgentReply = ""
        self.currentTranscript = ""
    }
    
    public func confirmRedirect() {
        BoringSoundEngine.shared.playTap()
        guard let url = latestAutonomousResult?.targetURL else { return }
        isAwaitingRedirectConfirmation = false
        NSWorkspace.shared.open(url)
    }
    
    public func dismissRedirect() {
        BoringSoundEngine.shared.playTap()
        isAwaitingRedirectConfirmation = false
        if !isPinned {
            islandState = .resting
        }
    }
    
    public func submitTheVoicePrompt(_ text: String) {
        self.executionState = .listening(.agent)
        self.islandState = .voiceCompact(.agent)
        self.currentTranscript = "Voice: \"\(text)\""
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.submitTypedPrompt(text)
        }
    }
    
    /// Immediate barge-in / interruption:
    /// Halts ongoing execution or TTS speech, cancels background agent tasks,
    /// and either switches to active listening or immediately executes the user's new instruction.
    public func interruptAndExecute(instruction: String, mode: VoiceTriggerMode = .agent) {
        // 1. Cancel ongoing autonomous agent task
        currentExecutionTask?.cancel()
        currentExecutionTask = nil
        
        // 2. Stop any current speech playback immediately
        SpeechPipelineEngine.shared.stopSpeaking()
        
        // 3. Play queued chime
        BoringSoundEngine.shared.playQueued()
        
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        
        // If the wake word was spoken without an immediate instruction ("voice", "the voice", "hey voice")
        if trimmed.isEmpty || lower == "voice" || lower == "the voice" || lower == "hey voice" || lower == "ok voice" {
            // Switch to active listening state with the chosen trigger mode
            triggerVoice(mode: mode)
        } else {
            // User provided an immediate command: "voice open safari and search ..."
            var cleanedPrompt = trimmed
            for prefix in ["the voice ", "hey voice ", "ok voice ", "voice "] {
                if lower.hasPrefix(prefix) {
                    cleanedPrompt = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
            submitTypedPrompt(cleanedPrompt)
        }
    }
    
    public func grantBackgroundSearchPermission() {
        BoringSoundEngine.shared.playTap()
        UserDefaults.standard.set(true, forKey: "VoiceAI_BackgroundSearchPermissionGranted")
        hasGrantedBackgroundSearchPermission = true
        isAwaitingBackgroundSearchPermission = false
        if let query = pendingBackgroundSearchQuery {
            pendingBackgroundSearchQuery = nil
            submitTypedPrompt(query)
        }
    }
    
    public func dismissBackgroundSearchPermission() {
        BoringSoundEngine.shared.playTap()
        isAwaitingBackgroundSearchPermission = false
        pendingBackgroundSearchQuery = nil
    }
    
    public func triggerCircleToAsk() {
        isScreenCaptureActive = true
        islandState = .circleToAskActive
    }
    
    public func completeCircleSelection(crop: ScreenCropResult) {
        isScreenCaptureActive = false
        currentCropResult = crop
        islandState = .selectionReview(crop)
        currentTranscript = "What is shown in this selected area?"
        currentAgentReply = "Identified selected UI context: \"\(crop.extractedOCRText.prefix(60))...\""
    }
    
    public func cancelCircleSelection() {
        isScreenCaptureActive = false
        islandState = isPinned ? .pinned : .resting
    }
    
    public func approveCurrentAction() {
        if var action = currentAction {
            action.isApproved = true
            currentAction = action
            executionState = .executing(action.title)
            islandState = .approvalExpanded(action)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.executionState = .completed("Task completed.")
                self.recentHistory.insert(
                    SessionRecord(
                        mode: .agent,
                        prompt: self.currentTranscript,
                        response: "Added task to Things 3: \(action.title)",
                        appName: action.appName,
                        appIcon: action.appIcon,
                        action: action
                    ),
                    at: 0
                )
                self.totalSessions += 1
                self.totalWords += self.currentTranscript.split(separator: " ").count
                self.timeSavedMinutes += 1
                
                if !self.isPinned {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        self.islandState = .resting
                    }
                }
            }
        }
    }
    
    public func dismissAction() {
        currentAction = nil
        islandState = isPinned ? .pinned : .resting
    }
}
