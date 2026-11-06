import SwiftUI
import VoiceOSCore
import AppKit

public struct AgentHubView: View {
    @ObservedObject var appState: AppState
    @State private var promptText: String = ""
    @State private var executionLogs: [String] = []
    
    let quickActions = [
        ("Open WhatsApp", "message.fill", "open WhatsApp"),
        ("Open Safari", "safari.fill", "open Safari"),
        ("Open Notes", "note.text", "open Notes"),
        ("Open VS Code", "chevron.left.forwardslash.chevron.right", "open Visual Studio Code"),
        ("Search macOS News", "globe", "search for latest macOS Sequoia features"),
        ("Open Settings", "gearshape.fill", "open System Settings")
    ]
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private func executeAction(_ command: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        executionLogs.insert("[\(timestamp)] Dispatching: \"\(command)\"", at: 0)
        appState.submitTypedPrompt(command)
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit6) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agent Hub")
                        .font(DesignTokens.Typography.fontTitle1)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    Text("Dispatch voice or text actions to native Mac apps, automation scripts, and search engines.")
                        .font(DesignTokens.Typography.fontSubheadline)
                        .foregroundColor(DesignTokens.Colors.textMuted)
                }
                
                // Prompt Input Box
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit3) {
                    Text("Command Console")
                        .font(DesignTokens.Typography.fontCallout)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    HStack(spacing: DesignTokens.Spacing.unit3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16))
                            .foregroundColor(DesignTokens.Colors.accentBlue)
                        
                        TextField("Type a command (e.g. 'open WhatsApp', 'search web for Apple', 'open Notes')...", text: $promptText, onCommit: {
                            guard !promptText.isEmpty else { return }
                            executeAction(promptText)
                            promptText = ""
                        })
                        .textFieldStyle(.plain)
                        .font(DesignTokens.Typography.fontBody)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                        
                        Button(action: {
                            guard !promptText.isEmpty else { return }
                            executeAction(promptText)
                            promptText = ""
                        }) {
                            Text("Execute")
                                .font(DesignTokens.Typography.fontCaptionBold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(DesignTokens.Gradients.brand)
                                .cornerRadius(DesignTokens.Radius.sm)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .background(DesignTokens.Colors.cardBackground)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                    )
                }
                
                // Quick Action Chips
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit3) {
                    Text("One-Click Test Actions")
                        .font(DesignTokens.Typography.fontCallout)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.unit3) {
                        ForEach(quickActions, id: \.0) { item in
                            Button(action: {
                                executeAction(item.2)
                            }) {
                                HStack(spacing: DesignTokens.Spacing.unit2) {
                                    Image(systemName: item.1)
                                        .font(.system(size: 13))
                                        .foregroundColor(DesignTokens.Colors.accentBlue)
                                    Text(item.0)
                                        .font(DesignTokens.Typography.fontBodyMedium)
                                        .foregroundColor(DesignTokens.Colors.textPrimary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(DesignTokens.Colors.textMuted)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(DesignTokens.Colors.cardBackground)
                                .cornerRadius(DesignTokens.Radius.md)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                        .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Current Execution Result Card (ChatGPT-Style Deep Response View)
                if !appState.currentAgentReply.isEmpty {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit3) {
                        HStack {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .font(.system(size: 14))
                                .foregroundColor(DesignTokens.Colors.accentBlue)
                            Text("Agent Intelligence & Search Output")
                                .font(DesignTokens.Typography.fontCallout)
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                            Spacer()
                            
                            // Copy button
                            Button(action: {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(appState.currentAgentReply, forType: .string)
                                BoringSoundEngine.shared.playTap()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                    Text("Copy")
                                        .font(DesignTokens.Typography.fontCaptionBold)
                                }
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(DesignTokens.Colors.inputBackground)
                                .cornerRadius(DesignTokens.Radius.xs)
                            }
                            .buttonStyle(.plain)
                            
                            // Speak Button
                            Button(action: {
                                SpeechPipelineEngine.shared.speakResponse(appState.currentAgentReply)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 11))
                                    Text("Speak")
                                        .font(DesignTokens.Typography.fontCaptionBold)
                                }
                                .foregroundColor(DesignTokens.Colors.accentBlue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(DesignTokens.Colors.inputBackground)
                                .cornerRadius(DesignTokens.Radius.xs)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(appState.currentAgentReply)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 380)
                        .background(DesignTokens.Colors.inputBackground)
                        .cornerRadius(DesignTokens.Radius.sm)
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .background(DesignTokens.Colors.cardBackground)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.accentBlue.opacity(0.3), lineWidth: 0.8)
                    )
                }
                
                // Live Execution Console Log
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit3) {
                    HStack {
                        Text("Live Execution Log")
                            .font(DesignTokens.Typography.fontCallout)
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        Spacer()
                        if !executionLogs.isEmpty {
                            Button(action: { executionLogs.removeAll() }) {
                                Text("Clear")
                                    .font(DesignTokens.Typography.fontCaption)
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        if executionLogs.isEmpty {
                            Text("No actions dispatched yet in this session.")
                                .font(DesignTokens.Typography.fontCaption)
                                .foregroundColor(DesignTokens.Colors.textMuted)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(executionLogs.prefix(6), id: \.self) { log in
                                Text(log)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                            }
                        }
                    }
                    .padding(DesignTokens.Spacing.unit3)
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

