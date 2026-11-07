import SwiftUI
import VoiceOSCore
import AppKit

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case voice = "Voice & Wake-Word"
    case brain = "AI Brain & Models"
    case permissions = "System Access"
    case account = "Account & Privacy"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .voice: return "waveform.badge.mic"
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
                
                // Segmented Tab Picker (Full width, single line, zero text squishing)
                HStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button(action: {
                            selectedTab = tab
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 11))
                                Text(tab.rawValue)
                                    .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .medium))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .foregroundColor(selectedTab == tab ? DesignTokens.Monochrome.textPrimary : DesignTokens.Monochrome.textMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedTab == tab ? DesignTokens.Monochrome.surfaceElevated : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(3)
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
            if activeMode == .local {
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
                    
                    if appState.isTheVoiceModeEnabled {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 11))
                            Text("Active: Say \"Voice, set volume to full\" or \"Voice, open Spotify\" anytime hands-free.")
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
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kokoro-82M Local TTS Engine")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Text("Runs on-device quantized neural audio synthesis in ~/.voiceos/models/ with sub-100ms conversational response.")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        Spacer()
                        
                        let hasKokoro = LocalModelDownloadManager.checkRealKokoroOnDisk()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(hasKokoro ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(hasKokoro ? "Ready (86 MB)" : "Local Engine")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(hasKokoro ? Color.green : Color.orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DesignTokens.Monochrome.surfaceElevated)
                        .cornerRadius(6)
                    }
                    
                    HStack {
                        Button(action: {
                            SpeechPipelineEngine.shared.speakResponse("Hello sir! Voice.AI offline neural voice synthesis is online and ready to control your computer.")
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "speaker.wave.2")
                                Text("Test Spoken Output")
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
                        
                        Spacer()
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
                        .onChange(of: activeMode) { newMode in
                            ModelRouter.shared.currentMode = newMode
                            if newMode == .local {
                                connectLocalAIModels()
                            }
                        }
                    }
                    
                    if activeMode == .local {
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
                            Text("The Brain (Llama 3.2 3B), The Eyes (Qwen2-VL 7B), and The Voice (Kokoro 82M).")
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
                                authEmailInput = ""
                                authPasswordInput = ""
                                authErrorMessage = ""
                                authSuccessMessage = "Logged out successfully."
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
        do {
            if authIsLoginMode {
                let account = try AccountAuthService.shared.logIn(email: trimmedEmail, password: authPasswordInput)
                currentAccount = account
                appState.userName = account.displayName
                appState.userEmail = account.email
                authSuccessMessage = "Welcome back, \(account.displayName)!"
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
        isAuthLoading = false
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
