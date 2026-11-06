import SwiftUI
import VoiceOSCore

public struct MainWindowView: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        ZStack {
            DesignTokens.Monochrome.windowBg.ignoresSafeArea()
            
            HStack(spacing: 0) {
                // Left Navigation Sidebar (Monochrome Minimalist)
                VStack(alignment: .leading, spacing: 16) {
                    // Minimalist Brand Header
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(DesignTokens.Monochrome.buttonPrimaryBg)
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: "waveform")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(DesignTokens.Monochrome.buttonPrimaryText)
                        }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(AppBrand.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            
                            Text("macOS AI Operating System")
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                    
                    // Nav Items List
                    VStack(spacing: 2) {
                        ForEach(AppState.NavTab.allCases) { tab in
                            let isSelected = appState.activeNavTab == tab
                            Button(action: {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                    appState.activeNavTab = tab
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: tab.iconName)
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                        .foregroundColor(isSelected ? DesignTokens.Monochrome.textPrimary : DesignTokens.Monochrome.textSecondary)
                                        .frame(width: 18)
                                    
                                    Text(tab.rawValue)
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                        .foregroundColor(isSelected ? DesignTokens.Monochrome.textPrimary : DesignTokens.Monochrome.textSecondary)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(isSelected ? DesignTokens.Monochrome.surfaceElevated : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isSelected ? DesignTokens.Monochrome.borderStrong : Color.clear, lineWidth: 1)
                                )
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    
                    Spacer()
                    
                    // User Profile / Settings Footer
                    Button(action: {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            appState.activeNavTab = .settings
                        }
                    }) {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(DesignTokens.Monochrome.surfaceElevated)
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                                Text(String((AccountAuthService.shared.currentAccount?.displayName ?? appState.userName).prefix(1)).uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                            }
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(AccountAuthService.shared.currentAccount?.displayName ?? appState.userName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(DesignTokens.Monochrome.textPrimary)
                                    .lineLimit(1)
                                
                                Text(AccountAuthService.shared.currentAccount?.email ?? appState.userEmail)
                                    .font(.system(size: 10))
                                    .foregroundColor(DesignTokens.Monochrome.textMuted)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundColor(DesignTokens.Monochrome.textMuted)
                        }
                        .padding(8)
                        .background(DesignTokens.Monochrome.surface)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DesignTokens.Monochrome.border, lineWidth: 1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                }
                .frame(width: 210)
                .background(DesignTokens.Monochrome.surface)
                
                Divider()
                    .overlay(DesignTokens.Monochrome.border)
                
                // Main Content View based on activeNavTab
                Group {
                    switch appState.activeNavTab {
                    case .dashboard:
                        DashboardView(appState: appState)
                    case .insights:
                        InsightsView(appState: appState)
                    case .history:
                        HistoryFullView(appState: appState)
                    case .dictation:
                        DictationStudioView(appState: appState)
                    case .agent:
                        AgentHubView(appState: appState)
                    case .apps:
                        AppsView(appState: appState)
                    case .settings:
                        SettingsView(appState: appState)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignTokens.Monochrome.windowBg)
            }
            
            // App Builder Modal Overlay
            if appState.isAppBuilderOpen {
                Color.black.opacity(0.6)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        appState.isAppBuilderOpen = false
                    }
                
                AppBuilderModalView(appState: appState)
                    .transition(.scale(scale: 0.98).combined(with: .opacity))
            }
        }
        .frame(minWidth: 940, minHeight: 650)
    }
}
