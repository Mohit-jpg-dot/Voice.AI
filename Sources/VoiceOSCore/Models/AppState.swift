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
    @Published public var isShelfDragTargetHovered: Bool = false
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
    @Published public var isAppBuilderOpen: Bool = false
    @Published public var activeEmailDraft: EmailDraft? = nil
    @Published public var activeEventDraft: CalendarEventDraft? = nil
    
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
    @Published public var llmSuggestions: [BrainSuggestion] = []
    @Published public var isThinkingSuggestions: Bool = false
    @Published public var structuredMemories: [StructuredMemoryItem] = []
    @Published public var configuredRoutines: [VoiceRoutine] = []
    private var recordingWatchdogWorkItem: DispatchWorkItem?
    private var autoCollapseWorkItem: DispatchWorkItem?
    private var activeResponseToken = UUID()
    
    // "THE VOICE" Hands-free ambient wake-word mode & 24/7 continuous listening mode
    @Published public var isTheVoiceModeEnabled: Bool {
        didSet {
            TheVoiceAmbientListener.shared.isTheVoiceModeEnabled = isTheVoiceModeEnabled
        }
    }
    @Published public var isAlwaysOnListeningMode: Bool {
        didSet {
            TheVoiceAmbientListener.shared.isAlwaysOn24x7Mode = isAlwaysOnListeningMode
            if isAlwaysOnListeningMode && !isTheVoiceModeEnabled {
                isTheVoiceModeEnabled = true
            }
        }
    }
    @Published public var isComputerAudioListeningEnabled: Bool {
        didSet {
            ComputerAudioListenerService.shared.isEnabled = isComputerAudioListeningEnabled
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
    @Published public var isHoveringPill: Bool = false
    
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
    
    // Real History - loaded from UserDefaults & EncryptedChatHistoryManager
    @Published public var recentHistory: [SessionRecord] = []
    @Published public var activeConversationId: String? = nil
    @Published public var selectedConversation: ConversationSessionRecord? = nil
    @Published public var conversationSessions: [ConversationSessionRecord] = []
    
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
        case shelf = "Shelf"
        case apps = "Apps"
        case tasks = "Agents"
        case memory = "Memory"
        
        public var id: String { rawValue }
        
        public var iconName: String {
            switch self {
            case .ask: return "sparkles"
            case .shelf: return "tray.2.fill"
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

        // 4. Initialize stored properties for "THE VOICE" Mode, 24/7 Listening & Background Search Permissions
        let theVoiceSaved = UserDefaults.standard.object(forKey: "VoiceAI_TheVoiceModeActive") == nil ? true : UserDefaults.standard.bool(forKey: "VoiceAI_TheVoiceModeActive")
        self.isTheVoiceModeEnabled = theVoiceSaved
        self.isAlwaysOnListeningMode = TheVoiceAmbientListener.shared.isAlwaysOn24x7Mode
        self.isComputerAudioListeningEnabled = ComputerAudioListenerService.shared.isEnabled
        let mediaDisplaySaved = UserDefaults.standard.object(forKey: "VoiceAI_NotchMediaDisplayEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "VoiceAI_NotchMediaDisplayEnabled")
        self.isNotchMediaDisplayEnabled = mediaDisplaySaved
        self.hasGrantedBackgroundSearchPermission = UserDefaults.standard.bool(forKey: "VoiceAI_BackgroundSearchPermissionGranted")

        // 5. Setup real connected macOS apps
        self.setupConnectedApps()

        // 6. Compute real app usages & hydrate ChatGPT-style encrypted conversation sessions
        self.recomputeAppUsages()
        let historyAccountId = AccountAuthService.shared.currentAccount?.id ?? "local"
        EncryptedChatHistoryManager.shared.loadForAccount(accountId: historyAccountId)
        var loadedSessions = EncryptedChatHistoryManager.shared.listConversations()
        if loadedSessions.isEmpty && !self.recentHistory.isEmpty {
            for item in self.recentHistory.prefix(30).reversed() {
                _ = EncryptedChatHistoryManager.shared.recordTurn(
                    conversationId: nil,
                    userText: item.prompt,
                    assistantText: item.response,
                    persona: PersonaManager.shared.getActivePersona().rawValue
                )
            }
            loadedSessions = EncryptedChatHistoryManager.shared.listConversations()
        }
        self.conversationSessions = loadedSessions
        if let savedId = UserDefaults.standard.string(forKey: "VoiceAI_ActiveConversationId"),
           let resumed = loadedSessions.first(where: { $0.id == savedId }) ?? loadedSessions.first {
            self.activeConversationId = resumed.id
            self.selectedConversation = resumed
        }

        // 7. Bind "THE VOICE" Hands-free ambient listener callback with interruption support
        TheVoiceAmbientListener.shared.onWakeWordTriggered = { [weak self] command in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.interruptAndExecute(instruction: command)
            }
        }
        TheVoiceAmbientListener.shared.canAcceptDirectSilenceCommand = { [weak self] in
            guard let self = self else { return false }
            return self.islandState != .resting ||
                   self.isMediaExpanded ||
                   SpeechPipelineEngine.shared.currentState == .speaking
        }
        TheVoiceAmbientListener.shared.onHotCaptureStarted = { [weak self] initial in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.cancelPendingAutoCollapse()
                self.recordingWatchdogWorkItem?.cancel()
                GoogleSearchEngine.shared.clearLastAnswer()
                self.currentTranscript = initial
                self.executionState = .listening(.agent)
                self.islandState = .voiceCompact(.agent)
            }
        }
        TheVoiceAmbientListener.shared.onHotCaptureLevels = { [weak self] levels in
            self?.audioLevels = levels
        }
        TheVoiceAmbientListener.shared.onHotCapturePartial = { [weak self] partial in
            DispatchQueue.main.async {
                self?.currentTranscript = partial
            }
        }
        TheVoiceAmbientListener.shared.onHotCaptureCompleted = { [weak self] captured in
            guard let self = self else { return }
            let trimmed = captured.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                BoringSoundEngine.shared.playError()
                self.executionState = .idle
                if !self.isPinned, case .voiceCompact = self.islandState {
                    self.islandState = .resting
                }
                return
            }
            if Self.isSilenceAndCollapseCommand(trimmed) {
                self.shutUpAndCollapse()
                return
            }
            self.submitTypedPrompt(trimmed)
        }
        if theVoiceSaved {
            TheVoiceAmbientListener.shared.startAmbientListening()
        }
        EventBus.shared.subscribe(matching: .custom("notch_collapse_requested")) { [weak self] _ in
            DispatchQueue.main.async {
                self?.shutUpAndCollapse()
            }
        }
        EventBus.shared.subscribe(matching: .custom("email_draft_dismiss_requested")) { [weak self] _ in
            DispatchQueue.main.async {
                self?.dismissEmailDraft()
            }
        }
        EventBus.shared.subscribe(matching: .custom("listening_mode_changed")) { [weak self] evt in
            let alwaysOn = evt.payload["always_on"] == "true"
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.isAlwaysOnListeningMode != alwaysOn {
                    self.isAlwaysOnListeningMode = alwaysOn
                }
                if alwaysOn && !self.isTheVoiceModeEnabled {
                    self.isTheVoiceModeEnabled = true
                }
            }
        }
        EventBus.shared.subscribe(matching: .custom("computer_audio_listening_changed")) { [weak self] evt in
            let enabled = evt.payload["enabled"] == "true"
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.isComputerAudioListeningEnabled != enabled {
                    self.isComputerAudioListeningEnabled = enabled
                }
            }
        }
        EventBus.shared.subscribe(matching: .custom("session_control")) { [weak self] evt in
            let action = evt.payload["action"] ?? ""
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch action {
                case "new_session":
                    self.activeConversationId = nil
                    self.selectedConversation = nil
                    UserDefaults.standard.removeObject(forKey: "VoiceAI_ActiveConversationId")
                case "select_session":
                    if let sid = evt.payload["id"],
                       let conv = EncryptedChatHistoryManager.shared.getConversation(id: sid) {
                        self.activeConversationId = conv.id
                        self.selectedConversation = conv
                        UserDefaults.standard.set(conv.id, forKey: "VoiceAI_ActiveConversationId")
                        self.conversationSessions = EncryptedChatHistoryManager.shared.listConversations()
                    }
                case "rename_session":
                    if let title = evt.payload["title"], let sid = self.activeConversationId {
                        EncryptedChatHistoryManager.shared.renameConversation(id: sid, newTitle: title)
                        self.conversationSessions = EncryptedChatHistoryManager.shared.listConversations()
                        self.selectedConversation = EncryptedChatHistoryManager.shared.getConversation(id: sid)
                    }
                default:
                    break
                }
            }
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

        EventBus.shared.subscribe(matching: .emailDraftCreated) { [weak self] event in
            guard let self = self else { return }
            let to = (event.payload["to"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let subj = event.payload["subject"] ?? ""
            let body = event.payload["body"] ?? ""
            let draftId = event.payload["draft_id"] ?? UUID().uuidString
            let draft = EmailDraft(id: draftId, to: to, subject: subj, body: body)
            DispatchQueue.main.async {
                self.presentEmailDraft(draft)
            }
        }

        EventBus.shared.subscribe(matching: .calendarDraftCreated) { [weak self] event in
            guard let self = self else { return }
            let id = event.payload["draft_id"] ?? UUID().uuidString
            let title = event.payload["title"] ?? "New Event"
            let typeStr = event.payload["type"] ?? "google_meet"
            let type = EventDraftType(rawValue: typeStr) ?? .googleMeet
            let dateStr = event.payload["date_string"] ?? "Thursday"
            let timeStr = event.payload["time_string"] ?? "2:00 – 2:30 PM"
            let participantsStr = event.payload["participants"] ?? ""
            let parts = participantsStr.isEmpty ? [] : participantsStr.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            let platform = event.payload["platform"] ?? type.defaultPlatform
            let isRem = event.payload["is_reminder"] == "true"

            let draft = CalendarEventDraft(
                id: id,
                title: title,
                type: type,
                dateString: dateStr,
                timeString: timeStr,
                participants: parts,
                platform: platform,
                isReminder: isRem
            )
            DispatchQueue.main.async {
                self.presentCalendarEventDraft(draft)
            }
        }

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
        EventBus.shared.subscribe(matching: .custom("email_watch_reply")) { evt in
            let isSilent = evt.payload["silent"] == "true"
            let sender = evt.payload["sender"] ?? "Someone"
            let subject = evt.payload["subject"] ?? "your email"
            if !isSilent && ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] != "1" {
                let text = "\(sender) replied to '\(subject)'."
                DispatchQueue.main.async {
                    SpeechPipelineEngine.shared.speakResponse(text)
                }
            }
        }
        let env = ProcessInfo.processInfo.environment
        if NSApp != nil && env["VOICE_AI_TEST_MODE"] != "1" {
            ProactiveRulesEngine.shared.startMonitoring(intervalSeconds: 60)
            VoiceEmailManager.shared.startWatchMonitoring()
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
        if let saved = EncryptedChatHistoryManager.shared.recordTurn(
            conversationId: self.activeConversationId,
            userText: prompt,
            assistantText: response,
            persona: PersonaManager.shared.getActivePersona().rawValue,
            actions: actionItems
        ) {
            self.activeConversationId = saved.id
            UserDefaults.standard.set(saved.id, forKey: "VoiceAI_ActiveConversationId")
            if self.selectedConversation?.id == saved.id {
                self.selectedConversation = saved
            }
            self.conversationSessions = EncryptedChatHistoryManager.shared.listConversations()
        }

        // Persist structured conversational turn & extract user preferences locally
        Task {
            await MemoryStore.shared.recordConversationExchange(
                userText: prompt,
                assistantText: response,
                timestamp: Date(),
                sourceTag: appName
            )
            await MainActor.run {
                self.structuredMemories = MemoryStore.shared.allItems(scope: nil)
            }
        }
        
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
        self.activeConversationId = nil
        self.selectedConversation = nil
        self.conversationSessions = []
        UserDefaults.standard.removeObject(forKey: "VoiceOS_RecentHistory")
        recomputeAppUsages()
    }

    public func clearAllMemoryAndHistory() {
        MemoryStore.shared.clearAllMemoryAndConversations()
        self.structuredMemories = []
        self.chatMessages = LocalChatMemoryManager.shared.allMessages()
        clearAllHistory()
    }

    public func toggleHistorySidebar() {
        refreshConversationSessions()
        isHistoryDrawerOpen.toggle()
    }

    public func refreshConversationSessions() {
        let historyAccountId = AccountAuthService.shared.currentAccount?.id ?? "local"
        EncryptedChatHistoryManager.shared.loadForAccount(accountId: historyAccountId)
        self.conversationSessions = EncryptedChatHistoryManager.shared.listConversations()
        if let currentId = self.selectedConversation?.id {
            self.selectedConversation = self.conversationSessions.first(where: { $0.id == currentId })
        }
    }

    public func openConversationSession(_ session: ConversationSessionRecord) {
        self.activeConversationId = session.id
        self.selectedConversation = session
        if let lastUser = session.messages.last(where: { $0.role == "user" }) {
            self.currentTranscript = lastUser.content
            self.lastPromptOrQuestion = lastUser.content
        }
        if let lastAssistant = session.messages.last(where: { $0.role == "assistant" }) {
            self.currentAgentReply = lastAssistant.content
            self.executionState = .completed(lastAssistant.content)
        }
    }

    public func startNewConversationSession() {
        self.activeConversationId = nil
        self.selectedConversation = nil
        self.currentTranscript = ""
        self.currentAgentReply = ""
        self.llmSuggestions = []
        self.executionState = .idle
    }

    public func deleteConversationSession(id: String) {
        EncryptedChatHistoryManager.shared.deleteConversation(id: id)
        if activeConversationId == id { activeConversationId = nil }
        if selectedConversation?.id == id { selectedConversation = nil }
        refreshConversationSessions()
    }

    public func togglePinConversationSession(id: String) {
        EncryptedChatHistoryManager.shared.togglePin(id: id)
        refreshConversationSessions()
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
            DispatchQueue.main.async {
                self?.currentTranscript = liveText
            }
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
            if Self.isSilenceAndCollapseCommand(polished.polishedText) {
                DispatchQueue.main.async {
                    self.shutUpAndCollapse()
                }
                return
            }
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
                }

                let activeCrop = self.currentCropResult
                self.currentAgentReply = ""
                self.currentExecutionTask?.cancel()
                self.currentExecutionTask = Task {
                    let result = await AutonomousAgentExecutor.shared.planAndExecute(
                        taskDescription: polished.polishedText,
                        triggerMode: mode,
                        screenCrop: activeCrop,
                        onPartialReply: { [weak self] partial in
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
                        self.presentCompletedAgentResult(result, forPrompt: polished.polishedText)
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
        cancelPendingAutoCollapse()
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
        if TheVoiceAmbientListener.shared.isCapturingHotCommand {
            TheVoiceAmbientListener.shared.cancelHotFollowUpCapture()
            if case .listening = executionState {
                executionState = .idle
            }
            if !isPinned, case .voiceCompact = islandState {
                islandState = .resting
            }
            return
        }
        SpeechPipelineEngine.shared.stopRecording()
    }

    @discardableResult
    public func cancelPendingAutoCollapse() -> UUID {
        autoCollapseWorkItem?.cancel()
        autoCollapseWorkItem = nil
        let next = UUID()
        activeResponseToken = next
        return next
    }

    public func scheduleAutoCollapse(after delaySeconds: Double = 1.0, forToken token: UUID? = nil) {
        autoCollapseWorkItem?.cancel()
        let targetToken = token ?? activeResponseToken

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.activeResponseToken == targetToken else { return }
            // Only keep open if user explicitly pinned the island, is actively typing, listening, or awaiting confirmation
            guard !self.isPinned, !self.isTypingFocused, !self.isCurrentlyListening, !self.isAwaitingRedirectConfirmation else { return }

            // If speech synthesis is still actively speaking the answer, wait until speech ends
            if SpeechPipelineEngine.shared.currentState == .speaking {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.scheduleAutoCollapse(after: 0.6, forToken: targetToken)
                }
                return
            }

            self.autoCollapseWorkItem = nil
            self.isMediaExpanded = false
            self.isHoveringPill = false

            self.islandState = .resting
            if case .completed = self.executionState {
                self.executionState = .idle
            }
        }
        self.autoCollapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds, execute: work)
    }

    public func scheduleAutoCollapseAfterSpeech(delaySeconds: Double = 0.55, forToken token: UUID) {
        scheduleAutoCollapse(after: delaySeconds, forToken: token)
    }

    private func presentCompletedAgentResult(_ result: AutonomousExecutionResult, forPrompt prompt: String) {
        let responseToken = cancelPendingAutoCollapse()

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

        if self.activeEmailDraft != nil || self.activeEventDraft != nil || VoiceEmailManager.shared.focusedDraft() != nil {
            if self.activeEmailDraft == nil, let focused = VoiceEmailManager.shared.focusedDraft() {
                self.presentEmailDraft(focused)
            }
            SpeechPipelineEngine.shared.speakResponse(result.summary)
            if result.success {
                self.refreshBrainSuggestions(query: prompt, reply: result.summary)
            }
            return
        }

        self.islandState = .hoverExpanded

        _ = LocalChatMemoryManager.shared.addMessage(
            role: "assistant",
            text: result.summary,
            sourceURL: result.targetURL?.absoluteString,
            sourceTitle: result.targetAppName
        )
        self.chatMessages = LocalChatMemoryManager.shared.allMessages()

        self.recordSession(
            mode: .agent,
            prompt: prompt,
            response: result.summary,
            appName: result.targetAppName,
            appIcon: "sparkles"
        )

        let isActionTask = summaryLower.contains("closed ") || summaryLower.contains("opened ") ||
                           summaryLower.contains("quit ") || summaryLower.contains("launched ") ||
                           summaryLower.contains("saved ") || summaryLower.contains("scheduled ") ||
                           summaryLower.contains("muted ") || summaryLower.contains("unmuted ") ||
                           summaryLower.contains("set volume") || summaryLower.contains("brightness") ||
                           summaryLower.contains("playing ") || summaryLower.contains("paused ")

        // 1. Guaranteed fallback auto-collapse timer (so pill ALWAYS collapses even if speech is fast, muted, or skipped)
        let fallbackDelay = isActionTask ? 2.0 : max(3.5, Double(result.summary.count) * 0.08 + 2.0)
        self.scheduleAutoCollapse(after: fallbackDelay, forToken: responseToken)

        // 2. Event-driven collapse triggered immediately after speech synthesis finishes
        SpeechPipelineEngine.shared.speakResponse(result.summary) { [weak self] in
            DispatchQueue.main.async {
                self?.scheduleAutoCollapse(after: isActionTask ? 0.6 : 1.2, forToken: responseToken)
            }
        }
        if result.success {
            self.refreshBrainSuggestions(query: prompt, reply: result.summary)
        }
    }
    
    public static func isSilenceAndCollapseCommand(_ text: String) -> Bool {
        var normalized = text
            .replacingOccurrences(of: "[,.!?।\"']", with: " ", options: .regularExpression)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        let customWake = NSRegularExpression.escapedPattern(for: TheVoiceAmbientListener.shared.wakePhrase)
        let wakePrefixPattern = "^(?:(?:hey|hi|ok|okay|hello|the|arey)\\s+)?(?:jarvis|friday|voice|\(customWake))\\s+"
        normalized = normalized.replacingOccurrences(of: wakePrefixPattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wakeSuffixPattern = "\\s+(?:jarvis|friday|voice|\(customWake))$"
        normalized = normalized.replacingOccurrences(of: wakeSuffixPattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let trimWords = ["please ", "ji ", "sir ", "bro "]
        for w in trimWords where normalized.hasPrefix(w) {
            normalized = String(normalized.dropFirst(w.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for w in [" please", " right now", " now", " already", " man", " bro", " sir"] where normalized.hasSuffix(w) {
            normalized = String(normalized.dropLast(w.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let silencePhrases: Set<String> = [
            "shut up", "be quiet", "quiet", "stop talking", "stop speaking",
            "mute yourself", "silence", "go away", "close notch", "collapse",
            "chup", "chup ho jao", "chup kar", "chup raho", "bas karo", "shant ho jao"
        ]
        return silencePhrases.contains(normalized) || normalized.hasPrefix("shut up ")
    }

    /// Silences TTS/execution immediately and resizes any opened Notch hover pill back to resting size.
    public func shutUpAndCollapse() {
        recordingWatchdogWorkItem?.cancel()
        recordingWatchdogWorkItem = nil
        currentExecutionTask?.cancel()
        currentExecutionTask = nil
        if ComputerUseOperator.shared.isRunning {
            ComputerUseOperator.shared.stopActiveRun()
        }
        SpeechPipelineEngine.shared.bargeIn()
        if case .recording = SpeechPipelineEngine.shared.currentState {
            SpeechPipelineEngine.shared.cancel()
        }
        _ = PersonaManager.shared.evaluateSafetyGuardrail(userInput: "shut up")
        isPinned = false
        isMediaExpanded = false
        isTypingFocused = false
        isAwaitingRedirectConfirmation = false
        isScreenCaptureActive = false
        executionState = .idle
        islandState = .resting
    }

    private static func isBrainSuggestionPrompt(_ lower: String) -> Bool {
        lower.contains("suggest something") || lower.contains("what should i do next") ||
        lower.contains("give me suggestions") || lower.contains("brain suggest") ||
        lower.contains("think and suggest")
    }

    public func submitTypedPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if Self.isSilenceAndCollapseCommand(trimmed) {
            promptInputText = ""
            shutUpAndCollapse()
            return
        }
        cancelPendingAutoCollapse()
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
        
        let activeCrop = self.currentCropResult
        self.currentAgentReply = ""
        currentExecutionTask?.cancel()
        currentExecutionTask = Task {
            let result = await AutonomousAgentExecutor.shared.planAndExecute(
                taskDescription: trimmed,
                screenCrop: activeCrop,
                onPartialReply: { [weak self] partial in
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
                self.presentCompletedAgentResult(result, forPrompt: trimmed)
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
                let responseToken = self.cancelPendingAutoCollapse()
                self.scheduleAutoCollapse(after: max(4.0, Double(outcome.insight.count) * 0.08 + 2.0), forToken: responseToken)
                SpeechPipelineEngine.shared.speakResponse(outcome.insight) { [weak self] in
                    DispatchQueue.main.async {
                        self?.scheduleAutoCollapse(after: 1.2, forToken: responseToken)
                    }
                }
            }
        }
    }

    public func triggerScreenVision() {
        self.executionState = .thinking("Scanning current screen via Apple Vision OCR...")
        self.islandState = .hoverExpanded
        _ = LocalChatMemoryManager.shared.addMessage(role: "user", text: "What is currently on my screen?", isScreenContext: true)
        self.chatMessages = LocalChatMemoryManager.shared.allMessages()
        
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
            ConversationSessionContext.shared.setLastScreenContext(
                ConversationSessionContext.CapturedScreenContext(
                    pngData: captured.pngData,
                    ocrText: captured.analysis.fullText,
                    appName: captured.analysis.activeAppTitle ?? "Active App",
                    initialSummary: finalSummary,
                    capturedAt: Date()
                )
            )
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
                let responseToken = self.cancelPendingAutoCollapse()
                self.scheduleAutoCollapse(after: max(4.0, Double(finalSummary.count) * 0.08 + 2.0), forToken: responseToken)
                SpeechPipelineEngine.shared.speakResponse(finalSummary) { [weak self] in
                    DispatchQueue.main.async {
                        self?.scheduleAutoCollapse(after: 1.2, forToken: responseToken)
                    }
                }
            }
        }
    }
    
    public func clearChatHistory() {
        BoringSoundEngine.shared.playTap()
        LocalChatMemoryManager.shared.clearChat()
        self.chatMessages = LocalChatMemoryManager.shared.allMessages()
        self.currentAgentReply = ""
        self.currentTranscript = ""
        self.llmSuggestions = []
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
        // 0. If user tells Jarvis to shut up / quiet down, silence speech and collapse open hover pill immediately
        cancelPendingAutoCollapse()
        if Self.isSilenceAndCollapseCommand(instruction) {
            shutUpAndCollapse()
            return
        }

        // 1. Cancel ongoing autonomous agent or computer-use task
        currentExecutionTask?.cancel()
        currentExecutionTask = nil
        if ComputerUseOperator.shared.isRunning {
            ComputerUseOperator.shared.stopActiveRun()
        }
        
        // 2. Stop any current speech playback immediately (barge-in)
        SpeechPipelineEngine.shared.bargeIn()
        
        // 3. Play queued chime
        BoringSoundEngine.shared.playQueued()
        
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let activeWake = TheVoiceAmbientListener.shared.wakePhrase
        
        // If bare wake word ("jarvis", "bro", "hey bro", "voice", "hey voice") without command:
        let isBareWake = trimmed.isEmpty || lower == activeWake || lower == "hey \(activeWake)" || lower == "ok \(activeWake)" ||
                         lower == "voice" || lower == "the voice" || lower == "hey voice" || lower == "ok voice" ||
                         lower == "bro" || lower == "hey bro" || lower == "yo bro" || lower == "ok bro"
        if isBareWake {
            // Use zero-lag hot capture on the already-running ambient AVAudioEngine when available!
            if mode == .agent && TheVoiceAmbientListener.shared.isListening {
                recordingWatchdogWorkItem?.cancel()
                GoogleSearchEngine.shared.clearLastAnswer()
                currentTranscript = ""
                executionState = .listening(.agent)
                islandState = .voiceCompact(.agent)
                TheVoiceAmbientListener.shared.beginHotFollowUpCapture()
            } else {
                triggerVoice(mode: mode)
            }
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

    // MARK: - Email Draft Presentation & Real-Time Send
    public func presentEmailDraft(_ draft: EmailDraft) {
        cancelPendingAutoCollapse()
        self.activeEmailDraft = draft
        self.islandState = .emailDraftExpanded(draft)
        self.isCompactResponseMode = false
        self.activeNotchTab = .ask
        BoringSoundEngine.shared.playNotchOpen()
    }

    public func openEmailComposerDemo() {
        let demoDraft = EmailDraft(
            to: ["david@company.com"],
            subject: "Project update and Thursday sync",
            body: "Hi David,\n\nThe designs look great. Let's sync Thursday.\n\nBest"
        )
        presentEmailDraft(demoDraft)
    }

    public func dismissEmailDraft() {
        cancelPendingAutoCollapse()
        self.activeEmailDraft = nil
        _ = VoiceEmailManager.shared.discardFocusedDraft()
        if let action = currentAction, action.appName.lowercased().contains("mail") || (action.payload["tool_name"] ?? "").contains("email") {
            dismissAction()
        } else {
            islandState = isPinned ? .pinned : .resting
        }
    }

    public func sendActiveEmailDraft(customDraft: EmailDraft? = nil) {
        if let action = currentAction, action.appName.lowercased().contains("mail") || (action.payload["tool_name"] ?? "").contains("email") {
            approveCurrentAction()
            self.activeEmailDraft = nil
            return
        }

        guard let draftToSend = customDraft ?? activeEmailDraft ?? VoiceEmailManager.shared.focusedDraft() else { return }

        // If called from the pill's onSend callback (after ViewModel already sent),
        // just clear state — don't re-send.
        if customDraft != nil {
            self.activeEmailDraft = nil
            self.executionState = .completed("✓ Email sent to \(draftToSend.to.joined(separator: ", ")).")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                if !self.isPinned { self.islandState = .resting }
                self.executionState = .idle
            }
            return
        }

        // Voice-triggered send path (no pill ViewModel) — send via backend
        Task { @MainActor in
            self.executionState = .executing("Sending email to \(draftToSend.to.joined(separator: ", "))...")
            let result = await VoiceEmailManager.shared.sendDraft(draftToSend, undoWindowOverride: 0) { _ in true }
            if result.success {
                BoringSoundEngine.shared.playDone()
                self.activeEmailDraft = nil
                self.executionState = .completed("✓ Email sent to \(draftToSend.to.joined(separator: ", ")).")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if !self.isPinned {
                        self.islandState = .resting
                    }
                    self.executionState = .idle
                }
            } else {
                self.executionState = .error(result.errorMessage ?? "Failed to send email.")
            }
        }
    }

    public func presentCalendarEventDraft(_ draft: CalendarEventDraft) {
        cancelPendingAutoCollapse()
        self.activeEventDraft = draft
        self.islandState = .calendarEventExpanded(draft)
        self.isCompactResponseMode = false
        self.activeNotchTab = .ask
        BoringSoundEngine.shared.playNotchOpen()
    }

    public func dismissCalendarEventDraft() {
        self.activeEventDraft = nil
        CalendarMessagesService.shared.clearEventDraft()
        if let action = currentAction, action.appName.lowercased().contains("calendar") || action.appName.lowercased().contains("reminder") || (action.payload["tool_name"] ?? "").contains("calendar") {
            dismissAction()
        } else {
            islandState = isPinned ? .pinned : .resting
        }
    }

    public func saveActiveCalendarEventDraft(customDraft: CalendarEventDraft? = nil) {
        if let action = currentAction, action.appName.lowercased().contains("calendar") || action.appName.lowercased().contains("reminder") || (action.payload["tool_name"] ?? "").contains("calendar") {
            approveCurrentAction()
            self.activeEventDraft = nil
            return
        }

        guard let draftToSave = customDraft ?? activeEventDraft ?? CalendarMessagesService.shared.focusedEventDraft() else { return }

        Task { @MainActor in
            self.executionState = .executing("Saving \(draftToSave.title)...")
            let result = await CalendarMessagesService.shared.saveDraft(draftToSave)
            if result.success {
                BoringSoundEngine.shared.playDone()
                self.activeEventDraft = nil
                self.executionState = .completed("✓ \(result.summary)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if !self.isPinned {
                        self.islandState = .resting
                    }
                }
            } else {
                self.executionState = .error(result.summary)
            }
        }
    }
}
