import SwiftUI
import VoiceOSCore
import AppKit

public struct AppIntegrationItem: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let iconSystemName: String
    public let isCustomIcon: Bool
    public let customLetter: String?
    public let gradientColors: [Color]
    public let iconColor: Color
    public let isDashedBorder: Bool
    public let appBundleOrName: String
    
    public init(
        id: String,
        name: String,
        iconSystemName: String,
        isCustomIcon: Bool = false,
        customLetter: String? = nil,
        gradientColors: [Color],
        iconColor: Color = .white,
        isDashedBorder: Bool = false,
        appBundleOrName: String
    ) {
        self.id = id
        self.name = name
        self.iconSystemName = iconSystemName
        self.isCustomIcon = isCustomIcon
        self.customLetter = customLetter
        self.gradientColors = gradientColors
        self.iconColor = iconColor
        self.isDashedBorder = isDashedBorder
        self.appBundleOrName = appBundleOrName
    }
}

public struct AppIntegrationsGridView: View {
    @ObservedObject var appState: AppState
    @State private var hoveredAppId: String? = nil
    @State private var feedbackText: String? = nil
    @State private var selectedDescriptor: IntegrationSetupDescriptor? = nil
    
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    // Exactly matches the 22 apps displayed in reference screenshot Image 2
    private var allApps: [AppIntegrationItem] {
        let currentDay = Calendar.current.component(.day, from: Date())
        return [
            // Row 1
            AppIntegrationItem(
                id: "imessage",
                name: "iMessage",
                iconSystemName: "message.fill",
                gradientColors: [Color(red: 0.22, green: 0.82, blue: 0.38), Color(red: 0.12, green: 0.70, blue: 0.28)],
                appBundleOrName: "Messages"
            ),
            AppIntegrationItem(
                id: "mail",
                name: "Apple Mail",
                iconSystemName: "envelope.fill",
                gradientColors: [Color(red: 0.12, green: 0.62, blue: 0.98), Color(red: 0.05, green: 0.46, blue: 0.90)],
                appBundleOrName: "Mail"
            ),
            AppIntegrationItem(
                id: "reminders",
                name: "Reminders",
                iconSystemName: "list.bullet.circle.fill",
                gradientColors: [Color(white: 0.95), Color(white: 0.88)],
                iconColor: Color(red: 0.20, green: 0.55, blue: 0.95),
                appBundleOrName: "Reminders"
            ),
            AppIntegrationItem(
                id: "finder",
                name: "Finder",
                iconSystemName: "macwindow",
                gradientColors: [Color(red: 0.18, green: 0.68, blue: 0.95), Color(red: 0.08, green: 0.42, blue: 0.92)],
                appBundleOrName: "Finder"
            ),
            AppIntegrationItem(
                id: "notes",
                name: "Notes",
                iconSystemName: "note.text",
                gradientColors: [Color(red: 0.98, green: 0.82, blue: 0.25), Color(red: 0.92, green: 0.72, blue: 0.16)],
                iconColor: Color(white: 0.2),
                appBundleOrName: "Notes"
            ),
            AppIntegrationItem(
                id: "spotify",
                name: "Spotify",
                iconSystemName: "wave.3.forward",
                gradientColors: [Color(red: 0.11, green: 0.73, blue: 0.33), Color(red: 0.08, green: 0.60, blue: 0.26)],
                appBundleOrName: "Spotify"
            ),
            
            // Row 2
            AppIntegrationItem(
                id: "music",
                name: "Apple Music",
                iconSystemName: "music.note",
                gradientColors: [Color(red: 0.98, green: 0.20, blue: 0.42), Color(red: 0.88, green: 0.10, blue: 0.32)],
                appBundleOrName: "Music"
            ),
            AppIntegrationItem(
                id: "slack",
                name: "Slack",
                iconSystemName: "number",
                gradientColors: [Color(red: 0.30, green: 0.10, blue: 0.35), Color(red: 0.22, green: 0.06, blue: 0.26)],
                iconColor: Color(red: 0.90, green: 0.75, blue: 0.20),
                appBundleOrName: "Slack"
            ),
            AppIntegrationItem(
                id: "gmail",
                name: "Gmail",
                iconSystemName: "envelope.badge",
                gradientColors: [Color(white: 0.95), Color(white: 0.88)],
                iconColor: Color(red: 0.90, green: 0.25, blue: 0.20),
                appBundleOrName: "Google Chrome"
            ),
            AppIntegrationItem(
                id: "google_cal",
                name: "Google Calendar",
                iconSystemName: "calendar.badge.clock",
                gradientColors: [Color(red: 0.20, green: 0.50, blue: 0.95), Color(red: 0.12, green: 0.40, blue: 0.85)],
                appBundleOrName: "Google Calendar"
            ),
            AppIntegrationItem(
                id: "apple_cal",
                name: "Apple Calendar",
                iconSystemName: "calendar",
                isCustomIcon: true,
                customLetter: "\(currentDay)",
                gradientColors: [Color(white: 0.96), Color(white: 0.88)],
                iconColor: Color(red: 0.92, green: 0.20, blue: 0.20),
                appBundleOrName: "Calendar"
            ),
            AppIntegrationItem(
                id: "google_maps",
                name: "Google Maps",
                iconSystemName: "map.fill",
                gradientColors: [Color(white: 0.95), Color(white: 0.88)],
                iconColor: Color(red: 0.22, green: 0.75, blue: 0.40),
                appBundleOrName: "Google Chrome"
            ),
            
            // Row 3
            AppIntegrationItem(
                id: "outlook",
                name: "Outlook",
                iconSystemName: "envelope.circle.fill",
                gradientColors: [Color(red: 0.05, green: 0.45, blue: 0.85), Color(red: 0.00, green: 0.32, blue: 0.72)],
                appBundleOrName: "Microsoft Outlook"
            ),
            AppIntegrationItem(
                id: "google_drive",
                name: "Google Drive",
                iconSystemName: "arrow.triangle.2.circlepath",
                gradientColors: [Color(white: 0.95), Color(white: 0.88)],
                iconColor: Color(red: 0.95, green: 0.75, blue: 0.15),
                appBundleOrName: "Google Drive"
            ),
            AppIntegrationItem(
                id: "linear",
                name: "Linear",
                iconSystemName: "circle.circle",
                gradientColors: [Color(red: 0.36, green: 0.38, blue: 0.92), Color(red: 0.25, green: 0.26, blue: 0.75)],
                appBundleOrName: "Linear"
            ),
            AppIntegrationItem(
                id: "jira",
                name: "Jira",
                iconSystemName: "square.3.layers.3d",
                gradientColors: [Color(red: 0.00, green: 0.32, blue: 0.80), Color(red: 0.00, green: 0.22, blue: 0.65)],
                appBundleOrName: "Jira"
            ),
            AppIntegrationItem(
                id: "codex",
                name: "Codex",
                iconSystemName: "chevron.left.forwardslash.chevron.right",
                gradientColors: [Color(red: 0.12, green: 0.16, blue: 0.28), Color(red: 0.08, green: 0.10, blue: 0.20)],
                iconColor: Color(red: 0.40, green: 0.75, blue: 1.0),
                appBundleOrName: "Visual Studio Code"
            ),
            AppIntegrationItem(
                id: "notion",
                name: "Notion",
                iconSystemName: "doc.text.fill",
                isCustomIcon: true,
                customLetter: "N",
                gradientColors: [Color(white: 0.96), Color(white: 0.90)],
                iconColor: Color.black,
                appBundleOrName: "Notion"
            ),
            
            // Row 4
            AppIntegrationItem(
                id: "whatsapp",
                name: "WhatsApp",
                iconSystemName: "message.fill",
                gradientColors: [Color(red: 0.14, green: 0.82, blue: 0.40), Color(red: 0.08, green: 0.65, blue: 0.30)],
                appBundleOrName: "WhatsApp"
            ),
            AppIntegrationItem(
                id: "discord",
                name: "Discord",
                iconSystemName: "bubble.left.and.bubble.right.fill",
                gradientColors: [Color(red: 0.34, green: 0.40, blue: 0.95), Color(red: 0.25, green: 0.28, blue: 0.78)],
                appBundleOrName: "Discord"
            ),
            AppIntegrationItem(
                id: "youtube",
                name: "YouTube",
                iconSystemName: "play.rectangle.fill",
                gradientColors: [Color(red: 0.95, green: 0.12, blue: 0.12), Color(red: 0.75, green: 0.05, blue: 0.08)],
                appBundleOrName: "YouTube"
            ),
            AppIntegrationItem(
                id: "terminal",
                name: "Terminal",
                iconSystemName: "terminal.fill",
                gradientColors: [Color(white: 0.16), Color(white: 0.08)],
                iconColor: .white,
                appBundleOrName: "Terminal"
            ),
            AppIntegrationItem(
                id: "obsidian",
                name: "Obsidian",
                iconSystemName: "suit.diamond.fill",
                gradientColors: [Color(red: 0.45, green: 0.22, blue: 0.78), Color(red: 0.32, green: 0.12, blue: 0.60)],
                iconColor: Color(red: 0.80, green: 0.60, blue: 1.0),
                appBundleOrName: "Obsidian"
            ),
            AppIntegrationItem(
                id: "your_own",
                name: "Your own",
                iconSystemName: "plus",
                gradientColors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                iconColor: Color.white.opacity(0.70),
                isDashedBorder: true,
                appBundleOrName: "custom_builder"
            )
        ]
    }
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Safari icon + Title sentence from screenshot Image 2
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.08, green: 0.50, blue: 0.95))
                        .frame(width: 18, height: 18)
                    Image(systemName: "safari.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("And connect to these apps, including your own integrations.")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.90))
                
                Spacer()
                
                if let feedback = feedbackText {
                    Text(feedback)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.55))
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            
            // Scrollable 6-Column Grid of Apps
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(allApps) { app in
                        Button(action: {
                            triggerAppLaunch(app)
                        }) {
                            VStack(spacing: 5) {
                                // Real macOS App Icon or Authentic Brand Artwork
                                AppTileIconView(appKey: app.id, appName: app.appBundleOrName, size: 38)
                                    .scaleEffect(hoveredAppId == app.id ? 1.08 : 1.0)
                                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hoveredAppId)
                                
                                // App Name
                                Text(app.name)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundColor(Color.white.opacity(hoveredAppId == app.id ? 1.0 : 0.72))
                                    .lineLimit(1)
                                    .frame(maxWidth: 82)
                            }
                        }
                        .buttonStyle(.plain)
                        .onHover { isHovered in
                            if isHovered {
                                hoveredAppId = app.id
                            } else if hoveredAppId == app.id {
                                hoveredAppId = nil
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $selectedDescriptor) { desc in
            IntegrationSetupView(
                appState: appState,
                descriptor: desc,
                onDismiss: { selectedDescriptor = nil }
            )
        }
    }
    
    private func triggerAppLaunch(_ app: AppIntegrationItem) {
        BoringSoundEngine.shared.playTap()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        
        if app.id == "your_own" {
            appState.toggleMainWindow()
            return
        }
        
        // Open in-app guided setup directly when clicked
        if let descriptor = IntegrationRegistry.shared.descriptor(for: app.id) {
            selectedDescriptor = descriptor
            return
        }

        withAnimation {
            feedbackText = "Opening \(app.name)..."
        }
        
        Task {
            if app.id == "youtube" {
                _ = await AgentActionDispatcher.shared.dispatch(transcript: "open YouTube on Safari")
            } else {
                _ = await AgentActionDispatcher.shared.dispatch(transcript: "open \(app.appBundleOrName)")
            }
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation {
                        feedbackText = nil
                    }
                }
            }
        }
    }
}

