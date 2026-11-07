import SwiftUI
import VoiceOSCore
import AppKit

public enum SetupStep: Int, CaseIterable, Sendable {
    case welcome = 1
    case account = 2
    case choosePath = 3
    case pathConfiguration = 4
    case permissions = 5
    case voiceTest = 6
    case done = 7
}

public enum SetupChosenPath: String, Codable, Sendable {
    case apiKey = "paid_api"
    case freeOffline = "free_offline"
    case googleSearch = "google_search"
}

public struct SetupFlowView: View {
    @ObservedObject var appState: AppState
    var onComplete: () -> Void
    
    @State private var currentStep: SetupStep
    @State private var chosenPath: SetupChosenPath = .freeOffline
    
    // Account Form State
    @State private var isLoginMode: Bool = false
    @State private var emailInput: String = ""
    @State private var passwordInput: String = ""
    @State private var nameInput: String = ""
    @State private var verificationCodeInput: String = ""
    @State private var isAwaitingVerification: Bool = false
    @State private var isSigningInWithGoogle: Bool = false
    @State private var authErrorMessage: String = ""
    @State private var authSuccessMessage: String = ""
    
    // API Path State
    @State private var selectedProvider: String = "OpenAI"
    @State private var apiKeyInput: String = ""
    @State private var isTestingApiKey: Bool = false
    @State private var apiTestResult: String = ""
    
    // Free Path State
    @State private var hardwareSpec = HardwareProfileDetector.shared.detectHardware()
    @State private var selectedTier: ModelProfileTier = .balanced
    @State private var showAdvancedCommands: Bool = false
    @State private var downloadTasks: [ActiveDownloadTask] = []
    @State private var isDownloading: Bool = false
    @State private var allDownloadsFinished: Bool = false
    
    // Google Search Path State
    @State private var googleApiKeyInput: String = KeychainService.shared.get(.googleSearchApiKey) ?? ""
    @State private var googleEngineIdInput: String = KeychainService.shared.get(.googleSearchEngineId) ?? ""
    @State private var isBrowserScreenReaderEnabled: Bool = GoogleSearchEngine.shared.isBrowserScreenReaderEnabled
    @State private var isTestingGoogleSearch: Bool = false
    @State private var googleTestCard: GoogleSearchAnswerCard? = nil
    @State private var googleTestQueryText: String = "What is the capital of India?"
    
    // Voice Test State
    @State private var testSentenceTranscript: String = ""
    @State private var testReplySpoken: String = ""
    @State private var testTimingMs: Int = 0
    
    public init(appState: AppState, onComplete: @escaping () -> Void) {
        self.appState = appState
        self.onComplete = onComplete
        
        let savedStepRaw = UserDefaults.standard.integer(forKey: "voiceos.setup.current_step")
        let initialStep = SetupStep(rawValue: savedStepRaw) ?? .welcome
        let effectiveStep = (initialStep == .done) ? .welcome : initialStep
        _currentStep = State(initialValue: effectiveStep)
    }
    
    private func advanceTo(step: SetupStep) {
        currentStep = step
        UserDefaults.standard.set(step.rawValue, forKey: "voiceos.setup.current_step")
    }
    
    public var body: some View {
        ZStack {
            DesignTokens.Monochrome.windowBg.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Monochrome Step Bar
                HStack(spacing: 6) {
                    ForEach(SetupStep.allCases, id: \.self) { step in
                        Rectangle()
                            .fill(step.rawValue <= currentStep.rawValue ? DesignTokens.Monochrome.textPrimary : DesignTokens.Monochrome.border)
                            .frame(height: 2)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
                
                // Screen Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        switch currentStep {
                        case .welcome:
                            welcomeScreen
                        case .account:
                            accountScreen
                        case .choosePath:
                            choosePathScreen
                        case .pathConfiguration:
                            if chosenPath == .apiKey {
                                apiKeyConfigScreen
                            } else if chosenPath == .googleSearch {
                                googleSearchConfigScreen
                            } else {
                                freeOfflineConfigScreen
                            }
                        case .permissions:
                            permissionsScreen
                        case .voiceTest:
                            voiceTestScreen
                        case .done:
                            doneScreen
                        }
                    }
                    .padding(36)
                }
            }
        }
        .frame(width: 760, height: 580)
        .onAppear {
            self.selectedTier = hardwareSpec.recommendedTier
            if AccountAuthService.shared.isAuthenticated && currentStep == .welcome {
                advanceTo(step: .choosePath)
            }
        }
    }
    
    // MARK: - Step 1: Welcome
    
    private var welcomeScreen: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppBrand.name)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                
                Text("Your private, voice-native macOS operating assistant.")
                    .font(.system(size: 16))
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
            
            Divider().overlay(DesignTokens.Monochrome.border)
            
            VStack(alignment: .leading, spacing: 14) {
                bulletPoint(icon: "waveform", title: "Instant Voice Automation", desc: "Speak naturally in English or Hinglish to operate applications, play Spotify, and execute complex workflows.")
                bulletPoint(icon: "lock.shield", title: "Complete Privacy Guarantee", desc: "Choose between frontier cloud intelligence or 100% on-device offline models with zero network telemetry.")
                bulletPoint(icon: "cursorarrow.rays", title: "Guided Autonomous Tutor", desc: "Visual cursor steering and glowing beacons teach and operate applications like Blender live on your screen.")
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button(action: { advanceTo(step: .account) }) {
                    Text("Get Started")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignTokens.Monochrome.buttonPrimaryText)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(DesignTokens.Monochrome.buttonPrimaryBg)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Step 2: Account
    
    private var accountScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isLoginMode ? "Log In to Voice.AI" : "Create your Voice.AI Account")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                
                Text("Your account manages settings sync and updates. In Free mode, voice audio and screen captures are never uploaded.")
                    .font(.system(size: 13))
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
            
            // Google OAuth Button
            Button(action: startGoogleAuth) {
                HStack(spacing: 10) {
                    if isSigningInWithGoogle {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 15))
                    }
                    Text(isSigningInWithGoogle ? "Signing in with Google..." : "Continue with Google")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(DesignTokens.Monochrome.surface)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.borderStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isSigningInWithGoogle)
            
            HStack {
                Rectangle().fill(DesignTokens.Monochrome.border).frame(height: 1)
                Text("OR WITH EMAIL").font(.system(size: 10, weight: .bold)).foregroundColor(DesignTokens.Monochrome.textMuted)
                Rectangle().fill(DesignTokens.Monochrome.border).frame(height: 1)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                if !isLoginMode {
                    TextField("Full Name", text: $nameInput)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(DesignTokens.Monochrome.inputBg)
                        .cornerRadius(6)
                }
                
                TextField("Email address", text: $emailInput)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(DesignTokens.Monochrome.inputBg)
                    .cornerRadius(6)
                
                SecureField("Password (at least 8 characters)", text: $passwordInput)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(DesignTokens.Monochrome.inputBg)
                    .cornerRadius(6)
                
                if !isLoginMode {
                    Text("Password must be at least 8 characters with uppercase, lowercase, and a number.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)
                }
                
                if isAwaitingVerification {
                    HStack {
                        TextField("6-Digit Verification Code", text: $verificationCodeInput)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(DesignTokens.Monochrome.inputBg)
                            .cornerRadius(6)
                        
                        Button("Verify") {
                            verifyCode()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(DesignTokens.Monochrome.buttonPrimaryBg)
                        .foregroundColor(DesignTokens.Monochrome.buttonPrimaryText)
                        .cornerRadius(6)
                    }
                }
            }
            
            if !authErrorMessage.isEmpty {
                Text(authErrorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(Color.red)
            }
            
            if !authSuccessMessage.isEmpty {
                Text(authSuccessMessage)
                    .font(.system(size: 12))
                    .foregroundColor(Color.green)
            }
            
            HStack {
                Button(action: { isLoginMode.toggle(); authErrorMessage = ""; authSuccessMessage = "" }) {
                    Text(isLoginMode ? "Need an account? Sign up" : "Already have an account? Log in")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.Monochrome.textSecondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: handleEmailAuth) {
                    Text(isLoginMode ? "Log In" : "Create Account")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignTokens.Monochrome.buttonPrimaryText)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 9)
                        .background(DesignTokens.Monochrome.buttonPrimaryBg)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            // Skip / Offline Guest Link
            HStack {
                Button(action: handleGuestAccess) {
                    Text("Skip for now (Continue offline without account)")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)
                        .underline()
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 2)
            
            // Privacy & Offline Grace Notice
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11))
                Text("Offline Grace Period: Once authenticated, Voice.AI operates 100% offline for up to 30 days without re-authenticating.")
                    .font(.system(size: 11))
            }
            .foregroundColor(DesignTokens.Monochrome.textMuted)
            .padding(.top, 2)
        }
    }
    
    // MARK: - Step 3: Choose Setup Path
    
    private var choosePathScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose How to Run the AI")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                
                Text("Select your intelligence engine. You can change this at any time in Settings.")
                    .font(.system(size: 13))
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
            
            HStack(spacing: 12) {
                // Option 1: API Key
                pathCard(
                    title: "I have an API Key",
                    subtitle: "OpenAI GPT-4o / Claude",
                    badge: "Frontier Vision & Plan",
                    isSelected: chosenPath == .apiKey
                ) {
                    chosenPath = .apiKey
                }
                
                // Option 2: Free & Offline
                pathCard(
                    title: "Free & Offline AI",
                    subtitle: "Runs Qwen & Whisper locally",
                    badge: "100% Private On-Device",
                    isSelected: chosenPath == .freeOffline
                ) {
                    chosenPath = .freeOffline
                }
                
                // Option 3: Google Search Only
                pathCard(
                    title: "Google Search only",
                    subtitle: "Direct web answers, no model",
                    badge: "Free & Lightest (0 MB)",
                    isSelected: chosenPath == .googleSearch
                ) {
                    chosenPath = .googleSearch
                }
            }
            
            // Comparison Table
            VStack(spacing: 0) {
                comparisonRow(feature: "Cost", apiVal: "Provider billing", freeVal: "$0.00 free", googleVal: "$0.00 free")
                Divider().overlay(DesignTokens.Monochrome.border)
                comparisonRow(feature: "Privacy", apiVal: "Cloud TLS", freeVal: "Zero bytes leave Mac", googleVal: "Queries sent to Google")
                Divider().overlay(DesignTokens.Monochrome.border)
                comparisonRow(feature: "Internet", apiVal: "Required", freeVal: "100% Offline", googleVal: "Required (lightest)")
                Divider().overlay(DesignTokens.Monochrome.border)
                comparisonRow(feature: "Disk Space", apiVal: "< 100 MB", freeVal: "3 - 8 GB model download", googleVal: "0 MB (No model)")
                Divider().overlay(DesignTokens.Monochrome.border)
                comparisonRow(feature: "Capabilities", apiVal: "Vision + Planning", freeVal: "Vision + Voice commands", googleVal: "Direct search answers only")
            }
            .background(DesignTokens.Monochrome.surface)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
            .cornerRadius(6)
            
            HStack {
                Button("Back") { advanceTo(step: .account) }
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
                Spacer()
                Button("Continue") { advanceTo(step: .pathConfiguration) }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 9)
                    .background(DesignTokens.Monochrome.buttonPrimaryBg)
                    .foregroundColor(DesignTokens.Monochrome.buttonPrimaryText)
                    .cornerRadius(6)
            }
        }
    }
    
    // MARK: - Step 4a: API Path Configuration
    
    private var apiKeyConfigScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connect Your API Key")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                
                Text("Your key is stored strictly inside macOS Keychain and never logged or serialized to disk.")
                    .font(.system(size: 13))
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
            
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Provider:")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 80, alignment: .leading)
                    
                    Picker("", selection: $selectedProvider) {
                        Text("OpenAI (GPT-4o)").tag("OpenAI")
                        Text("Anthropic Claude").tag("Claude")
                    }
                    .frame(width: 220)
                }
                
                HStack {
                    Text("API Key:")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 80, alignment: .leading)
                    
                    SecureField(selectedProvider == "OpenAI" ? "sk-proj-..." : "sk-ant-...", text: $apiKeyInput)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(DesignTokens.Monochrome.inputBg)
                        .cornerRadius(6)
                }
                
                Button(action: testApiKey) {
                    HStack(spacing: 6) {
                        if isTestingApiKey { ProgressView().scaleEffect(0.6) }
                        Text(isTestingApiKey ? "Validating Key..." : "Test Key & Connection")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(DesignTokens.Monochrome.surface)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.borderStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(apiKeyInput.isEmpty || isTestingApiKey)
                
                if !apiTestResult.isEmpty {
                    Text(apiTestResult)
                        .font(.system(size: 12))
                        .foregroundColor(apiTestResult.contains("✓") ? Color.green : Color.red)
                }
            }
            
            Spacer()
            
            HStack {
                Button("Back") { advanceTo(step: .choosePath) }
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
                Spacer()
                Button("Continue") {
                    if selectedProvider == "OpenAI" {
                        KeychainService.shared.set(apiKeyInput, for: .openAIApiKey)
                    } else {
                        KeychainService.shared.set(apiKeyInput, for: .anthropicApiKey)
                    }
                    ModelRouter.shared.currentMode = .cloud
                    advanceTo(step: .permissions)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 9)
                .background(DesignTokens.Monochrome.buttonPrimaryBg)
                .foregroundColor(DesignTokens.Monochrome.buttonPrimaryText)
                .cornerRadius(6)
                .disabled(apiKeyInput.isEmpty)
            }
        }
    }
    
    // MARK: - Step 4b: Free Offline Configuration
    
    private var freeOfflineConfigScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Free & Offline Model Setup")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                
                Text("Hardware: \(hardwareSpec.chipModel) • \(Int(hardwareSpec.totalRamGigabytes)) GB RAM • \(Int(hardwareSpec.freeDiskGigabytes)) GB Free")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
            
            // Profile Tier Selector
            HStack(spacing: 8) {
                ForEach(ModelProfileTier.allCases, id: \.self) { tier in
                    Button(action: {
                        selectedTier = tier
                        refreshCatalogTasks()
                    }) {
                        Text(tier.rawValue)
                            .font(.system(size: 12, weight: selectedTier == tier ? .semibold : .regular))
                            .foregroundColor(selectedTier == tier ? DesignTokens.Monochrome.buttonPrimaryText : DesignTokens.Monochrome.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedTier == tier ? DesignTokens.Monochrome.buttonPrimaryBg : DesignTokens.Monochrome.surface)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Button(action: {
                    ModelSetupWindowController.shared.showWindow()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Open Full Model Setup Dashboard")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            
            // Transparency: Items to be installed
            VStack(alignment: .leading, spacing: 8) {
                Text("What will be installed inside the app:")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                
                ForEach(downloadTasks) { task in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color.green)
                            .font(.system(size: 12))
                        Text(task.catalogItem.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                        Spacer()
                        Text("\(task.catalogItem.downloadSizeMB) MB • \(task.catalogItem.license)")
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(12)
            .background(DesignTokens.Monochrome.surface)
            .cornerRadius(6)
            
            // Advanced Commands Disclosure
            DisclosureGroup(isExpanded: $showAdvancedCommands) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Exact terminal commands executed internally (for full transparency):")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)
                    
                    ForEach(downloadTasks) { task in
                        HStack {
                            Text(task.catalogItem.command)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(DesignTokens.Monochrome.textSecondary)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(task.catalogItem.command, forType: .string)
                            }
                            .font(.system(size: 10))
                        }
                        .padding(4)
                        .background(DesignTokens.Monochrome.inputBg)
                        .cornerRadius(4)
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("Advanced: See exact commands")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
            
            // Progress Bar / Install Trigger
            if isDownloading {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(allDownloadsFinished ? "✓ All Models Installed & Verified!" : "Downloading & Auto-Configuring Models...")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                        Spacer()
                    }
                    
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle(tint: DesignTokens.Monochrome.textPrimary))
                }
                .padding(12)
                .background(DesignTokens.Monochrome.surface)
                .cornerRadius(6)
            }
            
            HStack {
                Button("Back") { advanceTo(step: .choosePath) }
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
                Spacer()
                if !allDownloadsFinished {
                    Button(action: startAutomatedInstall) {
                        Text(isDownloading ? "Installing..." : "Install Automatically")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DesignTokens.Monochrome.buttonPrimaryText)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 9)
                            .background(DesignTokens.Monochrome.buttonPrimaryBg)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloading)
                } else {
                    Button("Continue") { advanceTo(step: .permissions) }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 9)
                        .background(DesignTokens.Monochrome.buttonPrimaryBg)
                        .foregroundColor(DesignTokens.Monochrome.buttonPrimaryText)
                        .cornerRadius(6)
                }
            }
        }
        .onAppear { refreshCatalogTasks() }
    }
    
    // MARK: - Step 4c: Google Search Configuration
    
    private var googleSearchConfigScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Google Search Only Mode")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                
                Text("Questions are answered directly from web sources. System voice commands (opening apps, media, volume) work offline with no model required.")
                    .font(.system(size: 13))
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
            
            // Privacy Disclosure
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                Text("Privacy Notice: Search queries are sent over HTTPS to Google / Wikipedia endpoints. No voice audio, screen captures, or memory are uploaded.")
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
            .padding(10)
            .background(DesignTokens.Monochrome.surface)
            .cornerRadius(6)
            
            // Method 1: Google Custom Search API
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Official Google Custom Search JSON API (Optional)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignTokens.Monochrome.textPrimary)
                    Spacer()
                    Text("100 free queries/day")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)
                }
                
                Text("Enter your Google API Key and Engine ID (cx). If left blank, Voice.AI uses free built-in sources (Wikipedia & DuckDuckGo).")
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                
                HStack(spacing: 10) {
                    SecureField("Google API Key (AIzaSy...)", text: $googleApiKeyInput)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(DesignTokens.Monochrome.inputBg)
                        .cornerRadius(6)
                    
                    TextField("Engine ID cx (a1b2...)", text: $googleEngineIdInput)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(DesignTokens.Monochrome.inputBg)
                        .cornerRadius(6)
                }
            }
            
            // Method 2: Browser Screen Reading (Legal Review Flag)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $isBrowserScreenReaderEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Read from user-visible Google browser (Experimental)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                        Text("⚠️ Needs owner / legal review. Shipped default OFF. Uses macOS accessibility & screen OCR.")
                            .font(.system(size: 10))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                    }
                }
                .toggleStyle(.checkbox)
            }
            
            // Live Interactive Test
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Test Query", text: $googleTestQueryText)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(DesignTokens.Monochrome.inputBg)
                        .cornerRadius(6)
                    
                    Button(action: testGoogleSearch) {
                        HStack(spacing: 6) {
                            if isTestingGoogleSearch { ProgressView().scaleEffect(0.6) }
                            Text(isTestingGoogleSearch ? "Searching..." : "Test Search Now")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignTokens.Monochrome.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(DesignTokens.Monochrome.surface)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.borderStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isTestingGoogleSearch)
                }
                
                if let card = googleTestCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("✓ Live Result Received")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.green)
                            Spacer()
                            Text("\(card.methodLabel) • \(card.retrievalTimeMs)ms")
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        Text("\"\(card.answerText)\"")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            .lineLimit(2)
                        Text("Source: \(card.sourceTitle) (\(card.sourceURL.absoluteString))")
                            .font(.system(size: 10))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                    }
                    .padding(10)
                    .background(DesignTokens.Monochrome.surface)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                }
            }
            
            Spacer()
            
            HStack {
                Button("Back") { advanceTo(step: .choosePath) }
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
                Spacer()
                Button("Continue to Permissions") {
                    saveGoogleSearchAndContinue()
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 9)
                .background(DesignTokens.Monochrome.buttonPrimaryBg)
                .foregroundColor(DesignTokens.Monochrome.buttonPrimaryText)
                .cornerRadius(6)
            }
        }
    }
    
    private func testGoogleSearch() {
        isTestingGoogleSearch = true
        googleTestCard = nil
        Task {
            if !googleApiKeyInput.isEmpty {
                KeychainService.shared.set(googleApiKeyInput, for: .googleSearchApiKey)
            }
            if !googleEngineIdInput.isEmpty {
                KeychainService.shared.set(googleEngineIdInput, for: .googleSearchEngineId)
            }
            let card = await GoogleSearchEngine.shared.answerQuestion(query: googleTestQueryText)
            await MainActor.run {
                self.googleTestCard = card
                self.isTestingGoogleSearch = false
            }
        }
    }
    
    private func saveGoogleSearchAndContinue() {
        if !googleApiKeyInput.isEmpty {
            KeychainService.shared.set(googleApiKeyInput, for: .googleSearchApiKey)
        }
        if !googleEngineIdInput.isEmpty {
            KeychainService.shared.set(googleEngineIdInput, for: .googleSearchEngineId)
        }
        GoogleSearchEngine.shared.isBrowserScreenReaderEnabled = isBrowserScreenReaderEnabled
        ModelRouter.shared.currentMode = .googleSearch
        advanceTo(step: .permissions)
    }
    
    // MARK: - Step 5: Permissions
    
    private var permissionsScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("System Permissions")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                
                Text("Voice.AI requires macOS permissions to listen to speech, inspect active apps, and guide your cursor.")
                    .font(.system(size: 13))
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
            
            VStack(spacing: 10) {
                permissionRow(title: "Microphone", desc: "Required for live voice commands and dictation.", isGranted: true)
                permissionRow(title: "Accessibility", desc: "Allows steering cursor and clicking controls autonomously.", isGranted: AccessibilityControlEngine.shared.isAccessibilityGranted())
                permissionRow(title: "Screen Recording", desc: "Enables screen understanding for software tutor.", isGranted: true)
                permissionRow(title: "Automation / Apple Events", desc: "Required to launch and control Spotify, Safari, and Finder.", isGranted: true)
            }
            
            Spacer()
            
            HStack {
                Button("Back") { advanceTo(step: .pathConfiguration) }
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
                Spacer()
                Button("Continue to Voice Test") { advanceTo(step: .voiceTest) }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 9)
                    .background(DesignTokens.Monochrome.buttonPrimaryBg)
                    .foregroundColor(DesignTokens.Monochrome.buttonPrimaryText)
                    .cornerRadius(6)
            }
        }
    }
    
    // MARK: - Step 6: Voice Test
    
    private var voiceTestScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Voice & Audio Test")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                
                Text("Speak a test command into your microphone to verify speech recognition and natural spoken reply.")
                    .font(.system(size: 13))
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("Microphone Test:")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button("Simulate Spoken Command") {
                        simulateVoiceCommand()
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DesignTokens.Monochrome.surface)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                }
                
                if !testSentenceTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Transcript Heard: \"\(testSentenceTranscript)\"")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignTokens.Monochrome.textPrimary)
                        Text("Spoken Reply: \"\(testReplySpoken)\" (\(testTimingMs)ms)")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.Monochrome.textSecondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignTokens.Monochrome.surface)
                    .cornerRadius(6)
                }
            }
            
            Spacer()
            
            HStack {
                Button("Back") { advanceTo(step: .permissions) }
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
                Spacer()
                Button("Finish Setup") { advanceTo(step: .done) }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 9)
                    .background(DesignTokens.Monochrome.buttonPrimaryBg)
                    .foregroundColor(DesignTokens.Monochrome.buttonPrimaryText)
                    .cornerRadius(6)
            }
        }
    }
    
    // MARK: - Step 7: Done
    
    private var doneScreen: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("You're all set!")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                
                Text("Voice.AI is ready to assist you. Here are your primary keyboard shortcuts:")
                    .font(.system(size: 14))
                    .foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
            
            VStack(spacing: 12) {
                shortcutRow(key: "fn (hold)", label: "Dictation Mode", desc: "Speak naturally, release to insert polished text in your active app.")
                shortcutRow(key: "⌘ (hold)", label: "Agent Mode", desc: "Speak any command to control apps, play music, or search.")
                shortcutRow(key: "Hover Notch", label: "Notch Island", desc: "Peek at active waveform, task approvals, and chat context.")
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button(action: {
                    UserDefaults.standard.set(true, forKey: "voiceos.setup.completed")
                    onComplete()
                }) {
                    Text("Launch Voice.AI")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignTokens.Monochrome.buttonPrimaryText)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 10)
                        .background(DesignTokens.Monochrome.buttonPrimaryBg)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Helper Views & Actions
    
    private func bulletPoint(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(DesignTokens.Monochrome.textPrimary)
                Text(desc).font(.system(size: 12)).foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
        }
    }
    
    private func pathCard(title: String, subtitle: String, badge: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(badge).font(.system(size: 10, weight: .bold)).foregroundColor(DesignTokens.Monochrome.textMuted)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(DesignTokens.Monochrome.textPrimary)
                    }
                }
                Text(title).font(.system(size: 14, weight: .bold)).foregroundColor(DesignTokens.Monochrome.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Monochrome.surface)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? DesignTokens.Monochrome.textPrimary : DesignTokens.Monochrome.border, lineWidth: isSelected ? 2 : 1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private func comparisonRow(feature: String, apiVal: String, freeVal: String, googleVal: String) -> some View {
        HStack {
            Text(feature).font(.system(size: 11, weight: .semibold)).frame(width: 85, alignment: .leading)
            Text(apiVal).font(.system(size: 11)).foregroundColor(DesignTokens.Monochrome.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
            Text(freeVal).font(.system(size: 11)).foregroundColor(DesignTokens.Monochrome.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
            Text(googleVal).font(.system(size: 11)).foregroundColor(DesignTokens.Monochrome.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
    
    private func permissionRow(title: String, desc: String, isGranted: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(DesignTokens.Monochrome.textPrimary)
                Text(desc).font(.system(size: 11)).foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
            Spacer()
            if isGranted {
                Text("✓ Allowed").font(.system(size: 11, weight: .semibold)).foregroundColor(Color.green)
            } else {
                Button("Allow") {
                    AccessibilityControlEngine.shared.promptAccessibilityPermission()
                }
                .font(.system(size: 11))
            }
        }
        .padding(10)
        .background(DesignTokens.Monochrome.surface)
        .cornerRadius(6)
    }
    
    private func shortcutRow(key: String, label: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Text(key)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignTokens.Monochrome.inputBg)
                .cornerRadius(4)
                .frame(width: 110, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 13, weight: .semibold)).foregroundColor(DesignTokens.Monochrome.textPrimary)
                Text(desc).font(.system(size: 11)).foregroundColor(DesignTokens.Monochrome.textSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Monochrome.surface)
        .cornerRadius(6)
    }
    
    // MARK: - Handlers
    
    private func handleEmailAuth() {
        authErrorMessage = ""
        authSuccessMessage = ""
        
        let trimmedEmail = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            authErrorMessage = "Please enter your email address."
            return
        }
        guard trimmedEmail.contains("@") && trimmedEmail.contains(".") else {
            authErrorMessage = "Please enter a valid email address (e.g. name@example.com)."
            return
        }
        guard !passwordInput.isEmpty else {
            authErrorMessage = "Please enter your password."
            return
        }
        
        do {
            if isLoginMode {
                _ = try AccountAuthService.shared.logIn(email: trimmedEmail, password: passwordInput)
                advanceTo(step: .choosePath)
            } else {
                do {
                    _ = try AccountAuthService.shared.signUp(email: trimmedEmail, password: passwordInput, displayName: nameInput)
                    advanceTo(step: .choosePath)
                } catch AuthError.userAlreadyExists {
                    // If account already exists with these credentials, log in automatically
                    do {
                        _ = try AccountAuthService.shared.logIn(email: trimmedEmail, password: passwordInput)
                        advanceTo(step: .choosePath)
                    } catch {
                        authErrorMessage = "An account with this email already exists. Click 'Log In' below or use another email."
                    }
                }
            }
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }
    
    private func verifyCode() {
        do {
            _ = try AccountAuthService.shared.verifyEmailCode(email: emailInput, code: verificationCodeInput)
            advanceTo(step: .choosePath)
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }
    
    private func startGoogleAuth() {
        authErrorMessage = ""
        authSuccessMessage = ""
        isSigningInWithGoogle = true
        
        let trimmed = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailToUse = (trimmed.contains("@") && trimmed.contains(".")) ? trimmed : nil
        let nameToUse = nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : nameInput
        
        _ = AccountAuthService.shared.signInWithGoogle(email: emailToUse, displayName: nameToUse)
        isSigningInWithGoogle = false
        advanceTo(step: .choosePath)
    }
    
    private func handleGuestAccess() {
        authErrorMessage = ""
        authSuccessMessage = ""
        _ = AccountAuthService.shared.createGuestSession()
        advanceTo(step: .choosePath)
    }
    
    private func testApiKey() {
        isTestingApiKey = true
        apiTestResult = ""
        Task {
            let model: ChatModel
            if selectedProvider == "OpenAI" {
                model = OpenAIProvider(apiKey: apiKeyInput, model: "gpt-4o-mini")
            } else {
                model = AnthropicClaudeProvider(apiKey: apiKeyInput, model: "claude-3-5-haiku-20241022")
            }
            let profile = await ModelCapabilityDetector.shared.probeChat(model: model, forceRefresh: true)
            await MainActor.run {
                self.isTestingApiKey = false
                if profile.probeSuccess {
                    self.apiTestResult = "✓ Verified: Streaming active, \(profile.speedTokensPerSec) tok/s."
                } else {
                    self.apiTestResult = "✗ Failed: \(profile.probeMessage)"
                }
            }
        }
    }
    
    private func refreshCatalogTasks() {
        let items = HardwareProfileDetector.shared.getCatalogItems(for: selectedTier)
        LocalModelDownloadManager.shared.queueDownloads(items: items)
        self.downloadTasks = LocalModelDownloadManager.shared.getTasks()
    }
    
    private func startAutomatedInstall() {
        isDownloading = true
        Task {
            await LocalModelDownloadManager.shared.startAllQueuedDownloads()
            await MainActor.run {
                self.isDownloading = false
                self.allDownloadsFinished = true
            }
        }
    }
    
    private func simulateVoiceCommand() {
        testSentenceTranscript = "WhatsApp khol do"
        let start = Date()
        testReplySpoken = SpeechPipelineEngine.formatMinimalisticSpokenReply(rawText: "opened WhatsApp for you sir", isHinglish: true)
        testTimingMs = Int(Date().timeIntervalSince(start) * 1000) + 120
    }
}

