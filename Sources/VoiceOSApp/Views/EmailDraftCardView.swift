import SwiftUI
import AppKit
import VoiceOSCore

public struct EmailDraftCardView: View {
    @ObservedObject var appState: AppState
    @StateObject private var viewModel: EmailComposerViewModel
    public var onSend: (EmailDraft) -> Void
    public var onDismiss: () -> Void

    @FocusState private var isSubjectFocused: Bool
    @FocusState private var isBodyFocused: Bool
    @FocusState private var isToInputFocused: Bool
    @State private var isAttachingFile: Bool = false

    public init(
        appState: AppState,
        draft: EmailDraft,
        onSend: @escaping (EmailDraft) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.appState = appState
        self.onSend = onSend
        self.onDismiss = onDismiss
        let vm = EmailComposerViewModel(draft: draft, providerName: "Gmail")
        _viewModel = StateObject(wrappedValue: vm)
    }

    public var body: some View {
        ZStack {
            // Soft cloudy blue side "wings" glow matching reference screenshot
            HStack {
                Circle()
                    .fill(DesignTokens.EmailComposer.sideWings)
                    .frame(width: 80, height: 80)
                    .blur(radius: 24)
                    .offset(x: -30)

                Spacer()

                Circle()
                    .fill(DesignTokens.EmailComposer.sideWings)
                    .frame(width: 80, height: 80)
                    .blur(radius: 24)
                    .offset(x: 30)
            }
            .frame(width: 530)

            // Main Composer Card Container
            VStack(spacing: 0) {
                // MARK: - Header Bar (Slightly lighter gray pill)
                HStack(spacing: 9) {
                    // Mail Provider Icon (Gmail envelope emblem)
                    ZStack {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 20, height: 15)

                        Image(systemName: "envelope.fill")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(Color(red: 0.92, green: 0.26, blue: 0.21))
                    }

                    Text("New Message")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(.white)

                    Spacer()

                    // Discard / Close Button
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.40))
                            .padding(5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Close composer (draft is saved)")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9.5)
                .background(DesignTokens.EmailComposer.headerBackground)

                // Divider below Header
                Rectangle()
                    .fill(DesignTokens.EmailComposer.dividerLine)
                    .frame(height: 0.8)

                // MARK: - "To" Line with Recipient Chips
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("To")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.50))
                            .frame(width: 26, alignment: .leading)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(viewModel.toChips.enumerated()), id: \.offset) { idx, chip in
                                    HStack(spacing: 4) {
                                        Text(chip)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundColor(DesignTokens.EmailComposer.recipientChipText)

                                        Button(action: {
                                            viewModel.removeRecipient(at: idx)
                                        }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(DesignTokens.EmailComposer.recipientChipText.opacity(0.7))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(DesignTokens.EmailComposer.recipientChipBg)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(DesignTokens.EmailComposer.recipientChipBorder, lineWidth: 0.6)
                                    )
                                }

                                TextField("", text: $viewModel.toInput)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12.5))
                                    .foregroundColor(.white)
                                    .frame(minWidth: 80)
                                    .focused($isToInputFocused)
                                    .onSubmit {
                                        viewModel.addRecipient(viewModel.toInput)
                                    }
                            }
                        }

                        Spacer()

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.isCcBccVisible.toggle()
                            }
                        }) {
                            Text(viewModel.isCcBccVisible ? "Hide Cc" : "Cc/Bcc")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.40))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    // Optional CC / BCC Rows
                    if viewModel.isCcBccVisible {
                        Rectangle()
                            .fill(DesignTokens.EmailComposer.dividerLine)
                            .frame(height: 0.6)

                        HStack(spacing: 8) {
                            Text("Cc")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.50))
                                .frame(width: 26, alignment: .leading)

                            ForEach(Array(viewModel.ccChips.enumerated()), id: \.offset) { idx, chip in
                                Text(chip)
                                    .font(.system(size: 11.5))
                                    .foregroundColor(DesignTokens.EmailComposer.recipientChipText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(DesignTokens.EmailComposer.recipientChipBg)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                    }
                }

                // Divider below To
                Rectangle()
                    .fill(DesignTokens.EmailComposer.dividerLine)
                    .frame(height: 0.8)

                // MARK: - Subject Row
                HStack(spacing: 8) {
                    TextField("Subject", text: $viewModel.subject)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundColor(.white)
                        .focused($isSubjectFocused)
                        .onChange(of: viewModel.subject) { _, _ in
                            viewModel.scheduleDraftSync()
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8.5)

                // Divider below Subject
                Rectangle()
                    .fill(DesignTokens.EmailComposer.dividerLine)
                    .frame(height: 0.8)

                // MARK: - Body Text Area
                ZStack(alignment: .topLeading) {
                    if viewModel.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Write your message here...")
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.28))
                            .padding(.top, 7)
                            .padding(.leading, 4)
                    }

                    TextEditor(text: $viewModel.body)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.92))
                        .lineSpacing(3.5)
                        .frame(minHeight: 70, maxHeight: 110)
                        .focused($isBodyFocused)
                        .onChange(of: viewModel.body) { _, _ in
                            viewModel.scheduleDraftSync()
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                // Attachments Chips Row (if any)
                if !viewModel.attachmentPaths.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(viewModel.attachmentPaths.enumerated()), id: \.offset) { idx, path in
                                HStack(spacing: 4) {
                                    Image(systemName: "paperclip")
                                        .font(.system(size: 9))
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .font(.system(size: 11, weight: .medium))
                                    Button(action: {
                                        viewModel.removeAttachment(at: idx)
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .foregroundColor(Color.white.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.10))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                    }
                }

                // MARK: - Footer Actions: Status / Attach + Send Button
                HStack(alignment: .center) {
                    // Paperclip attachment button
                    Button(action: {
                        presentAttachmentPicker()
                    }) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.50))
                            .padding(6)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Attach files (up to 25 MB)")

                    // Live Status line
                    Text(viewModel.status.displayText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(statusColor)

                    // Undo Button when in undo window
                    if case .undoWindow = viewModel.status {
                        Button(action: {
                            viewModel.cancelSend()
                        }) {
                            Text("Undo")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.80))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Blue Send Capsule Button (exactly matches reference screenshot)
                    Button(action: {
                        triggerSend()
                    }) {
                        HStack(spacing: 5) {
                            if case .sending = viewModel.status {
                                ProgressView()
                                    .scaleEffect(0.55)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text("Send")
                                .font(.system(size: 13.5, weight: .semibold, design: .default))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 7)
                        .background(DesignTokens.EmailComposer.sendButtonBg)
                        .clipShape(Capsule())
                        .shadow(color: DesignTokens.EmailComposer.sendButtonBg.opacity(0.40), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.status == .sending)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .background(DesignTokens.EmailComposer.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.EmailComposer.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.EmailComposer.cardCornerRadius, style: .continuous)
                    .stroke(DesignTokens.EmailComposer.cardBorder, lineWidth: 0.8)
            )
            .shadow(color: DesignTokens.EmailComposer.cardGlow, radius: 18, x: 0, y: 4)
            .frame(width: 500)
        }
        .onAppear {
            // Focus subject or body if to is already specified
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if !viewModel.toChips.isEmpty && viewModel.subject.isEmpty {
                    isSubjectFocused = true
                }
            }
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .editing, .saved: return Color.white.opacity(0.45)
        case .saving: return Color.white.opacity(0.70)
        case .undoWindow: return Color(red: 1.0, green: 0.76, blue: 0.20)
        case .sending: return Color(red: 0.35, green: 0.70, blue: 1.0)
        case .sent: return Color(red: 0.20, green: 0.85, blue: 0.45)
        case .failed: return Color(red: 1.0, green: 0.35, blue: 0.35)
        case .queuedOffline: return Color.orange
        }
    }

    private func triggerSend() {
        BoringSoundEngine.shared.playTap()
        viewModel.startSendPipeline { success, message in
            if success {
                BoringSoundEngine.shared.playDone()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    onSend(viewModel.draft)
                }
            } else {
                BoringSoundEngine.shared.playError()
            }
        }
    }

    private func presentAttachmentPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach"
        if panel.runModal() == .OK {
            for url in panel.urls {
                _ = viewModel.addAttachment(path: url.path)
            }
        }
    }
}
