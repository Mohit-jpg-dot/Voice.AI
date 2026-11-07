import SwiftUI
import VoiceOSCore
import AppKit

public struct NotchGlassIslandView: View {
    @ObservedObject var appState: AppState
    @Namespace private var tabNamespace
    
    @State private var typedInput: String = ""
    @FocusState private var isFieldFocused: Bool
    @State private var isHovering: Bool = false
    @State private var hoverTask: Task<Void, Never>? = nil
    @State private var dragOffset: CGFloat = 0.0
    @State private var expandedMessage: ChatMessage? = nil
    @State private var isCompactMode: Bool = true
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private var isOpen: Bool {
        if appState.isMediaExpanded { return true }
        switch appState.islandState {
        case .resting, .voiceCompact:
            return false
        default:
            return true
        }
    }
    
    private var physicalNotchWidth: CGFloat {
        let screen = NotchHUDWindowController.targetNotchScreen()
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return screen.frame.width - left.width - right.width + 4.0
        }
        return 185.0
    }
    
    private var physicalNotchHeight: CGFloat {
        let screen = NotchHUDWindowController.targetNotchScreen()
        return screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 32.0
    }
    
    // MARK: - Dynamic Response-Adaptive Sizing Engine
    // Automatically calculates opening width and height based on current response length or view mode
    private var dynamicDimensions: (width: CGFloat, height: CGFloat) {
        if appState.isMediaExpanded {
            return (460.0, 185.0)
        }
        if !isOpen {
            if case .voiceCompact = appState.islandState {
                let count = appState.currentTranscript.count
                let width: CGFloat = count > 60 ? 560.0 : 480.0
                let height: CGFloat = count > 60 ? 125.0 : 96.0
                return (width, height)
            }
            if let media = appState.currentMedia, media.isPlaying {
                return (physicalNotchWidth + 100.0, physicalNotchHeight + 6.0)
            }
            return (physicalNotchWidth, physicalNotchHeight)
        }
        
        // Compact Pill Mode (matches reference Image 1 & 10)
        if isCompactMode || appState.isCompactResponseMode {
            return calculateAdaptiveNotchSize(for: compactDisplayText)
        }
        
        let mediaOffset: CGFloat = (appState.currentMedia != nil) ? 38.0 : 0.0
        
        // Full Opened States based on Tab & Response Length
        switch appState.activeNotchTab {
        case .apps:
            // App integrations grid matching Image 2
            return (580.0, 325.0 + mediaOffset)
            
        case .tasks:
            return (620.0, 310.0 + mediaOffset)
            
        case .memory:
            return (550.0, 200.0 + mediaOffset)
            
        case .ask:
            // Action confirmation card
            if appState.currentAction != nil {
                return (510.0, 135.0 + mediaOffset)
            }
            
            // Adaptive height based on active response length
            let reply = appState.currentAgentReply
            if !reply.isEmpty {
                let count = reply.count
                let width: CGFloat = max(520.0, min(630.0, CGFloat(count) * 1.5 + 420.0))
                let height: CGFloat
                if count <= 65 {
                    height = 110.0
                } else if count <= 160 {
                    height = 165.0
                } else if count <= 300 {
                    height = 235.0
                } else if count <= 550 {
                    height = 320.0
                } else {
                    height = 440.0
                }
                return (width, height + mediaOffset)
            }
            
            // Standard interactive Ask input
            if appState.chatMessages.isEmpty {
                return (510.0, 115.0 + mediaOffset)
            } else {
                return (560.0, 185.0 + mediaOffset)
            }
        }
    }
    
    // Adaptive auto-extending & auto-shrinking notch sizing based on answer length
    private func calculateAdaptiveNotchSize(for text: String) -> (width: CGFloat, height: CGFloat) {
        let count = text.count
        let width: CGFloat = max(540.0, min(680.0, CGFloat(count) * 1.2 + 440.0))
        
        let hasLink = (activeSourceURL != nil) || text.contains("http")
        let linkExtra: CGFloat = hasLink ? 38.0 : 0.0
        
        let height: CGFloat
        if count <= 45 {
            height = 118.0 + linkExtra
        } else if count <= 90 {
            height = 155.0 + linkExtra
        } else if count <= 160 {
            height = 205.0 + linkExtra
        } else if count <= 260 {
            height = 255.0 + linkExtra
        } else if count <= 400 {
            height = 320.0 + linkExtra
        } else if count <= 600 {
            height = 390.0 + linkExtra
        } else if count <= 850 {
            height = 450.0 + linkExtra
        } else {
            height = 480.0
        }
        return (width, height)
    }
    
    private var currentWidth: CGFloat {
        dynamicDimensions.width
    }
    
    private var currentHeight: CGFloat {
        dynamicDimensions.height
    }
    
    private var currentTopRadius: CGFloat {
        if case .voiceCompact = appState.islandState {
            return NotchAnimations.cornerRadiusOpenTop
        }
        return isOpen ? NotchAnimations.cornerRadiusOpenTop : NotchAnimations.cornerRadiusClosedTop
    }
    
    private var currentBottomRadius: CGFloat {
        if case .voiceCompact = appState.islandState {
            return NotchAnimations.cornerRadiusOpenBottom
        }
        return isOpen ? NotchAnimations.cornerRadiusOpenBottom : NotchAnimations.cornerRadiusClosedBottom
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            // Main Animated Notch Body (Liquid Translucent Black Glass)
            VStack(spacing: 0) {
                if appState.isMediaExpanded, let media = appState.currentMedia {
                    aestheticMediaPanel(media: media)
                } else if isOpen {
                    if isCompactMode || appState.isCompactResponseMode {
                        compactResponsePillView
                    } else {
                        openNotchContent
                    }
                } else if case .voiceCompact = appState.islandState {
                    liveActivityWings
                } else if let media = appState.currentMedia, media.isPlaying {
                    restingMediaWings(media: media)
                } else {
                    restingHardwareNotchPill
                }
            }
            .frame(width: currentWidth, height: currentHeight, alignment: .top)
            .background(
                Group {
                    if isOpen || appState.isCurrentlyListening {
                        // Black and transparent liquid dark glass aesthetic (matches reference images)
                        ZStack {
                            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                            Color.black.opacity(0.97)
                        }
                    } else if let media = appState.currentMedia, media.isPlaying {
                        Color.black.opacity(0.95)
                    } else {
                        // Closed: PURE BLACK hardware notch camouflage
                        Color.black
                    }
                }
            )
            .clipShape(
                NotchShape(
                    topCornerRadius: currentTopRadius,
                    bottomCornerRadius: currentBottomRadius
                )
            )
            .overlay(alignment: .top) {
                if isOpen || appState.isCurrentlyListening || appState.islandState == .resting {
                    // Top 1px seam overlay in black to eliminate any subpixel gap with screen bezel
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 1)
                        .padding(.horizontal, currentTopRadius)
                }
            }
            .overlay(
                Group {
                    if isOpen || appState.isCurrentlyListening {
                        NotchShape(
                            topCornerRadius: currentTopRadius,
                            bottomCornerRadius: currentBottomRadius
                        )
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                    }
                }
            )
            .shadow(
                color: (isOpen || appState.isCurrentlyListening || isHovering) ? Color.black.opacity(0.65) : Color.clear,
                radius: (isOpen || appState.isCurrentlyListening) ? 8 : 4,
                x: 0,
                y: (isOpen || appState.isCurrentlyListening) ? 4 : 2
            )
            .animation(isOpen ? NotchAnimations.openSpring : NotchAnimations.closeSpring, value: appState.islandState)
            .animation(isOpen ? NotchAnimations.openSpring : NotchAnimations.closeSpring, value: currentWidth)
            .animation(isOpen ? NotchAnimations.openSpring : NotchAnimations.closeSpring, value: currentHeight)
            .contentShape(Rectangle())
            .onHover { hovering in
                handleHover(hovering)
            }
        }
        .frame(
            width: NotchHUDWindowController.panelWindowWidth,
            height: NotchHUDWindowController.panelWindowHeight,
            alignment: .top
        )
        .preferredColorScheme(.dark)
        .gesture(
            DragGesture(minimumDistance: NotchAnimations.scrollActivationDistance)
                .onChanged { value in
                    dragOffset = value.translation.height
                    if value.translation.height > 12 && !isOpen {
                        withAnimation(NotchAnimations.openSpring) {
                            appState.setHoverExpanded(true)
                        }
                    } else if value.translation.height < -12 && isOpen && !appState.isPinned {
                        withAnimation(NotchAnimations.closeSpring) {
                            appState.setHoverExpanded(false)
                        }
                    }
                }
                .onEnded { _ in
                    dragOffset = 0
                }
        )
        .onExitCommand {
            appState.stopVoice()
            withAnimation(NotchAnimations.closeSpring) {
                appState.islandState = .resting
                appState.isMediaExpanded = false
                appState.isPinned = false
            }
        }
        .onAppear {
            appState.dynamicNotchSize = CGSize(width: currentWidth, height: currentHeight)
        }
        .onChange(of: currentWidth) { _, newWidth in
            appState.dynamicNotchSize = CGSize(width: newWidth, height: currentHeight)
        }
        .onChange(of: currentHeight) { _, newHeight in
            appState.dynamicNotchSize = CGSize(width: currentWidth, height: newHeight)
        }
    }
    
    // MARK: - Hover Management (boring.notch feel)
    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()
        
        if hovering {
            isHovering = true
            guard !isOpen, !appState.isPinned else { return }
            
            // Dwell Delay (200ms) strictly on hardware notch touch prevents swift cursor sweep opens
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.isHovering, !self.isOpen, !self.appState.isPinned else { return }
                    withAnimation(NotchAnimations.openSpring) {
                        if let media = self.appState.currentMedia, media.isPlaying {
                            self.appState.isMediaExpanded = true
                        } else {
                            self.appState.setHoverExpanded(true)
                        }
                    }
                }
            }
        } else {
            // Hover Out: 150ms grace period like boring.notch, then auto-close smoothly!
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    self.isHovering = false
                    
                    // Do not auto-close if pinned or user is actively typing in the Ask input box
                    guard !self.appState.isPinned, !self.appState.isTypingFocused else { return }
                    
                    // If in voice compact (listening), cancel recording and return to resting
                    if case .voiceCompact = self.appState.islandState {
                        self.appState.stopVoice()
                    }
                    
                    if self.isOpen || self.appState.islandState != .resting || self.appState.isMediaExpanded {
                        withAnimation(NotchAnimations.closeSpring) {
                            self.appState.setHoverExpanded(false)
                            self.appState.isMediaExpanded = false
                            self.appState.islandState = .resting
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Resting Hardware Notch Pill
    private var restingHardwareNotchPill: some View {
        Button(action: {
            withAnimation(NotchAnimations.openSpring) {
                appState.setHoverExpanded(true)
            }
        }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 4, height: 4)
                
                Text(AppBrand.name)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Live Voice Activity Listening Notch View
    private var liveActivityWings: some View {
        VStack(spacing: 5) {
            // Top Status Bar: Mode, Recording indicator, Frequency Visualizer, Stop button
            HStack(alignment: .center, spacing: 8) {
                // Left: Glowing Pulsing Red Dot + Mode Tag
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .scaleEffect(isVoiceActive ? 1.25 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(), value: isVoiceActive)
                    
                    Image(systemName: "mic.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(listeningModeTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.90))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
                
                Spacer()
                
                // Right: Jumping Frequency Waveform
                HStack(spacing: 2.5) {
                    ForEach(0..<min(8, appState.audioLevels.count), id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.2, green: 0.85, blue: 0.5), Color.cyan],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 2.5, height: max(6, appState.audioLevels[idx] * 20))
                            .animation(.easeOut(duration: 0.08), value: appState.audioLevels[idx])
                    }
                }
                .padding(.trailing, 4)
                
                // Stop Button
                Button(action: {
                    BoringSoundEngine.shared.playTap()
                    appState.stopVoice()
                    withAnimation(NotchAnimations.closeSpring) {
                        appState.islandState = .resting
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 20, height: 20)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white)
                            .frame(width: 6, height: 6)
                    }
                }
                .buttonStyle(.plain)
                .help("Cancel / Stop Listening")
            }
            .padding(.horizontal, 14)
            .padding(.top, physicalNotchHeight > 30 ? (physicalNotchHeight - 16) : 8)
            
            // Bottom Content: Live Speech Transcript (PROMINENT, CRISP, VISIBLE)
            HStack {
                if appState.currentTranscript.isEmpty {
                    Text("Listening... Speak your command or dictation")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.55))
                        .italic()
                } else {
                    Text(appState.currentTranscript)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: currentWidth, height: currentHeight, alignment: .top)
    }
    
    private var listeningModeTitle: String {
        if case .voiceCompact(let mode) = appState.islandState {
            return mode == .dictation ? "💬 Conversation (Fn)" : "⚡ Computer Control (⌘)"
        }
        return "Listening"
    }
    
    // MARK: - Resting Media Wings (BoringNotch style: Left & Right of physical camera notch)
    private func restingMediaWings(media: NowPlayingItem) -> some View {
        Button(action: {
            withAnimation(NotchAnimations.openSpring) {
                appState.isMediaExpanded = true
            }
        }) {
            HStack(spacing: 0) {
                // Left Wing: Source Icon (placed safely to the left of the MacBook camera notch)
                HStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(media.source == .spotify ? Color(red: 0.11, green: 0.73, blue: 0.33) : (media.source == .youtube ? Color.red : Color(red: 0.98, green: 0.14, blue: 0.24)))
                            .frame(width: 17, height: 17)
                            .shadow(color: (media.source == .spotify ? Color.green : Color.red).opacity(0.4), radius: 3)
                        Image(systemName: media.source.iconName)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 45, alignment: .center)
                
                // Center Spacer: Exact width of the physical MacBook Notch
                // Ensures ZERO text or controls are placed behind the plastic camera!
                Spacer(minLength: 0)
                    .frame(width: physicalNotchWidth)
                
                // Right Wing: EQ Bars + Play/Pause Button (placed safely to the right of the notch)
                HStack(spacing: 5) {
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { idx in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(media.source == .spotify ? Color(red: 0.11, green: 0.85, blue: 0.4) : Color.red)
                                .frame(width: 2, height: CGFloat(media.isPlaying ? [7, 13, 5, 11][idx] : 3))
                        }
                    }
                    
                    Button(action: {
                        BoringSoundEngine.shared.playTap()
                        NowPlayingMediaManager.shared.togglePlayPause()
                    }) {
                        Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 16, height: 16)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 50, alignment: .center)
            }
            .frame(width: currentWidth, height: currentHeight)
            .background(Color.black)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help("Click to expand media player")
    }
    
    // MARK: - Aesthetic Dark Glass Media Control Panel (YouTube & Spotify)
    private func aestheticMediaPanel(media: NowPlayingItem) -> some View {
        VStack(spacing: 8) {
            // Top notch avoidance padding: ensure all controls and text begin safely below the MacBook camera notch!
            Spacer()
                .frame(height: physicalNotchHeight > 30 ? (physicalNotchHeight - 8) : 6)
            
            // Header Bar: Source Badge + EQ + Close
            HStack(alignment: .center) {
                // Source Pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(media.source == .spotify ? Color(red: 0.11, green: 0.73, blue: 0.33) : (media.source == .youtube ? Color.red : Color.pink))
                        .frame(width: 7, height: 7)
                    Text(media.source.rawValue.uppercased())
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
                
                Spacer()
                
                // Live EQ Visualizer
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(media.source == .spotify ? Color(red: 0.11, green: 0.85, blue: 0.4) : Color.red)
                            .frame(width: 2, height: CGFloat(media.isPlaying ? [8, 14, 5, 12, 7][idx] : 3))
                    }
                }
                .padding(.trailing, 8)
                
                // Collapse / Close Button
                Button(action: {
                    withAnimation(NotchAnimations.closeSpring) {
                        appState.isMediaExpanded = false
                    }
                }) {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            
            // Middle Row: Album Artwork + Title & Scrubber
            HStack(spacing: 12) {
                // Album Art / Video Thumbnail Container
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [
                                    media.source == .spotify ? Color(red: 0.1, green: 0.3, blue: 0.15) : Color(red: 0.35, green: 0.08, blue: 0.08),
                                    Color.black
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                    
                    Image(systemName: media.source == .spotify ? "music.note" : "play.rectangle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(media.source == .spotify ? Color(red: 0.11, green: 0.85, blue: 0.4) : Color.red)
                }
                
                // Track Info & Progress Bar
                VStack(alignment: .leading, spacing: 3) {
                    Text(media.title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(media.artistOrChannel.isEmpty ? media.source.rawValue : media.artistOrChannel)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.6))
                        .lineLimit(1)
                    
                    // Scrubber Bar
                    VStack(spacing: 2) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 3)
                                Capsule()
                                    .fill(media.source == .spotify ? Color(red: 0.11, green: 0.85, blue: 0.4) : Color.white)
                                    .frame(width: max(4.0, geo.size.width * CGFloat(media.progress)), height: 3)
                            }
                        }
                        .frame(height: 3)
                        
                        HStack {
                            Text(String(format: "%d:%02d", media.positionSeconds / 60, media.positionSeconds % 60))
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.5))
                            Spacer()
                            if media.durationSeconds > 0 {
                                Text(String(format: "%d:%02d", media.durationSeconds / 60, media.durationSeconds % 60))
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundColor(Color.white.opacity(0.5))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            
            // Bottom Controls Bar: Previous | Play/Pause | Next
            HStack(spacing: 28) {
                Spacer()
                
                // Previous Button
                Button(action: {
                    BoringSoundEngine.shared.playTap()
                    NowPlayingMediaManager.shared.previousTrack()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Previous Track (Shift+P)")
                
                // Play / Pause Button (Prominent Center)
                Button(action: {
                    BoringSoundEngine.shared.playTap()
                    NowPlayingMediaManager.shared.togglePlayPause()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 36, height: 36)
                            .shadow(color: Color.white.opacity(0.25), radius: 5)
                        Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .buttonStyle(.plain)
                .help(media.isPlaying ? "Pause" : "Play")
                
                // Next Button
                Button(action: {
                    BoringSoundEngine.shared.playTap()
                    NowPlayingMediaManager.shared.nextTrack()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Next Track (Shift+N)")
                
                Spacer()
            }
            .padding(.bottom, 12)
        }
        .frame(width: 460, height: 185)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.96)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: Color.black.opacity(0.7), radius: 16, x: 0, y: 8)
    }
    
    // MARK: - Now Playing Mini Player Bar (Interactive Playback Controls)
    @ViewBuilder
    private func nowPlayingBar(media: NowPlayingItem) -> some View {
        HStack(spacing: 8) {
            // Source icon (Spotify green or YouTube red)
            ZStack {
                Circle()
                    .fill(media.source == .spotify ? Color(red: 0.11, green: 0.73, blue: 0.33) : (media.source == .youtube ? Color.red : Color(red: 0.98, green: 0.14, blue: 0.24)))
                    .frame(width: 18, height: 18)
                Image(systemName: media.source.iconName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Title & Artist
            VStack(alignment: .leading, spacing: 1) {
                Text(media.title)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(media.artistOrChannel.isEmpty ? media.source.rawValue : media.artistOrChannel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))
                        .lineLimit(1)
                    
                    if media.durationSeconds > 0 {
                        Text("• " + media.formattedPlaybackTime)
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.45))
                    }
                }
            }
            
            Spacer(minLength: 8)
            
            // Audio visualizer bars
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(media.source == .spotify ? Color(red: 0.11, green: 0.85, blue: 0.4) : Color.cyan)
                        .frame(width: 2, height: CGFloat(media.isPlaying ? [8, 14, 6, 12][idx] : 4))
                }
            }
            .padding(.trailing, 4)
            
            // Playback Controls
            HStack(spacing: 6) {
                Button(action: {
                    BoringSoundEngine.shared.playTap()
                    NowPlayingMediaManager.shared.previousTrack()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.85))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Previous Track")
                
                Button(action: {
                    BoringSoundEngine.shared.playTap()
                    NowPlayingMediaManager.shared.togglePlayPause()
                }) {
                    Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 22, height: 22)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(media.isPlaying ? "Pause" : "Play")
                
                Button(action: {
                    BoringSoundEngine.shared.playTap()
                    NowPlayingMediaManager.shared.nextTrack()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.85))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Next Track")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
    
    // MARK: - Compact Response Pill View (Matches Reference Images exactly)
    private var compactResponsePillView: some View {
        VStack(spacing: 6) {
            // Top Header Row: 4 glowing dots (left) and circular stop button (right)
            HStack(alignment: .center) {
                // Left: 4 glowing dots to expand into full panel or switch tabs
                Button(action: {
                    BoringSoundEngine.shared.playTap()
                    withAnimation(NotchAnimations.openSpring) {
                        isCompactMode = false
                        appState.isCompactResponseMode = false
                    }
                }) {
                    HStack(spacing: 3.5) {
                        ForEach(0..<4, id: \.self) { _ in
                            Circle()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 3.5, height: 3.5)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Expand panel")
                
                Spacer()
                
                // Right: Dark circular stop button with white square inside
                Button(action: {
                    BoringSoundEngine.shared.playTap()
                    appState.stopVoice()
                    appState.currentAgentReply = ""
                    appState.isAwaitingRedirectConfirmation = false
                    GoogleSearchEngine.shared.clearLastAnswer()
                    withAnimation(NotchAnimations.closeSpring) {
                        appState.setHoverExpanded(false)
                        appState.islandState = .resting
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 22, height: 22)
                        
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white)
                            .frame(width: 7, height: 7)
                    }
                }
                .buttonStyle(.plain)
                .help("Stop / Dismiss")
            }
            .padding(.horizontal, 14)
            .padding(.top, physicalNotchHeight > 30 ? 10 : 6)
            
            // Bottom Capsule: Translucent smoky dark glass pill with the text and interactive source link
            VStack(spacing: 8) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(cleanedAnswerText)
                            .font(.system(size: cleanedAnswerText.count > 100 ? 13.5 : 14.5, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.96))
                            .lineSpacing(3.5)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Clickable Source Button (Opens real search/wikipedia in default browser)
                        if let url = activeSourceURL {
                            HStack {
                                Spacer()
                                Button(action: {
                                    BoringSoundEngine.shared.playTap()
                                    NSWorkspace.shared.open(url)
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "safari.fill")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text(activeSourceTitle)
                                            .font(.system(size: 11, weight: .bold))
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.18))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("Open full source in default browser")
                                Spacer()
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
                .frame(maxHeight: currentHeight - (physicalNotchHeight > 30 ? 68 : 56))
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(NotchAnimations.openSpring) {
                    isCompactMode = false
                    appState.isCompactResponseMode = false
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private var activeSourceURL: URL? {
        if let targetURL = appState.latestAutonomousResult?.targetURL {
            return targetURL
        }
        if ModelRouter.shared.currentMode == .googleSearch, let card = GoogleSearchEngine.shared.lastAnswer {
            return card.sourceURL
        }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: cleanedAnswerText, options: [], range: NSRange(location: 0, length: cleanedAnswerText.utf16.count))
        return matches?.first?.url
    }
    
    private var activeSourceTitle: String {
        if let targetName = appState.latestAutonomousResult?.targetAppName, !targetName.isEmpty {
            return "Open on \(targetName)"
        }
        if ModelRouter.shared.currentMode == .googleSearch, let card = GoogleSearchEngine.shared.lastAnswer {
            let title = card.sourceTitle.isEmpty ? "Google Search" : card.sourceTitle
            return "Open on \(title)"
        }
        return "Open Web Source"
    }
    
    private var cleanedAnswerText: String {
        // 1. Live agent response takes top priority!
        if !appState.currentAgentReply.isEmpty {
            let raw = appState.currentAgentReply
            if let range = raw.range(of: "\n\n—") {
                return String(raw[..<range.lowerBound]).replacingOccurrences(of: "\"", with: "")
            }
            return raw
        }
        // 2. While running or thinking, show live execution state
        if case .executing(let step) = appState.executionState {
            return step
        }
        if case .thinking(let msg) = appState.executionState {
            return msg
        }
        // 3. While listening, show live transcription
        if !appState.currentTranscript.isEmpty {
            return appState.currentTranscript
        }
        // 4. Latest user chat message
        if let lastMsg = appState.chatMessages.last, !lastMsg.text.isEmpty {
            return lastMsg.text
        }
        // 5. Only in explicit Google Search Mode, fallback to Google card
        if ModelRouter.shared.currentMode == .googleSearch, let card = GoogleSearchEngine.shared.lastAnswer, !card.answerText.isEmpty {
            return card.answerText
        }
        return "Listening..."
    }
    
    private var compactDisplayText: String {
        if !appState.currentAgentReply.isEmpty {
            return appState.currentAgentReply
        }
        if !appState.lastPromptOrQuestion.isEmpty {
            return appState.lastPromptOrQuestion
        }
        if !appState.currentTranscript.isEmpty {
            return appState.currentTranscript
        }
        if let lastMsg = appState.chatMessages.last {
            return lastMsg.text
        }
        return "How are you being made?"
    }
    
    // MARK: - Open Notch Content (Dynamically sized)
    private var openNotchContent: some View {
        VStack(spacing: 8) {
            // 1. Triptych Header Row
            triptychHeader
                .frame(height: 32)
            
            // 2. Now Playing Mini Bar (if playing Spotify, YouTube, or Apple Music)
            if let media = appState.currentMedia {
                nowPlayingBar(media: media)
            }
            
            // 3. Tab Content View
            Group {
                switch appState.activeNotchTab {
                case .ask:
                    askTabView
                case .apps:
                    AppIntegrationsGridView(appState: appState)
                case .tasks:
                    tasksTabView
                case .memory:
                    memoryTabView
                }
            }
            .transition(NotchAnimations.contentTransition)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - Triptych Header Row
    private var triptychHeader: some View {
        HStack(spacing: 0) {
            // Left: Tab Capsule Switcher
            HStack(spacing: 2) {
                ForEach(AppState.NotchTab.allCases) { tab in
                    Button(action: {
                        BoringSoundEngine.shared.playTap()
                        withAnimation(.smooth(duration: 0.25)) {
                            appState.activeNotchTab = tab
                            isCompactMode = false
                            appState.isCompactResponseMode = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 10, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .bold))
                            if tab == .tasks && CodingAgentManager.shared.pendingInputCount > 0 {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .foregroundColor(appState.activeNotchTab == tab ? .white : Color.white.opacity(0.55))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            if appState.activeNotchTab == tab {
                                Capsule()
                                    .fill(Color.white.opacity(0.20))
                                    .matchedGeometryEffect(id: "tabPill", in: tabNamespace)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())
            
            Spacer(minLength: 8)
            
            // Center: Black Hardware Mask Spacer
            Rectangle()
                .fill(Color.black)
                .frame(width: min(physicalNotchWidth, currentWidth * 0.28))
                .mask {
                    NotchShape(topCornerRadius: 4, bottomCornerRadius: 8)
                }
            
            Spacer(minLength: 8)
            
            // Right: Action Buttons
            HStack(spacing: 6) {
                // Minimize to Compact Pill (Image 1 style)
                HoverActionButton(icon: "arrow.down.right.and.arrow.up.left", tooltip: "Compact Pill") {
                    withAnimation(NotchAnimations.openSpring) {
                        isCompactMode = true
                        appState.isCompactResponseMode = true
                    }
                }
                
                // Circle-to-Ask (Camera/Screenshot)
                HoverActionButton(icon: "camera.viewfinder", tooltip: "Circle to Ask") {
                    appState.triggerCircleToAsk()
                }
                
                // Pin Notch Toggle
                HoverActionButton(
                    icon: appState.isPinned ? "pin.fill" : "pin",
                    iconColor: appState.isPinned ? Color.orange : Color.white.opacity(0.7)
                ) {
                    appState.togglePin()
                }
                
                // Open Full Desktop Panel
                HoverActionButton(icon: "macwindow.on.rectangle", tooltip: "\(AppBrand.name) Window") {
                    appState.toggleMainWindow()
                }
                
                // Collapse to Resting Notch
                HoverActionButton(icon: "chevron.up", tooltip: "Collapse") {
                    withAnimation(NotchAnimations.closeSpring) {
                        appState.islandState = .resting
                        appState.isPinned = false
                    }
                }
            }
        }
    }
    
    // MARK: - Ask Tab View (Dynamic Conversational Space)
    @ViewBuilder
    private var askTabView: some View {
        Group {
            if let fullMsg = expandedMessage {
                chatGPTFullReaderView(message: fullMsg)
                    .frame(height: 220)
                    .transition(.opacity)
            } else if let action = appState.currentAction {
                actionApprovalCard(action)
                    .transition(.opacity)
            } else {
                VStack(spacing: 8) {
                    // Top Input Bar with Key Focus & Action Glyphs
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 0.40, green: 0.55, blue: 1.0))
                        
                        TextField("Ask anything, search, control Mac, or Hinglish...", text: $typedInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .focused($isFieldFocused)
                            .onChange(of: isFieldFocused) { _, focused in
                                appState.isTypingFocused = focused
                            }
                            .onSubmit {
                                guard !typedInput.isEmpty else { return }
                                let prompt = typedInput
                                typedInput = ""
                                appState.submitTypedPrompt(prompt)
                            }
                        
                        // Screen Vision Context Button
                        Button(action: {
                            BoringSoundEngine.shared.playTap()
                            appState.triggerScreenVision()
                        }) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.75))
                                .help("Scan & understand what's on my screen")
                        }
                        .buttonStyle(.plain)
                        
                        // Mic Button
                        Button(action: {
                            if case .listening = appState.executionState {
                                appState.stopVoice()
                            } else {
                                appState.triggerVoice(mode: .agent)
                            }
                        }) {
                            ZStack {
                                if isVoiceActive {
                                    Circle()
                                        .fill(Color.red.opacity(0.25))
                                        .frame(width: 18, height: 18)
                                }
                                Image(systemName: isVoiceActive ? "stop.circle.fill" : "mic.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(isVoiceActive ? Color.red : Color(red: 0.40, green: 0.55, blue: 1.0))
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Clear History Button
                        Button(action: {
                            appState.clearChatHistory()
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(Color.white.opacity(0.4))
                                .help("Clear chat memory")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                    
                    // Active Spoken / Answer Bubble (if present)
                    if !appState.currentAgentReply.isEmpty {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(Color.green)
                                    Text("Latest Response")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(Color.white.opacity(0.6))
                                    Spacer()
                                    Button(action: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(appState.currentAgentReply, forType: .string)
                                        BoringSoundEngine.shared.playTap()
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 8))
                                            .foregroundColor(Color.white.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                }
                                Text(appState.currentAgentReply)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineSpacing(2.5)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    
                    // Scrollable Persistent Chat Conversation History (for taller heights)
                    if currentHeight > 180 && !appState.chatMessages.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(spacing: 6) {
                                    ForEach(appState.chatMessages) { message in
                                        chatMessageBubble(message)
                                            .id(message.id)
                                    }
                                }
                                .padding(.horizontal, 2)
                                .padding(.vertical, 2)
                            }
                            .frame(maxHeight: currentHeight - 160)
                            .onChange(of: appState.chatMessages.count) { _, _ in
                                if let lastID = appState.chatMessages.last?.id {
                                    withAnimation {
                                        proxy.scrollTo(lastID, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Redirect / Browser Action Bar
                    if appState.isAwaitingRedirectConfirmation, let result = appState.latestAutonomousResult {
                        HStack(spacing: 8) {
                            if let _ = result.targetURL {
                                Button(action: {
                                    appState.confirmRedirect()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.up.right.square.fill")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("Open in \(result.targetAppName)")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(DesignTokens.Gradients.brand)
                                    .clipShape(Capsule())
                                    .shadow(color: DesignTokens.Colors.accentBlue.opacity(0.3), radius: 4, y: 1)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Button(action: {
                                appState.dismissRedirect()
                            }) {
                                Text("Dismiss")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.70))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.10))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Action Approval Card
    @ViewBuilder
    private func actionApprovalCard(_ action: AgentAction) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.15, green: 0.65, blue: 0.35))
                    .frame(width: 34, height: 34)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let sub = action.subtitle {
                    Text(sub)
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: {
                    appState.dismissAction()
                }) {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    appState.approveCurrentAction()
                }) {
                    Text("Approve")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }
    
    // MARK: - Chat Message Bubble
    @ViewBuilder
    private func chatMessageBubble(_ message: ChatMessage) -> some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 40)
                HStack(spacing: 5) {
                    if message.isScreenContext {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.85))
                    }
                    Text(message.text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.20, green: 0.40, blue: 0.88), Color(red: 0.14, green: 0.30, blue: 0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                )
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(DesignTokens.Gradients.brand)
                                .frame(width: 14, height: 14)
                            Image(systemName: "sparkles")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text(AppBrand.name)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        if let source = message.sourceTitle {
                            Text("• " + source)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.50))
                        }
                        
                        Spacer()
                        
                        // Copy Button
                        Button(action: {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(message.text, forType: .string)
                            BoringSoundEngine.shared.playTap()
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 8))
                                .foregroundColor(Color.white.opacity(0.55))
                                .padding(3)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Copy reply")
                        
                        // Expand to Full Reader View Button
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                expandedMessage = message
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 8, weight: .semibold))
                                Text("Full View")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(.white.opacity(0.95))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .help("View full report")
                    }
                    
                    Text(message.text)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.94))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                    
                    if let urlStr = message.sourceURL, let url = URL(string: urlStr) {
                        Button(action: {
                            NSWorkspace.shared.open(url)
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 7))
                                Text("View on Web")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .foregroundColor(Color.cyan.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.35))
                .cornerRadius(8)
                
                Spacer(minLength: 40)
            }
        }
    }
    
    // MARK: - Full Visible Reader View
    @ViewBuilder
    private func chatGPTFullReaderView(message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Bar
            HStack(spacing: 6) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.cyan)
                
                Text(message.sourceTitle ?? "Voice.AI Deep Intelligence")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Copy full text
                Button(action: {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(message.text, forType: .string)
                    BoringSoundEngine.shared.playTap()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("Copy")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                
                // Speak full text
                Button(action: {
                    SpeechPipelineEngine.shared.speakResponse(message.text)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 9))
                        Text("Speak")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                
                // Open in Main Window
                Button(action: {
                    appState.toggleMainWindow()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 9))
                        Text("Expand")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.15))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Open in full desktop window")
                
                // Close button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedMessage = nil
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08))
            .cornerRadius(6)
            
            // Full Scrollable Formatted Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.text)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.95))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
            }
            .background(Color.black.opacity(0.40))
            .cornerRadius(8)
        }
        .padding(6)
        .background(Color(white: 0.08).opacity(0.98))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
        )
    }
    
    // MARK: - Active Coding Agents & Background Workflows Monitor
    private var tasksTabView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Bar with Agent & Task Counts
            HStack(spacing: 8) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.cyan)
                
                Text("Active Coding Agents")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                let activeCount = appState.activeCodingAgents.count
                let pendingCount = CodingAgentManager.shared.pendingInputCount
                
                HStack(spacing: 6) {
                    if pendingCount > 0 {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 5, height: 5)
                            Text("\(pendingCount) Needs Input")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.orange.opacity(0.18))
                        .clipShape(Capsule())
                    }
                    
                    Text("\(activeCount) Running")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.cyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.cyan.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 2)
            
            // Scrollable List of Active Coding Agents
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(appState.activeCodingAgents) { agent in
                        codingAgentCard(agent)
                    }
                    
                    // Legacy autonomous result fallback (if any)
                    if let result = appState.latestAutonomousResult {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color.green)
                                    .font(.system(size: 10))
                                Text(result.summary)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text("Completed")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Color.green)
                            }
                            
                            ForEach(result.executedSteps, id: \.self) { step in
                                Text("• " + step)
                                    .font(.system(size: 9))
                                    .foregroundColor(Color.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.35))
                        .cornerRadius(8)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
    
    // MARK: - Coding Agent Card
    @ViewBuilder
    private func codingAgentCard(_ agent: CodingAgentTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top Row: Agent Name, Role Pill, Status & Elapsed Time
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(agent.isWaitingForInput ? Color.orange.opacity(0.25) : Color.cyan.opacity(0.20))
                        .frame(width: 22, height: 22)
                    Image(systemName: agent.isWaitingForInput ? "exclamationmark.bubble.fill" : "person.badge.shield.checkmark.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(agent.isWaitingForInput ? .orange : .cyan)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(agent.name)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(agent.role)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.70))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }
                
                Spacer()
                
                // Status Pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(agent.isWaitingForInput ? Color.orange : (agent.state.label == "Active" ? Color.green : Color.gray))
                        .frame(width: 5, height: 5)
                    Text("\(agent.state.label) • \(agent.elapsedFormatted)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(agent.isWaitingForInput ? .orange : Color.white.opacity(0.85))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(agent.isWaitingForInput ? Color.orange.opacity(0.18) : Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
            
            // Running State Progress Bar & Step
            if case .running(let currentStep, let progress) = agent.state {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 3)
                            Capsule()
                                .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, geo.size.width * CGFloat(progress)), height: 3)
                        }
                    }
                    .frame(height: 3)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 8))
                            .foregroundColor(.cyan)
                        Text(currentStep)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            }
            
            // Tasks Performed Section
            if !agent.tasksPerformed.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "checklist")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.60))
                        Text("Tasks Performed (\(agent.tasksPerformed.count)):")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.60))
                    }
                    
                    ForEach(agent.tasksPerformed, id: \.self) { task in
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(Color.green.opacity(0.9))
                                .padding(.top, 2)
                            Text(task)
                                .font(.system(size: 9.5, weight: .regular))
                                .foregroundColor(Color.white.opacity(0.85))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            
            // Interactive User Attention Prompt (Asking For Something)
            if case .waitingForInput(let question, let options) = agent.state {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                        Text("Agent Needs Your Guidance:")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                    }
                    
                    Text(question)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Interactive Action Buttons
                    HStack(spacing: 8) {
                        ForEach(options, id: \.self) { option in
                            Button(action: {
                                BoringSoundEngine.shared.playTap()
                                CodingAgentManager.shared.respondToAgent(agentId: agent.id, response: option)
                            }) {
                                Text(option)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4.5)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.orange.opacity(0.90), Color.red.opacity(0.80)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .clipShape(Capsule())
                                    .shadow(color: Color.orange.opacity(0.3), radius: 3, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.orange.opacity(0.45), lineWidth: 0.8)
                )
            } else if let userResp = agent.userResponse {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.green)
                    Text("Decision: \(userResp)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.green.opacity(0.9))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(agent.isWaitingForInput ? Color.orange.opacity(0.45) : Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }
    
    // MARK: - Memory Tab View
    private var memoryTabView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent Voice Sessions & Shortcuts")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.white.opacity(0.6))
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(appState.recentHistory.prefix(4)) { session in
                        HStack {
                            Image(systemName: session.appIcon)
                                .font(.system(size: 9))
                                .foregroundColor(Color.cyan)
                            Text(session.prompt)
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            Text(session.appName)
                                .font(.system(size: 9))
                                .foregroundColor(Color.white.opacity(0.45))
                        }
                        .padding(6)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }
    
    private var isVoiceActive: Bool {
        if case .listening = appState.executionState { return true }
        return false
    }
}

// MARK: - Hover Action Button
public struct HoverActionButton: View {
    let icon: String
    var iconColor: Color = Color.white.opacity(0.85)
    var tooltip: String = ""
    let action: () -> Void
    
    @State private var isHovering: Bool = false
    
    public var body: some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(isHovering ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                    .frame(width: 28, height: 26)
                
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(iconColor)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) {
                self.isHovering = hovering
            }
        }
    }
}
