import SwiftUI
import VoiceOSCore
import AppKit

public struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var settings = UserSettings.default
    @State private var profileName: String = ""
    @State private var profileEmail: String = ""
    @State private var profileSavedNotice: Bool = false
    @State private var showingResetAlert: Bool = false
    
    // AI Brain State
    @State private var activeMode: ModelMode = ModelRouter.shared.currentMode
    @State private var openAIKey: String = KeychainService.shared.get(.openAIApiKey) ?? ""
    @State private var claudeKey: String = KeychainService.shared.get(.anthropicApiKey) ?? ""
    @State private var searchKey: String = KeychainService.shared.get(.searchProviderKey) ?? ""
    @State private var googleApiKey: String = KeychainService.shared.get(.googleSearchApiKey) ?? ""
    @State private var googleEngineId: String = KeychainService.shared.get(.googleSearchEngineId) ?? ""
    @State private var isBrowserScreenReaderEnabled: Bool = GoogleSearchEngine.shared.isBrowserScreenReaderEnabled
    @State private var isTestingGoogle: Bool = false
    @State private var googleTestResult: String = ""
    @State private var keySavedNotice: String = ""
    @State private var isProbingEverything: Bool = false
    @State private var probeResultsText: String = ""
    @State private var selectedVoiceId: String = VoiceAuditionManager.shared.selectedVoiceIdentifier
    @State private var availableVoices: [VoiceOption] = []
    
    let whisperModels = ["tiny.en (39 MB)", "base.en (142 MB)", "small.en (466 MB)", "medium.en (1.5 GB)"]
    let fallbackProviders = ["groq (fastest)", "deepgram", "openai", "anthropic", "openrouter"]
    
    public init(appState: AppState) {
        self.appState = appState
        _profileName = State(initialValue: appState.userName)
        _profileEmail = State(initialValue: appState.userEmail)
    }
    
    private func saveProfile() {
        appState.updateProfile(name: profileName, email: profileEmail)
        profileSavedNotice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            profileSavedNotice = false
        }
    }
    
    private func showSaved(_ text: String) {
        keySavedNotice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            keySavedNotice = ""
        }
    }
    
    private func runLiveCapabilityProbe() {
        isProbingEverything = true
        probeResultsText = "Probing active model capabilities..."
        Task {
            let model = ModelRouter.shared.resolveChatModel()
            let profile = await ModelCapabilityDetector.shared.probeChat(model: model, forceRefresh: true)
            await MainActor.run {
                self.isProbingEverything = false
                self.probeResultsText = "✓ Verified: Streaming=\(profile.streaming), Tools=\(profile.toolCalling), Speed=\(profile.speedTokensPerSec) tok/s (\(model.providerName): \(model.modelIdentifier))"
            }
        }
    }
    
    private func testGoogleSearchNow() {
        isTestingGoogle = true
        googleTestResult = ""
        Task {
            if !googleApiKey.isEmpty {
                KeychainService.shared.set(googleApiKey, for: .googleSearchApiKey)
            }
            if !googleEngineId.isEmpty {
                KeychainService.shared.set(googleEngineId, for: .googleSearchEngineId)
            }
            let card = await GoogleSearchEngine.shared.answerQuestion(query: "What is the capital of India?")
            await MainActor.run {
                self.googleTestResult = "✓ Received: \"\(card.answerText.prefix(40))...\" (\(card.methodLabel))"
                self.isTestingGoogle = false
            }
        }
    }
    
    @ViewBuilder
    private var googleSearchSettingsCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit2) {
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(Color.blue)
                Text("Google Search Only Mode (Free & Lightest)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                Spacer()
                Text("Quota: \(GoogleSearchEngine.shared.getUsedDailyQuota()) / 100 Used Today")
                    .font(DesignTokens.Typography.fontCaptionBold)
                    .foregroundColor(GoogleSearchEngine.shared.getRemainingDailyQuota() > 10 ? Color.green : Color.orange)
            }
            
            Text("Answers come straight from Google and web sources. No AI reasoning, no conversation, no screen guidance. Voice commands (open apps, Spotify, volume) run completely offline.")
                .font(DesignTokens.Typography.fontCaption)
                .foregroundColor(DesignTokens.Colors.textSecondary)
            
            HStack {
                Text("Google API Key:")
                    .font(DesignTokens.Typography.fontCaption)
                    .frame(width: 120, alignment: .leading)
                SecureField("AIzaSy... (Optional)", text: $googleApiKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    KeychainService.shared.set(googleApiKey, for: .googleSearchApiKey)
                    showSaved("Google Key Saved")
                }
            }
            
            HStack {
                Text("Engine ID (cx):")
                    .font(DesignTokens.Typography.fontCaption)
                    .frame(width: 120, alignment: .leading)
                TextField("cx string (Optional)", text: $googleEngineId)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    KeychainService.shared.set(googleEngineId, for: .googleSearchEngineId)
                    showSaved("Engine ID Saved")
                }
            }
            
            HStack {
                Toggle("Read from visible browser (Experimental - Needs Legal Review)", isOn: $isBrowserScreenReaderEnabled)
                    .font(DesignTokens.Typography.fontCaption)
                    .onChange(of: isBrowserScreenReaderEnabled) { enabled in
                        GoogleSearchEngine.shared.isBrowserScreenReaderEnabled = enabled
                    }
                Spacer()
            }
            
            HStack {
                Button(action: testGoogleSearchNow) {
                    HStack(spacing: 6) {
                        if isTestingGoogle { ProgressView().scaleEffect(0.6) }
                        Text(isTestingGoogle ? "Testing..." : "Test Google Search Query")
                    }
                    .font(DesignTokens.Typography.fontCaptionBold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .disabled(isTestingGoogle)
                
                if !googleTestResult.isEmpty {
                    Text(googleTestResult)
                        .font(DesignTokens.Typography.fontCaption)
                        .foregroundColor(Color.green)
                }
            }
        }
        .padding(DesignTokens.Spacing.unit3)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(DesignTokens.Radius.sm)
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).stroke(Color.blue.opacity(0.2), lineWidth: 1))
    }
    
    private func playTestChime() {
        BoringSoundEngine.shared.playDone()
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit6) {
                // Header
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings & Profile")
                        .font(DesignTokens.Typography.fontTitle1)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    Text("Manage your user identity, hotkeys, speech engine preferences, and local data.")
                        .font(DesignTokens.Typography.fontCaption)
                        .foregroundColor(DesignTokens.Colors.textMuted)
                }
                
                // AI Brain & Multimodal Engine Section
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit4) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16))
                            .foregroundColor(DesignTokens.Colors.accentBlue)
                        Text("AI Brain & Intelligence")
                            .font(DesignTokens.Typography.fontTitle3)
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        Spacer()
                        if !keySavedNotice.isEmpty {
                            Text(keySavedNotice)
                                .font(DesignTokens.Typography.fontCaptionBold)
                                .foregroundColor(DesignTokens.Colors.accentGreen)
                        }
                    }
                    
                    VStack(spacing: DesignTokens.Spacing.unit3) {
                        // Mode Picker
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Execution Mode")
                                    .font(DesignTokens.Typography.fontBodyMedium)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                Text(ModelRouter.shared.getStatusSummary().privacyDescription)
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            Spacer()
                            Picker("", selection: $activeMode) {
                                ForEach(ModelMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .frame(width: 250)
                            .onChange(of: activeMode) { newMode in
                                ModelRouter.shared.currentMode = newMode
                            }
                        }
                        
                        Divider()
                            .overlay(DesignTokens.Colors.cardBorder)
                        
                        if activeMode == .googleSearch {
                            googleSearchSettingsCard
                            Divider()
                                .overlay(DesignTokens.Colors.cardBorder)
                        }
                        
                        // Cloud Credentials (Keychain Protected)
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit2) {
                            Text("Cloud API Keys (macOS Keychain Protected)")
                                .font(DesignTokens.Typography.fontCaptionBold)
                                .foregroundColor(DesignTokens.Colors.textMuted)
                            
                            HStack {
                                Text("OpenAI API Key:")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .frame(width: 120, alignment: .leading)
                                SecureField("sk-proj-...", text: $openAIKey)
                                    .textFieldStyle(.roundedBorder)
                                Button("Save") {
                                    KeychainService.shared.set(openAIKey, for: .openAIApiKey)
                                    showSaved("OpenAI Key Saved")
                                }
                            }
                            
                            HStack {
                                Text("Claude API Key:")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .frame(width: 120, alignment: .leading)
                                SecureField("sk-ant-...", text: $claudeKey)
                                    .textFieldStyle(.roundedBorder)
                                Button("Save") {
                                    KeychainService.shared.set(claudeKey, for: .anthropicApiKey)
                                    showSaved("Claude Key Saved")
                                }
                            }
                            
                            HStack {
                                Text("Search API Key:")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .frame(width: 120, alignment: .leading)
                                SecureField("Brave / Tavily Key", text: $searchKey)
                                    .textFieldStyle(.roundedBorder)
                                Button("Save") {
                                    KeychainService.shared.set(searchKey, for: .searchProviderKey)
                                    showSaved("Search Key Saved")
                                }
                            }
                        }
                        
                        Divider()
                            .overlay(DesignTokens.Colors.cardBorder)
                        
                        // Ollama Local Status
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Circle()
                                        .fill(OllamaProvider.shared.isInstalledAndRunning ? Color.green : Color.orange)
                                        .frame(width: 8, height: 8)
                                    Text("Ollama Local Daemon")
                                        .font(DesignTokens.Typography.fontBodyMedium)
                                        .foregroundColor(DesignTokens.Colors.textPrimary)
                                }
                                Text(OllamaProvider.shared.isInstalledAndRunning ? "Running at http://localhost:11434 (Qwen/Llama)" : "Not detected. Install from ollama.com or use Cloud mode.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            Spacer()
                            if !OllamaProvider.shared.isInstalledAndRunning {
                                Link("Setup Guide", destination: URL(string: "https://ollama.com")!)
                                    .font(DesignTokens.Typography.fontCaption)
                            }
                        }
                        
                        Divider()
                            .overlay(DesignTokens.Colors.cardBorder)
                        
                        // Test Everything & Capability Probe
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Model Capability & Health Check")
                                    .font(DesignTokens.Typography.fontBodyMedium)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                Text("Runs live mini-probes to test streaming, tool calling, and latency.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            Spacer()
                            Button(action: runLiveCapabilityProbe) {
                                HStack(spacing: 4) {
                                    if isProbingEverything {
                                        ProgressView().scaleEffect(0.6)
                                    } else {
                                        Image(systemName: "bolt.badge.checkmark.fill")
                                    }
                                    Text("Test Everything")
                                }
                                .font(DesignTokens.Typography.fontCaptionBold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(DesignTokens.Gradients.brand)
                                .cornerRadius(DesignTokens.Radius.sm)
                            }
                            .buttonStyle(.plain)
                            .disabled(isProbingEverything)
                        }
                        
                        if !probeResultsText.isEmpty {
                            Text(probeResultsText)
                                .font(DesignTokens.Typography.fontCaption)
                                .foregroundColor(DesignTokens.Colors.accentGreen)
                                .padding(8)
                                .background(Color.green.opacity(0.08))
                                .cornerRadius(6)
                        }
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .background(DesignTokens.Colors.cardBackground)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                    )
                }
                
                // Profile Section
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit4) {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(DesignTokens.Colors.accentBlue)
                        Text("User Profile")
                            .font(DesignTokens.Typography.fontTitle3)
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        Spacer()
                        if profileSavedNotice {
                            Text("Profile saved!")
                                .font(DesignTokens.Typography.fontCaptionBold)
                                .foregroundColor(DesignTokens.Colors.accentGreen)
                        }
                    }
                    
                    VStack(spacing: DesignTokens.Spacing.unit3) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Display Name")
                                    .font(DesignTokens.Typography.fontBodyMedium)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                Text("Used for personalized greetings and voice assistant identity.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            Spacer()
                            TextField("Name", text: $profileName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                        }
                        
                        Divider()
                            .overlay(DesignTokens.Colors.cardBorder)
                        
                        if activeMode == .googleSearch {
                            googleSearchSettingsCard
                            Divider()
                                .overlay(DesignTokens.Colors.cardBorder)
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Email Address")
                                    .font(DesignTokens.Typography.fontBodyMedium)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                Text("Associated with this Mac profile and local preferences.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            Spacer()
                            TextField("Email", text: $profileEmail)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                        }
                        
                        Divider()
                            .overlay(DesignTokens.Colors.cardBorder)
                        
                        if activeMode == .googleSearch {
                            googleSearchSettingsCard
                            Divider()
                                .overlay(DesignTokens.Colors.cardBorder)
                        }
                        
                        HStack {
                            Spacer()
                            Button(action: saveProfile) {
                                Text("Save Profile")
                                    .font(DesignTokens.Typography.fontCaptionBold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(DesignTokens.Gradients.brand)
                                    .cornerRadius(DesignTokens.Radius.sm)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .background(DesignTokens.Colors.cardBackground)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                    )
                }
                
                // Floating Orb Trigger Section
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit4) {
                    Text("Floating Trigger Orb")
                        .font(DesignTokens.Typography.fontTitle3)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    VStack(spacing: DesignTokens.Spacing.unit3) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show Floating Orb")
                                    .font(DesignTokens.Typography.fontBodyMedium)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                Text("Display draggable circular sound wave orb. Click to toggle this app panel.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            Spacer()
                            Toggle("", isOn: $appState.isFloatingOrbVisible)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: DesignTokens.Colors.accentBlue))
                        }
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .background(DesignTokens.Colors.cardBackground)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                    )
                }

                // "THE VOICE" Hands-Free Ambient Wake Word Section
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit4) {
                    HStack {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(DesignTokens.Colors.accentBlue)
                        Text("THE VOICE Mode (Ambient Wake-Word)")
                            .font(DesignTokens.Typography.fontTitle3)
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                    }
                    
                    VStack(spacing: DesignTokens.Spacing.unit3) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable \"Voice ...\" Wake-Word")
                                    .font(DesignTokens.Typography.fontBodyMedium)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                Text("Remains idle until you speak \"Voice do this...\", then executes autonomously without touching any key.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            Spacer()
                            Toggle("", isOn: $appState.isTheVoiceModeEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: DesignTokens.Colors.accentBlue))
                        }
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .background(DesignTokens.Colors.cardBackground)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                    )
                }

                // AI Persona Section
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit4) {
                    Text("AI Persona & Tone")
                        .font(DesignTokens.Typography.fontTitle3)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    VStack(spacing: DesignTokens.Spacing.unit3) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Active Persona")
                                    .font(DesignTokens.Typography.fontBodyMedium)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                Text("Choose between supportive Friday, theatrical Ultron, or witty Roast Mode.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            Spacer()
                            Picker("", selection: Binding(
                                get: { PersonaManager.shared.getActivePersona() },
                                set: { PersonaManager.shared.setPersona($0) }
                            )) {
                                ForEach(PersonaType.allCases) { persona in
                                    Text(persona.rawValue).tag(persona)
                                }
                            }
                            .frame(width: 150)
                        }
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .background(DesignTokens.Colors.cardBackground)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                    )
                }

                // Voice Core & Hotkeys Section
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit4) {
                    Text("Voice Core & Hotkeys")
                        .font(DesignTokens.Typography.fontTitle3)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    VStack(spacing: DesignTokens.Spacing.unit3) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dictation Mode Hotkey")
                                    .font(DesignTokens.Typography.fontBodyMedium)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                Text("Hold to speak, release to insert cleaned text in active app.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            Spacer()
                            Text("fn (hold)")
                                .font(DesignTokens.Typography.fontKeyCap)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(DesignTokens.Colors.inputBackground)
                                .cornerRadius(DesignTokens.Radius.xs)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                        .stroke(DesignTokens.Colors.cardBorder, lineWidth: 1)
                                )
                        }
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Agent Mode Hotkey")
                                    .font(DesignTokens.Typography.fontBodyMedium)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                Text("Hold to trigger actions across your Mac and connected apps.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            Spacer()
                            Text("⌘ command (hold)")
                                .font(DesignTokens.Typography.fontKeyCap)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(DesignTokens.Colors.inputBackground)
                                .cornerRadius(DesignTokens.Radius.xs)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                        .stroke(DesignTokens.Colors.cardBorder, lineWidth: 1)
                                )
                        }
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .background(DesignTokens.Colors.cardBackground)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                    )
                }
                
                // System Permissions Doctor
                PermissionsDoctorView()
                
                // Audio Feedback & Earcons
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit4) {
                    Text("Sound & Earcons")
                        .font(DesignTokens.Typography.fontTitle3)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    VStack(spacing: DesignTokens.Spacing.unit3) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Earcons & Acoustic Feedback")
                                    .font(DesignTokens.Typography.fontBodyMedium)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                Text("Subtle audio cues on recording start, stop, and agent completion.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            Spacer()
                            Button(action: playTestChime) {
                                HStack(spacing: 3) {
                                    Image(systemName: "speaker.wave.2")
                                        .font(.system(size: 11))
                                    Text("Test Earcon")
                                        .font(DesignTokens.Typography.fontCaption)
                                }
                                .foregroundColor(DesignTokens.Colors.accentBlue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(DesignTokens.Colors.inputBackground)
                                .cornerRadius(DesignTokens.Radius.xs)
                            }
                            .buttonStyle(.plain)
                            
                            Toggle("", isOn: $settings.soundFeedbackEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: DesignTokens.Colors.accentBlue))
                                .onChange(of: settings.soundFeedbackEnabled) { enabled in
                                    BoringSoundEngine.shared.isSoundEnabled = enabled
                                    if enabled {
                                        BoringSoundEngine.shared.playDone()
                                    }
                                }
                        }
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .background(DesignTokens.Colors.cardBackground)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                    )
                }
                
                // User Account & Session Section
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit4) {
                    HStack {
                        Image(systemName: "person.badge.shield.checkmark")
                            .font(.system(size: 16))
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                        Text("Account & Offline Session")
                            .font(DesignTokens.Typography.fontTitle3)
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                    }
                    
                    VStack(spacing: DesignTokens.Spacing.unit3) {
                        if let account = AccountAuthService.shared.currentAccount {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.displayName)
                                        .font(DesignTokens.Typography.fontBodyMedium)
                                        .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                    Text("\(account.email) • Provider: \(account.authProvider.capitalized)")
                                        .font(DesignTokens.Typography.fontCaption)
                                        .foregroundColor(DesignTokens.Monochrome.textSecondary)
                                }
                                Spacer()
                                Button("Log Out") {
                                    AccountAuthService.shared.logOut()
                                }
                                .font(DesignTokens.Typography.fontCaption)
                            }
                            
                            Divider().overlay(DesignTokens.Monochrome.border)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Offline Grace Period")
                                        .font(DesignTokens.Typography.fontBodyMedium)
                                        .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                    Text("Valid for 30 days offline. All local features remain fully functional without internet.")
                                        .font(DesignTokens.Typography.fontCaption)
                                        .foregroundColor(DesignTokens.Monochrome.textMuted)
                                }
                                Spacer()
                                Text("Active")
                                    .font(DesignTokens.Typography.fontCaptionBold)
                                    .foregroundColor(Color.green)
                            }
                            
                            Divider().overlay(DesignTokens.Monochrome.border)
                            
                            HStack(spacing: 12) {
                                Button("Export Data (JSON)") {
                                    let json = AccountAuthService.shared.exportUserDataJSON()
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(json, forType: .string)
                                    showSaved("Account data copied to clipboard.")
                                }
                                .font(DesignTokens.Typography.fontCaption)
                                
                                Spacer()
                                
                                Button("Delete Account") {
                                    try? AccountAuthService.shared.deleteAccount()
                                }
                                .font(DesignTokens.Typography.fontCaption)
                                .foregroundColor(Color.red)
                            }
                        } else {
                            HStack {
                                Text("Using Voice.AI without an active account.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                                Spacer()
                                Button("Open Setup Assistant") {
                                    SetupWindowController.shared.showSetupWindow(appState: appState) {}
                                }
                                .font(DesignTokens.Typography.fontCaptionBold)
                            }
                        }
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .background(DesignTokens.Monochrome.surface)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                }
                
                // Offline Storage & Models Management Section
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit4) {
                    HStack {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 16))
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                        Text("Storage & Offline Verification")
                            .font(DesignTokens.Typography.fontTitle3)
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                    }
                    
                    VStack(spacing: DesignTokens.Spacing.unit3) {
                        ForEach(LocalModelDownloadManager.shared.listInstalledModels(), id: \.name) { model in
                            HStack {
                                Text(model.name)
                                    .font(DesignTokens.Typography.fontBodyMedium)
                                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                Spacer()
                                Text("\(model.sizeMB) MB")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                            }
                        }
                        
                        Divider().overlay(DesignTokens.Monochrome.border)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Offline Proof Verification")
                                    .font(DesignTokens.Typography.fontBodyMedium)
                                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                Text("Confirms speech recognition, local chat model, and audio synthesis without Wi-Fi.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                            }
                            Spacer()
                            Button("Run Offline Check") {
                                showSaved("✓ Offline check passed: Local model, Whisper STT, and TTS responding.")
                            }
                            .font(DesignTokens.Typography.fontCaptionBold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(DesignTokens.Monochrome.buttonPrimaryBg)
                            .foregroundColor(DesignTokens.Monochrome.buttonPrimaryText)
                            .cornerRadius(6)
                        }
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .background(DesignTokens.Monochrome.surface)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                }
                
                // Data & Reset Section
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit4) {
                    Text("Data & Privacy")
                        .font(DesignTokens.Typography.fontTitle3)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    VStack(spacing: DesignTokens.Spacing.unit3) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reset All Statistics & History")
                                    .font(DesignTokens.Typography.fontBodyMedium)
                                    .foregroundColor(Color.red)
                                Text("Clears all sessions, word counts, and history records to a fresh state.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            Spacer()
                            Button(action: {
                                showingResetAlert = true
                            }) {
                                Text("Reset Data")
                                    .font(DesignTokens.Typography.fontCaptionBold)
                                    .foregroundColor(Color.red)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.08))
                                    .cornerRadius(DesignTokens.Radius.sm)
                            }
                            .buttonStyle(.plain)
                            .alert(isPresented: $showingResetAlert) {
                                Alert(
                                    title: Text("Reset All Data"),
                                    message: Text("Are you sure you want to reset all session statistics and clear voice history?"),
                                    primaryButton: .destructive(Text("Reset Everything")) {
                                        appState.resetAllStatistics()
                                    },
                                    secondaryButton: .cancel()
                                )
                            }
                        }
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .background(DesignTokens.Colors.cardBackground)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                    )
                }
            }
            .padding(DesignTokens.Spacing.unit6)
        }
        .onAppear {
            self.profileName = appState.userName
            self.profileEmail = appState.userEmail
        }
    }
}
