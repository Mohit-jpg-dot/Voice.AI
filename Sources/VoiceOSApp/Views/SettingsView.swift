import SwiftUI
import VoiceOSCore
import AppKit

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case brain = "AI Brain & Models"
    case permissions = "System Access"
    case account = "Account & Privacy"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .general: return "gearshape.fill"
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
    
    public init(appState: AppState) {
        self.appState = appState
        _profileName = State(initialValue: appState.userName)
        _profileEmail = State(initialValue: appState.userEmail)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(DesignTokens.Monochrome.textPrimary)
                    Text("Configure your voice assistant, local models, hardware preferences, and system privileges.")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)
                }
                
                Spacer()
                
                // Segmented Tab Picker
                HStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button(action: {
                            selectedTab = tab
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 11))
                                Text(tab.rawValue)
                                    .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                            }
                            .foregroundColor(selectedTab == tab ? DesignTokens.Monochrome.textPrimary : DesignTokens.Monochrome.textMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedTab == tab ? DesignTokens.Monochrome.surfaceElevated : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
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
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider()
                .overlay(DesignTokens.Monochrome.border)
            
            // Tab Content Body
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .general:
                        generalSettingsTab
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
                        Text("⌘ Command (Hold)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(DesignTokens.Monochrome.surfaceElevated)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
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
                        }
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
            settingsCard(title: "Account & Offline Grace Period", icon: "person.badge.shield.checkmark.fill") {
                VStack(spacing: 12) {
                    if let account = AccountAuthService.shared.currentAccount {
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
                            }
                            .font(.system(size: 11))
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
                        HStack {
                            Text("Running Voice.AI in Local Guest Session.")
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.Monochrome.textSecondary)
                            Spacer()
                            Button("Sign Up / Log In") {
                                SetupWindowController.shared.showSetupWindow(appState: appState) {}
                            }
                            .font(.system(size: 11, weight: .bold))
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
}
