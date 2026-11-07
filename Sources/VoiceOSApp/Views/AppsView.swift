import SwiftUI
import VoiceOSCore
import AppKit

public struct AppsView: View {
    @ObservedObject var appState: AppState
    @State private var buildPrompt: String = ""
    @State private var selectedSubtab: String = "Connected Apps"
    @State private var actionMessage: String? = nil
    
    let subtabs = ["Connected Apps", "System Integrations", "Developer Tools"]
    
    public init(appState: AppState) {
        self.appState = appState
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
                    ForEach($appState.connectedApps) { $app in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                // App Squircle Icon
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(Color(hex: app.iconColor))
                                        .frame(width: 38, height: 38)
                                        .shadow(color: Color(hex: app.iconColor).opacity(0.35), radius: 4, x: 0, y: 2)
                                    
                                    Image(systemName: app.iconName)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(DesignTokens.Colors.textPrimary)
                                    
                                    Text(app.description)
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundColor(DesignTokens.Colors.textSecondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $app.isConnected)
                                    .labelsHidden()
                                    .toggleStyle(SwitchToggleStyle(tint: DesignTokens.Colors.accentGreen))
                            }
                            
                            Divider()
                                .overlay(DesignTokens.Colors.cardBorder)
                            
                            // App Action Buttons & Status
                            HStack(spacing: 8) {
                                Button(action: {
                                    launchApp(named: app.name)
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "arrow.up.forward.app")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("Launch App")
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
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(app.isConnected ? DesignTokens.Colors.accentGreen : DesignTokens.Colors.textMuted)
                                        .frame(width: 5, height: 5)
                                    
                                    Text(app.isConnected ? "Automated" : "Disabled")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(app.isConnected ? DesignTokens.Colors.accentGreen : DesignTokens.Colors.textMuted)
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
