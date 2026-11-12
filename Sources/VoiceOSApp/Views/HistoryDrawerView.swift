import SwiftUI
import AppKit
import VoiceOSCore

/// Floating Left-Edge History Sidebar + Collapsed Trigger Pill + ChatGPT-style Session Viewer.
/// Toggleable anytime with Command + H or by clicking the left-edge pill.
public struct HistoryDrawerView: View {
    @ObservedObject var appState: AppState
    @State private var searchQuery: String = ""
    @State private var followUpText: String = ""
    @State private var hoveredSessionId: String? = nil
    @State private var isPillHovered: Bool = false
    @State private var copiedConversationId: String? = nil

    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredSessions: [ConversationSessionRecord] {
        let base = appState.conversationSessions
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.filter { session in
            if session.title.localizedCaseInsensitiveContains(trimmed) { return true }
            return session.messages.contains { $0.content.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    private var groupedSections: [(title: String, items: [ConversationSessionRecord])] {
        let sessions = filteredSessions
        guard !sessions.isEmpty else { return [] }

        let cal = Calendar.current
        let pinned = sessions.filter { $0.isPinned }
        let unpinned = sessions.filter { !$0.isPinned }

        var today: [ConversationSessionRecord] = []
        var yesterday: [ConversationSessionRecord] = []
        var week: [ConversationSessionRecord] = []
        var earlier: [ConversationSessionRecord] = []

        let now = Date()
        for item in unpinned {
            if cal.isDateInToday(item.updatedAt) {
                today.append(item)
            } else if cal.isDateInYesterday(item.updatedAt) {
                yesterday.append(item)
            } else if let days = cal.dateComponents([.day], from: item.updatedAt, to: now).day, days <= 7 {
                week.append(item)
            } else {
                earlier.append(item)
            }
        }

        var result: [(String, [ConversationSessionRecord])] = []
        if !pinned.isEmpty { result.append(("Pinned", pinned)) }
        if let firstToday = today.first {
            let tf = DateFormatter()
            tf.dateFormat = "HH:mm"
            result.append(("Today, \(tf.string(from: firstToday.updatedAt))", today))
        }
        if !yesterday.isEmpty { result.append(("Yesterday", yesterday)) }
        if !week.isEmpty { result.append(("Previous 7 Days", week)) }
        if !earlier.isEmpty { result.append(("Earlier", earlier)) }
        return result
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if !appState.isHistoryDrawerOpen {
                collapsedLeftEdgePill
                Spacer()
            } else {
                expandedSidebarColumn
                    .transition(.move(edge: .leading).combined(with: .opacity))

                if let selected = appState.selectedConversation {
                    sessionDetailPane(session: selected)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear {
            appState.refreshConversationSessions()
        }
    }

    // MARK: - Collapsed Left-Edge Trigger Pill (matches reference Pic 2)

    private var collapsedLeftEdgePill: some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                appState.toggleHistorySidebar()
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.08, blue: 0.10).opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(isPillHovered ? 0.34 : 0.16), lineWidth: 1)
                    )
                    .offset(x: -10)

                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.88))
                        .frame(width: 3, height: 10)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 3, height: 6)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.88))
                        .frame(width: 3, height: 10)
                }
                .padding(.leading, 3)
            }
            .frame(width: isPillHovered ? 28 : 22, height: 84)
            .clipped()
            .shadow(color: Color.black.opacity(0.35), radius: 8, x: 2, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isPillHovered = hovering
            }
        }
        .help("Open History Sidebar (⌘H)")
    }

    // MARK: - Expanded Left Sidebar (matches reference Pic 1)

    private var expandedSidebarColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top Header: Search pill + Lock + New Chat + Collapse
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textSecondaryDark)

                    TextField("Search", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundColor(DesignTokens.Colors.textPrimaryDark)

                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Colors.textMutedDark)
                        }
                        .buttonStyle(.plain)
                    }

                    Image(systemName: EncryptedChatHistoryManager.shared.isIncognito ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Colors.textMutedDark)
                        .help(EncryptedChatHistoryManager.shared.isIncognito ? "Incognito active" : "AES-256 Encrypted Local History")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)

                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        appState.startNewConversationSession()
                    }
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("New Session")

                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        appState.isHistoryDrawerOpen = false
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.textSecondaryDark)
                        .frame(width: 26, height: 28)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Hide Sidebar (⌘H)")
            }

            // Dynamic Scrollable Sectioned Sessions List
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if groupedSections.isEmpty {
                        VStack(spacing: 8) {
                            Spacer().frame(height: 36)
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 24))
                                .foregroundColor(DesignTokens.Colors.textMutedDark)
                            Text(searchQuery.isEmpty ? "No sessions saved yet" : "No matching sessions")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                            Text("Speak with Voice.AI or type a prompt to start a persistent session.")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Colors.textMutedDark)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(groupedSections, id: \.title) { section in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(DesignTokens.Colors.textMutedDark)
                                    .padding(.horizontal, 6)
                                    .padding(.top, 2)

                                ForEach(section.items) { session in
                                    sessionRow(session)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Footer Keyboard Shortcut Hints (matches reference Pic 1)
            VStack(alignment: .leading, spacing: 3) {
                Divider().overlay(Color.white.opacity(0.10)).padding(.bottom, 4)
                HStack {
                    Text("⌘H")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                    Text("— toggle sidebar")
                        .font(.system(size: 10.5))
                        .foregroundColor(DesignTokens.Colors.textMutedDark)
                    Spacer()
                    Text("\(appState.conversationSessions.count) sessions")
                        .font(.system(size: 10))
                        .foregroundColor(DesignTokens.Colors.textMutedDark)
                }
                HStack(spacing: 4) {
                    Text("Click session")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textSecondaryDark)
                    Text("to open & continue ·")
                        .font(.system(size: 10.5))
                        .foregroundColor(DesignTokens.Colors.textMutedDark)
                    Text("Esc")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textSecondaryDark)
                    Text("to close")
                        .font(.system(size: 10.5))
                        .foregroundColor(DesignTokens.Colors.textMutedDark)
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 288)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.05, green: 0.06, blue: 0.08).opacity(0.84)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 16, x: 4, y: 6)
        .padding(.leading, 8)
    }

    private func sessionRow(_ session: ConversationSessionRecord) -> some View {
        let isSelected = appState.selectedConversation?.id == session.id
        let isHovered = hoveredSessionId == session.id
        let iconName = sessionIconName(for: session)

        return HStack(spacing: 9) {
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    appState.openConversationSession(session)
                }
            }) {
                HStack(spacing: 9) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [DesignTokens.Colors.accentBlue, DesignTokens.Colors.accentCyan.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 22, height: 22)
                        Image(systemName: iconName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 1.5) {
                        HStack(spacing: 4) {
                            Text(session.title)
                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                                .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                                .lineLimit(1)
                            if session.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 8.5))
                                    .foregroundColor(DesignTokens.Colors.accentBlue)
                            }
                        }

                        if isHovered || isSelected {
                            Text("\(session.messages.count) msgs • \(relativeTime(session.updatedAt))")
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Colors.textMutedDark)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isHovered || isSelected {
                HStack(spacing: 4) {
                    Button(action: {
                        appState.togglePinConversationSession(id: session.id)
                    }) {
                        Image(systemName: session.isPinned ? "pin.slash" : "pin")
                            .font(.system(size: 10))
                            .foregroundColor(DesignTokens.Colors.textSecondaryDark)
                            .padding(4)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            appState.deleteConversationSession(id: session.id)
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(DesignTokens.Colors.accentRed.opacity(0.85))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.14) : (isHovered ? Color.white.opacity(0.08) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.20) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            hoveredSessionId = hovering ? session.id : (hoveredSessionId == session.id ? nil : hoveredSessionId)
        }
    }

    // MARK: - ChatGPT-style Open Session Detail & Continue Conversation Pane

    private func sessionDetailPane(session: ConversationSessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Session Detail Header
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                        .lineLimit(1)
                    Text("\(session.persona) • \(session.messages.count) messages • Active Session")
                        .font(.system(size: 10.5))
                        .foregroundColor(DesignTokens.Colors.textMutedDark)
                }

                Spacer()

                Button(action: {
                    if let md = EncryptedChatHistoryManager.shared.exportConversationMarkdown(id: session.id) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(md, forType: .string)
                        copiedConversationId = session.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedConversationId = nil }
                    }
                }) {
                    Image(systemName: copiedConversationId == session.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Colors.textSecondaryDark)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .help("Copy Session Transcript")

                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        appState.selectedConversation = nil
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.textSecondaryDark)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .help("Close Session View")
            }

            Divider().overlay(Color.white.opacity(0.10))

            // Scrollable Conversation Turns
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(session.messages) { msg in
                            messageBubble(msg, persona: session.persona)
                                .id(msg.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: session.messages.count) { _ in
                    if let last = session.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Continue Session Composer (ChatGPT Follow-Up)
            HStack(spacing: 8) {
                TextField("Ask a follow-up in this session...", text: $followUpText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                    .onSubmit {
                        sendFollowUp()
                    }

                Button(action: {
                    appState.triggerVoice(mode: .agent)
                }) {
                    Image(systemName: appState.isCurrentlyListening ? "waveform.circle.fill" : "mic.fill")
                        .font(.system(size: 14))
                        .foregroundColor(appState.isCurrentlyListening ? DesignTokens.Colors.accentBlue : DesignTokens.Colors.textSecondaryDark)
                }
                .buttonStyle(.plain)
                .help("Speak Follow-up")

                Button(action: sendFollowUp) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DesignTokens.Colors.textMutedDark : DesignTokens.Colors.accentBlue)
                }
                .buttonStyle(.plain)
                .disabled(followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .padding(14)
        .frame(width: 388)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.05, green: 0.06, blue: 0.08).opacity(0.88)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 16, x: 4, y: 6)
    }

    private func messageBubble(_ msg: MessageRecordItem, persona: String) -> some View {
        let isUser = msg.role == "user"
        return VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            HStack {
                if isUser { Spacer() }
                Text(isUser ? "You" : persona)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.textMutedDark)
                if !isUser { Spacer() }
            }

            HStack {
                if isUser { Spacer(minLength: 36) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(msg.content)
                        .font(.system(size: 12.5))
                        .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if !msg.actions.isEmpty {
                        ForEach(msg.actions) { act in
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(DesignTokens.Colors.accentGreen)
                                Text(act.toolName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(DesignTokens.Colors.textSecondaryDark)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isUser ? DesignTokens.Colors.accentBlue.opacity(0.28) : Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(isUser ? 0.18 : 0.08), lineWidth: 0.8)
                )
                if !isUser { Spacer(minLength: 24) }
            }
        }
    }

    private func sendFollowUp() {
        let q = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        followUpText = ""
        appState.submitTypedPrompt(q)
    }

    private func sessionIconName(for session: ConversationSessionRecord) -> String {
        let lower = session.title.lowercased()
        if lower.contains("weather") || lower.contains("search") || lower.contains("screen") {
            return "globe"
        }
        if lower.contains("mail") || lower.contains("email") {
            return "envelope.fill"
        }
        if lower.contains("note") {
            return "note.text"
        }
        if lower.contains("terminal") || lower.contains("code") || lower.contains("git") {
            return "terminal.fill"
        }
        if lower.contains("music") || lower.contains("spotify") || lower.contains("youtube") {
            return "play.fill"
        }
        return "globe"
    }

    private func relativeTime(_ date: Date) -> String {
        let tf = DateFormatter()
        tf.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MMM d"
        return tf.string(from: date)
    }
}
