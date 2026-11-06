import SwiftUI
import VoiceOSCore
import AppKit

public struct DictationStudioView: View {
    @ObservedObject var appState: AppState
    @State private var dictationText: String = ""
    @State private var selectedProfile: AppContextProfile = .general
    @State private var isRecording: Bool = false
    @State private var statusMessage: String = "Ready to dictate"
    @State private var copiedNotice: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private func toggleRecording() {
        if isRecording {
            isRecording = false
            statusMessage = "Processing & polishing..."
            appState.stopVoice()
        } else {
            isRecording = true
            statusMessage = "Listening... Speak naturally"
            appState.triggerVoice(mode: .dictation)
        }
    }
    
    private func polishCurrentText() {
        guard !dictationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let result = DictationPolishEngine.shared.polish(rawText: dictationText, profile: selectedProfile)
        dictationText = result.polishedText
        statusMessage = "Polished (\(result.correctionTags.count) corrections applied)"
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit6) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dictation Studio")
                        .font(DesignTokens.Typography.fontTitle1)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    Text("Instant on-device speech dictation sandbox. Test speech input, live audio waveform, and text polish.")
                        .font(DesignTokens.Typography.fontSubheadline)
                        .foregroundColor(DesignTokens.Colors.textMuted)
                }
                
                // Live Audio Level & Record Controller
                VStack(spacing: DesignTokens.Spacing.unit4) {
                    HStack(spacing: DesignTokens.Spacing.unit4) {
                        // Microphone Visualizer
                        HStack(spacing: 4) {
                            ForEach(0..<appState.audioLevels.count, id: \.self) { idx in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isRecording ? DesignTokens.Colors.accentGreen : DesignTokens.Colors.textMuted)
                                    .frame(width: 4, height: max(6, appState.audioLevels[idx] * 40))
                                    .animation(.easeOut(duration: 0.1), value: appState.audioLevels[idx])
                            }
                        }
                        .frame(width: 100, height: 44)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isRecording ? Color.red : DesignTokens.Colors.accentGreen)
                                    .frame(width: 8, height: 8)
                                Text(isRecording ? "RECORDING ACTIVE" : "MICROPHONE STANDBY")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(isRecording ? Color.red : DesignTokens.Colors.accentGreen)
                            }
                            Text(statusMessage)
                                .font(DesignTokens.Typography.fontCaption)
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                        }
                        
                        Spacer()
                        
                        // Big Start/Stop Button
                        Button(action: toggleRecording) {
                            HStack(spacing: 8) {
                                Image(systemName: isRecording ? "stop.circle.fill" : "mic.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(isRecording ? "Stop Dictation" : "Start Dictating")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isRecording ? Color.red : DesignTokens.Colors.accentBlue)
                            .cornerRadius(DesignTokens.Radius.pill)
                            .shadow(color: (isRecording ? Color.red : DesignTokens.Colors.accentBlue).opacity(0.3), radius: 6, y: 2)
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
                
                // Transcription Text Area
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit3) {
                    HStack {
                        Text("Transcribed Output")
                            .font(DesignTokens.Typography.fontCallout)
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        
                        Spacer()
                        
                        // Polish Context Picker
                        Picker("Target App", selection: $selectedProfile) {
                            ForEach(AppContextProfile.allCases, id: \.self) { profile in
                                Text(profile.rawValue).tag(profile)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 380)
                    }
                    
                    TextEditor(text: $dictationText)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .lineSpacing(4)
                        .padding(12)
                        .frame(minHeight: 180)
                        .background(DesignTokens.Colors.cardBackground)
                        .cornerRadius(DesignTokens.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                        )
                    
                    // Action Buttons Row
                    HStack(spacing: DesignTokens.Spacing.unit3) {
                        Button(action: polishCurrentText) {
                            HStack(spacing: 4) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 12))
                                Text("Polish Tone")
                                    .font(DesignTokens.Typography.fontCaptionBold)
                            }
                            .foregroundColor(DesignTokens.Colors.accentBlue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DesignTokens.Colors.inputBackground)
                            .cornerRadius(DesignTokens.Radius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            guard !dictationText.isEmpty else { return }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(dictationText, forType: .string)
                            copiedNotice = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedNotice = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: copiedNotice ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 12))
                                Text(copiedNotice ? "Copied!" : "Copy Text")
                                    .font(DesignTokens.Typography.fontCaptionBold)
                            }
                            .foregroundColor(copiedNotice ? DesignTokens.Colors.accentGreen : DesignTokens.Colors.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DesignTokens.Colors.inputBackground)
                            .cornerRadius(DesignTokens.Radius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            guard !dictationText.isEmpty else { return }
                            UniversalTextInserter.shared.insertText(dictationText) { _ in }
                            statusMessage = "Inserted text into active application!"
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right.doc.on.clipboard")
                                    .font(.system(size: 12))
                                Text("Insert into Frontmost App")
                                    .font(DesignTokens.Typography.fontCaptionBold)
                            }
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DesignTokens.Colors.inputBackground)
                            .cornerRadius(DesignTokens.Radius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button(action: {
                            dictationText = ""
                            statusMessage = "Cleared"
                        }) {
                            Text("Clear")
                                .font(DesignTokens.Typography.fontCaption)
                                .foregroundColor(DesignTokens.Colors.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(DesignTokens.Spacing.unit6)
        }
        .onReceive(appState.$currentTranscript) { newTranscript in
            if !newTranscript.isEmpty && isRecording {
                self.dictationText = newTranscript
            }
        }
    }
}
