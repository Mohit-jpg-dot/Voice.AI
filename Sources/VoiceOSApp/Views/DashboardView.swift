import SwiftUI
import VoiceOSCore
import AppKit

public struct DashboardView: View {
    @ObservedObject var appState: AppState
    @State private var showingAboutModal: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private var dynamicGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String
        if hour >= 5 && hour < 12 {
            greeting = "Good morning"
        } else if hour >= 12 && hour < 17 {
            greeting = "Good afternoon"
        } else {
            greeting = "Good evening"
        }
        let firstName = appState.userName.components(separatedBy: " ").first ?? "there"
        return "\(greeting), \(firstName)"
    }
    
    private var dictationPercentage: Double {
        guard !appState.recentHistory.isEmpty else { return 0 }
        let count = appState.recentHistory.filter { $0.mode == .dictation }.count
        return Double(count) / Double(appState.recentHistory.count)
    }
    
    private var agentPercentage: Double {
        guard !appState.recentHistory.isEmpty else { return 0 }
        let count = appState.recentHistory.filter { $0.mode == .agent }.count
        return Double(count) / Double(appState.recentHistory.count)
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit6) {
                // Top Header Row
                HStack(spacing: DesignTokens.Spacing.unit3) {
                    Image(systemName: "globe")
                        .font(DesignTokens.Typography.fontTitle2)
                        .foregroundColor(DesignTokens.Colors.accentBlue)
                    
                    Text(dynamicGreeting)
                        .font(DesignTokens.Typography.fontTitle1)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    Spacer()
                    
                    // About / System Info buttom
                    Button(action: {
                        showingAboutModal.toggle()
                    }) {
                        HStack(spacing: DesignTokens.Spacing.unit2) {
                            HStack(spacing: -6) {
                                Circle()
                                    .fill(Color(red: 0.85, green: 0.75, blue: 0.65))
                                    .frame(width: 18, height: 18)
                                    .overlay(Text("V").font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                                Circle()
                                    .fill(Color(red: 0.65, green: 0.75, blue: 0.85))
                                    .frame(width: 18, height: 18)
                                    .overlay(Text("O").font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                            }
                            
                            Text("About \(AppBrand.name)")
                                .font(DesignTokens.Typography.fontCaptionBold)
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.unit3)
                        .padding(.vertical, 7)
                        .background(DesignTokens.Colors.cardBackground)
                        .cornerRadius(DesignTokens.Radius.pill)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.pill)
                                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                        )
                        .shadow(
                            color: DesignTokens.Shadows.subtle.color,
                            radius: DesignTokens.Shadows.subtle.radius,
                            x: DesignTokens.Shadows.subtle.x,
                            y: DesignTokens.Shadows.subtle.y
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingAboutModal) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "waveform.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(DesignTokens.Colors.accentBlue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(AppBrand.name) for macOS")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("Version 1.0.0 (Build 42) · Native Apple Silicon")
                                        .font(.system(size: 11))
                                        .foregroundColor(DesignTokens.Colors.textMutedLight)
                                }
                            }
                            Divider()
                            Text("A voice-first macOS computer agent engineered for instant speech dictation, notch HUD interaction, and on-device natural language automation.")
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.Colors.textSecondaryLight)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("Open GitHub") {
                                    if let url = URL(string: "https://github.com") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                Spacer()
                                Button("Close") {
                                    showingAboutModal = false
                                }
                            }
                        }
                        .padding(16)
                        .frame(width: 320)
                    }
                }
                
                // Two Mode Cards Grid - interactive to switch tabs
                HStack(spacing: DesignTokens.Spacing.unit4) {
                    // Dictation Mode Card
                    Button(action: {
                        appState.activeNavTab = .dictation
                    }) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit3) {
                            HStack(spacing: DesignTokens.Spacing.unit2) {
                                Image(systemName: "mic.fill")
                                    .font(DesignTokens.Typography.fontCallout)
                                    .foregroundColor(DesignTokens.Colors.accentBlue)
                                
                                Text("Dictation Mode")
                                    .font(DesignTokens.Typography.fontCallout)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            
                            HStack(spacing: DesignTokens.Spacing.unit1) {
                                Text("Hold")
                                    .font(DesignTokens.Typography.fontSubheadline)
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                                
                                Text("fn")
                                    .font(DesignTokens.Typography.fontKeyCap)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DesignTokens.Colors.inputBackground)
                                    .cornerRadius(DesignTokens.Radius.xs)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.8)
                                    )
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                
                                Text("in any text field")
                                    .font(DesignTokens.Typography.fontSubheadline)
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                            }
                            
                            Text("Speak naturally, polishes into clean text.")
                                .font(DesignTokens.Typography.fontCaption)
                                .foregroundColor(DesignTokens.Colors.textMuted)
                        }
                        .padding(DesignTokens.Spacing.unit5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.Colors.cardBackground)
                        .cornerRadius(DesignTokens.Radius.lg)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Agent Mode Card
                    Button(action: {
                        appState.activeNavTab = .agent
                    }) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit3) {
                            HStack(spacing: DesignTokens.Spacing.unit2) {
                                Image(systemName: "sparkles")
                                    .font(DesignTokens.Typography.fontCallout)
                                    .foregroundColor(DesignTokens.Colors.accentPurple)
                                
                                Text("Agent Mode")
                                    .font(DesignTokens.Typography.fontCallout)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            
                            HStack(spacing: DesignTokens.Spacing.unit1) {
                                Text("Hold")
                                    .font(DesignTokens.Typography.fontSubheadline)
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                                
                                Text("command")
                                    .font(DesignTokens.Typography.fontKeyCap)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DesignTokens.Colors.inputBackground)
                                    .cornerRadius(DesignTokens.Radius.xs)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.8)
                                    )
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                
                                Text("to speak")
                                    .font(DesignTokens.Typography.fontSubheadline)
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                            }
                            
                            Text("Trigger AI actions in WhatsApp, Notes, Safari, and more.")
                                .font(DesignTokens.Typography.fontCaption)
                                .foregroundColor(DesignTokens.Colors.textMuted)
                        }
                        .padding(DesignTokens.Spacing.unit5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.Colors.cardBackground)
                        .cornerRadius(DesignTokens.Radius.lg)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // Statistics Section (Real live counters)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit3) {
                    Text("Statistics")
                        .font(DesignTokens.Typography.fontTitle3)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    HStack(spacing: DesignTokens.Spacing.unit4) {
                        // Total Sessions
                        HStack(spacing: DesignTokens.Spacing.unit3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 16))
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(DesignTokens.Colors.inputBackground)
                                .cornerRadius(DesignTokens.Radius.sm)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Total Sessions")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                                Text("\(appState.totalSessions)")
                                    .font(DesignTokens.Typography.fontTitle2)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                            }
                        }
                        .padding(DesignTokens.Spacing.unit4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.Colors.cardBackground)
                        .cornerRadius(DesignTokens.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                        )
                        
                        // Total Words
                        HStack(spacing: DesignTokens.Spacing.unit3) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 16))
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(DesignTokens.Colors.inputBackground)
                                .cornerRadius(DesignTokens.Radius.sm)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Total Words")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                                Text("\(appState.totalWords)")
                                    .font(DesignTokens.Typography.fontTitle2)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                            }
                        }
                        .padding(DesignTokens.Spacing.unit4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.Colors.cardBackground)
                        .cornerRadius(DesignTokens.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                        )
                        
                        // Time Saved
                        HStack(spacing: DesignTokens.Spacing.unit3) {
                            Image(systemName: "clock")
                                .font(.system(size: 16))
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(DesignTokens.Colors.inputBackground)
                                .cornerRadius(DesignTokens.Radius.sm)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Time Saved")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                                Text("\(appState.timeSavedMinutes)m")
                                    .font(DesignTokens.Typography.fontTitle2)
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                            }
                        }
                        .padding(DesignTokens.Spacing.unit4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.Colors.cardBackground)
                        .cornerRadius(DesignTokens.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                        )
                    }
                }
                
                // Apps Usage & Modes Usage row
                HStack(spacing: DesignTokens.Spacing.unit4) {
                    // Apps Usage Card
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit3) {
                        Text("Apps Usage")
                            .font(DesignTokens.Typography.fontCallout)
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        
                        if appState.appUsages.isEmpty {
                            VStack(alignment: .center, spacing: DesignTokens.Spacing.unit2) {
                                Image(systemName: "app.dashed")
                                    .font(.system(size: 24))
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                                Text("No app activity yet")
                                    .font(DesignTokens.Typography.fontCaptionBold)
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                                Text("Dictate in WhatsApp, Safari, or Notes to see usage metrics.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 90)
                        } else {
                            VStack(spacing: DesignTokens.Spacing.unit2) {
                                ForEach(appState.appUsages) { stat in
                                    HStack {
                                        HStack(spacing: DesignTokens.Spacing.unit2) {
                                            Image(systemName: stat.iconName)
                                                .font(.system(size: 12))
                                                .foregroundColor(.white)
                                                .frame(width: 22, height: 22)
                                                .background(Color.black)
                                                .cornerRadius(DesignTokens.Radius.xs)
                                            
                                            Text(stat.appName)
                                                .font(DesignTokens.Typography.fontBody)
                                                .foregroundColor(DesignTokens.Colors.textPrimary)
                                        }
                                        
                                        Spacer()
                                        
                                        Text("\(stat.count)")
                                            .font(DesignTokens.Typography.fontCaptionBold)
                                            .foregroundColor(DesignTokens.Colors.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignTokens.Colors.cardBackground)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                    )
                    
                    // Modes Usage Card
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit3) {
                        Text("Modes Usage")
                            .font(DesignTokens.Typography.fontCallout)
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        
                        if appState.recentHistory.isEmpty {
                            VStack(alignment: .center, spacing: DesignTokens.Spacing.unit2) {
                                Image(systemName: "chart.bar.xaxis")
                                    .font(.system(size: 24))
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                                Text("No mode data yet")
                                    .font(DesignTokens.Typography.fontCaptionBold)
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                                Text("Dictate or run agent commands to view mode distribution.")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 90)
                        } else {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit3) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Dictation Mode")
                                            .font(DesignTokens.Typography.fontCaption)
                                            .foregroundColor(DesignTokens.Colors.textSecondary)
                                        Spacer()
                                        Text("\(Int(dictationPercentage * 100))%")
                                            .font(DesignTokens.Typography.fontCaptionBold)
                                            .foregroundColor(DesignTokens.Colors.textMuted)
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(DesignTokens.Colors.cardBorder)
                                                .frame(width: geo.size.width, height: 6)
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(DesignTokens.Colors.accentBlue)
                                                .frame(width: max(4, geo.size.width * CGFloat(dictationPercentage)), height: 6)
                                        }
                                    }
                                    .frame(height: 6)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Agent Mode")
                                            .font(DesignTokens.Typography.fontCaption)
                                            .foregroundColor(DesignTokens.Colors.textSecondary)
                                        Spacer()
                                        Text("\(Int(agentPercentage * 100))%")
                                            .font(DesignTokens.Typography.fontCaptionBold)
                                            .foregroundColor(DesignTokens.Colors.accentBlue)
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(DesignTokens.Colors.cardBorder)
                                                .frame(width: geo.size.width, height: 6)
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(DesignTokens.Colors.accentBlue)
                                                .frame(width: max(4, geo.size.width * CGFloat(agentPercentage)), height: 6)
                                        }
                                    }
                                    .frame(height: 6)
                                }
                            }
                        }
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}
