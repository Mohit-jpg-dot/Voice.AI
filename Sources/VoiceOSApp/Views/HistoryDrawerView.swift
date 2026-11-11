import SwiftUI
import VoiceOSCore

/// ChatGPT-style dynamic scrollable left-edge History Sidebar.
/// Toggled with Command+H or by clicking the left edge handle of the screen.
public struct HistoryDrawerView: View {
    @ObservedObject var appState: AppState
    @State private var searchQuery: String = ""
    @State private var hoveredSessionId: String? = nil

    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredSessions: [VoiceChatSession] {
        let base = appState.chatSessions
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter { session in
            session.title.localizedCaseInsensitiveContains(q) ||
            session.messages.contains { $0.text.localizedCaseInsensitiveContains(q) }
        }
    }

    private var filteredLegacyRecords: [SessionRecord] {
        // Show recentHistory items that don't duplicate existing VoiceChatSession titles
        let existingPrompts = Set(appState.chatSessions.flatMap { s in
            s.messages.filter { $0.role == "user" }.map { $0.text.lowercased() }
        })
        let unique = appState.recentHistory.filter { !existingPrompts.contains($0.prompt.lowercased()) }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return unique }
        return unique.filter {
            $0.prompt.localizedCaseInsensitiveContains(q) ||
            $0.response.localizedCaseInsensitiveContains(q) ||
            $0.appName.localizedCaseInsensitiveContains(q)
        }
    }

    private struct SessionGroup: Identifiable {
        let id: String
        let title: String
        let sessions: [VoiceChatSession]
    }

    private var groupedSessions: [SessionGroup] {
        let sessions = filteredSessions
        let cal = Calendar.current
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"

        var pinned: [VoiceChatSession] = []
        var today: [VoiceChatSession] = []
        var yesterday: [VoiceChatSession] = []
        var week: [VoiceChatSession] = []
        var earlier: [VoiceChatSession] = []

        for s in sessions {
            if s.isPinned {
                pinned.append(s)
            } else if cal.isDateInToday(s.updatedAt) {
                today.append(s)
            } else if cal.isDateInYesterday(s.updatedAt) {
                yesterday.append(s)
            } else if let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()), s.updatedAt >= weekAgo {
                week.append(s)
            } else {
                earlier.append(s)
            }
        }

        var groups: [SessionGroup] = []
        if !pinned.isEmpty {
            groups.append(SessionGroup(id: "pinned", title: "Pinned", sessions: pinned))
        }
        if !today.isEmpty {
            let newest = today.first?.updatedAt ?? Date()
            groups.append(SessionGroup(id: "today", title: "Today, \(timeFmt.string(from: newest))", sessions: today))
        }
        if !yesterday.isEmpty {
            groups.append(SessionGroup(id: "yesterday", title: "Yesterday", sessions: yesterday))
        }
        if !week.isEmpty {
            groups.append(SessionGroup(id: "week", title: "Previous 7 Days", sessions: week))
        }
        if !earlier.isEmpty {
            groups.append(SessionGroup(id: "earlier", title: "Earlier", sessions: earlier))
        }
        return groups
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top bar: Search pill + New Chat + Lock/Pin toggle + Close
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DesignTokens.Colors.textMutedDark)
                        .font(.system(size: 12, weight: .medium))

                    TextField("Search", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(DesignTokens.Colors.textPrimaryDark)

                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Colors.textMutedDark)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .cornerRadius(14)

                Button(action: { appState.startNewChatSession() }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("New Conversation")

                Button(action: {
                    appState.isHistorySidebarPinned.toggle()
                }) {
                    Image(systemName: appState.isHistorySidebarPinned ? "lock.fill" : "lock.open")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(appState.isHistorySidebarPinned ? DesignTokens.Colors.accentBlue : DesignTokens.Colors.textMutedDark)
                        .frame(width: 28, height: 28)
                        .background(appState.isHistorySidebarPinned ? DesignTokens.Colors.accentBlue.opacity(0.18) : Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(appState.isHistorySidebarPinned ? "Unpin sidebar (auto-close on selection)" : "Pin sidebar open")
            }

            // Dynamic Scrollable Session Threads
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if groupedSessions.isEmpty && filteredLegacyRecords.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 22))
                                .foregroundColor(DesignTokens.Colors.textMutedDark)
                            Text(searchQuery.isEmpty ? "No saved sessions yet" : "No matching sessions")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DesignTokens.Colors.textSecondaryDark)
                            Text("Hold Fn or Ctrl to talk, then revisit threads anytime here.")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Colors.textMutedDark)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    } else {
                        ForEach(groupedSessions) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(DesignTokens.Colors.textMutedDark)
                                    .padding(.horizontal, 6)

                                ForEach(group.sessions) { session in
                                    sessionRow(session)
                                }
                            }
                        }

                        if !filteredLegacyRecords.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Recent Activity")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(DesignTokens.Colors.textMutedDark)
                                    .padding(.horizontal, 6)

                                ForEach(filteredLegacyRecords.prefix(30)) { record in
                                    legacyRecordRow(record)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // Footer hints matching ChatGPT/reference drawer aesthetics
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("⌘H  — toggle history sidebar")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textSecondaryDark)
                    Text("Click any thread to reopen & follow up")
                        .font(.system(size: 10))
                        .foregroundColor(DesignTokens.Colors.textMutedDark)
                }

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        appState.isHistoryDrawerOpen = false
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.textSecondaryDark)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Collapse Sidebar (⌘H)")
            }
        }
        .padding(14)
        .frame(width: 280)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.68)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 20, x: 4, y: 0)
    }

    @ViewBuilder
    private func sessionRow(_ session: VoiceChatSession) -> some View {
        let isActive = session.id == appState.activeChatSessionId
        let isHovered = hoveredSessionId == session.id

        Button(action: {
            appState.openChatSession(session)
        }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(iconColor(for: session.iconName).opacity(0.18))
                        .frame(width: 24, height: 24)
                    Image(systemName: session.iconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(iconColor(for: session.iconName))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                        .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                        .lineLimit(1)

                    let turnCount = max(1, session.messages.filter { $0.role == "user" }.count)
                    Text("\(turnCount) turn\(turnCount == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundColor(DesignTokens.Colors.textMutedDark)
                }

                Spacer(minLength: 4)

                if isHovered || session.isPinned {
                    HStack(spacing: 4) {
                        Button(action: { appState.togglePinChatSession(id: session.id) }) {
                            Image(systemName: session.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 10))
                                .foregroundColor(session.isPinned ? DesignTokens.Colors.accentBlue : DesignTokens.Colors.textMutedDark)
                        }
                        .buttonStyle(.plain)

                        if isHovered {
                            Button(action: { appState.deleteChatSession(id: session.id) }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundColor(DesignTokens.Colors.accentRed.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.14) : (isHovered ? Color.white.opacity(0.08) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSessionId = hovering ? session.id : (hoveredSessionId == session.id ? nil : hoveredSessionId)
        }
        .contextMenu {
            Button(session.isPinned ? "Unpin Thread" : "Pin Thread") {
                appState.togglePinChatSession(id: session.id)
            }
            Button("Delete Thread", role: .destructive) {
                appState.deleteChatSession(id: session.id)
            }
        }
    }

    @ViewBuilder
    private func legacyRecordRow(_ record: SessionRecord) -> some View {
        Button(action: {
            appState.openLegacyHistoryRecord(record)
        }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(DesignTokens.Colors.accentBlue.opacity(0.16))
                        .frame(width: 24, height: 24)
                    Image(systemName: record.appIcon)
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Colors.accentBlue)
                }

                Text(record.prompt)
                    .font(.system(size: 12.5))
                    .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }

    private func iconColor(for symbol: String) -> Color {
        switch symbol {
        case "globe": return DesignTokens.Colors.accentBlue
        case "display": return Color.cyan
        case "music.note": return Color.green
        case "envelope.fill": return Color.orange
        case "folder.fill": return Color.yellow
        case "terminal.fill": return Color.purple
        default: return DesignTokens.Colors.accentBlue
        }
    }
}
