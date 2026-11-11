import Foundation
import Combine
import CoreGraphics
import AppKit

public final class AppState: ObservableObject, ToolApprovalPresenting, @unchecked Sendable {
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
    @Published public var isNotchMediaDisplayEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isNotchMediaDisplayEnabled, forKey: "VoiceAI_NotchMediaDisplayEnabled")
            VoiceOSConfigStore.shared.set("showMediaInNotch", value: isNotchMediaDisplayEnabled)
            if !isNotchMediaDisplayEnabled {
                isMediaExpanded = false
                currentMedia = nil
                NowPlayingMediaManager.shared.clearMedia()
            }
        }
    }
    @Published public var isNotchHUDVisible: Bool = true
    @Published public var isFloatingOrbVisible: Bool = true {
        didSet {
            UserDefaults.standard.set(isFloatingOrbVisible, forKey: "VoiceAI_ShowFloatingOrb")
        }
    }
    @Published public var isHistoryDrawerOpen: Bool = false
    @Published public var isHistorySidebarPinned: Bool = false
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
    
    // Persistent Multi-turn Chat Memory & Sessions
    @Published public var chatMessages: [ChatMessage] = []
    @Published public var chatSessions: [VoiceChatSession] = []
    @Published public var activeChatSessionId: String = ""
    
    // Prompt & Query input (coexisting voice & typing)
    @Published public var promptInputText: String = ""
    @Published public var currentTranscript: String = ""
    @Published public var currentAgentReply: String = ""
    @Published public var latestAutonomousResult: AutonomousExecutionResult? = nil
    @Published public var isAwaitingRedirectConfirmation: Bool = false
    @Published public var dynamicNotchSize: CGSize = CGSize(width: 185, height: 32)
    @Published public var isCompactResponseMode: Bool = true
    @Published public var lastPromptOrQuestion: String = ""
    @Published public var llmSuggestions: [BrainSuggestion] = []
    @Published public var isThinkingSuggestions: Bool = false
    @Published public var structuredMemories: [StructuredMemoryItem] = []
    @Published public var configuredRoutines: [VoiceRoutine] = []
    private var recordingWatchdogWorkItem: DispatchWorkItem?
    
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
    private var pendingApprovalContinuation: CheckedContinuation<Bool, Never>? = nil
    
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
    
    // Real macOS Connected Applications (persists enable/disable toggles into AppIntegrationEngine)
    @Published public var connectedApps: [ConnectedApp] = [] {
        didSet {
            for app in connectedApps {
                AppIntegrationEngine.shared.setAppIntegrated(app.id, enabled: app.isConnected)
            }
        }
    }
    
    // Real History - loaded from UserDefaults
    @Published public var recentHistory: [SessionRecord] = []
    
    // Waveform visualization data for Notch HUD (values between 0.1 and 1.0)
    @Published public var audioLevels: [CGFloat] = [0.15, 0.2, 0.18, 0.22, 0.19, 0.25, 0.2, 0.18, 0.15, 0.12]
    
    // Live Now Playing Media State (Spotify, YouTube, Apple Music)
    @Published public var currentMedia: NowPlayingItem? = nil
    
    // Active Coding Subagents State
    @Published public var activeCodingAgents: [CodingAgentTask] = []

    // Phase 2: Proactive Alerts, On-Device RAG Folders & Smart Home Devices
    @Published public var proactiveAlerts: [ProactiveAlert] = []
    @Published public var ragIndexedFolders: [String] = []
    @Published public var smartHomeDevices: [SmartHomeDevice] = []

    // Phase 3: Hologram 3D CAD Preview, Security Scan, Companion & User Plugins
    @Published public var latestHologramHTML: String? = nil
    @Published public var latestSecurityReport: SecurityScanReport? = nil
    @Published public var pairedCompanionDevices: [PairedCompanionDevice] = []
    @Published public var installedUserPlugins: [ExternalPluginManifest] = []
    @Published public var lastCopiedDictation: String = ""
    @Published public var activeBrainStatusLabel: String = "\(ModelRouter.shared.currentMode.rawValue) • \(ModelRouter.shared.ollamaChatModel)"
    public var onWriteToClipboard: (@Sendable (String) -> Void)? = nil
    
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
        self.chatSessions = LocalChatMemoryManager.shared.allSessions()
        self.activeChatSessionId = LocalChatMemoryManager.shared.currentSessionId()

        // 4. Initialize stored properties for "THE VOICE" Mode & Background Search Permissions
        let theVoiceSaved = UserDefaults.standard.object(forKey: "VoiceAI_TheVoiceModeActive") == nil ? true : UserDefaults.standard.bool(forKey: "VoiceAI_TheVoiceModeActive")
        self.isTheVoiceModeEnabled = theVoiceSaved
        let mediaDisplaySaved = UserDefaults.standard.object(forKey: "VoiceAI_NotchMediaDisplayEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "VoiceAI_NotchMediaDisplayEnabled")
        self.isNotchMediaDisplayEnabled = mediaDisplaySaved
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

        // 9. Initialize per-account encrypted MemoryStore & bind interactive ToolApprovalCoordinator UI
        let accountScope = AccountAuthService.shared.currentSession?.accountId ?? resolvedEmail
        MemoryStore.shared.load(accountId: accountScope)
        self.structuredMemories = MemoryStore.shared.allItems(scope: nil)
        self.configuredRoutines = RoutineManager.shared.allRoutines()
        EventBus.shared.subscribe(matching: .memoryUpdated) { [weak self] _ in
            DispatchQueue.main.async {
                self?.structuredMemories = MemoryStore.shared.allItems(scope: nil)
            }
        }
        ToolApprovalCoordinator.shared.setPresenter(self)

        // 10. Phase 2 Proactive Rules, RAG folders, and Smart Home state bindings
        self.proactiveAlerts = ProactiveRulesEngine.shared.activeAlerts()
        self.ragIndexedFolders = LocalKnowledgeStore.shared.configuredFolders()
        self.smartHomeDevices = SmartHomeManager.shared.allDevices()

        EventBus.shared.subscribe(matching: .custom("proactive_alert_raised")) { [weak self] _ in
            DispatchQueue.main.async {
                self?.proactiveAlerts = ProactiveRulesEngine.shared.activeAlerts()
            }
        }
        EventBus.shared.subscribe(matching: .custom("proactive_alerts_changed")) { [weak self] _ in
            DispatchQueue.main.async {
                self?.proactiveAlerts = ProactiveRulesEngine.shared.activeAlerts()
            }
        }
        EventBus.shared.subscribe(matching: .custom("smarthome_updated")) { [weak self] _ in
            DispatchQueue.main.async {
                self?.smartHomeDevices = SmartHomeManager.shared.allDevices()
            }
        }
        EventBus.shared.subscribe(matching: .custom("rag_folder_indexed")) { [weak self] _ in
            DispatchQueue.main.async {
                self?.ragIndexedFolders = LocalKnowledgeStore.shared.configuredFolders()
            }
        }
        EventBus.shared.subscribe(matching: .custom("model_switched")) { [weak self] evt in
            let mode = evt.payload["mode"] ?? ""
            let model = evt.payload["model"] ?? ""
            DispatchQueue.main.async {
                self?.activeBrainStatusLabel = "\(mode) • \(model)"
            }
        }
        let env = ProcessInfo.processInfo.environment
        if NSApp != nil && env["VOICE_AI_TEST_MODE"] != "1" {
            ProactiveRulesEngine.shared.startMonitoring(intervalSeconds: 60)
        }
    }
    
    private func setupNowPlayingAndAgentBindings() {
        self.currentMedia = NowPlayingMediaManager.shared.currentMedia
        NowPlayingMediaManager.shared.onMediaChanged = { [weak self] item in
            DispatchQueue.main.async {
                self?.currentMedia = item
                if item == nil || !(item?.isPlaying ?? false) {
                    self?.isMediaExpanded = false
                }
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
        let engine = AppIntegrationEngine.shared
        self.connectedApps = [
            ConnectedApp(
                id: "mail",
                name: "Email (Mail / Gmail)",
                description: "Draft emails, reply to threads, check unread inbox, and send mail by voice.",
                iconName: "envelope.fill",
                iconColor: "#007AFF",
                isConnected: engine.isAppIntegrated("mail"),
                category: "Connected Apps"
            ),
            ConnectedApp(
                id: "whatsapp",
                name: "WhatsApp",
                description: "Open chats, voice-draft replies, and send WhatsApp messages hands-free.",
                iconName: "message.fill",
                iconColor: "#25D366",
                isConnected: engine.isAppIntegrated("whatsapp"),
                category: "Connected Apps"
            ),
            ConnectedApp(
                id: "slack",
                name: "Slack",
                description: "Switch to #channels or DMs, draft updates, or post via webhook.",
                iconName: "number.square.fill",
                iconColor: "#4A154B",
                isConnected: engine.isAppIntegrated("slack"),
                category: "Connected Apps"
            ),
            ConnectedApp(
                id: "discord",
                name: "Discord",
                description: "Jump to servers/channels, draft chat messages, or post via webhook.",
                iconName: "bubble.left.and.bubble.right.fill",
                iconColor: "#5865F2",
                isConnected: engine.isAppIntegrated("discord"),
                category: "Connected Apps"
            ),
            ConnectedApp(
                id: "youtube",
                name: "YouTube",
                description: "Search videos, control playback, skip, mute, like, subscribe, or summarize.",
                iconName: "play.rectangle.fill",
                iconColor: "#FF0000",
                isConnected: engine.isAppIntegrated("youtube"),
                category: "System Integrations"
            ),
            ConnectedApp(
                id: "notion",
                name: "Notion",
                description: "Create Notion pages, Quick Find docs, and append notes by voice.",
                iconName: "doc.text.fill",
                iconColor: "#191919",
                isConnected: engine.isAppIntegrated("notion"),
                category: "Connected Apps"
            ),
            ConnectedApp(
                id: "notes",
                name: "Apple Notes",
                description: "Create rich notes, append ideas, read, and list notes via AppleScript.",
                iconName: "note.text",
                iconColor: "#F5A623",
                isConnected: engine.isAppIntegrated("notes"),
                category: "System Integrations"
            ),
            ConnectedApp(
                id: "terminal",
                name: "Terminal",
                description: "Execute safe shell commands, read stdout, or launch commands in Terminal.app.",
                iconName: "terminal.fill",
                iconColor: "#24292E",
                isConnected: engine.isAppIntegrated("terminal"),
                category: "Developer Tools"
            ),
            ConnectedApp(
                id: "spotify",
                name: "Spotify",
                description: "Play tracks or artists, skip, pause, and resume playback by voice.",
                iconName: "music.note",
                iconColor: "#1DB954",
                isConnected: engine.isAppIntegrated("spotify"),
                category: "System Integrations"
            ),
            ConnectedApp(
                id: "safari",
                name: "Safari",
                description: "Instant web searches, URL navigation, and DOM browser automation.",
                iconName: "safari.fill",
                iconColor: "#007AFF",
                isConnected: engine.isAppIntegrated("safari"),
                category: "System Integrations"
            ),
            ConnectedApp(
                id: "chrome",
                name: "Google Chrome",
                description: "Web automation, YouTube/Gmail tab control, and active tab scripting.",
                iconName: "globe",
                iconColor: "#EA4335",
                isConnected: engine.isAppIntegrated("chrome"),
                category: "System Integrations"
            ),
            ConnectedApp(
                id: "calendar",
                name: "Apple Calendar",
                description: "Check schedule and voice-add roadmap events or meetings.",
                iconName: "calendar",
                iconColor: "#FF3B30",
                isConnected: engine.isAppIntegrated("calendar"),
                category: "System Integrations"
            ),
            ConnectedApp(
                id: "reminders",
                name: "Apple Reminders",
                description: "Voice-create to-dos, shopping lists, and follow-up alerts.",
                iconName: "list.bullet.circle.fill",
                iconColor: "#FF9500",
                isConnected: engine.isAppIntegrated("reminders"),
                category: "System Integrations"
            ),
            ConnectedApp(
                id: "vscode",
                name: "Visual Studio Code",
                description: "Create code files, dictate comments, and automate IDE workflows.",
                iconName: "chevron.left.forwardslash.chevron.right",
                iconColor: "#0078D7",
                isConnected: engine.isAppIntegrated("vscode"),
                category: "Developer Tools"
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
        
        // Persist to SQLite Database (APP-SECRET.md line 122-131)
        let userId = AccountAuthService.shared.currentAccount?.id ?? "local_user"
        let sessionId = UUID().uuidString
        VoiceOSDatabaseManager.shared.insertSession(
            id: sessionId,
            userId: userId,
            transcript: prompt,
            mode: mode.rawValue,
            durationMs: Double(wordCount) * 200.0
        )
        let metricsJSON = "{\"words\":\(wordCount),\"timeSaved\":\(self.timeSavedMinutes),\"mode\":\"\(mode.rawValue)\"}"
        _ = try? VoiceOSDatabaseManager.shared.insertInsight(
            id: sessionId,
            userId: userId,
            sourceUpdatedAt: ISO8601DateFormatter().string(from: Date()),
            metricsJSON: metricsJSON
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
            MemoryStore.shared.updateUserProfile { $0.displayName = trimmedName }
        }
        if !trimmedEmail.isEmpty {
            self.userEmail = trimmedEmail
            UserDefaults.standard.set(trimmedEmail, forKey: "VoiceOS_UserEmail")
        }
    }

    public func refreshPhase1State() {
        self.structuredMemories = MemoryStore.shared.allItems(scope: nil)
        self.configuredRoutines = RoutineManager.shared.allRoutines()
    }

    public func rememberNoteFromUI(_ text: String, kind: MemoryFactKind = .fact) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        Task {
            _ = await MemoryStore.shared.remember(content: clean, scope: .longTerm, kind: kind, tags: ["manual"])
            await MainActor.run {
                self.structuredMemories = MemoryStore.shared.allItems(scope: nil)
            }
        }
    }

    public func forgetMemoryFromUI(id: String) {
        Task {
            _ = await MemoryStore.shared.forget(id: id)
            await MainActor.run {
                self.structuredMemories = MemoryStore.shared.allItems(scope: nil)
            }
        }
    }

    public func refreshPhase2State() {
        self.proactiveAlerts = ProactiveRulesEngine.shared.activeAlerts()
        self.ragIndexedFolders = LocalKnowledgeStore.shared.configuredFolders()
        self.smartHomeDevices = SmartHomeManager.shared.allDevices()
    }

    public func dismissProactiveAlert(id: String) {
        ProactiveRulesEngine.shared.dismissAlert(id: id)
        self.proactiveAlerts = ProactiveRulesEngine.shared.activeAlerts()
    }

    public func addAndIndexRAGFolder(path: String) {
        let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        LocalKnowledgeStore.shared.addFolder(path: clean)
        self.ragIndexedFolders = LocalKnowledgeStore.shared.configuredFolders()
        Task {
            _ = await LocalKnowledgeStore.shared.indexFolder(path: clean)
            await MainActor.run {
                self.ragIndexedFolders = LocalKnowledgeStore.shared.configuredFolders()
            }
        }
    }

    public func removeRAGFolder(path: String) {
        LocalKnowledgeStore.shared.removeFolder(path: path)
        self.ragIndexedFolders = LocalKnowledgeStore.shared.configuredFolders()
    }

    public func controlSmartHomeDeviceFromUI(_ device: SmartHomeDevice, action: String) {
        Task {
            let toolName = device.kind.isSecurityCritical ? "smarthome_control_security" : "smarthome_control_comfort"
            _ = await ToolRegistry.shared.invoke(
                name: toolName,
                arguments: ["device": device.name, "action": action]
            )
            await MainActor.run {
                self.smartHomeDevices = SmartHomeManager.shared.allDevices()
            }
        }
    }

    public func refreshPhase3State() {
        self.pairedCompanionDevices = PhoneCompanionService.shared.pairedDevices()
        self.installedUserPlugins = UserPluginManager.shared.installedPlugins()
    }

    public func launchIronLegionMission(goal: String) {
        let clean = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        self.activeNotchTab = .tasks
        Task {
            let res = await IronLegionCoordinator.shared.dispatchParallelMission(goal: clean)
            await MainActor.run {
                self.currentAgentReply = res.unifiedSummary
            }
        }
    }

    public func generateHologramCAD(shape: CADShapeKind, backend: CADBackend) {
        let cad = EngineeringStudioEngine.shared.generateCAD(shape: shape, backend: backend)
        self.latestHologramHTML = cad.hologramHTML
        self.currentAgentReply = "Generated \(cad.title):\n\(cad.sourceCode)"
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

            // Dedicated Clipboard Dictation Mode (Fn + D): copy spoken text directly to NSPasteboard.general
            if mode == .clipboardDictation {
                DispatchQueue.main.async {
                    _ = self.finalizeClipboardDictation(trimmed, writeToPasteboard: true)
                }
                return
            }

            let lower = polished.polishedText.lowercased()
            if Self.isBrainSuggestionPrompt(lower) {
                DispatchQueue.main.async {
                    self.triggerBrainThinkAndSuggest()
                }
                return
            }

            let isCommand = AgentActionDispatcher.shared.isCommandIntent(polished.polishedText)
            let isHinglish = HinglishParser.isHinglishQuery(polished.polishedText)
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
        self.chatSessions = LocalChatMemoryManager.shared.allSessions()
        self.activeChatSessionId = LocalChatMemoryManager.shared.currentSessionId()
                }

                let activeCrop = self.currentCropResult
                let speechTracker = StreamingSpeechTracker()
                self.currentAgentReply = ""
                self.currentExecutionTask?.cancel()
                self.currentExecutionTask = Task {
                    let result = await AutonomousAgentExecutor.shared.planAndExecute(
                        taskDescription: polished.polishedText,
                        triggerMode: mode,
                        screenCrop: activeCrop,
                        onPartialReply: { [weak self] partial in
                            speechTracker.pushPartial(partial)
                            Task { @MainActor in
                                self?.currentAgentReply = partial
                            }
                        }
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
                        self.syncChatMemoryFromStore()

                        self.recordSession(
                            mode: .agent,
                            prompt: polished.polishedText,
                            response: result.summary,
                            appName: result.targetAppName,
                            appIcon: "sparkles"
                        )
                        // Speak aloud direct answer / summary (or unspoken tail if already streaming)
                        speechTracker.finish(finalSummary: result.summary)
                        if result.success {
                            self.refreshBrainSuggestions(query: polished.polishedText, reply: result.summary)
                        }

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
        recordingWatchdogWorkItem?.cancel()
        GoogleSearchEngine.shared.clearLastAnswer()
        BoringSoundEngine.shared.playQueued()
        executionState = .listening(mode)
        islandState = .voiceCompact(mode)
        SpeechPipelineEngine.shared.startRecording(mode: mode)
        
        // Safety Watchdog: Auto-cancel recording after 20s if mic stalls (cancelled on stop or new recording)
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if case .listening = self.executionState {
                self.stopVoice()
            }
        }
        recordingWatchdogWorkItem = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 20.0, execute: watchdog)
    }

    public func triggerClipboardDictation() {
        interruptAndExecute(instruction: "", mode: .clipboardDictation)
    }

    public func toggleClipboardDictation() {
        if isCurrentlyListening {
            stopVoice()
        } else {
            triggerClipboardDictation()
        }
    }

    @discardableResult
    public func finalizeClipboardDictation(_ rawText: String, writeToPasteboard: Bool = true) -> String {
        let cleanedRaw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedRaw.isEmpty else { return "" }

        let polished = DictationPolishEngine.shared.polish(rawText: cleanedRaw, profile: .general).polishedText
        let finalText = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else { return "" }

        if writeToPasteboard {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(finalText, forType: .string)
            onWriteToClipboard?(finalText)
        }

        self.currentTranscript = finalText
        self.lastCopiedDictation = finalText
        self.currentAgentReply = "Copied to clipboard (press ⌘V anywhere to paste):\n\"\(finalText)\""
        self.executionState = .completed("Copied to clipboard — ⌘V ready")
        if !self.isPinned {
            self.islandState = .hoverExpanded
        }
        BoringSoundEngine.shared.playDone()

        self.recordSession(
            mode: .clipboardDictation,
            prompt: finalText,
            response: "Copied spoken text to clipboard (⌘V ready).",
            appName: "Clipboard",
            appIcon: "doc.on.clipboard.fill"
        )

        EventBus.shared.publish(VoiceEvent(
            kind: .custom("clipboard_dictation_copied"),
            source: "AppState",
            severity: .info,
            payload: ["length": "\(finalText.count)"]
        ))

        if !self.isPinned {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
                guard let self = self else { return }
                if !self.isPinned && !self.isCurrentlyListening && !self.isTypingFocused,
                   case .hoverExpanded = self.islandState {
                    self.islandState = .resting
                }
            }
        }
        return finalText
    }
    
    public func stopVoice() {
        recordingWatchdogWorkItem?.cancel()
        recordingWatchdogWorkItem = nil
        BoringSoundEngine.shared.playSend()
        SpeechPipelineEngine.shared.stopRecording()
    }
    
    private static func isBrainSuggestionPrompt(_ lower: String) -> Bool {
        lower.contains("suggest something") || lower.contains("what should i do next") ||
        lower.contains("give me suggestions") || lower.contains("brain suggest") ||
        lower.contains("think and suggest")
    }

    public func submitTypedPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Support instant barge-in when user sends a typed follow-up while speaking
        SpeechPipelineEngine.shared.bargeIn()
        if Self.isBrainSuggestionPrompt(trimmed.lowercased()) {
            promptInputText = ""
            triggerBrainThinkAndSuggest()
            return
        }
        BoringSoundEngine.shared.playSend()
        currentTranscript = trimmed
        lastPromptOrQuestion = trimmed
        promptInputText = ""
        llmSuggestions = []
        BoringSoundEngine.shared.playReply()
        executionState = .thinking("Formulating answer & executing task...")
        islandState = .hoverExpanded
        isAwaitingRedirectConfirmation = false
        
        // Add to persistent local chat memory
        _ = LocalChatMemoryManager.shared.addMessage(role: "user", text: trimmed)
        self.chatMessages = LocalChatMemoryManager.shared.allMessages()
        self.chatSessions = LocalChatMemoryManager.shared.allSessions()
        self.activeChatSessionId = LocalChatMemoryManager.shared.currentSessionId()
        
        let activeCrop = self.currentCropResult
        let speechTracker = StreamingSpeechTracker()
        self.currentAgentReply = ""
        currentExecutionTask?.cancel()
        currentExecutionTask = Task {
            let result = await AutonomousAgentExecutor.shared.planAndExecute(
                taskDescription: trimmed,
                screenCrop: activeCrop,
                onPartialReply: { [weak self] partial in
                    speechTracker.pushPartial(partial)
                    Task { @MainActor in
                        self?.currentAgentReply = partial
                    }
                }
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
                
                // Add assistant response to persistent chat memory
                _ = LocalChatMemoryManager.shared.addMessage(
                    role: "assistant",
                    text: result.summary,
                    sourceURL: result.targetURL?.absoluteString,
                    sourceTitle: result.targetAppName
                )
                self.syncChatMemoryFromStore()
                
                self.recordSession(
                    mode: .agent,
                    prompt: trimmed,
                    response: result.summary,
                    appName: result.targetAppName,
                    appIcon: "sparkles"
                )
                speechTracker.finish(finalSummary: result.summary)
                if result.success {
                    self.refreshBrainSuggestions(query: trimmed, reply: result.summary)
                }
            }
        }
    }
    
    private func refreshBrainSuggestions(query: String, reply: String) {
        guard ModelRouter.shared.currentMode != .googleSearch else { return }
        self.isThinkingSuggestions = true
        Task.detached(priority: .utility) { [weak self] in
            let generated = await AutonomousAgentExecutor.shared.generateBrainSuggestions(
                forQuery: query,
                reply: reply
            )
            await MainActor.run {
                self?.llmSuggestions = generated
                self?.isThinkingSuggestions = false
            }
        }
    }

    public func triggerBrainThinkAndSuggest() {
        BoringSoundEngine.shared.playReply()
        self.executionState = .thinking("Local Brain analyzing your Mac & screen context...")
        self.islandState = .hoverExpanded
        self.activeNotchTab = .ask
        self.isThinkingSuggestions = true
        self.llmSuggestions = []
        
        Task {
            let outcome = await AutonomousAgentExecutor.shared.thinkAndSuggestForCurrentContext()
            await MainActor.run {
                BoringSoundEngine.shared.playDone()
                self.executionState = .completed(outcome.insight)
                self.currentAgentReply = outcome.insight
                self.llmSuggestions = outcome.suggestions
                self.isThinkingSuggestions = false
                _ = LocalChatMemoryManager.shared.addMessage(
                    role: "assistant",
                    text: outcome.insight,
                    sourceTitle: "Ollama Brain Suggestions"
                )
                self.chatMessages = LocalChatMemoryManager.shared.allMessages()
        self.chatSessions = LocalChatMemoryManager.shared.allSessions()
        self.activeChatSessionId = LocalChatMemoryManager.shared.currentSessionId()
                SpeechPipelineEngine.shared.speakResponse(outcome.insight)
            }
        }
    }

    public func triggerScreenVision() {
        self.executionState = .thinking("Scanning current screen via Apple Vision OCR...")
        self.islandState = .hoverExpanded
        _ = LocalChatMemoryManager.shared.addMessage(role: "user", text: "What is currently on my screen?", isScreenContext: true)
        self.chatMessages = LocalChatMemoryManager.shared.allMessages()
        self.chatSessions = LocalChatMemoryManager.shared.allSessions()
        self.activeChatSessionId = LocalChatMemoryManager.shared.currentSessionId()
        
        Task {
            let captured = await ScreenVisionService.shared.captureFullScreenWithImage()
            let llmResult = await AutonomousAgentExecutor.shared.analyzeScreenWithActiveModel(
                pngData: captured.pngData,
                ocrText: captured.analysis.fullText,
                appName: captured.analysis.activeAppTitle ?? "Active App",
                sourceLabel: "Full Screen",
                question: "Summarize what is currently visible on my screen concisely and clearly."
            )
            let finalSummary = llmResult?.summary ?? captured.analysis.summary
            let sourceLabel = llmResult?.usedProvider ?? "Screen OCR"
            await MainActor.run {
                self.executionState = .completed(finalSummary)
                self.currentAgentReply = finalSummary
                _ = LocalChatMemoryManager.shared.addMessage(
                    role: "assistant",
                    text: finalSummary,
                    sourceTitle: sourceLabel,
                    isScreenContext: true
                )
                self.chatMessages = LocalChatMemoryManager.shared.allMessages()
        self.chatSessions = LocalChatMemoryManager.shared.allSessions()
        self.activeChatSessionId = LocalChatMemoryManager.shared.currentSessionId()
                SpeechPipelineEngine.shared.speakResponse(finalSummary)
            }
        }
    }
    
    public func clearChatHistory() {
        BoringSoundEngine.shared.playTap()
        LocalChatMemoryManager.shared.clearChat()
        syncChatMemoryFromStore()
        self.currentAgentReply = ""
        self.currentTranscript = ""
        self.llmSuggestions = []
    }

    public func syncChatMemoryFromStore() {
        self.chatMessages = LocalChatMemoryManager.shared.allMessages()
        self.chatSessions = LocalChatMemoryManager.shared.allSessions()
        self.activeChatSessionId = LocalChatMemoryManager.shared.currentSessionId()
    }

    public func toggleHistorySidebar() {
        isHistoryDrawerOpen.toggle()
    }

    public func startNewChatSession() {
        BoringSoundEngine.shared.playTap()
        _ = LocalChatMemoryManager.shared.startNewSession()
        syncChatMemoryFromStore()
        self.currentTranscript = ""
        self.currentAgentReply = ""
        self.llmSuggestions = []
        self.executionState = .idle
        self.activeNotchTab = .ask
        self.islandState = .hoverExpanded
        self.isNotchHUDVisible = true
        if !isHistorySidebarPinned {
            isHistoryDrawerOpen = false
        }
    }

    public func openChatSession(_ session: VoiceChatSession) {
        BoringSoundEngine.shared.playTap()
        guard let loaded = LocalChatMemoryManager.shared.switchToSession(id: session.id) else { return }
        syncChatMemoryFromStore()
        self.currentTranscript = loaded.messages.last(where: { $0.role == "user" })?.text ?? loaded.title
        self.currentAgentReply = loaded.messages.last(where: { $0.role == "assistant" })?.text ?? ""
        self.executionState = self.currentAgentReply.isEmpty ? .idle : .completed(self.currentAgentReply)
        self.activeNotchTab = .ask
        self.islandState = .hoverExpanded
        self.isNotchHUDVisible = true
        if !isHistorySidebarPinned {
            isHistoryDrawerOpen = false
        }
    }

    public func openLegacyHistoryRecord(_ record: SessionRecord) {
        BoringSoundEngine.shared.playTap()
        _ = LocalChatMemoryManager.shared.startNewSession()
        _ = LocalChatMemoryManager.shared.addMessage(role: "user", text: record.prompt)
        _ = LocalChatMemoryManager.shared.addMessage(role: "assistant", text: record.response, sourceTitle: record.appName)
        syncChatMemoryFromStore()
        self.currentTranscript = record.prompt
        self.currentAgentReply = record.response
        self.currentAction = record.action
        self.executionState = .completed(record.response)
        self.activeNotchTab = .ask
        self.islandState = .hoverExpanded
        self.isNotchHUDVisible = true
        if !isHistorySidebarPinned {
            isHistoryDrawerOpen = false
        }
    }

    public func togglePinChatSession(id: String) {
        LocalChatMemoryManager.shared.togglePinSession(id: id)
        syncChatMemoryFromStore()
    }

    public func deleteChatSession(id: String) {
        LocalChatMemoryManager.shared.deleteSession(id: id)
        syncChatMemoryFromStore()
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
        
        // 2. Stop any current speech playback immediately (barge-in)
        SpeechPipelineEngine.shared.bargeIn()
        
        // 3. Play queued chime
        BoringSoundEngine.shared.playQueued()
        
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let activeWake = TheVoiceAmbientListener.shared.wakePhrase
        
        // If the wake word was spoken without an immediate instruction ("jarvis", "hey jarvis", "voice", "hey voice")
        if trimmed.isEmpty || lower == activeWake || lower == "hey \(activeWake)" || lower == "ok \(activeWake)" ||
           lower == "voice" || lower == "the voice" || lower == "hey voice" || lower == "ok voice" {
            // Switch to active listening state with the chosen trigger mode
            triggerVoice(mode: mode)
        } else {
            let cleanedPrompt = TheVoiceAmbientListener.extractCommand(from: trimmed, wakePhrase: activeWake) ?? trimmed
            submitTypedPrompt(cleanedPrompt.isEmpty ? trimmed : cleanedPrompt)
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
        BoringSoundEngine.shared.playTap()
        isScreenCaptureActive = true
        islandState = .circleToAskActive
    }
    
    public func completeCircleSelection(crop: ScreenCropResult) {
        BoringSoundEngine.shared.playDone()
        isScreenCaptureActive = false
        currentCropResult = crop
        activeNotchTab = .ask
        isCompactResponseMode = false
        islandState = .selectionReview(crop)
        let appLabel = crop.sourceAppName ?? "Screen"
        currentTranscript = "Captured \(crop.toolUsed.rawValue) from \(appLabel)"
        if crop.extractedOCRText.isEmpty {
            currentAgentReply = "Selected region captured (\(Int(crop.boundingBox.width))×\(Int(crop.boundingBox.height)) px). Ask anything about it."
        } else {
            currentAgentReply = ""
        }
    }
    
    public func cancelCircleSelection() {
        isScreenCaptureActive = false
        islandState = isPinned ? .pinned : .resting
    }
    
    public func clearCircleSelection() {
        currentCropResult = nil
        if case .selectionReview = islandState {
            islandState = isPinned ? .pinned : .hoverExpanded
        }
    }
    
    @MainActor
    public func presentApprovalCard(for action: AgentAction) async -> Bool {
        if let stale = pendingApprovalContinuation {
            pendingApprovalContinuation = nil
            stale.resume(returning: false)
        }
        self.currentAction = action
        self.executionState = .awaitingApproval(action)
        self.activeNotchTab = .ask
        self.islandState = .approvalExpanded(action)

        return await withCheckedContinuation { continuation in
            self.pendingApprovalContinuation = continuation
        }
    }

    public func approveCurrentAction() {
        guard var action = currentAction else { return }
        action.isApproved = true
        currentAction = nil
        executionState = .executing(action.title)

        if let continuation = pendingApprovalContinuation {
            pendingApprovalContinuation = nil
            continuation.resume(returning: true)
            if !self.isPinned {
                islandState = .hoverExpanded
            }
            return
        }

        // Fallback completion for standalone manual action cards
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.executionState = .completed("Approved: \(action.title)")
            self.recentHistory.insert(
                SessionRecord(
                    mode: .agent,
                    prompt: self.currentTranscript.isEmpty ? action.title : self.currentTranscript,
                    response: action.subtitle ?? "Approved \(action.title)",
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
    
    public func dismissAction() {
        currentAction = nil
        if let continuation = pendingApprovalContinuation {
            pendingApprovalContinuation = nil
            continuation.resume(returning: false)
        }
        executionState = .idle
        islandState = isPinned ? .pinned : .resting
    }
}
