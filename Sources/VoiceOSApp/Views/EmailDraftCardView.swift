import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VoiceOSCore

public struct EmailDraftCardView: View {
    @ObservedObject var appState: AppState
    @StateObject private var viewModel: EmailComposerViewModel
    public var onSend: (EmailDraft) -> Void
    public var onDismiss: () -> Void

    @FocusState private var isSubjectFocused: Bool
    @FocusState private var isBodyFocused: Bool
    @FocusState private var isToInputFocused: Bool
    @FocusState private var isFromInputFocused: Bool
    @State private var isDropTargeted: Bool = false
    @State private var isHoveringCard: Bool = false
    @State private var autoCollapseTimer: Timer? = nil

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
                    Button(action: {
                        cancelAutoCollapseTimer()
                        onDismiss()
                    }) {
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
                .padding(.vertical, 8.5)
                .background(DesignTokens.EmailComposer.headerBackground)

                // Divider below Header
                Rectangle()
                    .fill(DesignTokens.EmailComposer.dividerLine)
                    .frame(height: 0.8)

                // MARK: - "From" Sender Row (Manual Sender Editing)
                HStack(spacing: 8) {
                    Text("From")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.45))
                        .frame(width: 32, alignment: .leading)

                    TextField("sender@company.com (optional)", text: $viewModel.fromAddress)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.0))
                        .foregroundColor(.white.opacity(0.85))
                        .focused($isFromInputFocused)
                        .onChange(of: viewModel.fromAddress) { _, _ in
                            resetAutoCollapseTimer()
                            viewModel.scheduleDraftSync()
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)

                Rectangle()
                    .fill(DesignTokens.EmailComposer.dividerLine)
                    .frame(height: 0.6)

                // MARK: - "To" Line with Recipient Chips & Manual Text Field
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("To")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.50))
                            .frame(width: 32, alignment: .leading)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(viewModel.toChips.enumerated()), id: \.offset) { idx, chip in
                                    HStack(spacing: 4) {
                                        Text(chip)
                                            .font(.system(size: 12.0, weight: .medium))
                                            .foregroundColor(DesignTokens.EmailComposer.recipientChipText)

                                        Button(action: {
                                            viewModel.removeRecipient(at: idx)
                                            resetAutoCollapseTimer()
                                        }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(DesignTokens.EmailComposer.recipientChipText.opacity(0.7))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3.5)
                                    .background(DesignTokens.EmailComposer.recipientChipBg)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(DesignTokens.EmailComposer.recipientChipBorder, lineWidth: 0.6)
                                    )
                                }

                                TextField(viewModel.toChips.isEmpty ? "recipient@company.com" : "+ Add recipient", text: $viewModel.toInput)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12.0))
                                    .foregroundColor(.white)
                                    .frame(minWidth: 110)
                                    .focused($isToInputFocused)
                                    .onChange(of: viewModel.toInput) { _, _ in
                                        resetAutoCollapseTimer()
                                    }
                                    .onSubmit {
                                        let input = viewModel.toInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !input.isEmpty {
                                            viewModel.addRecipient(input)
                                        }
                                        resetAutoCollapseTimer()
                                    }
                            }
                        }

                        Spacer()

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.isCcBccVisible.toggle()
                            }
                            resetAutoCollapseTimer()
                        }) {
                            Text(viewModel.isCcBccVisible ? "Hide Cc" : "Cc/Bcc")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.40))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6.5)

                    // Optional CC / BCC Rows
                    if viewModel.isCcBccVisible {
                        Rectangle()
                            .fill(DesignTokens.EmailComposer.dividerLine)
                            .frame(height: 0.6)

                        HStack(spacing: 8) {
                            Text("Cc")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.50))
                                .frame(width: 32, alignment: .leading)

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
                        .font(.system(size: 13.5, weight: .medium, design: .default))
                        .foregroundColor(.white)
                        .focused($isSubjectFocused)
                        .onChange(of: viewModel.subject) { _, _ in
                            resetAutoCollapseTimer()
                            viewModel.scheduleDraftSync()
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)

                // Divider below Subject
                Rectangle()
                    .fill(DesignTokens.EmailComposer.dividerLine)
                    .frame(height: 0.8)

                // MARK: - Body Text Area
                ZStack(alignment: .topLeading) {
                    if viewModel.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Write your message here...")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.28))
                            .padding(.top, 7)
                            .padding(.leading, 4)
                    }

                    TextEditor(text: $viewModel.body)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.92))
                        .lineSpacing(3.5)
                        .frame(minHeight: 80, maxHeight: 130)
                        .focused($isBodyFocused)
                        .onChange(of: viewModel.body) { _, _ in
                            resetAutoCollapseTimer()
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
                                        resetAutoCollapseTimer()
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
                        HStack(spacing: 4) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.60))
                        }
                        .padding(6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Attach files (or drag and drop into card)")

                    // Live Status line
                    Text(viewModel.status.displayText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(statusColor)

                    Spacer()

                    // Blue Send Capsule Button
                    Button(action: {
                        triggerSend()
                    }) {
                        HStack(spacing: 5) {
                            if case .sending = viewModel.status {
                                ProgressView()
                                    .scaleEffect(0.55)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(viewModel.status == .sending ? "Sending..." : "Send")
                                .font(.system(size: 13.5, weight: .semibold, design: .default))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 22)
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
                .padding(.vertical, 8)
            }
            .background(DesignTokens.EmailComposer.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.EmailComposer.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.EmailComposer.cardCornerRadius, style: .continuous)
                    .stroke(isDropTargeted ? Color.cyan.opacity(0.8) : DesignTokens.EmailComposer.cardBorder, lineWidth: isDropTargeted ? 1.5 : 0.8)
            )
            .shadow(color: isDropTargeted ? Color.cyan.opacity(0.4) : DesignTokens.EmailComposer.cardGlow, radius: 18, x: 0, y: 4)
            .frame(width: 500)
            // MARK: - Drag and Drop Files
            .onDrop(of: [UTType.fileURL.identifier, UTType.item.identifier], isTargeted: $isDropTargeted) { providers in
                resetAutoCollapseTimer()
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let fileUrl = url {
                            DispatchQueue.main.async {
                                _ = viewModel.addAttachment(path: fileUrl.path)
                                BoringSoundEngine.shared.playTap()
                            }
                        }
                    }
                }
                return true
            }
        }
        // MARK: - 5-Second Idle Auto-Collapse Timer
        .onHover { hovering in
            isHoveringCard = hovering
            if hovering {
                cancelAutoCollapseTimer()
            } else {
                startAutoCollapseTimer()
            }
        }
        .onAppear {
            startAutoCollapseTimer()
        }
        .onDisappear {
            cancelAutoCollapseTimer()
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
        cancelAutoCollapseTimer()
        BoringSoundEngine.shared.playTap()
        let val = viewModel.validateBeforeSend()
        guard val.valid else {
            viewModel.validationError = val.reason
            viewModel.status = .failed(reason: val.reason ?? "Invalid draft")
            BoringSoundEngine.shared.playError()
            return
        }

        viewModel.updateDraftModel()
        viewModel.status = .sending
        onSend(viewModel.draft)
    }

    private func presentAttachmentPicker() {
        resetAutoCollapseTimer()
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach"
        panel.level = .modalPanel
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    _ = viewModel.addAttachment(path: url.path)
                }
                BoringSoundEngine.shared.playTap()
            }
        }
    }

    private func startAutoCollapseTimer() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            DispatchQueue.main.async {
                if !isSubjectFocused && !isBodyFocused && !isToInputFocused && !isFromInputFocused && !isHoveringCard {
                    withAnimation(NotchAnimations.closeSpring) {
                        appState.islandState = .resting
                    }
                }
            }
        }
    }

    private func resetAutoCollapseTimer() {
        autoCollapseTimer?.invalidate()
        startAutoCollapseTimer()
    }

    private func cancelAutoCollapseTimer() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
    }
}
