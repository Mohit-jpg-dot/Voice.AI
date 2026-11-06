import SwiftUI
import VoiceOSCore

public struct NotchHUDView: View {
    @ObservedObject var appState: AppState
    @State private var notesText: String = ""
    @State private var isChecked: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit3) {
            // Top Bar: Notch anchor indicator & App branding
            HStack(spacing: DesignTokens.Spacing.unit2) {
                Image(systemName: "globe")
                    .font(DesignTokens.Typography.fontBodyMedium)
                    .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                
                Text(AppBrand.name)
                    .font(DesignTokens.Typography.fontCaptionBold)
                    .foregroundColor(DesignTokens.Colors.textPrimaryDark.opacity(0.85))
                
                Spacer()
                
                // State Indicator or Live Waveform
                switch appState.executionState {
                case .listening(let mode):
                    HStack(spacing: 3) {
                        ForEach(0..<appState.audioLevels.count, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(DesignTokens.Colors.accentBlue)
                                .frame(width: 2.5, height: max(6, appState.audioLevels[index] * 18))
                        }
                    }
                    .frame(height: 18)
                    
                    Text(mode.rawValue)
                        .font(DesignTokens.Typography.fontCaption)
                        .foregroundColor(DesignTokens.Colors.accentBlue)
                case .thinking:
                    ProgressView()
                        .scaleEffect(0.65)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Thinking...")
                        .font(DesignTokens.Typography.fontCaption)
                        .foregroundColor(DesignTokens.Colors.textSecondaryDark)
                case .executing(let task):
                    Text("Executing: \(task)")
                        .font(DesignTokens.Typography.fontCaption)
                        .foregroundColor(DesignTokens.Colors.accentGreen)
                default:
                    Button(action: {
                        withAnimation(.spring()) {
                            appState.isHistoryDrawerOpen.toggle()
                        }
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.Colors.textSecondaryDark)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        withAnimation(.spring()) {
                            appState.isNotchHUDVisible = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(DesignTokens.Colors.textMutedDark)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 2)
            
            // User Speech Bubble / Prompt
            Text(appState.currentTranscript)
                .font(DesignTokens.Typography.fontBodyMedium)
                .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            // Agent Response Text
            Text(appState.currentAgentReply)
                .font(DesignTokens.Typography.fontSubheadline)
                .foregroundColor(DesignTokens.Colors.textSecondaryDark)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            // Embedded Confirmation / Interactive Card (Calendar / Things 3)
            if let action = appState.currentAction {
                if action.appName == "Calendar" || action.title.contains("Roadmap") {
                    // Meeting Confirmation Card matching reference screenshot
                    VStack(alignment: .leading, spacing: 6) {
                        Text(action.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(action.subtitle ?? "Monday, June 15, 2026, 2:00 PM - 3:00 PM PDT")
                            .font(.system(size: 13))
                            .foregroundColor(Color.gray)
                        
                        HStack(spacing: 4) {
                            Text("Attendees: ")
                                .font(.system(size: 12))
                                .foregroundColor(Color.gray)
                            Text("kai@voiceos.com, maksim@voiceos.com")
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.Colors.accentBlue)
                        }
                        
                        HStack {
                            Text("Google Meet Link")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DesignTokens.Colors.accentBlue)
                            Spacer()
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundColor(Color.gray)
                        }
                        .padding(.top, 4)
                    }
                    .padding(DesignTokens.Spacing.unit3)
                    .background(DesignTokens.Colors.surfaceElevatedDark.opacity(0.85))
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.borderSubtleDark, lineWidth: 1)
                    )
                    
                    // Sources Row
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 16, height: 16)
                                .overlay(Text("G").font(.system(size: 10, weight: .bold)).foregroundColor(.blue))
                            Circle()
                                .fill(Color.red)
                                .frame(width: 16, height: 16)
                                .overlay(Text("G").font(.system(size: 10, weight: .bold)).foregroundColor(.white))
                        }
                        Text("Sources")
                            .font(.system(size: 11))
                            .foregroundColor(Color.gray)
                    }
                    .padding(.top, 2)
                    .padding(.leading, 4)
                } else {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit2) {
                        HStack {
                            HStack(spacing: DesignTokens.Spacing.unit1) {
                                Text("W")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(3)
                                    .background(Color.white.opacity(0.12))
                                    .cornerRadius(DesignTokens.Radius.xs)
                                
                                Text("TO-DO")
                                    .font(DesignTokens.Typography.fontCaptionBold)
                                    .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                            }
                            
                            Spacer()
                            
                            Text("Today")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(DesignTokens.Colors.accentBlue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DesignTokens.Colors.accentBlue.opacity(0.16))
                                .cornerRadius(DesignTokens.Radius.xs)
                        }
                        
                        // Checkbox & Task Title
                        HStack(alignment: .top, spacing: DesignTokens.Spacing.unit2) {
                            Button(action: { isChecked.toggle() }) {
                                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 14))
                                    .foregroundColor(isChecked ? DesignTokens.Colors.accentBlue : DesignTokens.Colors.textMutedDark)
                            }
                            .buttonStyle(.plain)
                            
                            Text(action.title)
                                .font(DesignTokens.Typography.fontBody)
                                .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                        }
                        
                        // Optional Notes Field
                        TextField("Notes (optional)", text: $notesText)
                            .textFieldStyle(.plain)
                            .font(DesignTokens.Typography.fontSubheadline)
                            .padding(.horizontal, DesignTokens.Spacing.unit2)
                            .padding(.vertical, 6)
                            .background(DesignTokens.Colors.borderSubtleDark)
                            .cornerRadius(DesignTokens.Radius.sm)
                            .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                        
                        // Metadata & Actions
                        HStack {
                            if let subtitle = action.subtitle {
                                Text(subtitle)
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMutedDark)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                appState.approveCurrentAction()
                            }) {
                                Text(action.isApproved ? "Added" : "Add to-do")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(action.isApproved ? DesignTokens.Colors.accentGreen : .white)
                                    .padding(.horizontal, DesignTokens.Spacing.unit3)
                                    .padding(.vertical, 6)
                                    .background(action.isApproved ? Color.white.opacity(0.15) : DesignTokens.Colors.accentBlue)
                                    .cornerRadius(DesignTokens.Radius.pill)
                            }
                            .buttonStyle(.plain)
                            .disabled(action.isApproved)
                        }
                    }
                    .padding(DesignTokens.Spacing.unit3)
                    .background(DesignTokens.Colors.surfaceElevatedDark.opacity(0.85))
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.borderSubtleDark, lineWidth: 1)
                    )
                }
            }
        }
        .padding(DesignTokens.Spacing.unit4)
        .frame(width: 460)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                DesignTokens.Colors.hudBackground
            }
        )
        .cornerRadius(DesignTokens.Radius.xxl)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xxl)
                .stroke(DesignTokens.Colors.borderGlassSpecular, lineWidth: 1)
        )
        .shadow(
            color: DesignTokens.Shadows.hud.color,
            radius: DesignTokens.Shadows.hud.radius,
            x: DesignTokens.Shadows.hud.x,
            y: DesignTokens.Shadows.hud.y
        )
    }
}

