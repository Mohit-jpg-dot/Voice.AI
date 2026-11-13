import SwiftUI
import VoiceOSCore
import AppKit

public struct AppsView: View {
    @ObservedObject var appState: AppState
    @State private var buildPrompt: String = ""
    @State private var selectedSubtab: String = "All Apps"
    @State private var actionMessage: String? = nil
    @State private var configuringApp: ConnectedApp? = nil
    
    let subtabs = ["All Apps", "Connected", "System", "Dev Tools"]
    
    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredAppIndices: [Int] {
        appState.connectedApps.indices.filter { idx in
            let app = appState.connectedApps[idx]
            if selectedSubtab == "All Apps" { return true }
            if selectedSubtab == "Connected" { return app.category.contains("Connected") }
            if selectedSubtab == "System" { return app.category.contains("System") }
            if selectedSubtab == "Dev Tools" { return app.category.contains("Dev") }
            return app.category == selectedSubtab
        }
    }
    
    private func isActuallyIntegrated(_ app: ConnectedApp) -> Bool {
        let settings = AppIntegrationEngine.shared.currentSettings()
        switch app.id {
        case "mail":
            let hasGmail = !(KeychainService.shared.get(GmailAPIEmailBackend.tokenKeychainKey) ?? "").isEmpty
            let hasAppleMail = MacOSAppIconResolver.isInstalled(nameOrKey: "Mail")
            return hasGmail || hasAppleMail
        case "whatsapp":
            let hasCloudApi = !(KeychainService.shared.get(.whatsappCloudToken) ?? "").isEmpty
            let hasDesktopApp = MacOSAppIconResolver.isInstalled(nameOrKey: "WhatsApp")
            return hasCloudApi || hasDesktopApp
        case "slack":
            let hasToken = !(KeychainService.shared.get(.slackUserToken) ?? "").isEmpty
            let hasWebhook = !settings.slackWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasToken || hasWebhook
        case "discord":
            let hasToken = !(KeychainService.shared.get(.discordBotToken) ?? "").isEmpty
            let hasWebhook = !settings.discordWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasToken || hasWebhook
        case "notion":
            return !(KeychainService.shared.get(.notionToken) ?? "").isEmpty || !settings.notionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "youtube":
            return MacOSAppIconResolver.isInstalled(nameOrKey: "Safari") || MacOSAppIconResolver.isInstalled(nameOrKey: "Google Chrome")
        case "spotify":
            return MacOSAppIconResolver.isInstalled(nameOrKey: "Spotify")
        case "notes", "calendar", "reminders", "terminal", "safari", "chrome", "vscode":
            return MacOSAppIconResolver.isInstalled(nameOrKey: app.id)
        default:
            return MacOSAppIconResolver.isInstalled(nameOrKey: app.id) || MacOSAppIconResolver.isInstalled(nameOrKey: app.name)
        }
    }

    private func launchApp(named name: String) {
        Task {
            let res = await AgentActionDispatcher.shared.dispatch(transcript: "open \(name)")
            await MainActor.run {
                actionMessage = res.summary
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    actionMessage = nil
                }
            }
        }
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                // Header & Subtabs
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Apps")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                            
                            Text("macOS")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(DesignTokens.Colors.accentBlue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DesignTokens.Colors.accentBlue.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        
                        Text("Native macOS applications integrated with high-speed voice automation.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Segmented Subtab Pills
                    HStack(spacing: 2) {
                        ForEach(subtabs, id: \.self) { tab in
                            let isTabSelected = selectedSubtab == tab
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    selectedSubtab = tab
                                }
                            }) {
                                Text(tab)
                                    .font(.system(size: 11, weight: isTabSelected ? .semibold : .medium))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .foregroundColor(isTabSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textMuted)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        isTabSelected ?
                                            DesignTokens.Colors.cardBackground :
                                            Color.clear
                                    )
                                    .clipShape(Capsule())
                                    .shadow(color: isTabSelected ? Color.black.opacity(0.08) : Color.clear, radius: 3, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(DesignTokens.Colors.inputBackground)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                    )
                }
                
                // Status banner if an app action was executed
                if let message = actionMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DesignTokens.Colors.accentGreen)
                            .font(.system(size: 14))
                        Text(message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(DesignTokens.Colors.accentGreen.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DesignTokens.Colors.accentGreen.opacity(0.3), lineWidth: 0.5)
                    )
                }
                
                // Raycast/Spotlight-style Natural Language Command Bar
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Natural Language Command Bar", systemImage: "sparkles")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        
                        Spacer()
                        
                        Text("Instant Execution")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DesignTokens.Colors.textMuted)
                    }
                    
                    HStack(spacing: 10) {
                        ZStack(alignment: .leading) {
                            if buildPrompt.isEmpty && !appState.isCurrentlyListening {
                                Text("Ask anything, search, control Mac, or Hinglish (e.g. \"open WhatsApp and draft message\")...")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                                    .padding(.leading, 12)
                            }
                            
                            TextField("", text: $buildPrompt, onCommit: {
                                guard !buildPrompt.isEmpty else { return }
                                appState.submitTypedPrompt(buildPrompt)
                                buildPrompt = ""
                            })
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .background(DesignTokens.Colors.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    appState.isCurrentlyListening ?
                                        DesignTokens.Colors.accentBlue :
                                        DesignTokens.Colors.cardBorder,
                                    lineWidth: appState.isCurrentlyListening ? 1.5 : 0.5
                                )
                        )
                        
                        // Dictation Microphone Button
                        Button(action: {
                            if appState.isCurrentlyListening {
                                appState.stopVoice()
                            } else {
                                appState.triggerVoice(mode: .agent)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: appState.isCurrentlyListening ? "stop.circle.fill" : "mic.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(appState.isCurrentlyListening ? .red : DesignTokens.Colors.accentBlue)
                                Text(appState.isCurrentlyListening ? "Stop" : "Dictate")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                appState.isCurrentlyListening ?
                                    Color.red.opacity(0.12) :
                                    DesignTokens.Colors.cardBackground
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(appState.isCurrentlyListening ? Color.red.opacity(0.4) : DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Dictate action or command by voice (or hold Control key)")
                        
                        // Dispatch Button with Return Keycap
                        Button(action: {
                            guard !buildPrompt.isEmpty else { return }
                            appState.submitTypedPrompt(buildPrompt)
                            buildPrompt = ""
                        }) {
                            HStack(spacing: 5) {
                                Text("Dispatch")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Text("↵")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color.white.opacity(0.8))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(DesignTokens.Gradients.brand)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .shadow(color: DesignTokens.Colors.accentBlue.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                    .onChange(of: appState.currentTranscript) { transcript in
                        if appState.isCurrentlyListening && !transcript.isEmpty {
                            buildPrompt = transcript
                        }
                    }
                }
                .padding(14)
                .background(DesignTokens.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                )
                
                // Section Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Installed Mac Applications")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        
                        Text("Ready for native scriptless and accessibility-driven voice automation")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(DesignTokens.Colors.textMuted)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 5) {
                        Circle()
                            .fill(DesignTokens.Colors.accentGreen)
                            .frame(width: 6, height: 6)
                        Text("Native macOS Engine")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(DesignTokens.Colors.inputBackground)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                    )
                }
                
                // Grid of Connected Apps (Modern Sleek macOS Cards)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(filteredAppIndices, id: \.self) { idx in
                        let appBinding = $appState.connectedApps[idx]
                        let app = appState.connectedApps[idx]
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                // Real macOS App Icon or Authentic Brand Artwork
                                AppTileIconView(appKey: app.id, appName: app.name, size: 40)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(DesignTokens.Colors.textPrimary)
                                    
                                    Text(app.description)
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundColor(DesignTokens.Colors.textSecondary)
                                        .lineLimit(2)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: appBinding.isConnected)
                                    .labelsHidden()
                                    .toggleStyle(SwitchToggleStyle(tint: DesignTokens.Colors.accentGreen))
                            }
                            
                            Divider()
                                .overlay(DesignTokens.Colors.cardBorder)
                            
                            // App Action Buttons & Status
                            HStack(spacing: 8) {
                                Button(action: {
                                    launchApp(named: app.id == "mail" ? "Mail" : (app.id == "youtube" ? "Safari" : app.name))
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "arrow.up.forward.app")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("Launch")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundColor(DesignTokens.Colors.accentBlue)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(DesignTokens.Colors.accentBlue.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(DesignTokens.Colors.accentBlue.opacity(0.25), lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    configuringApp = app
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "slider.horizontal.3")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("Configure")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(DesignTokens.Colors.inputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                Spacer()
                                
                                let installedOrConfigured = isActuallyIntegrated(app)
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(!app.isConnected ? DesignTokens.Colors.textMuted : (installedOrConfigured ? DesignTokens.Colors.accentGreen : Color.orange))
                                        .frame(width: 6, height: 6)
                                    
                                    Text(!app.isConnected ? "Disabled" : (installedOrConfigured ? "Integrated" : "Not Configured"))
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundColor(!app.isConnected ? DesignTokens.Colors.textMuted : (installedOrConfigured ? DesignTokens.Colors.accentGreen : Color.orange))
                                }
                            }
                        }
                        .padding(14)
                        .background(DesignTokens.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                        )
                    }
                }
            }
            .padding(22)
        }
        .sheet(item: $configuringApp) { app in
            AppIntegrationConfigSheet(
                app: app,
                isEnabled: Binding(
                    get: {
                        appState.connectedApps.first(where: { $0.id == app.id })?.isConnected ?? true
                    },
                    set: { newVal in
                        if let i = appState.connectedApps.firstIndex(where: { $0.id == app.id }) {
                            appState.connectedApps[i].isConnected = newVal
                        }
                    }
                ),
                onRunCommand: { sample in
                    configuringApp = nil
                    appState.submitTypedPrompt(sample)
                }
            )
        }
    }
}

private struct AppIntegrationConfigSheet: View {
    let app: ConnectedApp
    @Binding var isEnabled: Bool
    let onRunCommand: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var settings = AppIntegrationEngine.shared.currentSettings()

    private var sampleCommands: [String] {
        switch app.id {
        case "mail":
            return [
                "Check my unread emails",
                "Draft an email to boss about weekly project update",
                "Reply to this email saying thanks, I will review it today",
                "Send email to team@acme.com saying standup moved to 11 AM"
            ]
        case "whatsapp":
            return [
                "Open WhatsApp",
                "Draft whatsapp message to Rahul saying running 10 mins late",
                "Send whatsapp message to Mom saying reached safely",
                "Read my WhatsApp screen"
            ]
        case "slack":
            return [
                "Open #general in Slack",
                "Draft slack message to #engineering saying PR is ready",
                "Send slack message to #updates saying build passed",
                "Summarize this Slack channel"
            ]
        case "discord":
            return [
                "Open Discord",
                "Draft discord message to #general saying hopping on in 5",
                "Send discord message to #voice saying stream started"
            ]
        case "youtube":
            return [
                "Search Swift concurrency tutorial on YouTube",
                "Pause YouTube",
                "Fast forward 10 seconds",
                "Mute YouTube",
                "Summarize this YouTube video"
            ]
        case "notion":
            return [
                "Create Notion page titled Sprint Notes with review API",
                "Search Roadmap in Notion",
                "Append ship voice integrations to Notion"
            ]
        case "notes":
            return [
                "Create a note Buy coffee and oat milk",
                "Add call dentist to my Tasks note",
                "Read my Tasks note",
                "List my notes"
            ]
        case "terminal":
            return [
                "Run command in terminal git status",
                "Open terminal and run ls -la",
                "Read terminal output"
            ]
        default:
            return ["Open \(app.name)"]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: app.iconColor))
                        .frame(width: 40, height: 40)
                    Image(systemName: app.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 16, weight: .bold))
                    Text(app.description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("Integrated", isOn: $isEnabled)
                    .toggleStyle(.switch)
            }

            Divider()

            // App-specific configuration controls
            if app.id == "mail" {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Email Client Backend")
                        .font(.system(size: 12, weight: .semibold))
                    Picker("", selection: $settings.emailClientMode) {
                        Text("Auto (Apple Mail + Gmail fallback)").tag("auto")
                        Text("Apple Mail App").tag("apple_mail")
                        Text("Gmail in Browser").tag("gmail")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Text("Optional Email Signature")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("Sent with Voice.AI", text: $settings.emailSignature)
                        .textFieldStyle(.roundedBorder)
                }
            } else if app.id == "slack" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Slack Incoming Webhook URL (Optional — enables instant background send)")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("https://hooks.slack.com/services/...", text: $settings.slackWebhookURL)
                        .textFieldStyle(.roundedBorder)
                }
            } else if app.id == "discord" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Discord Channel Webhook URL (Optional — enables instant background send)")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("https://discord.com/api/webhooks/...", text: $settings.discordWebhookURL)
                        .textFieldStyle(.roundedBorder)
                }
            } else if app.id == "notion" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notion Internal Integration Token (Optional — enables REST API page creation)")
                        .font(.system(size: 12, weight: .semibold))
                    SecureField("secret_...", text: $settings.notionToken)
                        .textFieldStyle(.roundedBorder)
                    Text("Default Parent Page ID (32-char UUID from Notion URL)")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("Optional Notion Page ID", text: $settings.notionParentPageId)
                        .textFieldStyle(.roundedBorder)
                }
            } else if app.id == "youtube" || app.id == "safari" || app.id == "chrome" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preferred Browser for Web / YouTube Automation")
                        .font(.system(size: 12, weight: .semibold))
                    Picker("", selection: $settings.youtubePreferredBrowser) {
                        Text("Safari").tag("Safari")
                        Text("Google Chrome").tag("Google Chrome")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            } else if app.id == "notes" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Default Apple Notes Folder")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("Notes", text: $settings.notesDefaultFolder)
                        .textFieldStyle(.roundedBorder)
                }
            } else if app.id == "terminal" {
                Toggle("Run commands inside visible Terminal.app window by default", isOn: $settings.terminalOpenWindowByDefault)
                    .font(.system(size: 12, weight: .medium))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Try Voice / Click to Run")
                    .font(.system(size: 12, weight: .semibold))
                ForEach(sampleCommands, id: \.self) { sample in
                    Button(action: {
                        saveSettings()
                        onRunCommand(sample)
                    }) {
                        HStack {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Colors.accentBlue)
                            Text("\"\(sample)\"")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save Settings") {
                    saveSettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 480, height: 470)
    }

    private func saveSettings() {
        let updated = settings
        AppIntegrationEngine.shared.updateSettings { current in
            current.emailClientMode = updated.emailClientMode
            current.emailSignature = updated.emailSignature
            current.slackWebhookURL = updated.slackWebhookURL
            current.discordWebhookURL = updated.discordWebhookURL
            current.notionToken = updated.notionToken
            current.notionParentPageId = updated.notionParentPageId
            current.youtubePreferredBrowser = updated.youtubePreferredBrowser
            current.notesDefaultFolder = updated.notesDefaultFolder
            current.terminalOpenWindowByDefault = updated.terminalOpenWindowByDefault
        }
    }
}

// Color hex helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
