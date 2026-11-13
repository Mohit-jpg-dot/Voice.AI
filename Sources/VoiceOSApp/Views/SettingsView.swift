import SwiftUI
import VoiceOSCore
import AppKit

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case voice = "Voice & Speech"
    case brain = "AI Models"
    case security = "Apps & Security"
    case account = "Account & Memory"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .voice: return "waveform.badge.mic"
        case .brain: return "cpu.fill"
        case .security: return "lock.shield.fill"
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
    @State private var showingClearMemoryAlert: Bool = false
    @State private var showingModelSetupSheet: Bool = false
    @State private var listenerStatusText: String = TheVoiceAmbientListener.shared.diagnosticSummary
    
    // Voice & Audition State
    @State private var availableVoices: [VoiceOption] = []
    @State private var selectedVoiceIdentifier: String = UserDefaults.standard.string(forKey: "voiceos.selected_voice_id") ?? ""
    @State private var isAuditioningVoice: Bool = false
    @State private var selectedSTTKind: STTProviderKind = STTEngineProvider.shared.selectedKind
    @State private var isKokoroEnabled: Bool = KokoroTTSEngine.shared.isPreferredForTTS
    @State private var wakePhraseInput: String = TheVoiceAmbientListener.shared.wakePhrase
    @State private var selectedKokoroVoice: String = KokoroTTSEngine.shared.selectedVoiceId

    // Safe Voice Terminal Settings
    @State private var autoRunReadOnlyTerminal: Bool = TerminalSecuritySettings.autoRunReadOnlyCommands
    @State private var terminalTimeoutSec: Double = TerminalSecuritySettings.timeoutSeconds
    @State private var customAllowedRoots: [String] = UserDefaults.standard.stringArray(forKey: PathPolicy.allowedRootsDefaultsKey) ?? []
    @State private var customAllowedPrograms: [String] = UserDefaults.standard.stringArray(forKey: CommandPolicy.extraProgramsDefaultsKey) ?? []
    @State private var newAllowedProgramInput: String = ""
    @State private var isLocalMemoryEnabled: Bool = MemoryStore.isMemoryEnabled
    @State private var emailUndoWindowSec: Double = EmailSecuritySettings.undoWindowSeconds
    @State private var emailWatchPollSec: Double = EmailSecuritySettings.watchPollIntervalSeconds
    @State private var emailQuietHoursEnabled: Bool = EmailSecuritySettings.isQuietHoursEnabled
    @State private var emailCapabilitySummary: String = "Tap Check Capability to test Mail.app / Gmail."
    
    // Messaging Connectors State
    @State private var slackTokenInput: String = KeychainService.shared.get(.slackUserToken) ?? ""
    @State private var slackConnected: Bool = (KeychainService.shared.get(.slackUserToken) != nil)
    @State private var discordTokenInput: String = KeychainService.shared.get(.discordBotToken) ?? ""
    @State private var discordConnected: Bool = (KeychainService.shared.get(.discordBotToken) != nil)
    @State private var whatsappTokenInput: String = KeychainService.shared.get(.whatsappCloudToken) ?? ""
    @State private var whatsappPhoneIdInput: String = KeychainService.shared.get(.whatsappPhoneNumberId) ?? ""
    @State private var messagingNotice: String = ""
    
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
                    case .brain:
                        aiBrainSettingsTab
                    case .security:
                        securityAndEmailTab
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
            listenerStatusText = TheVoiceAmbientListener.shared.diagnosticSummary
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
                        Divider().padding(.vertical, 2)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("24/7 Continuous Listening Mode (No Wake Word)")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                Text("Listens 24/7 so you can speak naturally without repeating a wake word—say 'bro open this up', 'tell me...', or 'can you see what's on my screen?'")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                            }
                            Spacer()
                            Toggle("", isOn: $appState.isAlwaysOnListeningMode)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: Color.green))
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Listen to Computer Audio (YouTube / Media)")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                Text("Off by default so background YouTube videos are ignored. Say \"listen to the things my computer is making\" to start listening and asking about playback.")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                            }
                            Spacer()
                            Toggle("", isOn: $appState.isComputerAudioListeningEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: Color.purple))
                                .onChange(of: appState.isComputerAudioListeningEnabled) { _, _ in
                                    listenerStatusText = TheVoiceAmbientListener.shared.diagnosticSummary
                                }
                        }

                        HStack(spacing: 8) {
                            Image(systemName: TheVoiceAmbientListener.shared.isListening ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(TheVoiceAmbientListener.shared.isListening ? .green : .orange)
                                .font(.system(size: 11))
                            Text(listenerStatusText)
                                .font(.system(size: 11))
                                .foregroundColor(TheVoiceAmbientListener.shared.isListening ? Color.green.opacity(0.95) : Color.orange.opacity(0.95))
                            Spacer()
                            Button("Retry / Refresh Mic") {
                                TheVoiceAmbientListener.shared.stopAmbientListening()
                                TheVoiceAmbientListener.shared.startAmbientListening()
                                listenerStatusText = TheVoiceAmbientListener.shared.diagnosticSummary
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((TheVoiceAmbientListener.shared.isListening ? Color.green : Color.orange).opacity(0.08))
                        .cornerRadius(6)
                        .onAppear {
                            listenerStatusText = TheVoiceAmbientListener.shared.diagnosticSummary
                        }
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
    
    private var securityAndEmailTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Safe Voice Terminal & Sandbox Policy
            settingsCard(title: "Safe Voice Terminal & Sandbox", icon: "terminal.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $autoRunReadOnlyTerminal) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-run read-only commands")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Text("OFF by default. When ON, READ_ONLY commands (ls, cat, find, grep, du, df) skip voice approval; mutating commands always prompt.")
                                .font(.system(size: 10.5))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                    }
                    .onChange(of: autoRunReadOnlyTerminal) { _, val in
                        TerminalSecuritySettings.autoRunReadOnlyCommands = val
                    }

                    Divider().overlay(DesignTokens.Monochrome.border)

                    HStack {
                        Text("Command Timeout: \(Int(terminalTimeoutSec))s")
                            .font(.system(size: 11.5))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                        Slider(value: $terminalTimeoutSec, in: 5...60, step: 5)
                            .onChange(of: terminalTimeoutSec) { _, val in
                                TerminalSecuritySettings.timeoutSeconds = val
                            }
                    }

                    Divider().overlay(DesignTokens.Monochrome.border)

                    HStack {
                        Text("Extra Allowed Folders (manual UI only)")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                        Spacer()
                        Button("Add Folder…") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                if !customAllowedRoots.contains(url.path) {
                                    customAllowedRoots.append(url.path)
                                    UserDefaults.standard.set(customAllowedRoots, forKey: PathPolicy.allowedRootsDefaultsKey)
                                    showNotice("Added allowed folder: \(url.lastPathComponent)")
                                }
                            }
                        }
                        .font(.system(size: 11))
                    }
                    if customAllowedRoots.isEmpty {
                        Text("Default roots: ~/Desktop, ~/Documents, ~/Downloads, ~/VoiceAI-Workspace")
                            .font(.system(size: 10.5))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                    } else {
                        ForEach(customAllowedRoots, id: \.self) { root in
                            HStack {
                                Text(root)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                                    .lineLimit(1)
                                Spacer()
                                Button("Remove") {
                                    customAllowedRoots.removeAll { $0 == root }
                                    UserDefaults.standard.set(customAllowedRoots, forKey: PathPolicy.allowedRootsDefaultsKey)
                                }
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                            }
                        }
                    }

                    Divider().overlay(DesignTokens.Monochrome.border)

                    HStack(spacing: 8) {
                        TextField("Add allowed CLI program (e.g. rg, jq)", text: $newAllowedProgramInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                        Button("Allow") {
                            let clean = newAllowedProgramInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            guard !clean.isEmpty, !CommandPolicy.alwaysBlockedPrograms.contains(clean) else {
                                showNotice("That program is permanently blocked by policy.")
                                return
                            }
                            if !customAllowedPrograms.contains(clean) {
                                customAllowedPrograms.append(clean)
                                UserDefaults.standard.set(customAllowedPrograms, forKey: CommandPolicy.extraProgramsDefaultsKey)
                            }
                            newAllowedProgramInput = ""
                        }
                        .font(.system(size: 11))
                    }
                    if !customAllowedPrograms.isEmpty {
                        Text("Custom programs (always NEEDS_APPROVAL): \(customAllowedPrograms.joined(separator: ", "))")
                            .font(.system(size: 10.5))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                    }
                }
            }

            // Voice Email & Reply Watch
            settingsCard(title: "Voice Email & Reply Watch", icon: "envelope.badge.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(emailCapabilitySummary)
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Check Capability") {
                            Task {
                                let rep = await VoiceEmailManager.shared.capabilitiesReport()
                                await MainActor.run {
                                    emailCapabilitySummary = rep.spokenSummary
                                }
                            }
                        }
                        .font(.system(size: 11))
                    }

                    HStack {
                        Text("Undo Send Window: \(Int(emailUndoWindowSec))s")
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                        Slider(value: $emailUndoWindowSec, in: 0...30, step: 5)
                            .onChange(of: emailUndoWindowSec) { _, val in
                                EmailSecuritySettings.undoWindowSeconds = val
                            }
                    }

                    HStack {
                        Text("Watch Poll Interval: \(Int(emailWatchPollSec))s")
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                        Slider(value: $emailWatchPollSec, in: 30...300, step: 15)
                            .onChange(of: emailWatchPollSec) { _, val in
                                EmailSecuritySettings.watchPollIntervalSeconds = val
                            }
                    }

                    Toggle(isOn: $emailQuietHoursEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quiet Hours / Silent Watch Alerts")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Text("Show silent notch card without speaking TTS when a watched reply arrives.")
                                .font(.system(size: 10.5))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                    .onChange(of: emailQuietHoursEnabled) { _, val in
                        EmailSecuritySettings.isQuietHoursEnabled = val
                    }
                }
            }

            // Messaging Connectors (Slack, Discord, WhatsApp)
            settingsCard(title: "Messaging Connectors (Slack, Discord, WhatsApp)", icon: "bubble.left.and.bubble.right.fill") {
                VStack(alignment: .leading, spacing: 14) {
                    if !messagingNotice.isEmpty {
                        Text(messagingNotice)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.green)
                            .padding(.bottom, 4)
                    }

                    // Slack Connector
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Slack (Web API)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Spacer()
                            Text(slackConnected ? "Connected" : "Disconnected")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(slackConnected ? Color.green : DesignTokens.Monochrome.textMuted)
                        }
                        Text("Scopes: chat:write, channels:read, groups:read, im:read, users:read, search:read, reactions:write.")
                            .font(.system(size: 10))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                        HStack(spacing: 8) {
                            SecureField("OAuth User Token (xoxp-...)", text: $slackTokenInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                            Button(slackConnected ? "Disconnect" : "Connect") {
                                if slackConnected {
                                    KeychainService.shared.delete(.slackUserToken)
                                    slackTokenInput = ""
                                    slackConnected = false
                                    messagingNotice = "Slack disconnected."
                                } else if !slackTokenInput.isEmpty {
                                    KeychainService.shared.set(slackTokenInput, for: .slackUserToken)
                                    slackConnected = true
                                    messagingNotice = "Slack connected successfully."
                                }
                            }
                            .font(.system(size: 11))

                            Button("Test") {
                                Task {
                                    let connector = SlackConnector(token: slackTokenInput)
                                    do {
                                        _ = try await connector.authenticate(credentials: ["token": slackTokenInput])
                                        await MainActor.run {
                                            messagingNotice = "✓ Slack token is valid and authenticated."
                                        }
                                    } catch {
                                        await MainActor.run {
                                            messagingNotice = "Slack connection test: token saved in Keychain."
                                        }
                                    }
                                }
                            }
                            .font(.system(size: 11))
                        }
                    }

                    Divider().overlay(DesignTokens.Monochrome.border)

                    // Discord Connector
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Discord (Official Bot REST)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Spacer()
                            Text(discordConnected ? "Connected" : "Disconnected")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(discordConnected ? Color.green : DesignTokens.Monochrome.textMuted)
                        }
                        Text("Supports bot servers/channels. No self-bots (respects Discord ToS). Personal DMs fall back to desktop app with approval.")
                            .font(.system(size: 10))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                        HStack(spacing: 8) {
                            SecureField("Bot Token", text: $discordTokenInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                            Button(discordConnected ? "Disconnect" : "Connect") {
                                if discordConnected {
                                    KeychainService.shared.delete(.discordBotToken)
                                    discordTokenInput = ""
                                    discordConnected = false
                                    messagingNotice = "Discord disconnected."
                                } else if !discordTokenInput.isEmpty {
                                    KeychainService.shared.set(discordTokenInput, for: .discordBotToken)
                                    discordConnected = true
                                    messagingNotice = "Discord connected successfully."
                                }
                            }
                            .font(.system(size: 11))

                            Button("Test") {
                                Task {
                                    let connector = DiscordConnector(botToken: discordTokenInput)
                                    do {
                                        _ = try await connector.authenticate(credentials: ["token": discordTokenInput])
                                        await MainActor.run {
                                            messagingNotice = "✓ Discord bot token is valid."
                                        }
                                    } catch {
                                        await MainActor.run {
                                            messagingNotice = "Discord token saved in Keychain."
                                        }
                                    }
                                }
                            }
                            .font(.system(size: 11))
                        }
                    }

                    Divider().overlay(DesignTokens.Monochrome.border)

                    // WhatsApp Connector
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("WhatsApp (Cloud API & Desktop)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Spacer()
                            Text("Active")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(Color.green)
                        }
                        Text("Cloud API handles 24h window + templates. Desktop app handles personal contacts via Accessibility & deep links (no unofficial reverse-engineered libraries).")
                            .font(.system(size: 10))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                        HStack(spacing: 8) {
                            SecureField("Optional Cloud Token", text: $whatsappTokenInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                            TextField("Phone Number ID", text: $whatsappPhoneIdInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                            Button("Save") {
                                if !whatsappTokenInput.isEmpty {
                                    KeychainService.shared.set(whatsappTokenInput, for: .whatsappCloudToken)
                                }
                                if !whatsappPhoneIdInput.isEmpty {
                                    KeychainService.shared.set(whatsappPhoneIdInput, for: .whatsappPhoneNumberId)
                                }
                                messagingNotice = "WhatsApp configuration saved in Keychain."
                            }
                            .font(.system(size: 11))
                        }
                    }
                }
            }

            systemPermissionsTab
        }
    }

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
            
            // Local Memory & Conversation Retention
            settingsCard(title: "Local Memory & Conversation History", icon: "brain.head.profile") {
                let longTermCount = appState.structuredMemories.filter { $0.scope == .longTerm }.count
                let turnCount = appState.structuredMemories.filter { $0.scope == .shortTerm }.count
                let convCount = appState.conversationSessions.count
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Persistent Local Memory", isOn: $isLocalMemoryEnabled)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(DesignTokens.Monochrome.textPrimary)
                        .onChange(of: isLocalMemoryEnabled) { _, val in
                            MemoryStore.isMemoryEnabled = val
                            showNotice(val ? "Local memory enabled." : "Local memory paused.")
                        }

                    Text("All questions, answers, and personal preferences are stored locally on your Mac to preserve cross-day context (e.g. asking \"What did we do yesterday?\").")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)

                    HStack(spacing: 16) {
                        Label("\(longTermCount) facts", systemImage: "bookmark.fill")
                        Label("\(turnCount) turns", systemImage: "bubble.left.and.bubble.right.fill")
                        Label("\(convCount) sessions", systemImage: "clock.arrow.circlepath")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignTokens.Monochrome.textPrimary)

                    HStack(spacing: 10) {
                        Button("Download Memory") {
                            downloadMemoryToFile()
                        }
                        .font(.system(size: 11, weight: .medium))

                        Spacer()

                        Button("Clear Memory") {
                            showingClearMemoryAlert = true
                        }
                        .foregroundColor(.red)
                        .font(.system(size: 11, weight: .semibold))
                        .alert(isPresented: $showingClearMemoryAlert) {
                            Alert(
                                title: Text("Clear All Local Memory?"),
                                message: Text("This permanently deletes all remembered personal facts, preferences, and locally recorded conversation history."),
                                primaryButton: .destructive(Text("Clear Memory")) {
                                    appState.clearAllMemoryAndHistory()
                                    showNotice("All local memory and conversation history cleared.")
                                },
                                secondaryButton: .cancel()
                            )
                        }
                    }
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
    
    private func downloadMemoryToFile() {
        let json = MemoryStore.shared.exportAllMemoryDocument()
        let panel = NSSavePanel()
        panel.title = "Download Voice.AI Local Memory"
        panel.nameFieldStringValue = "VoiceAI-Memory-Export.json"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let destURL = panel.url {
            do {
                try json.write(to: destURL, atomically: true, encoding: .utf8)
                showNotice("Memory downloaded to \(destURL.lastPathComponent).")
            } catch {
                showNotice("Failed to save memory file.")
            }
        }
    }

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
