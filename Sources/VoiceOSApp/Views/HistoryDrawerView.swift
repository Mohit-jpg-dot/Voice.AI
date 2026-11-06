import SwiftUI
import VoiceOSCore

public struct HistoryDrawerView: View {
    @ObservedObject var appState: AppState
    @State private var searchQuery: String = ""
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    var filteredHistory: [SessionRecord] {
        if searchQuery.isEmpty {
            return appState.recentHistory
        }
        return appState.recentHistory.filter {
            $0.prompt.localizedCaseInsensitiveContains(searchQuery) ||
            $0.response.localizedCaseInsensitiveContains(searchQuery) ||
            $0.appName.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit3) {
            // Header with search & lock icon matching reference
            HStack(spacing: DesignTokens.Spacing.unit2) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DesignTokens.Colors.textMutedDark)
                    .font(.system(size: 13))
                
                TextField("Search", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.fontSubheadline)
                    .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                
                Spacer()
                
                Image(systemName: "lock.fill")
                    .foregroundColor(DesignTokens.Colors.textMutedDark)
                    .font(.system(size: 11))
                
                Button(action: {
                    withAnimation(.spring()) {
                        appState.isHistoryDrawerOpen = false
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.textSecondaryDark)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.unit3)
            .padding(.vertical, DesignTokens.Spacing.unit2)
            .background(DesignTokens.Colors.borderSubtleDark)
            .cornerRadius(DesignTokens.Radius.sm)
            
            // Threads List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: DesignTokens.Spacing.unit1) {
                    ForEach(filteredHistory) { record in
                        Button(action: {
                            appState.currentTranscript = record.prompt
                            appState.currentAgentReply = record.response
                            appState.currentAction = record.action
                            appState.isNotchHUDVisible = true
                        }) {
                            HStack(spacing: DesignTokens.Spacing.unit3) {
                                Image(systemName: record.appIcon)
                                    .font(.system(size: 13))
                                    .foregroundColor(appIconColor(for: record.appName))
                                    .frame(width: 20)
                                
                                Text(record.prompt)
                                    .font(DesignTokens.Typography.fontSubheadline)
                                    .foregroundColor(DesignTokens.Colors.textPrimaryDark)
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                            .padding(.horizontal, DesignTokens.Spacing.unit3)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(DesignTokens.Radius.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.unit4)
        .frame(width: 280)
        .background(
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                DesignTokens.Colors.hudBackground
            }
        )
        .cornerRadius(DesignTokens.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .stroke(DesignTokens.Colors.borderSubtleDark, lineWidth: 1)
        )
    }
    
    private func appIconColor(for app: String) -> Color {
        switch app.lowercased() {
        case "slack": return Color(red: 0.89, green: 0.13, blue: 0.43)
        case "things 3": return DesignTokens.Colors.accentBlue
        case "gmail", "mail": return DesignTokens.Colors.accentRed
        default: return DesignTokens.Colors.accentBlue
        }
    }
}

