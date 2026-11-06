import SwiftUI
import VoiceOSCore

public struct AppBuilderModalView: View {
    @ObservedObject var appState: AppState
    @State private var promptText: String = "build me an integration into Things 3 so that I can add tasks into my inbox on Things 3 using just my voice."
    @State private var isGenerating: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.unit5) {
            // Modal Top Close Button
            HStack {
                Spacer()
                Button(action: {
                    appState.isAppBuilderOpen = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.textMuted)
                }
                .buttonStyle(.plain)
            }
            
            // BETA pill badge
            Text("BETA")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(DesignTokens.Colors.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DesignTokens.Colors.inputBackground)
                .cornerRadius(DesignTokens.Radius.xs)
            
            // Headline & Subtitle
            VStack(spacing: DesignTokens.Spacing.unit2) {
                Text("Tell \(AppBrand.name) what to build")
                    .font(DesignTokens.Typography.fontDisplay)
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                
                Text("Describe it in your own words, or paste an MCP server URL.")
                    .font(DesignTokens.Typography.fontBody)
                    .foregroundColor(DesignTokens.Colors.textSecondary)
            }
            
            // Input Box with prompt and actions
            VStack(spacing: DesignTokens.Spacing.unit3) {
                TextEditor(text: $promptText)
                    .font(DesignTokens.Typography.fontCallout)
                    .lineSpacing(4)
                    .frame(height: 90)
                    .padding(DesignTokens.Spacing.unit2)
                    .background(Color.clear)
                    .foregroundColor(DesignTokens.Colors.textPrimary)
                
                HStack {
                    Button(action: {}) {
                        HStack(spacing: DesignTokens.Spacing.unit1) {
                            Image(systemName: "photo")
                                .font(.system(size: 12))
                            Text("Image")
                                .font(DesignTokens.Typography.fontCaptionBold)
                        }
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                        .padding(.horizontal, DesignTokens.Spacing.unit3)
                        .padding(.vertical, 6)
                        .background(DesignTokens.Colors.inputBackground)
                        .cornerRadius(DesignTokens.Radius.sm)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Button(action: {
                        isGenerating = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            isGenerating = false
                            appState.isAppBuilderOpen = false
                            appState.connectedApps.insert(
                                ConnectedApp(
                                    id: "custom-things-integration",
                                    name: "Things 3 Custom MCP",
                                    description: "Custom inbox task adder built via voice prompt.",
                                    iconName: "hammer.fill",
                                    iconColor: "#007AFF",
                                    isConnected: true
                                ),
                                at: 0
                            )
                        }
                    }) {
                        HStack(spacing: DesignTokens.Spacing.unit1) {
                            if isGenerating {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isGenerating ? "Building..." : "Generate")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.unit4)
                        .padding(.vertical, 8)
                        .background(DesignTokens.Colors.accentBlue)
                        .cornerRadius(DesignTokens.Radius.pill)
                    }
                    .buttonStyle(.plain)
                    .disabled(isGenerating)
                }
            }
            .padding(DesignTokens.Spacing.unit4)
            .background(DesignTokens.Colors.cardBackground)
            .cornerRadius(DesignTokens.Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
            )
            .shadow(
                color: DesignTokens.Shadows.card.color,
                radius: DesignTokens.Shadows.card.radius,
                x: DesignTokens.Shadows.card.x,
                y: DesignTokens.Shadows.card.y
            )
        }
        .padding(DesignTokens.Spacing.unit8)
        .frame(width: 580)
        .background(
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                DesignTokens.Colors.canvasBackground.opacity(0.85)
            }
        )
        .cornerRadius(DesignTokens.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
        )
    }
}

