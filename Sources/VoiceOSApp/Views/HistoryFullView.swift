import SwiftUI
import VoiceOSCore
import AppKit

public struct HistoryFullView: View {
    @ObservedObject var appState: AppState
    @State private var viewMode: HistoryViewMode = .conversations
    @State private var searchQuery: String = ""
    @State private var selectedConversation: ConversationSessionRecord? = nil
    @State private var showingClearConfirmation: Bool = false
    @State private var copiedId: String? = nil
    @State private var isEditingTitle: Bool = false
    @State private var editedTitle: String = ""
    
    public enum HistoryViewMode: String, CaseIterable, Identifiable {
        case conversations = "Conversations"
        case sessions = "Voice Events"
        
        public var id: String { rawValue }
    }
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private var conversationsList: [ConversationSessionRecord] {
        let currentAccountId = AccountAuthService.shared.currentAccount?.id ?? "local"
        EncryptedChatHistoryManager.shared.loadForAccount(accountId: currentAccountId)
        return EncryptedChatHistoryManager.shared.listConversations(query: searchQuery)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Row
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat History")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(DesignTokens.Monochrome.textPrimary)
                    
                    Text(AccountAuthService.shared.isAuthenticated ?
                         "Encrypted & scoped to \(AccountAuthService.shared.currentAccount?.email ?? "active account")" :
                         "Offline local history (Sign in to isolate and sync)")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)
                }
                
                Spacer()
                
                // Segmented Toggle between Conversations and Voice Events
                HStack(spacing: 2) {
                    ForEach(HistoryViewMode.allCases) { mode in
                        Button(action: { viewMode = mode }) {
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: viewMode == mode ? .semibold : .regular))
                                .foregroundColor(viewMode == mode ? DesignTokens.Monochrome.buttonPrimaryText : DesignTokens.Monochrome.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(viewMode == mode ? DesignTokens.Monochrome.buttonPrimaryBg : Color.clear)
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(DesignTokens.Monochrome.surface)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                
                Button(action: { showingClearConfirmation = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)
                        .padding(6)
                        .background(DesignTokens.Monochrome.surface)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .alert(isPresented: $showingClearConfirmation) {
                    Alert(
                        title: Text("Clear All History"),
                        message: Text("Are you sure you want to delete all conversation transcripts? This action cannot be undone."),
                        primaryButton: .destructive(Text("Clear Everything")) {
                            EncryptedChatHistoryManager.shared.clearAllHistory()
                            appState.clearAllHistory()
                            selectedConversation = nil
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                
                TextField("Search history and commands...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.Monochrome.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(DesignTokens.Monochrome.inputBg)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
            .cornerRadius(6)
            .padding(.horizontal, 24)
            
            Divider().overlay(DesignTokens.Monochrome.border).padding(.horizontal, 24)
            
            // Main Content Area
            if viewMode == .conversations {
                conversationsContentView
            } else {
                legacySessionsView
            }
        }
    }
    
    // MARK: - Conversations View
    
    private var conversationsContentView: some View {
        HStack(spacing: 0) {
            // Left List: Conversations
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 6) {
                    if conversationsList.isEmpty {
                        VStack(spacing: 8) {
                            Spacer().frame(height: 40)
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 28))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                            Text("No conversations yet")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            Text("Spoken or typed commands will be securely recorded here.")
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                    } else {
                        ForEach(conversationsList) { conv in
                            let isSelected = selectedConversation?.id == conv.id
                            Button(action: {
                                selectedConversation = conv
                                editedTitle = conv.title
                            }) {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            if conv.isPinned {
                                                Image(systemName: "pin.fill")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                            }
                                            Text(conv.title)
                                                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(formatDate(conv.updatedAt))
                                                .font(.system(size: 10))
                                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                                        }
                                        
                                        if let lastMsg = conv.messages.last {
                                            Text(lastMsg.content)
                                                .font(.system(size: 11))
                                                .foregroundColor(DesignTokens.Monochrome.textSecondary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                                .padding(10)
                                .background(isSelected ? DesignTokens.Monochrome.surfaceElevated : DesignTokens.Monochrome.surface)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? DesignTokens.Monochrome.textPrimary : DesignTokens.Monochrome.border, lineWidth: isSelected ? 1.5 : 1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(width: 320)
            
            Divider().overlay(DesignTokens.Monochrome.border)
            
            // Right Pane: Detail Transcript
            if let conv = selectedConversation {
                conversationDetailView(conv: conv)
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "text.bubble")
                        .font(.system(size: 32))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)
                    Text("Select a conversation to view the full transcript.")
                        .font(.system(size: 13))
                        .foregroundColor(DesignTokens.Monochrome.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private func conversationDetailView(conv: ConversationSessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Detail Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conv.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignTokens.Monochrome.textPrimary)
                    Text("Persona: \(conv.persona) • \(conv.messages.count) messages")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.Monochrome.textMuted)
                }
                
                Spacer()
                
                Button(action: {
                    EncryptedChatHistoryManager.shared.togglePin(id: conv.id)
                    selectedConversation?.isPinned.toggle()
                }) {
                    Image(systemName: conv.isPinned ? "pin.slash.fill" : "pin")
                        .font(.system(size: 12))
                        .padding(6)
                        .background(DesignTokens.Monochrome.surface)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    if let md = EncryptedChatHistoryManager.shared.exportConversationMarkdown(id: conv.id) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(md, forType: .string)
                        copiedId = conv.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedId = nil }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copiedId == conv.id ? "checkmark" : "square.and.arrow.up")
                        Text(copiedId == conv.id ? "Copied" : "Export")
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DesignTokens.Monochrome.surface)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    EncryptedChatHistoryManager.shared.deleteConversation(id: conv.id)
                    selectedConversation = nil
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(Color.red.opacity(0.8))
                        .padding(6)
                        .background(DesignTokens.Monochrome.surface)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            
            Divider().overlay(DesignTokens.Monochrome.border)
            
            // Messages Scroll
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(conv.messages) { msg in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(msg.role == "user" ? "You" : "Voice.AI (\(conv.persona))")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(msg.role == "user" ? DesignTokens.Monochrome.textPrimary : DesignTokens.Monochrome.textSecondary)
                                Spacer()
                                Text(formatTime(msg.timestamp))
                                    .font(.system(size: 10))
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                            }
                            
                            Text(msg.content)
                                .font(.system(size: 13))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(msg.role == "user" ? DesignTokens.Monochrome.surfaceElevated : DesignTokens.Monochrome.surface)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                                .cornerRadius(6)
                            
                            if !msg.actions.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(msg.actions) { act in
                                        HStack(spacing: 6) {
                                            Image(systemName: "terminal")
                                                .font(.system(size: 10))
                                            Text("\(act.toolName): \(act.resultSummary)")
                                                .font(.system(size: 11, design: .monospaced))
                                        }
                                        .foregroundColor(DesignTokens.Monochrome.textMuted)
                                    }
                                }
                                .padding(.leading, 6)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Legacy Voice Sessions View
    
    private var legacySessionsView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 8) {
                ForEach(appState.recentHistory) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(session.appName)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                Text("• \(session.mode.rawValue)")
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                                Spacer()
                                Text(formatDate(session.timestamp))
                                    .font(.system(size: 10))
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                            }
                            Text("\"\(session.prompt)\"")
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.Monochrome.textSecondary)
                        }
                    }
                    .padding(10)
                    .background(DesignTokens.Monochrome.surface)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 24)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        return f.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}
