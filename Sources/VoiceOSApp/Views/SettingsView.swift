import SwiftUI
import VoiceOSCore
import AppKit

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case voice = "Voice & Wake-Word"
    case jarvis = "JARVIS & Routines"
    case proactive = "Proactive & Home"
    case advanced = "Lab & Security"
    case brain = "AI Brain & Models"
    case permissions = "System Access"
    case account = "Account & Privacy"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .voice: return "waveform.badge.mic"
        case .jarvis: return "sparkles"
        case .proactive: return "bolt.shield.fill"
        case .advanced: return "cube.transparent"
        case .brain: return "brain.head.profile"
        case .permissions: return "hand.raised.fill"
        case .account: return "person.crop.circle.badge.checkmark"
        }
    }
}

public struct SettingsView: View {
    @ObservedObject var appState: AppState
    
    @State private var selectedTab: SettingsTab = .general
    @State private var profileName: String = ""
    @State private var profileEmail: String = ""
    @State private var profileSavedNotice: Bool = false
    @State private var showingResetAlert: Bool = false
    @State private var showingModelSetupSheet: Bool = false
    
    // Voice & Audition State
    @State private var availableVoices: [VoiceOption] = []
    @State private var selectedVoiceIdentifier: String = UserDefaults.standard.string(forKey: "voiceos.selected_voice_id") ?? ""
    @State private var isAuditioningVoice: Bool = false
    @State private var selectedSTTKind: STTProviderKind = STTEngineProvider.shared.selectedKind
    @State private var isKokoroEnabled: Bool = KokoroTTSEngine.shared.isPreferredForTTS
    @State private var wakePhraseInput: String = TheVoiceAmbientListener.shared.wakePhrase
    @State private var selectedKokoroVoice: String = KokoroTTSEngine.shared.selectedVoiceId

    // Phase 1: Persona, Routines & Memory State
    @State private var personaConfig: PersonaConfiguration = PersonaManager.shared.currentConfiguration()
    @State private var newRoutineName: String = ""
    @State private var newRoutineTrigger: String = ""
    @State private var newRoutineStepsText: String = ""
    @State private var routineStatusBanner: String = ""
    @State private var newMemoryNote: String = ""
    @State private var newMemoryKind: MemoryFactKind = .fact

    // Phase 2: Proactive, Local RAG, Smart Home & Health State
    @State private var proactiveRules: [ProactiveRuleConfig] = ProactiveRulesEngine.shared.allRules()
    @State private var ragFolderInput: String = ""
    @State private var ragChunkCount: Int = LocalKnowledgeStore.shared.totalIndexedChunks()
    @State private var haURLInput: String = SmartHomeManager.shared.configuration().homeAssistantURL
    @State private var haTokenInput: String = KeychainService.shared.get(.homeAssistantToken) ?? ""
    @State private var mqttHostInput: String = SmartHomeManager.shared.configuration().mqttHost
    @State private var mqttPasswordInput: String = KeychainService.shared.get(.mqttPassword) ?? ""
    @State private var smartHomeSavedBanner: String = ""
    @State private var healthOptInToggle: Bool = HealthInsightsManager.shared.isOptedIn()
    @State private var healthSummaryText: String = HealthInsightsManager.shared.computeDigest().summaryText
    @State private var healthReminderTitle: String = ""
    @State private var healthReminderSchedule: String = "Daily 09:00"

    // Phase 3: Iron Legion, CAD/3D Hologram, Cyber Defense, Camera Vision, Companion & Plugins
    @State private var legionMissionInput: String = "Audit module architecture"
    @State private var cadShapeChoice: CADShapeKind = .bracket
    @State private var cadBackendChoice: CADBackend = .openscad
    @State private var generatedCADResult: CADGenerationResult = EngineeringStudioEngine.shared.generateCAD(shape: .bracket, backend: .openscad)
    @State private var physicsSummary: String = ""
    @State private var securityReportSummary: String = "Not scanned yet."
    @State private var cameraOptIn: Bool = LocalCameraVisionService.shared.isCameraOptedIn()
    @State private var faceRecOptIn: Bool = LocalCameraVisionService.shared.isFaceRecognitionEnabled()
    @State private var activePairingPIN: String = ""
    @State private var pairingDeviceNameInput: String = "iPhone"
    @State private var companionPinInput: String = ""
    @State private var companionStatusBanner: String = ""
    @State private var newPluginName: String = ""
    @State private var newPluginReplyTemplate: String = ""
    
    // Account Authentication State
    @State private var authIsLoginMode: Bool = true
    @State private var authEmailInput: String = ""
    @State private var authPasswordInput: String = ""
    @State private var authNameInput: String = ""
    @State private var authErrorMessage: String = ""
    @State private var authSuccessMessage: String = ""
    @State private var isAuthLoading: Bool = false
    @State private var currentAccount: UserAccount? = AccountAuthService.shared.currentAccount
    
    // AI Brain State
    @State private var activeMode: ModelMode = ModelRouter.shared.currentMode
    @State private var openAIKey: String = KeychainService.shared.get(.openAIApiKey) ?? ""
    @State private var claudeKey: String = KeychainService.shared.get(.anthropicApiKey) ?? ""
    @State private var searchKey: String = KeychainService.shared.get(.searchProviderKey) ?? ""
    @State private var googleApiKey: String = KeychainService.shared.get(.googleSearchApiKey) ?? ""
    @State private var googleEngineId: String = KeychainService.shared.get(.googleSearchEngineId) ?? ""
    @State private var isTestingGoogle: Bool = false
    @State private var googleTestResult: String = ""
    @State private var keySavedNotice: String = ""
    @State private var isProbingHealth: Bool = false
    @State private var healthProbeResult: String = ""
    @State private var isSoundEnabled: Bool = BoringSoundEngine.shared.isSoundEnabled
    
    // Local AI Auto-Connection State
    @State private var isConnectingLocalModels: Bool = false
    @State private var localModelStatusMessage: String = ""
    @State private var isLocalModelConnected: Bool = false
    @State private var localDiscoveredCount: Int = 0
    @State private var localActiveModelName: String = ""
    
    public init(appState: AppState) {
        self.appState = appState
        _profileName = State(initialValue: appState.userName)
        _profileEmail = State(initialValue: appState.userEmail)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Settings")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                        Text("Preferences, voice configuration, local models, and account privacy.")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                    }
                    Spacer()
                }
                
                // Segmented Tab Picker (Scrollable if narrow, fixedSize single line, never squished)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(SettingsTab.allCases) { tab in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedTab = tab
                                }
                            }) {
                                HStack(spacing: 7) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(tab.rawValue)
                                        .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .medium))
                                        .lineLimit(1)
                                }
                                .foregroundColor(selectedTab == tab ? DesignTokens.Monochrome.textPrimary : DesignTokens.Monochrome.textMuted)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedTab == tab ? DesignTokens.Monochrome.surfaceElevated : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                            .fixedSize(horizontal: true, vertical: true)
                        }
                    }
                    .padding(3)
                }
                .background(DesignTokens.Monochrome.surface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DesignTokens.Monochrome.border, lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 14)
            
            Divider()
                .overlay(DesignTokens.Monochrome.border)
            
            // Tab Content Body
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .general:
                        generalSettingsTab
                    case .voice:
                        voiceSettingsTab
                    case .jarvis:
                        jarvisSettingsTab
                    case .proactive:
                        proactiveSettingsTab
                    case .advanced:
                        advancedLabSettingsTab
                    case .brain:
                        aiBrainSettingsTab
                    case .permissions:
                        systemPermissionsTab
                    case .account:
                        accountAndPrivacyTab
                    }
                }
                .padding(24)
            }
        }
        .onAppear {
            availableVoices = VoiceAuditionManager.shared.listAllAvailableVoices()
            if selectedVoiceIdentifier.isEmpty, let first = availableVoices.first {
                selectedVoiceIdentifier = first.identifier
            }
            wakePhraseInput = TheVoiceAmbientListener.shared.wakePhrase
            selectedKokoroVoice = KokoroTTSEngine.shared.selectedVoiceId
            personaConfig = PersonaManager.shared.currentConfiguration()
            appState.refreshPhase1State()
            appState.refreshPhase2State()
            proactiveRules = ProactiveRulesEngine.shared.allRules()
            ragChunkCount = LocalKnowledgeStore.shared.totalIndexedChunks()
            healthOptInToggle = HealthInsightsManager.shared.isOptedIn()
            healthSummaryText = HealthInsightsManager.shared.computeDigest().summaryText
            appState.refreshPhase3State()
            cameraOptIn = LocalCameraVisionService.shared.isCameraOptedIn()
            faceRecOptIn = LocalCameraVisionService.shared.isFaceRecognitionEnabled()
        }
        .background(DesignTokens.Monochrome.windowBg)
        .sheet(isPresented: $showingModelSetupSheet) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") {
                        showingModelSetupSheet = false
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(16)
                }
                ModelSetupDashboardView()
            }
            .frame(minWidth: 780, minHeight: 620)
            .background(Color(red: 0.08, green: 0.08, blue: 0.09))
        }
        .onAppear {
            self.profileName = appState.userName
            self.profileEmail = appState.userEmail
            self.isSoundEnabled = BoringSoundEngine.shared.isSoundEnabled
            self.currentAccount = AccountAuthService.shared.currentAccount
            if activeMode == .local || activeMode == .hybrid {
                connectLocalAIModels()
            }
        }
    }
    
    // MARK: - Tab: Voice & Hands-Free Ambient Wake-Word
    
    private var voiceSettingsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Hands-Free Ambient Wake-Word Card
            settingsCard(title: "Hands-Free Ambient Wake-Word (\"Voice ...\")", icon: "waveform.badge.mic") {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(appState.isTheVoiceModeEnabled ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text("Enable \"Voice ...\" Ambient Wake-Word")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            }
                            Text("When enabled, Voice.AI runs low-power background listening. You can speak 'Voice, adjust volume to 80%' or 'Voice, open Spotify' hands-free without touching any key.")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        Spacer()
                        Toggle("", isOn: $appState.isTheVoiceModeEnabled)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                    }
                    
                    HStack(spacing: 10) {
                        Text("Wake Phrase:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DesignTokens.Monochrome.textSecondary)
                        TextField("jarvis", text: $wakePhraseInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 140)
                            .onChange(of: wakePhraseInput) { _, newValue in
                                let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !clean.isEmpty {
                                    TheVoiceAmbientListener.shared.wakePhrase = clean
                                }
                            }
                        ForEach(["jarvis", "friday", "voice"], id: \.self) { preset in
                            Button(preset.capitalized) {
                                wakePhraseInput = preset
                                TheVoiceAmbientListener.shared.wakePhrase = preset
                            }
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(wakePhraseInput.lowercased() == preset ? Color.blue.opacity(0.22) : DesignTokens.Monochrome.surfaceElevated)
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            .cornerRadius(5)
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }

                    if appState.isTheVoiceModeEnabled {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 11))
                            Text("Active: Say \"\(wakePhraseInput.isEmpty ? "Jarvis" : wakePhraseInput.capitalized), open Spotify\" anytime hands-free (on-device).")
                                .font(.system(size: 11))
                                .foregroundColor(Color.blue.opacity(0.9))
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(6)
                    }
                }
            }
            
            // 2. Offline Neural Voice Card (Kokoro-82M)
            settingsCard(title: "Offline Neural Voice (Kokoro-82M)", icon: "speaker.wave.3.fill") {
                let kokoroDiag = KokoroTTSEngine.shared.diagnostics()
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kokoro-82M Local TTS Engine")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Text(kokoroDiag.statusSummary)
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        Spacer()
                        
                        Toggle("", isOn: $isKokoroEnabled)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                            .onChange(of: isKokoroEnabled) { _, enabled in
                                KokoroTTSEngine.shared.isPreferredForTTS = enabled
                            }
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(kokoroDiag.isFullyReady ? Color.green : (kokoroDiag.hasWeights ? Color.yellow : Color.orange))
                                .frame(width: 8, height: 8)
                            Text(kokoroDiag.isFullyReady ? "Active (86 MB)" : (kokoroDiag.hasWeights ? "Weights Only" : "Missing Weights"))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(kokoroDiag.isFullyReady ? Color.green : (kokoroDiag.hasWeights ? Color.yellow : Color.orange))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DesignTokens.Monochrome.surfaceElevated)
                        .cornerRadius(6)
                    }

                    HStack(spacing: 10) {
                        Text("Neural Voice:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DesignTokens.Monochrome.textSecondary)
                        Picker("Neural Voice", selection: $selectedKokoroVoice) {
                            ForEach(KokoroVoicePreset.presets) { preset in
                                Text("\(preset.label) — \(preset.style)").tag(preset.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 280)
                        .onChange(of: selectedKokoroVoice) { _, voiceId in
                            KokoroTTSEngine.shared.selectedVoiceId = voiceId
                        }
                        Spacer()
                    }
                    
                    HStack(spacing: 10) {
                        Button(action: {
                            SpeechPipelineEngine.shared.speakResponse("At your service. Voice AI streaming synthesis and barge-in interruption are online.")
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "speaker.wave.2")
                                Text("Test Streaming Voice")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(DesignTokens.Monochrome.surfaceElevated)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            SpeechPipelineEngine.shared.bargeIn()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "stop.circle")
                                Text("Stop (Barge-In)")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        if !kokoroDiag.hasWeights {
                            Button(action: {
                                showingModelSetupSheet = true
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Download / Repair Kokoro")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Spacer()
                    }
                }
            }
            
            // 2b. Speech-to-Text Engine (Apple Speech / Local Whisper)
            settingsCard(title: "Speech Recognition Engine (Whisper & Apple Speech)", icon: "waveform") {
                let whisperDiag = LocalWhisperProvider.diagnostics()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active STT Provider")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Text(whisperDiag.statusSummary)
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        Spacer()
                        Picker("", selection: $selectedSTTKind) {
                            Text("Apple Speech").tag(STTProviderKind.appleEnhanced)
                            Text("Local Whisper").tag(STTProviderKind.localWhisper)
                        }
                        .frame(width: 170)
                        .onChange(of: selectedSTTKind) { _, newKind in
                            STTEngineProvider.shared.selectedKind = newKind
                        }
                    }
                    
                    if whisperDiag.modelPath == nil {
                        HStack {
                            Button(action: {
                                if let item = HardwareProfileDetector.shared.getCatalogItems(for: .lite).first(where: { $0.id == "speech.whisper.base" }) {
                                    LocalModelDownloadManager.shared.queueDownloads(items: [item])
                                    Task {
                                        await LocalModelDownloadManager.shared.startDownload(for: item)
                                    }
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.down.circle")
                                    Text("Download Whisper Base Model (142 MB)")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                    }
                }
            }
            
            // 3. System & Accent Voice Selection Card
            settingsCard(title: "System & Accent Voice Selection", icon: "person.wave.2.fill") {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active Spoken Voice")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Text("Select preferred voice persona and accent for assistant speech.")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        Spacer()
                        
                        if !availableVoices.isEmpty {
                            Picker("", selection: $selectedVoiceIdentifier) {
                                ForEach(availableVoices, id: \.identifier) { voice in
                                    Text(voice.name).tag(voice.identifier)
                                }
                            }
                            .frame(width: 220)
                            .onChange(of: selectedVoiceIdentifier) { newId in
                                UserDefaults.standard.set(newId, forKey: "voiceos.selected_voice_id")
                            }
                        } else {
                            Text("Default System Voice (Ava / Samantha)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                    }
                    
                    HStack {
                        Button(action: {
                            if let opt = availableVoices.first(where: { $0.identifier == selectedVoiceIdentifier }) {
                                Task {
                                    isAuditioningVoice = true
                                    try? await VoiceAuditionManager.shared.auditionVoice(voice: opt)
                                    isAuditioningVoice = false
                                }
                            } else {
                                SpeechPipelineEngine.shared.speakResponse("This is your assistant speaking.")
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: isAuditioningVoice ? "waveform" : "play.circle")
                                Text(isAuditioningVoice ? "Playing Audition..." : "Audition Voice Sample")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(DesignTokens.Monochrome.surfaceElevated)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isAuditioningVoice)
                        
                        Spacer()
                    }
                }
            }
        }
    }
    
    // MARK: - Tab 1: General & Hotkeys
    
    private var generalSettingsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Hotkeys Card
            settingsCard(title: "Voice Hotkeys & Triggers", icon: "keyboard.fill") {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dictation Mode Hotkey")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Text("Hold to speak, release to insert clean transcribed text into the active app.")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        Spacer()
                        Text("fn / Globe (Hold)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(DesignTokens.Monochrome.surfaceElevated)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                    }
                    
                    Divider().overlay(DesignTokens.Monochrome.border)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Agent Action Mode Hotkey")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Text("Hold to issue natural voice actions across macOS, connected apps, and tools.")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        Spacer()
                        Text("⌃ Control (Hold)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(DesignTokens.Monochrome.surfaceElevated)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                    }
                }
            }
            
            // Notch Media Display Card (Spotify & YouTube)
            settingsCard(title: "Notch Media Display (Spotify & YouTube)", icon: "play.rectangle.on.rectangle.fill") {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show Media in Notch Display")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Text("Shows interactive wings and hover controls on the MacBook notch when Spotify or YouTube is actively playing.")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        Spacer()
                        
                        Toggle("", isOn: $appState.isNotchMediaDisplayEnabled)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                    }
                    
                    if !appState.isNotchMediaDisplayEnabled {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.slash.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                            Text("Media wings and playback controls are hidden from the notch display.")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.Monochrome.surfaceElevated)
                        .cornerRadius(6)
                    }
                }
            }
            
            // Audio Feedback Card
            settingsCard(title: "Acoustic Audio Feedback", icon: "speaker.wave.2.fill") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Earcons & Acoustic Feedback")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                        Text("Plays subtle, high-fidelity audio cues on voice start, plan dispatch, and completion.")
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                    }
                    Spacer()
                    
                    Button(action: {
                        BoringSoundEngine.shared.playDone()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle")
                            Text("Test Earcon")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DesignTokens.Monochrome.surfaceElevated)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    Toggle("", isOn: $isSoundEnabled)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                        .onChange(of: isSoundEnabled) { enabled in
                            BoringSoundEngine.shared.isSoundEnabled = enabled
                            if enabled {
                                BoringSoundEngine.shared.playDone()
                            }
                        }
                }
            }
            
            // Profile Card
            settingsCard(title: "User Profile & Identity", icon: "person.text.rectangle.fill") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Display Name")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.Monochrome.textSecondary)
                            .frame(width: 110, alignment: .leading)
                        TextField("Name", text: $profileName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Email Address")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.Monochrome.textSecondary)
                            .frame(width: 110, alignment: .leading)
                        TextField("Email", text: $profileEmail)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        if profileSavedNotice {
                            Text("✓ Profile saved successfully")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color.green)
                        }
                        Spacer()
                        Button(action: {
                            appState.updateProfile(name: profileName, email: profileEmail)
                            profileSavedNotice = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                profileSavedNotice = false
                            }
                        }) {
                            Text("Save Profile")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    // MARK: - Tab 2: AI Brain & Models
    
    private var aiBrainSettingsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Execution Mode
            settingsCard(title: "Execution Mode", icon: "cpu.fill") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active Intelligence Routing")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Text(ModelRouter.shared.getStatusSummary().privacyDescription)
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        Spacer()
                        Picker("", selection: $activeMode) {
                            ForEach(ModelMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .frame(width: 240)
                        .onChange(of: activeMode) { _, newMode in
                            ModelRouter.shared.currentMode = newMode
                            if newMode == .local || newMode == .hybrid {
                                connectLocalAIModels()
                            } else {
                                isLocalModelConnected = false
                                localModelStatusMessage = "Local Ollama paused (\(newMode.rawValue) active)."
                                Task.detached {
                                    await ModelLifecycleManager.shared.offloadAllModelsImmediately()
                                }
                            }
                        }
                    }
                    
                    if activeMode == .local || activeMode == .hybrid {
                        Divider().overlay(DesignTokens.Monochrome.border)
                        localModelStatusBanner
                    }
                }
            }
            
            // In-App Local Models & Dashboard Card
            settingsCard(title: "Local On-Device Models", icon: "internaldrive.fill") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Core 3 Architecture (100% Offline)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Text("The Brain (Llama 3.2 3B), The Eyes (LLaVA 7B), and The Voice (Kokoro 82M).")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        Spacer()
                        Button(action: {
                            showingModelSetupSheet = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Open Model Setup Dashboard")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider().overlay(DesignTokens.Monochrome.border)
                    
                    // Hardware & Dynamic RAM Status
                    HStack {
                        let hw = HardwareProfileDetector.shared.detectHardware()
                        HStack(spacing: 6) {
                            Image(systemName: "memorychip")
                                .foregroundColor(hw.hasLowMemoryGuardrail ? .orange : .green)
                            Text("\(Int(hw.totalRamGigabytes)) GB RAM Detected")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                        }
                        
                        Spacer()
                        
                        Text("Dynamic RAM Suspension: Active")
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                    }
                }
            }
            
            // Cloud Credentials
            settingsCard(title: "Cloud API Keys (macOS Keychain)", icon: "key.fill") {
                VStack(spacing: 12) {
                    HStack {
                        Text("OpenAI Key:")
                            .font(.system(size: 12))
                            .frame(width: 100, alignment: .leading)
                            .foregroundColor(DesignTokens.Monochrome.textSecondary)
                        SecureField("sk-proj-...", text: $openAIKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            KeychainService.shared.set(openAIKey, for: .openAIApiKey)
                            showNotice("OpenAI Key Saved")
                        }
                    }
                    
                    HStack {
                        Text("Claude Key:")
                            .font(.system(size: 12))
                            .frame(width: 100, alignment: .leading)
                            .foregroundColor(DesignTokens.Monochrome.textSecondary)
                        SecureField("sk-ant-...", text: $claudeKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            KeychainService.shared.set(claudeKey, for: .anthropicApiKey)
                            showNotice("Claude Key Saved")
                        }
                    }
                    
                    if !keySavedNotice.isEmpty {
                        HStack {
                            Text("✓ \(keySavedNotice)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color.green)
                            Spacer()
                        }
                    }
                }
            }
            
            // Google Search Settings (if mode is Google Search or general)
            if activeMode == .googleSearch {
                settingsCard(title: "Google Search Mode Options", icon: "globe") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quota: \(GoogleSearchEngine.shared.getUsedDailyQuota()) / 100 queries used today")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.green)
                        
                        HStack {
                            Text("Google API Key:")
                                .font(.system(size: 12))
                                .frame(width: 110, alignment: .leading)
                                .foregroundColor(DesignTokens.Monochrome.textSecondary)
                            SecureField("AIzaSy... (Optional)", text: $googleApiKey)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") {
                                KeychainService.shared.set(googleApiKey, for: .googleSearchApiKey)
                                showNotice("Google Key Saved")
                            }
                        }
                        
                        HStack {
                            Button(action: testGoogleSearch) {
                                HStack(spacing: 4) {
                                    if isTestingGoogle { ProgressView().scaleEffect(0.6) }
                                    Text(isTestingGoogle ? "Testing..." : "Test Google Query")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(DesignTokens.Monochrome.surfaceElevated)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(isTestingGoogle)
                            
                            if !googleTestResult.isEmpty {
                                Text(googleTestResult)
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.green)
                            }
                        }
                    }
                }
            }
            
            // Live Health Probe
            settingsCard(title: "Health & Capability Probe", icon: "bolt.badge.checkmark.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active Model Live Audit")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Text("Tests response streaming, tool calling schema, and tokens/sec latency.")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        Spacer()
                        Button(action: runHealthProbe) {
                            HStack(spacing: 4) {
                                if isProbingHealth { ProgressView().scaleEffect(0.6) }
                                Text(isProbingHealth ? "Probing..." : "Run Health Check")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isProbingHealth)
                    }
                    
                    if !healthProbeResult.isEmpty {
                        Text(healthProbeResult)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color.green)
                            .padding(8)
                            .background(Color.green.opacity(0.08))
                            .cornerRadius(6)
                    }
                }
            }
        }
    }
    
    // MARK: - Tab 3: System Access
    
    private var systemPermissionsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            PermissionsDoctorView()
        }
    }
    
    // MARK: - Tab 4: Account & Privacy
    
    private var accountAndPrivacyTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Account Session
            settingsCard(title: currentAccount != nil ? "Account & Offline Grace Period" : "Sign In to Voice.AI Account", icon: currentAccount != nil ? "person.badge.shield.checkmark.fill" : "person.badge.key.fill") {
                VStack(spacing: 14) {
                    if let account = currentAccount {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                Text("\(account.email) • Provider: \(account.authProvider.capitalized)")
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                            }
                            Spacer()
                            Button("Log Out") {
                                AccountAuthService.shared.logOut()
                                currentAccount = nil
                                appState.userName = "Local User"
                                appState.userEmail = ""
                                authEmailInput = ""
                                authPasswordInput = ""
                                authErrorMessage = ""
                                authSuccessMessage = "Logged out successfully. You can sign in below or continue offline."
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.red.opacity(0.85))
                        }
                        
                        Divider().overlay(DesignTokens.Monochrome.border)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Offline Grace Period")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                Text("Valid for 30 days offline. Local voice control remains fully operational.")
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                            }
                            Spacer()
                            Text("Active ✓")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.green)
                        }
                    } else {
                        // Inline Log In / Create Account Form
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("", selection: $authIsLoginMode) {
                                Text("Log In").tag(true)
                                Text("Create Account").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 240)
                            
                            if !authIsLoginMode {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Display Name")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(DesignTokens.Monochrome.textSecondary)
                                    TextField("Your Name", text: $authNameInput)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Email Address")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
                                TextField("name@example.com", text: $authEmailInput)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Password")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
                                SecureField(authIsLoginMode ? "Enter password" : "At least 8 chars (upper, lower, number)", text: $authPasswordInput)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            if !authErrorMessage.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 12))
                                    Text(authErrorMessage)
                                        .font(.system(size: 11))
                                        .foregroundColor(.orange)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(6)
                            }
                            
                            if !authSuccessMessage.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 12))
                                    Text(authSuccessMessage)
                                        .font(.system(size: 11))
                                        .foregroundColor(.green)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                            }
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    performInlineAuth()
                                }) {
                                    HStack(spacing: 6) {
                                        if isAuthLoading {
                                            ProgressView().controlSize(.small)
                                        }
                                        Text(authIsLoginMode ? "Log In" : "Sign Up")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 7)
                                    .background(Color.blue)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .disabled(isAuthLoading)
                                
                                Button(action: {
                                    performGoogleAuth()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "globe")
                                        Text("Continue with Google")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(DesignTokens.Monochrome.surfaceElevated)
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                
                                Spacer()
                            }
                        }
                    }
                }
            }
            
            // Performance & Cache Metrics
            settingsCard(title: "Semantic Action Cache", icon: "bolt.fill") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cached UI Layout Coordinates")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                        Text("\(SemanticActionCache.shared.cachedEntriesCount) verified button coordinates cached for sub-5ms instant execution.")
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                    }
                    Spacer()
                    Button("Clear Cache") {
                        SemanticActionCache.shared.clear()
                        showNotice("Cache reset.")
                    }
                    .font(.system(size: 11))
                }
            }
            
            // Data Management & Reset
            settingsCard(title: "Data Management & Privacy", icon: "trash.fill") {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Export Local Data")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Text("Copies encrypted account history and profile to system clipboard as JSON.")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        Spacer()
                        Button("Export JSON") {
                            let json = AccountAuthService.shared.exportUserDataJSON()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(json, forType: .string)
                            showNotice("Data copied to clipboard.")
                        }
                        .font(.system(size: 11))
                    }
                    
                    Divider().overlay(DesignTokens.Monochrome.border)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reset All Conversation Data")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.red)
                            Text("Clears all sessions, word counts, and history records.")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        Spacer()
                        Button("Reset Everything") {
                            showingResetAlert = true
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.red)
                        .alert(isPresented: $showingResetAlert) {
                            Alert(
                                title: Text("Reset All Conversation Data"),
                                message: Text("Are you sure you want to clear all history records and session statistics?"),
                                primaryButton: .destructive(Text("Reset")) {
                                    appState.resetAllStatistics()
                                },
                                secondaryButton: .cancel()
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Reusable Settings Card Container
    
    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color.blue)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                Spacer()
            }
            
            content()
        }
        .padding(16)
        .background(DesignTokens.Monochrome.surface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DesignTokens.Monochrome.border, lineWidth: 1)
        )
    }
    
    // MARK: - Actions
    
    private func showNotice(_ text: String) {
        keySavedNotice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            keySavedNotice = ""
        }
    }
    
    private func runHealthProbe() {
        isProbingHealth = true
        healthProbeResult = "Probing active model..."
        Task {
            let model = ModelRouter.shared.resolveChatModel()
            let profile = await ModelCapabilityDetector.shared.probeChat(model: model, forceRefresh: true)
            await MainActor.run {
                self.isProbingHealth = false
                self.healthProbeResult = "✓ Verified: Streaming=\(profile.streaming), Tools=\(profile.toolCalling), Speed=\(profile.speedTokensPerSec) tok/s (\(model.providerName): \(model.modelIdentifier))"
            }
        }
    }
    
    private func testGoogleSearch() {
        isTestingGoogle = true
        googleTestResult = ""
        Task {
            if !googleApiKey.isEmpty {
                KeychainService.shared.set(googleApiKey, for: .googleSearchApiKey)
            }
            let card = await GoogleSearchEngine.shared.answerQuestion(query: "What is the capital of India?")
            await MainActor.run {
                self.googleTestResult = "✓ Received: \"\(card.answerText.prefix(35))...\" (\(card.methodLabel))"
                self.isTestingGoogle = false
            }
        }
    }
    
    // MARK: - Inline Account Authentication
    
    private func performInlineAuth() {
        authErrorMessage = ""
        authSuccessMessage = ""
        let trimmedEmail = authEmailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            authErrorMessage = "Please enter your email."
            return
        }
        guard trimmedEmail.contains("@") && trimmedEmail.contains(".") else {
            authErrorMessage = "Please enter a valid email address (e.g. name@example.com)."
            return
        }
        guard !authPasswordInput.isEmpty else {
            authErrorMessage = "Please enter your password."
            return
        }
        
        isAuthLoading = true
        defer { isAuthLoading = false }
        do {
            if authIsLoginMode {
                do {
                    let account = try AccountAuthService.shared.logIn(email: trimmedEmail, password: authPasswordInput)
                    currentAccount = account
                    appState.userName = account.displayName
                    appState.userEmail = account.email
                    authSuccessMessage = "Welcome back, \(account.displayName)!"
                } catch AuthError.invalidCredentials {
                    // If account doesn't exist yet, automatically create it with these credentials
                    do {
                        let defaultName = trimmedEmail.components(separatedBy: "@").first?.capitalized ?? "User"
                        let account = try AccountAuthService.shared.signUp(email: trimmedEmail, password: authPasswordInput, displayName: defaultName)
                        currentAccount = account
                        appState.userName = account.displayName
                        appState.userEmail = account.email
                        authSuccessMessage = "New account created and signed in as \(account.displayName)!"
                    } catch {
                        authErrorMessage = "Invalid credentials or password doesn't meet requirements. Switch to 'Create Account' above to set up a new account."
                    }
                }
            } else {
                do {
                    let account = try AccountAuthService.shared.signUp(email: trimmedEmail, password: authPasswordInput, displayName: authNameInput)
                    currentAccount = account
                    appState.userName = account.displayName
                    appState.userEmail = account.email
                    authSuccessMessage = "Account created successfully!"
                } catch AuthError.userAlreadyExists {
                    // Try logging in with the credentials
                    let account = try AccountAuthService.shared.logIn(email: trimmedEmail, password: authPasswordInput)
                    currentAccount = account
                    appState.userName = account.displayName
                    appState.userEmail = account.email
                    authSuccessMessage = "Welcome back, \(account.displayName)!"
                }
            }
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }
    
    private func performGoogleAuth() {
        let trimmed = authEmailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailToUse = (trimmed.contains("@") && trimmed.contains(".")) ? trimmed : nil
        let nameToUse = authNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : authNameInput
        let account = AccountAuthService.shared.signInWithGoogle(email: emailToUse, displayName: nameToUse)
        currentAccount = account
        appState.userName = account.displayName
        appState.userEmail = account.email
        authSuccessMessage = "Signed in with Google as \(account.displayName)!"
    }
    
    private var bannerColor: Color {
        if isLocalModelConnected { return .green }
        if isConnectingLocalModels { return .blue }
        return .orange
    }
    
    @ViewBuilder
    private var localModelStatusBanner: some View {
        HStack(spacing: 10) {
            if isConnectingLocalModels {
                ProgressView()
                    .controlSize(.small)
                Text("Turning on Ollama & connecting local AI models...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.blue)
            } else if isLocalModelConnected {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Local AI Models Online & Connected (\(localDiscoveredCount) discovered • Active: \(localActiveModelName))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.green)
                Spacer()
                Button(action: {
                    Task.detached {
                        await ModelLifecycleManager.shared.offloadAllModelsImmediately()
                        await MainActor.run {
                            self.isLocalModelConnected = false
                            self.localModelStatusMessage = "Ollama models offloaded from RAM."
                        }
                    }
                }) {
                    Text("Unload RAM")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.12))
                        .foregroundColor(.white)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color.green)
            } else {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                Text(localModelStatusMessage.isEmpty ? "Local models ready to start via Ollama" : localModelStatusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.orange)
                Spacer()
                Button(action: {
                    connectLocalAIModels()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Connect Ollama Now")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(bannerColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(bannerColor.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var jarvisSettingsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(title: "JARVIS Persona & Wit Layer", icon: "sparkles") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Configure assistant voice personality, dry wit, polite warnings, and candid probability estimates (works across English, Hindi, and Hinglish).")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)

                    Picker("Active Persona", selection: Binding(
                        get: { personaConfig.activePersona },
                        set: { newPersona in
                            personaConfig.activePersona = newPersona
                            PersonaManager.shared.updateConfiguration { $0.activePersona = newPersona }
                        }
                    )) {
                        ForEach(PersonaType.allCases) { persona in
                            Text(persona.rawValue).tag(persona)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(personaConfig.activePersona.description)
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textSecondary)

                    HStack {
                        Text("Dry Wit Level: \(Int(personaConfig.humorLevel * 100))%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            .frame(width: 140, alignment: .leading)
                        Slider(value: Binding(
                            get: { personaConfig.humorLevel },
                            set: { val in
                                personaConfig.humorLevel = val
                                PersonaManager.shared.updateConfiguration { $0.humorLevel = val }
                            }
                        ), in: 0.0...1.0, step: 0.05)
                    }

                    Toggle("Honest Probability Estimates before Risky Actions", isOn: Binding(
                        get: { personaConfig.honestProbabilityEstimates },
                        set: { val in
                            personaConfig.honestProbabilityEstimates = val
                            PersonaManager.shared.updateConfiguration { $0.honestProbabilityEstimates = val }
                        }
                    ))
                    .font(.system(size: 12))

                    Toggle("Polite Safety Warnings & Risk Cautions", isOn: Binding(
                        get: { personaConfig.politeWarningsEnabled },
                        set: { val in
                            personaConfig.politeWarningsEnabled = val
                            PersonaManager.shared.updateConfiguration { $0.politeWarningsEnabled = val }
                        }
                    ))
                    .font(.system(size: 12))

                    HStack(spacing: 10) {
                        Text("Language Style:")
                            .font(.system(size: 11, weight: .semibold))
                        Picker("Language Style", selection: Binding(
                            get: { personaConfig.languageStyle },
                            set: { style in
                                personaConfig.languageStyle = style
                                PersonaManager.shared.updateConfiguration { $0.languageStyle = style }
                            }
                        )) {
                            Text("Auto-Detect").tag("auto")
                            Text("English").tag("en")
                            Text("Hindi").tag("hi")
                            Text("Hinglish").tag("hinglish")
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        Spacer()
                    }
                }
            }

            settingsCard(title: "Routines & Protocols", icon: "flowchart.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Trigger multi-step workflows with one phrase (e.g. \"Good morning\", \"Focus mode\", \"House party protocol\"). Consequential steps still require Notch Approval.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)

                    if !routineStatusBanner.isEmpty {
                        Text(routineStatusBanner)
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(6)
                    }

                    ForEach(appState.configuredRoutines) { routine in
                        HStack(alignment: .top, spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { routine.isEnabled },
                                set: { enabled in
                                    RoutineManager.shared.setRoutineEnabled(id: routine.id, enabled: enabled)
                                    appState.refreshPhase1State()
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: Color.blue))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(routine.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                    if routine.isBuiltIn {
                                        Text("BUILT-IN")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.blue.opacity(0.12))
                                            .cornerRadius(4)
                                    }
                                    Text("\(routine.steps.count) steps")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(DesignTokens.Monochrome.textMuted)
                                }
                                Text("Triggers: \(routine.triggerPhrases.joined(separator: ", "))")
                                    .font(.system(size: 10))
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                            }

                            Spacer()

                            Button("Run") {
                                routineStatusBanner = "Running \"\(routine.name)\"..."
                                Task {
                                    let res = await RoutineManager.shared.runRoutine(routine, onProgress: nil)
                                    await MainActor.run {
                                        routineStatusBanner = "\(routine.name): \(res.summary)"
                                    }
                                }
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(5)
                            .buttonStyle(.plain)

                            if !routine.isBuiltIn {
                                Button(action: {
                                    RoutineManager.shared.deleteRoutine(id: routine.id)
                                    appState.refreshPhase1State()
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .background(DesignTokens.Monochrome.surfaceElevated)
                        .cornerRadius(6)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create Custom Routine")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(DesignTokens.Monochrome.textSecondary)
                        HStack(spacing: 8) {
                            TextField("Name (e.g. Coding Setup)", text: $newRoutineName)
                                .textFieldStyle(.roundedBorder)
                            TextField("Trigger phrase (e.g. start coding)", text: $newRoutineTrigger)
                                .textFieldStyle(.roundedBorder)
                        }
                        TextField("Steps (comma or newline separated prompts)", text: $newRoutineStepsText)
                            .textFieldStyle(.roundedBorder)
                        Button("Save Custom Routine") {
                            let name = newRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let trigger = newRoutineTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
                            let rawSteps = newRoutineStepsText
                                .components(separatedBy: CharacterSet(charactersIn: "\n,"))
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            guard !name.isEmpty, !trigger.isEmpty, !rawSteps.isEmpty else { return }
                            let steps = rawSteps.map { stepPrompt in
                                VoiceRoutineStep(title: stepPrompt, actionPrompt: stepPrompt, permissionTier: .reversible)
                            }
                            let routine = VoiceRoutine(
                                name: name,
                                triggerPhrases: [trigger.lowercased()],
                                summary: "Custom user workflow (\(steps.count) steps)",
                                isEnabled: true,
                                isBuiltIn: false,
                                steps: steps
                            )
                            RoutineManager.shared.saveRoutine(routine)
                            appState.refreshPhase1State()
                            newRoutineName = ""
                            newRoutineTrigger = ""
                            newRoutineStepsText = ""
                            routineStatusBanner = "Saved custom routine \"\(name)\"."
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                    }
                }
            }

            settingsCard(title: "Long-Term Memory Viewer", icon: "brain") {
                let longTermItems = appState.structuredMemories.filter { $0.scope == .longTerm }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Semantic long-term facts, preferences, projects, and people stored in encrypted per-account memory.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)

                    HStack(spacing: 8) {
                        Picker("Kind", selection: $newMemoryKind) {
                            Text("Fact").tag(MemoryFactKind.fact)
                            Text("Preference").tag(MemoryFactKind.preference)
                            Text("Project").tag(MemoryFactKind.project)
                            Text("Person").tag(MemoryFactKind.person)
                        }
                        .labelsHidden()
                        .frame(width: 110)

                        TextField("Say \"Remember this...\" or add a fact here", text: $newMemoryNote)
                            .textFieldStyle(.roundedBorder)

                        Button("Remember") {
                            let clean = newMemoryNote.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !clean.isEmpty else { return }
                            appState.rememberNoteFromUI(clean, kind: newMemoryKind)
                            newMemoryNote = ""
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                    }

                    if longTermItems.isEmpty {
                        Text("No long-term memories stored yet.")
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(longTermItems) { item in
                            HStack(spacing: 8) {
                                Text(item.kind.rawValue.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.cyan)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.cyan.opacity(0.14))
                                    .cornerRadius(4)
                                Text(item.content)
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                Spacer()
                                Button(action: {
                                    appState.forgetMemoryFromUI(id: item.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(DesignTokens.Monochrome.surfaceElevated)
                            .cornerRadius(6)
                        }
                    }
                }
            }
        }
    }

    private var proactiveSettingsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(title: "Proactive Alert Rules Engine (Event Bus)", icon: "bell.badge.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Configure rate-limited proactive alerts triggered by EventBus telemetry (battery, CPU/RAM, failed builds, calendar conflicts, important emails).")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)

                    ForEach(proactiveRules) { rule in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { rule.isEnabled },
                                set: { enabled in
                                    ProactiveRulesEngine.shared.setRuleEnabled(id: rule.id, enabled: enabled)
                                    proactiveRules = ProactiveRulesEngine.shared.allRules()
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: Color.blue))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                Text("Threshold: \(Int(rule.threshold)) • Cooldown: \(Int(rule.cooldownSeconds))s")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                            }
                            Spacer()
                        }
                        .padding(7)
                        .background(DesignTokens.Monochrome.surfaceElevated)
                        .cornerRadius(6)
                    }

                    HStack(spacing: 10) {
                        Button("Run Live Health Check") {
                            Task {
                                await ProactiveRulesEngine.shared.pollSystemHealthOnce()
                                await MainActor.run { appState.refreshPhase2State() }
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.16))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                        .buttonStyle(.plain)

                        if !appState.proactiveAlerts.isEmpty {
                            Button("Dismiss All Alerts (\(appState.proactiveAlerts.count))") {
                                ProactiveRulesEngine.shared.dismissAllAlerts()
                                appState.refreshPhase2State()
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }
            }

            settingsCard(title: "On-Device Local File & Knowledge Search (RAG)", icon: "doc.text.magnifyingglass") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Index user-chosen folders 100% locally with encrypted secret scrubbing and on-device embeddings (\(ragChunkCount) chunks indexed).")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)

                    HStack(spacing: 8) {
                        TextField("Folder path (e.g. ~/Documents/Notes)", text: $ragFolderInput)
                            .textFieldStyle(.roundedBorder)

                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                ragFolderInput = url.path
                            }
                        }
                        .font(.system(size: 11))

                        Button("Add & Index") {
                            appState.addAndIndexRAGFolder(path: ragFolderInput)
                            ragFolderInput = ""
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                ragChunkCount = LocalKnowledgeStore.shared.totalIndexedChunks()
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                    }

                    ForEach(appState.ragIndexedFolders, id: \.self) { folder in
                        HStack {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                            Text(folder)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Button(action: {
                                appState.removeRAGFolder(path: folder)
                                ragChunkCount = LocalKnowledgeStore.shared.totalIndexedChunks()
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(7)
                        .background(DesignTokens.Monochrome.surfaceElevated)
                        .cornerRadius(6)
                    }
                }
            }

            settingsCard(title: "Smart Home (Home Assistant / HomeKit / MQTT)", icon: "homekit") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Credentials are stored strictly in macOS Keychain. Locks & security alarms always require a Notch Approval Card (CONSEQUENTIAL tier).")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)

                    HStack(spacing: 8) {
                        TextField("Home Assistant URL", text: $haURLInput)
                            .textFieldStyle(.roundedBorder)
                        SecureField("HA Long-Lived Token (Keychain)", text: $haTokenInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 8) {
                        TextField("MQTT Host", text: $mqttHostInput)
                            .textFieldStyle(.roundedBorder)
                        SecureField("MQTT Password (Keychain)", text: $mqttPasswordInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 10) {
                        Button("Save Bridges to Keychain") {
                            SmartHomeManager.shared.updateConfiguration { cfg in
                                cfg.homeAssistantURL = haURLInput
                                cfg.mqttHost = mqttHostInput
                            }
                            SmartHomeManager.shared.setCredentials(
                                homeAssistantToken: haTokenInput,
                                mqttPassword: mqttPasswordInput
                            )
                            smartHomeSavedBanner = "Smart Home endpoints updated and credentials saved securely in Keychain."
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .buttonStyle(.plain)

                        if !smartHomeSavedBanner.isEmpty {
                            Text(smartHomeSavedBanner)
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        }
                    }

                    ForEach(appState.smartHomeDevices) { dev in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(dev.name)
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text(dev.kind.isSecurityCritical ? "CONSEQUENTIAL" : "REVERSIBLE")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundColor(dev.kind.isSecurityCritical ? .orange : .green)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background((dev.kind.isSecurityCritical ? Color.orange : Color.green).opacity(0.14))
                                        .cornerRadius(4)
                                }
                                Text("\(dev.room) • \(dev.bridge.rawValue) • State: \(dev.state)")
                                    .font(.system(size: 10))
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                            }
                            Spacer()
                            Button(dev.kind == .lock ? (dev.state == "locked" ? "Unlock" : "Lock") : (dev.state == "on" ? "Off" : "On")) {
                                let act: String
                                if dev.kind == .lock {
                                    act = dev.state == "locked" ? "unlock" : "lock"
                                } else if dev.kind == .securitySystem {
                                    act = dev.state == "armed" ? "disarm" : "arm"
                                } else {
                                    act = dev.state == "on" ? "off" : "on"
                                }
                                appState.controlSmartHomeDeviceFromUI(dev, action: act)
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(DesignTokens.Monochrome.surfaceElevated)
                            .cornerRadius(5)
                            .buttonStyle(.plain)
                        }
                        .padding(7)
                        .background(DesignTokens.Monochrome.surfaceElevated)
                        .cornerRadius(6)
                    }
                }
            }

            settingsCard(title: "Apple Health & Wearables (Opt-In, On-Device)", icon: "heart.text.square.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable Opt-In On-Device Health Import & Trend Warnings", isOn: $healthOptInToggle)
                        .font(.system(size: 12, weight: .semibold))
                        .onChange(of: healthOptInToggle) { _, enabled in
                            HealthInsightsManager.shared.setOptedIn(enabled)
                            healthSummaryText = HealthInsightsManager.shared.computeDigest().summaryText
                        }

                    Text(healthSummaryText)
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textSecondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.Monochrome.surfaceElevated)
                        .cornerRadius(6)

                    if healthOptInToggle {
                        HStack(spacing: 8) {
                            Button("Import Apple Health export.xml / JSON...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = true
                                panel.canChooseDirectories = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    let count = HealthInsightsManager.shared.importFromFileURL(url)
                                    healthSummaryText = "Imported \(count) sample(s). " + HealthInsightsManager.shared.computeDigest().summaryText
                                }
                            }
                            .font(.system(size: 11, weight: .semibold))

                            TextField("Reminder (e.g. Hydrate)", text: $healthReminderTitle)
                                .textFieldStyle(.roundedBorder)
                            Button("Add Reminder") {
                                let title = healthReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !title.isEmpty else { return }
                                _ = HealthInsightsManager.shared.addReminder(title: title, scheduleText: healthReminderSchedule)
                                healthReminderTitle = ""
                            }
                            .font(.system(size: 11, weight: .semibold))
                        }
                    }
                }
            }
        }
    }

    private var advancedLabSettingsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(title: "Iron Legion Parallel Subagents", icon: "cpu.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Spawn parallel Research, Code, and Summarize subagents tracked live in the Notch Agents tab.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)
                    HStack(spacing: 8) {
                        TextField("Mission goal...", text: $legionMissionInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Launch Iron Legion") {
                            appState.launchIronLegionMission(goal: legionMissionInput)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                    }
                }
            }

            settingsCard(title: "Engineering Studio: CAD, Physics & 3D Hologram", icon: "cube.transparent") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Picker("Shape", selection: $cadShapeChoice) {
                            ForEach(CADShapeKind.allCases, id: \.self) { shape in
                                Text(shape.rawValue.capitalized).tag(shape)
                            }
                        }
                        .frame(width: 150)

                        Picker("CAD Backend", selection: $cadBackendChoice) {
                            ForEach(CADBackend.allCases, id: \.self) { backend in
                                Text(backend.rawValue).tag(backend)
                            }
                        }
                        .frame(width: 150)

                        Button("Generate CAD & Hologram") {
                            generatedCADResult = EngineeringStudioEngine.shared.generateCAD(
                                shape: cadShapeChoice,
                                backend: cadBackendChoice
                            )
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .buttonStyle(.plain)

                        Button("Run Physics Sim") {
                            let sim = EngineeringStudioEngine.shared.simulateProjectile(velocityMS: 24, angleDegrees: 45)
                            physicsSummary = sim.summary
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }

                    HologramViewerView(htmlString: generatedCADResult.hologramHTML)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.4), lineWidth: 1))

                    Text(generatedCADResult.sourceCode)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(DesignTokens.Monochrome.textSecondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.Monochrome.surfaceElevated)
                        .cornerRadius(6)

                    if !physicsSummary.isEmpty {
                        Text(physicsSummary)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.cyan)
                    }
                }
            }

            settingsCard(title: "Cyber Defense & Lockdown Guardrail", icon: "shield.lefthalf.filled") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(securityReportSummary)
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textSecondary)

                    HStack(spacing: 10) {
                        Button("Run Port & LAN Scan") {
                            Task {
                                let rep = await CyberDefenseMonitor.shared.runLiveAnomalyScan()
                                await MainActor.run {
                                    securityReportSummary = rep.summary
                                    appState.latestSecurityReport = rep
                                }
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))

                        Button("Emergency Lockdown (CONSEQUENTIAL)") {
                            Task {
                                _ = await ToolRegistry.shared.invoke(name: "security_lockdown", arguments: ["reason": "User UI trigger"])
                            }
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.18))
                        .foregroundColor(.red)
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                    }
                }
            }

            settingsCard(title: "Local Camera Vision (Opt-In, On-Device Only)", icon: "camera.metering.center.weighted") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalCameraVisionService.privacyNotice)
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)

                    Toggle("Enable Opt-In Camera Object Detection & Hand Gestures", isOn: $cameraOptIn)
                        .font(.system(size: 12, weight: .semibold))
                        .onChange(of: cameraOptIn) { _, enabled in
                            LocalCameraVisionService.shared.setCameraOptedIn(enabled)
                            faceRecOptIn = LocalCameraVisionService.shared.isFaceRecognitionEnabled()
                        }

                    if cameraOptIn {
                        Toggle("Enable Local Face Recognition (Explicit Opt-In; Hashed Templates Only)", isOn: $faceRecOptIn)
                            .font(.system(size: 11))
                            .onChange(of: faceRecOptIn) { _, enabled in
                                LocalCameraVisionService.shared.setFaceRecognitionEnabled(enabled)
                            }
                        Button("Wipe Stored Face Templates") {
                            LocalCameraVisionService.shared.wipeFaceTemplates()
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    }
                }
            }

            settingsCard(title: "Phone Remote Companion & Approval Bridge", icon: "iphone.radiowaves.left.and.right") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Generate Pairing PIN") {
                            let challenge = PhoneCompanionService.shared.beginPairing()
                            activePairingPIN = challenge.code
                            companionStatusBanner = "Enter PIN \(challenge.code) to pair a companion device (expires in 5 min)."
                        }
                        .font(.system(size: 11, weight: .semibold))

                        if !activePairingPIN.isEmpty {
                            Text("PIN: \(activePairingPIN)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Device Name", text: $pairingDeviceNameInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        TextField("6-digit PIN", text: $companionPinInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Button("Complete Pair") {
                            if let paired = PhoneCompanionService.shared.completePairing(deviceName: pairingDeviceNameInput, code: companionPinInput) {
                                companionStatusBanner = "Paired '\(paired.device.deviceName)' securely via Keychain."
                                appState.refreshPhase3State()
                            } else {
                                companionStatusBanner = "Invalid or expired PIN."
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }

                    if !companionStatusBanner.isEmpty {
                        Text(companionStatusBanner)
                            .font(.system(size: 10.5))
                            .foregroundColor(.blue)
                    }

                    ForEach(appState.pairedCompanionDevices) { dev in
                        HStack {
                            Text(dev.deviceName)
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Button("Unpair") {
                                PhoneCompanionService.shared.unpairDevice(id: dev.id)
                                appState.refreshPhase3State()
                            }
                            .font(.system(size: 10.5))
                            .foregroundColor(.red)
                        }
                    }
                }
            }

            settingsCard(title: "External Plugin & MCP Loader", icon: "puzzlepiece.extension.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Plugin Tool Name (e.g. standup_note)", text: $newPluginName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Reply Template ({{input}})", text: $newPluginReplyTemplate)
                            .textFieldStyle(.roundedBorder)
                        Button("Install Plugin") {
                            let cleanName = newPluginName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "_")
                            guard !cleanName.isEmpty, !newPluginReplyTemplate.isEmpty else { return }
                            let manifest = ExternalPluginManifest(
                                id: "user_\(cleanName)",
                                name: cleanName.capitalized,
                                declarativeTools: [
                                    DeclarativePluginToolSpec(
                                        name: cleanName,
                                        description: "User-defined declarative plugin tool",
                                        permissionTier: "REVERSIBLE",
                                        responseTemplate: newPluginReplyTemplate
                                    )
                                ]
                            )
                            Task {
                                _ = await UserPluginManager.shared.installPlugin(manifest: manifest)
                                await MainActor.run {
                                    appState.refreshPhase3State()
                                    newPluginName = ""
                                    newPluginReplyTemplate = ""
                                }
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }

                    ForEach(appState.installedUserPlugins) { plugin in
                        HStack {
                            Text("\(plugin.name) (\(plugin.declarativeTools.count) tool(s))")
                                .font(.system(size: 11))
                            Spacer()
                            Button("Uninstall") {
                                UserPluginManager.shared.uninstallPlugin(id: plugin.id)
                                appState.refreshPhase3State()
                            }
                            .font(.system(size: 10.5))
                            .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }

    private func connectLocalAIModels() {
        isConnectingLocalModels = true
        localModelStatusMessage = "Turning on Ollama daemon & starting local AI models..."
        Task {
            let res = await ModelRouter.shared.connectLocalOfflineModels(timeoutSeconds: 12.0)
            await MainActor.run {
                self.isConnectingLocalModels = false
                self.isLocalModelConnected = res.success
                self.localModelStatusMessage = res.message
                self.localDiscoveredCount = res.models.count
                self.localActiveModelName = ModelRouter.shared.ollamaChatModel
            }
        }
    }
}
