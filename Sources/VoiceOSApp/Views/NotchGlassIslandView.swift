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
    @State private var memorySearchText: String = ""
    @State private var newMemoryText: String = ""
    @State private var memoryTabFilter: String = "Long-Term"
    @State private var semanticMemoryMatches: [StructuredMemoryItem] = []
    @State private var liveTelemetry: LiveHostTelemetrySnapshot = LiveHostTelemetrySnapshot.capture()
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private var currentEmailDraft: EmailDraft? {
        if let active = appState.activeEmailDraft {
            return active
        }
        if case .emailDraftExpanded(let draft) = appState.islandState {
            return draft
        }
        if let action = appState.currentAction, isEmailAction(action) {
            let to = action.payload["to"] ?? action.payload["recipient"] ?? ""
            let subj = action.payload["subject"] ?? action.title.replacingOccurrences(of: "Send email to ", with: "")
            let body = action.payload["body"] ?? action.subtitle ?? ""
            return EmailDraft(
                to: to.isEmpty ? [] : to.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) },
                subject: subj,
                body: body
            )
        }
        return nil
    }

    private var currentEventDraft: CalendarEventDraft? {
        if let active = appState.activeEventDraft {
            return active
        }
        if case .calendarEventExpanded(let draft) = appState.islandState {
            return draft
        }
        if let action = appState.currentAction, isCalendarOrReminderAction(action) {
            let rawTitle = action.payload["title"] ?? action.title
            let title = rawTitle
                .replacingOccurrences(of: "Schedule ", with: "")
                .replacingOccurrences(of: "Add reminder: ", with: "")
                .replacingOccurrences(of: "Create event: ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isRem = action.appName.lowercased().contains("reminder") || (action.payload["tool_name"] ?? "").contains("reminder") || action.title.lowercased().contains("reminder")
            let isMeet = action.title.lowercased().contains("meet") || (action.payload["platform"] ?? "").lowercased().contains("meet") || (action.payload["type"] ?? "").contains("meet")
            let type: EventDraftType = isRem ? .reminder : (isMeet ? .googleMeet : .calendar)
            let dateStr = action.payload["date"] ?? action.payload["date_string"] ?? "Thursday"
            let timeStr = action.payload["time"] ?? action.payload["time_string"] ?? "2:00 – 2:30 PM"
            let participant = action.payload["participant"] ?? action.payload["recipient"] ?? "david@company.com"
            let platform = isRem ? "Reminders" : (type == .googleMeet ? "Google Meet" : "Apple Calendar")
            return CalendarEventDraft(
                title: title.isEmpty ? (isRem ? "New Reminder" : "Design review with David") : title,
                type: type,
                dateString: dateStr,
                timeString: timeStr,
                participants: [participant],
                platform: platform,
                isReminder: isRem
            )
        }
        return nil
    }

    private func isEmailAction(_ action: AgentAction) -> Bool {
        let name = (action.payload["tool_name"] ?? action.appName).lowercased()
        let title = action.title.lowercased()
        return name.contains("email") || name.contains("mail") || title.contains("email") || action.payload["to"] != nil || action.payload["recipient"] != nil
    }

    private func isCalendarOrReminderAction(_ action: AgentAction) -> Bool {
        let name = (action.payload["tool_name"] ?? action.appName).lowercased()
        let title = action.title.lowercased()
        return name.contains("calendar") || name.contains("reminder") || name.contains("meet") ||
               title.contains("calendar") || title.contains("meeting") || title.contains("reminder") ||
               action.payload["date_string"] != nil || action.payload["time_string"] != nil
    }

    private var isOpen: Bool {
        if appState.isMediaExpanded { return true }
        if currentEmailDraft != nil || currentEventDraft != nil { return true }
        switch appState.islandState {
        case .resting, .voiceCompact, .circleToAskActive:
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
            return (480.0, 215.0)
        }
        if !isOpen {
            if case .voiceCompact = appState.islandState {
                let count = appState.currentTranscript.count
                let width: CGFloat = count > 60 ? 480.0 : (count > 0 ? 430.0 : 370.0)
                let height: CGFloat = count > 80 ? 122.0 : (count > 0 ? 100.0 : 78.0)
                return (width, height)
            }
            if appState.isNotchMediaDisplayEnabled, let media = appState.currentMedia, media.isPlaying {
                return (physicalNotchWidth + 100.0, physicalNotchHeight + 6.0)
            }
            let shelfCount = ShelfStore.shared.count
            if shelfCount > 0 && ShelfStore.shared.settings.showCountBadgeOnCollapsedNotch {
                return (physicalNotchWidth + 40.0, physicalNotchHeight)
            }
            return (physicalNotchWidth, physicalNotchHeight)
        }
        
        if currentEmailDraft != nil || currentEventDraft != nil {
            return (550.0, 395.0)
        }

        // Compact Pill Mode (matches reference Image 1 & 10)
        if isCompactMode || appState.isCompactResponseMode {
            return calculateAdaptiveNotchSize(for: compactDisplayText)
        }
        
        let mediaOffset: CGFloat = (appState.currentMedia != nil) ? 38.0 : 0.0
        
        // Full Opened States based on Tab & Response Length
        switch appState.activeNotchTab {
        case .shelf:
            let count = ShelfStore.shared.count
            let width: CGFloat = count > 3 ? 640.0 : (count > 0 ? 560.0 : 500.0)
            return (width, 215.0 + mediaOffset)

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
            
            let cropOffset: CGFloat = (appState.currentCropResult != nil) ? 118.0 : 0.0
            let suggestionOffset: CGFloat = !appState.llmSuggestions.isEmpty ? 36.0 : 0.0
            
            // Adapt height smoothly so long text keeps comfortable room while staying freely scrollable
            let reply = appState.currentAgentReply
            if !reply.isEmpty {
                let count = reply.count
                let width: CGFloat = max(540.0, min(650.0, CGFloat(count) * 1.5 + 420.0))
                let height: CGFloat
                if count <= 65 {
                    height = 170.0
                } else if count <= 160 {
                    height = 215.0
                } else if count <= 300 {
                    height = 275.0
                } else if count <= 550 {
                    height = 350.0
                } else {
                    height = 460.0
                }
                return (width, min(560.0, height + mediaOffset + cropOffset + suggestionOffset))
            }
            
            if appState.currentCropResult != nil {
                return (580.0, 240.0 + mediaOffset)
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
                if appState.isNotchMediaDisplayEnabled && appState.isMediaExpanded, let media = appState.currentMedia {
                    aestheticMediaPanel(media: media)
                } else if isOpen {
                    if let draft = currentEmailDraft {
                        VStack(spacing: 0) {
                            EmailDraftCardView(
                                appState: appState,
                                draft: draft,
                                onSend: { updatedDraft in
                                    appState.sendActiveEmailDraft(customDraft: updatedDraft)
                                },
                                onDismiss: {
                                    appState.dismissEmailDraft()
                                }
                            )
                            .id(draft.id)
                        }
                        .padding(.top, max(physicalNotchHeight + 4.0, 36.0))
                        .padding(.bottom, 12)
                        .transition(.opacity)
                    } else if let eventDraft = currentEventDraft {
                        VStack(spacing: 0) {
                            CalendarEventDraftCardView(
                                appState: appState,
                                draft: eventDraft,
                                onSave: { updatedDraft in
                                    appState.saveActiveCalendarEventDraft(customDraft: updatedDraft)
                                },
                                onDismiss: {
                                    appState.dismissCalendarEventDraft()
                                }
                            )
                            .id(eventDraft.id)
                        }
                        .padding(.top, max(physicalNotchHeight + 4.0, 36.0))
                        .padding(.bottom, 12)
                        .transition(.opacity)
                    } else if isCompactMode || appState.isCompactResponseMode {
                        compactResponsePillView
                    } else {
                        openNotchContent
                    }
                } else if case .voiceCompact = appState.islandState {
                    liveActivityWings
                } else if appState.isNotchMediaDisplayEnabled, let media = appState.currentMedia, media.isPlaying {
                    restingMediaWings(media: media)
                } else {
                    restingHardwareNotchPill
                }
            }
            .frame(width: currentWidth, height: currentHeight, alignment: .top)
            .background(
                Group {
                    if isOpen || appState.isCurrentlyListening {
                        Color.black
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
                    if appState.isShelfDragTargetHovered {
                        NotchShape(
                            topCornerRadius: currentTopRadius,
                            bottomCornerRadius: currentBottomRadius
                        )
                        .stroke(
                            DesignTokens.Colors.accentCyan,
                            lineWidth: 2.0
                        )
                    } else if isOpen || appState.isCurrentlyListening {
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
            .overlay(alignment: .trailing) {
                if !isOpen && ShelfStore.shared.settings.showCountBadgeOnCollapsedNotch && ShelfStore.shared.count > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "tray.2.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(DesignTokens.Colors.accentCyan)
                        Text("\(ShelfStore.shared.count)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
                    .padding(.trailing, 10)
                }
            }
            .overlay(alignment: .topLeading) {
                if currentEmailDraft != nil || currentEventDraft != nil {
                    Image(systemName: "globe")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                        .padding(.leading, 24)
                        .padding(.top, max(physicalNotchHeight * 0.28, 9.0))
                        .transition(.opacity)
                }
            }
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
            liveTelemetry = LiveHostTelemetrySnapshot.capture()

            ShelfDragDetector.shared.onDragNearNotch = { [weak appState] _ in
                DispatchQueue.main.async {
                    guard let appState = appState else { return }
                    if ShelfStore.shared.settings.isEnabled && ShelfStore.shared.settings.autoOpenOnDragNearNotch {
                        withAnimation(NotchAnimations.openSpring) {
                            appState.activeNotchTab = .shelf
                            appState.setHoverExpanded(true)
                        }
                    }
                }
            }
            ShelfDragDetector.shared.startMonitoring()
        }
        .onDisappear {
            ShelfDragDetector.shared.stopMonitoring()
        }
        .onReceive(Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()) { _ in
            if isOpen || isHovering {
                liveTelemetry = LiveHostTelemetrySnapshot.capture()
            }
        }
        .onChange(of: currentWidth) { _, newWidth in
            appState.dynamicNotchSize = CGSize(width: newWidth, height: currentHeight)
        }
        .onChange(of: currentHeight) { _, newHeight in
            appState.dynamicNotchSize = CGSize(width: currentWidth, height: newHeight)
        }
        .onChange(of: appState.islandState) { _, newState in
            if case .selectionReview = newState {
                isCompactMode = false
                appState.isCompactResponseMode = false
                appState.activeNotchTab = .ask
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFieldFocused = true
                }
            } else if case .emailDraftExpanded = newState {
                isCompactMode = false
                appState.isCompactResponseMode = false
                appState.activeNotchTab = .ask
            } else if case .calendarEventExpanded = newState {
                isCompactMode = false
                appState.isCompactResponseMode = false
                appState.activeNotchTab = .ask
            } else if case .resting = newState {
                isFieldFocused = false
                isHovering = false
                hoverTask?.cancel()
                isCompactMode = true
            }
        }
        .onChange(of: appState.activeEmailDraft) { _, newDraft in
            if newDraft != nil {
                isCompactMode = false
                appState.isCompactResponseMode = false
            }
        }
        .onChange(of: appState.activeEventDraft) { _, newDraft in
            if newDraft != nil {
                isCompactMode = false
                appState.isCompactResponseMode = false
            }
        }
    }
    
    // MARK: - Hover Management (boring.notch feel)
    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()
        
        if hovering {
            isHovering = true
            appState.isHoveringPill = true
            guard !isOpen, !appState.isPinned, appState.islandState != .circleToAskActive else { return }
            
            // Dwell Delay (200ms) strictly on hardware notch touch prevents swift cursor sweep opens
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.isHovering, !self.isOpen, !self.appState.isPinned, self.appState.islandState != .circleToAskActive else { return }
                    withAnimation(NotchAnimations.openSpring) {
                        if self.appState.isNotchMediaDisplayEnabled, let media = self.appState.currentMedia, media.isPlaying {
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
                    self.appState.isHoveringPill = false
                    
                    // Do not auto-close if pinned, typing, or actively using Circle to Ask
                    guard !self.appState.isPinned, !self.appState.isTypingFocused else { return }
                    if self.appState.islandState == .circleToAskActive || self.appState.isScreenCaptureActive {
                        return
                    }
                    if case .selectionReview = self.appState.islandState {
                        return
                    }
                    
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

                let shelfCount = ShelfStore.shared.count
                if shelfCount > 0 && ShelfStore.shared.settings.showCountBadgeOnCollapsedNotch {
                    HStack(spacing: 3) {
                        Image(systemName: "tray.2.fill")
                            .font(.system(size: 8))
                        Text("\(shelfCount)")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Color.white.opacity(0.9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Minimalist Notch Listening UI
    private var liveActivityWings: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Minimal single-row status header safely below hardware notch
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.executionState == .transcribing ? Color.cyan : Color.white)
                        .frame(width: 6, height: 6)
                        .opacity(isVoiceActive ? 1.0 : 0.45)
                        .scaleEffect(isVoiceActive ? 1.2 : 0.9)
                        .animation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true), value: isVoiceActive)

                    Text(appState.executionState == .transcribing ? "Processing" : "Listening")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.68))
                }

                Spacer()

                // Subtle Minimalist Waveform
                HStack(spacing: 2.5) {
                    ForEach(0..<min(6, appState.audioLevels.count), id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 2, height: max(4, appState.audioLevels[idx] * 14))
                            .animation(.easeOut(duration: 0.08), value: appState.audioLevels[idx])
                    }
                }
                .padding(.trailing, 4)

                // Minimal Stop Button
                Button(action: {
                    BoringSoundEngine.shared.playTap()
                    appState.stopVoice()
                    withAnimation(NotchAnimations.closeSpring) {
                        appState.islandState = .resting
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.75))
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Stop Listening")
            }
            .padding(.horizontal, 26)
            .padding(.top, max(physicalNotchHeight + 2.0, 34.0))

            // Clean live transcript directly on pure black notch surface (zero clipping)
            if !appState.currentTranscript.isEmpty {
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(appState.currentTranscript)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.white)
                            .lineSpacing(2.5)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id("liveTranscriptBottom")
                    }
                    .frame(maxHeight: 54)
                    .onChange(of: appState.currentTranscript) { _, _ in
                        scrollProxy.scrollTo("liveTranscriptBottom", anchor: .bottom)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 10)
            }
        }
        .frame(width: currentWidth, height: currentHeight, alignment: .top)
        .background(Color.black)
    }
    
    private var listeningModeTitle: String {
        if case .voiceCompact(let mode) = appState.islandState {
            switch mode {
            case .dictation: return "💬 Conversation (Fn)"
            case .clipboardDictation: return "📋 Clipboard Dictation (Fn+D)"
            case .agent, .ask: return "⚡ Computer Control (⌃)"
            }
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
                // Left Wing: Source Icon / Compact Thumbnail
                HStack(spacing: 4) {
                    if media.source == .spotify {
                        SpotifyBrandIconView(size: 18)
                    } else if media.source == .youtube {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(red: 0.18, green: 0.03, blue: 0.03))
                                .frame(width: 26, height: 18)
                            if !media.artworkUrl.isEmpty, let artUrl = URL(string: media.artworkUrl) {
                                AsyncImage(url: artUrl) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 26, height: 18)
                                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    default:
                                        YouTubeIconView(size: 14)
                                    }
                                }
                            } else {
                                YouTubeIconView(size: 14)
                            }
                        }
                        .frame(width: 26, height: 18)
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.98, green: 0.14, blue: 0.24))
                                .frame(width: 17, height: 17)
                                .shadow(color: Color.red.opacity(0.4), radius: 3)
                            Image(systemName: media.source.iconName)
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(width: 45, alignment: .center)
                
                // Center Spacer: Exact width of the physical MacBook Notch
                // Ensures ZERO text or controls are placed behind the plastic camera!
                Spacer(minLength: 0)
                    .frame(width: physicalNotchWidth)
                
                // Right Wing: Real-Time Animated EQ Bars + Play/Pause Button
                HStack(spacing: 5) {
                    TimelineView(.animation(minimumInterval: 0.18, paused: !media.isPlaying)) { timeline in
                        let step = Int(timeline.date.timeIntervalSinceReferenceDate * 5.0)
                        HStack(spacing: 2) {
                            ForEach(0..<4, id: \.self) { idx in
                                let wave = 5 + ((step + idx * 3) % 9)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(media.source == .spotify ? Color(red: 0.11, green: 0.85, blue: 0.4) : Color.red)
                                    .frame(width: 2, height: CGFloat(media.isPlaying ? wave : 3))
                            }
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
        VStack(spacing: 10) {
            // Top notch avoidance padding: ensure all controls and text begin safely below the MacBook camera notch!
            Spacer()
                .frame(height: max(physicalNotchHeight + 6.0, 38.0))
            
            // Header Bar: Source Badge + EQ Visualizer + Dismiss/Collapse
            HStack(alignment: .center) {
                // Source Pill
                HStack(spacing: 5) {
                    if media.source == .spotify {
                        SpotifyBrandIconView(size: 11)
                    } else if media.source == .youtube {
                        YouTubeIconView(size: 11)
                    } else {
                        Circle()
                            .fill(Color.pink)
                            .frame(width: 7, height: 7)
                    }
                    Text(media.source.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .cornerRadius(7)
                
                Spacer()
                
                // Real-Time EQ Visualizer
                TimelineView(.animation(minimumInterval: 0.18, paused: !media.isPlaying)) { timeline in
                    let step = Int(timeline.date.timeIntervalSinceReferenceDate * 5.0)
                    HStack(spacing: 2.5) {
                        ForEach(0..<5, id: \.self) { idx in
                            let wave = 5 + ((step + idx * 2) % 10)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(media.source == .spotify ? Color(red: 0.11, green: 0.85, blue: 0.4) : Color.red)
                                .frame(width: 2, height: CGFloat(media.isPlaying ? wave : 3))
                        }
                    }
                }
                .padding(.trailing, 10)
                
                HStack(spacing: 8) {
                    // Dismiss / Clear Media Button
                    Button(action: {
                        withAnimation(NotchAnimations.closeSpring) {
                            appState.isMediaExpanded = false
                            appState.currentMedia = nil
                            NowPlayingMediaManager.shared.clearMedia()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss now playing media")
                    
                    // Collapse Button
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
                    .help("Collapse media panel")
                }
            }
            .padding(.horizontal, 30)
            
            // Middle Row: Bigger Album Artwork (64x64) + Track Name, Creator Name & Scrubber
            HStack(spacing: 14) {
                // Real Song Album Art / Video Thumbnail Container (Larger 64x64)
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                        .frame(width: 64, height: 64)

                    if !media.artworkUrl.isEmpty {
                        let artStr = media.artworkUrl
                        if artStr.hasPrefix("file://") || artStr.hasPrefix("/"),
                           let nsImg = resolveLocalArtwork(artStr) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else if let artUrl = URL(string: artStr) {
                            AsyncImage(url: artUrl) { phase in
                                switch phase {
                                case .success(let img):
                                    img
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                case .failure, .empty:
                                    mediaArtworkPlaceholder(media: media)
                                @unknown default:
                                    mediaArtworkPlaceholder(media: media)
                                }
                            }
                        } else {
                            mediaArtworkPlaceholder(media: media)
                        }
                    } else {
                        mediaArtworkPlaceholder(media: media)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 6, x: 0, y: 3)
                
                // Track Info & Progress Scrubber Line
                VStack(alignment: .leading, spacing: 3) {
                    Text(media.title)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(media.artistOrChannel.isEmpty ? media.source.rawValue : media.artistOrChannel)
                        .font(.system(size: 12.0, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.72))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Scrubber Bar Container with safe insets so play line NEVER goes outside the pill
                    VStack(spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.16))
                                    .frame(height: 3.5)
                                Capsule()
                                    .fill(
                                        media.source == .spotify
                                            ? LinearGradient(colors: [Color(red: 0.11, green: 0.85, blue: 0.4), Color(red: 0.2, green: 1.0, blue: 0.5)], startPoint: .leading, endPoint: .trailing)
                                            : LinearGradient(colors: [Color(red: 1.0, green: 0.25, blue: 0.25), Color(red: 1.0, green: 0.45, blue: 0.45)], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .frame(width: max(4.0, min(geo.size.width, geo.size.width * CGFloat(media.progress))), height: 3.5)
                            }
                        }
                        .frame(height: 3.5)
                        .frame(maxWidth: .infinity)
                        
                        HStack(spacing: 0) {
                            Text(String(format: "%d:%02d", media.positionSeconds / 60, media.positionSeconds % 60))
                                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.60))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if media.durationSeconds > 0 {
                                Text(String(format: "%d:%02d", media.durationSeconds / 60, media.durationSeconds % 60))
                                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color.white.opacity(0.60))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 30)
            
            // Bottom Controls Bar: Previous | Play/Pause | Next
            HStack(spacing: 30) {
                Spacer()
                
                // Previous Button
                Button(action: {
                    BoringSoundEngine.shared.playTap()
                    NowPlayingMediaManager.shared.previousTrack()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                        .frame(width: 34, height: 34)
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
                            .frame(width: 40, height: 40)
                            .shadow(color: Color.white.opacity(0.30), radius: 6)
                        Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold))
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
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Next Track (Shift+N)")
                
                Spacer()
            }
            .padding(.bottom, 14)
        }
        .frame(width: 480, height: 215)
    }
    
    @ViewBuilder
    private func mediaArtworkPlaceholder(media: NowPlayingItem) -> some View {
        if media.source == .spotify {
            AnyView(SpotifyBrandIconView(size: 26))
        } else if media.source == .youtube {
            AnyView(YouTubeIconView(size: 28))
        } else {
            AnyView(Image(systemName: "music.note")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(red: 0.11, green: 0.85, blue: 0.4)))
        }
    }
    
    /// Resolves a local file:// or absolute path artwork string to NSImage.
    private func resolveLocalArtwork(_ artStr: String) -> NSImage? {
        let filePath: String
        if artStr.hasPrefix("file://"), let fu = URL(string: artStr) {
            filePath = fu.path
        } else {
            filePath = artStr
        }
        return NSImage(contentsOfFile: filePath)
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
                // Left: 4 glowing dots + Expand label
                Button(action: {
                    BoringSoundEngine.shared.playTap()
                    withAnimation(NotchAnimations.openSpring) {
                        isCompactMode = false
                        appState.isCompactResponseMode = false
                    }
                }) {
                    HStack(spacing: 4) {
                        HStack(spacing: 3.5) {
                            ForEach(0..<4, id: \.self) { _ in
                                Circle()
                                    .fill(Color.white.opacity(0.85))
                                    .frame(width: 3.5, height: 3.5)
                            }
                        }
                        Text("Expand")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.65))
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
            .padding(.top, max(physicalNotchHeight + 4.0, 36.0))
            
            // Bottom Capsule: Freely Scrollable Translucent Dark Glass Pill
            VStack(spacing: 8) {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(cleanedAnswerText)
                            .font(.system(size: cleanedAnswerText.count > 100 ? 13.5 : 14.5, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.96))
                            .lineSpacing(3.5)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        
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
                .frame(maxHeight: max(76, currentHeight - (physicalNotchHeight > 30 ? 74 : 62)))
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private var liveCompactTelemetryPill: some View {
        HStack(spacing: 6) {
            Text("\(liveTelemetry.ramUsagePercent)% RAM")
            if let bat = liveTelemetry.batteryPercent {
                Text("•")
                Text("\(bat)%\(liveTelemetry.isCharging ? "⚡" : "")")
            }
            Text("•")
            Text(liveTelemetry.activeAIMode)
            if liveTelemetry.computerAudioEnabled {
                Text("•")
                Text("Audio ON")
                    .foregroundColor(.purple)
            }
        }
        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
        .foregroundColor(Color.white.opacity(0.62))
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Color.white.opacity(0.07))
        .clipShape(Capsule())
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
        if let lastResult = appState.latestAutonomousResult, !lastResult.summary.isEmpty {
            return lastResult.summary
        }
        return "Ready for your command..."
    }
    
    // MARK: - Open Notch Content (Dynamically sized)
    private var openNotchContent: some View {
        VStack(spacing: 8) {
            if let draft = currentEmailDraft {
                EmailDraftCardView(
                    appState: appState,
                    draft: draft,
                    onSend: { updatedDraft in
                        appState.sendActiveEmailDraft(customDraft: updatedDraft)
                    },
                    onDismiss: {
                        appState.dismissEmailDraft()
                    }
                )
                .transition(.opacity)
            } else if let eventDraft = currentEventDraft {
                CalendarEventDraftCardView(
                    appState: appState,
                    draft: eventDraft,
                    onSave: { updatedDraft in
                        appState.saveActiveCalendarEventDraft(customDraft: updatedDraft)
                    },
                    onDismiss: {
                        appState.dismissCalendarEventDraft()
                    }
                )
                .transition(.opacity)
            } else {
                // 1. Triptych Header Row
                triptychHeader
                    .frame(height: 32)

            // 2. Now Playing Mini Bar (if playing Spotify, YouTube, or Apple Music)
            if appState.isNotchMediaDisplayEnabled, let media = appState.currentMedia {
                nowPlayingBar(media: media)
            }
            
            // 3. Tab Content View
            Group {
                switch appState.activeNotchTab {
                case .ask:
                    askTabView
                case .shelf:
                    ShelfView(appState: appState)
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
        }
        .padding(.horizontal, 16)
        .padding(.top, max(physicalNotchHeight + 4.0, 36.0))
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - Triptych Header Row
    private var triptychHeader: some View {
        HStack(spacing: 6) {
            // Left: Tab Capsule Switcher (full labels never truncate)
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
                                .fixedSize(horizontal: true, vertical: false)
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
            
            // Right: Essential Clean Action Controls
            HStack(spacing: 6) {
                // Pin Notch Toggle
                HoverActionButton(
                    icon: appState.isPinned ? "pin.fill" : "pin",
                    iconColor: appState.isPinned ? Color.orange : Color.white.opacity(0.75)
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
                if isEmailAction(action), let draft = currentEmailDraft {
                    EmailDraftCardView(
                        appState: appState,
                        draft: draft,
                        onSend: { updatedDraft in
                            appState.sendActiveEmailDraft(customDraft: updatedDraft)
                        },
                        onDismiss: {
                            appState.dismissEmailDraft()
                        }
                    )
                    .transition(.opacity)
                } else if isCalendarOrReminderAction(action), let draft = currentEventDraft {
                    CalendarEventDraftCardView(
                        appState: appState,
                        draft: draft,
                        onSave: { updatedDraft in
                            appState.saveActiveCalendarEventDraft(customDraft: updatedDraft)
                        },
                        onDismiss: {
                            appState.dismissCalendarEventDraft()
                        }
                    )
                    .transition(.opacity)
                } else {
                    actionApprovalCard(action)
                        .transition(.opacity)
                }
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
                        
                        // Circle to Ask / Lasso Selection Button
                        Button(action: {
                            appState.triggerCircleToAsk()
                        }) {
                            Image(systemName: "lasso")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color.cyan.opacity(0.9))
                                .help("Circle / Lasso anything on screen to Ask (⌘⇧C)")
                        }
                        .buttonStyle(.plain)
                        
                        // Camera / Screen Vision Context Button
                        Button(action: {
                            BoringSoundEngine.shared.playTap()
                            appState.triggerScreenVision()
                        }) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.80))
                                .help("Scan & understand full screen")
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
                        
                        // Delete / Clear History Button
                        Button(action: {
                            appState.clearChatHistory()
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(Color.white.opacity(0.55))
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
                    
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 8) {
                            // Circle to Ask / Lasso Selection Preview Card
                            if let crop = appState.currentCropResult {
                                circleCropPreviewCard(crop)
                            }
                            
                            // Only the Latest Response (pure black background, no questions or previous history)
                            let displayedReply: String = {
                                if !appState.currentAgentReply.isEmpty {
                                    return appState.currentAgentReply
                                }
                                return appState.chatMessages.last(where: { $0.role == "assistant" })?.text ?? ""
                            }()
                            if !displayedReply.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Spacer()
                                        Button(action: {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(displayedReply, forType: .string)
                                            BoringSoundEngine.shared.playTap()
                                        }) {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 9))
                                                .foregroundColor(Color.white.opacity(0.55))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Copy response")
                                    }
                                    Text(displayedReply)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .padding(10)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        }
    }
    
    // MARK: - Circle to Ask Crop Preview Card
    @ViewBuilder
    private func circleCropPreviewCard(_ crop: ScreenCropResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if let pngData = crop.capturedImagePNGData, let nsImage = NSImage(data: pngData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 58, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.cyan.opacity(0.45), lineWidth: 1)
                        )
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(crop.toolUsed.rawValue.uppercased())
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.cyan.opacity(0.18))
                            .cornerRadius(4)
                        
                        if let appName = crop.sourceAppName, !appName.isEmpty {
                            Text(appName)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        
                        if crop.redactedItemsCount > 0 {
                            Text("\(crop.redactedItemsCount) REDACTED")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.18))
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            BoringSoundEngine.shared.playTap()
                            appState.clearCircleSelection()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Clear selected region")
                    }
                    
                    Text(crop.extractedOCRText.isEmpty ? "Visual region captured (\(Int(crop.boundingBox.width))×\(Int(crop.boundingBox.height)) px)" : crop.extractedOCRText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.85))
                        .lineLimit(2)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text(ModelRouter.shared.currentMode == .cloud || (ModelRouter.shared.currentMode == .hybrid && ModelRouter.shared.hasUserConsentedToCloudUpload) ? "VLM OPT-IN" : "ON-DEVICE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.16))
                        .cornerRadius(4)

                    ForEach(["What does this error mean?", "Which button should I click?", "Explain this", "Summarize"], id: \.self) { chipTitle in
                        Button(action: {
                            appState.submitTypedPrompt(chipTitle)
                        }) {
                            Text(chipTitle)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.cyan.opacity(0.20))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.cyan.opacity(0.35), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        appState.triggerCircleToAsk()
                    }) {
                        Text("Re-circle")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background(Color.cyan.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.cyan.opacity(0.28), lineWidth: 0.75)
        )
    }
    
    // MARK: - Action Approval Card
    @ViewBuilder
    private func actionApprovalCard(_ action: AgentAction) -> some View {
        let tier = PermissionTier(from: action.riskLevel)
        let tierColor: Color = tier == .consequential
            ? Color(red: 0.92, green: 0.34, blue: 0.28)
            : (tier == .reversible ? Color(red: 0.25, green: 0.56, blue: 0.98) : Color(red: 0.15, green: 0.65, blue: 0.35))

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tierColor)
                    .frame(width: 34, height: 34)
                Image(systemName: action.appIcon.isEmpty ? "bolt.shield.fill" : action.appIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(action.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(tier.rawValue)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(tierColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tierColor.opacity(0.16))
                        .clipShape(Capsule())
                }
                
                if let sub = action.subtitle {
                    Text(sub)
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.75))
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: {
                    appState.dismissAction()
                }) {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.75))
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
                .stroke(tierColor.opacity(0.35), lineWidth: 0.75)
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
            // Header Bar with Real Active Agent Count
            HStack(spacing: 8) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.cyan)
                
                Text("Active Agents")
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
                    
                    Text("\(activeCount) Active")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.cyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.cyan.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 2)
            
                            // Scrollable List of Active Real Agents
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 8) {
                    if appState.activeCodingAgents.isEmpty && appState.latestAutonomousResult == nil {
                        VStack(spacing: 6) {
                            Image(systemName: "cpu")
                                .font(.system(size: 20))
                                .foregroundColor(Color.white.opacity(0.35))
                            Text("No active agents running")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.65))
                            Text("Spawn a real task by voice or via Ask to monitor live execution here.")
                                .font(.system(size: 9.5))
                                .foregroundColor(Color.white.opacity(0.45))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    } else {
                        ForEach(appState.activeCodingAgents) { agent in
                            codingAgentCard(agent)
                        }
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
        let filteredItems: [StructuredMemoryItem] = {
            if !memorySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !semanticMemoryMatches.isEmpty {
                let targetScope: MemoryScope? = memoryTabFilter == "Long-Term" ? .longTerm : (memoryTabFilter == "Short-Term" ? .shortTerm : nil)
                return semanticMemoryMatches.filter { targetScope == nil || $0.scope == targetScope }
            }
            let targetScope: MemoryScope = memoryTabFilter == "Short-Term" ? .shortTerm : .longTerm
            let query = memorySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return appState.structuredMemories.filter { item in
                guard item.scope == targetScope else { return false }
                if query.isEmpty { return true }
                return item.content.lowercased().contains(query) || item.kind.rawValue.lowercased().contains(query)
            }
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(["Long-Term", "Short-Term", "Sessions"], id: \.self) { tab in
                    Button(action: {
                        memoryTabFilter = tab
                        appState.refreshPhase1State()
                    }) {
                        Text(tab)
                            .font(.system(size: 9.5, weight: memoryTabFilter == tab ? .bold : .medium))
                            .foregroundColor(memoryTabFilter == tab ? .black : .white.opacity(0.75))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(memoryTabFilter == tab ? Color.cyan : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if memoryTabFilter != "Sessions" {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.45))
                        TextField("Recall...", text: $memorySearchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .frame(width: 90)
                            .onChange(of: memorySearchText) { _, newValue in
                                let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                if q.isEmpty {
                                    semanticMemoryMatches = []
                                } else {
                                    Task {
                                        let hits = await MemoryStore.shared.searchSemantic(query: q, scope: nil, limit: 8)
                                        await MainActor.run {
                                            if memorySearchText.trimmingCharacters(in: .whitespacesAndNewlines) == q {
                                                semanticMemoryMatches = hits.map { $0.item }
                                            }
                                        }
                                    }
                                }
                            }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
                }
            }

            if memoryTabFilter != "Sessions" {
                HStack(spacing: 6) {
                    TextField("Remember a fact or preference...", text: $newMemoryText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                        .onSubmit {
                            let clean = newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !clean.isEmpty else { return }
                            appState.rememberNoteFromUI(clean, kind: .fact)
                            newMemoryText = ""
                        }

                    Button(action: {
                        let clean = newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !clean.isEmpty else { return }
                        appState.rememberNoteFromUI(clean, kind: .fact)
                        newMemoryText = ""
                    }) {
                        Text("Remember")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cyan)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    if memoryTabFilter == "Sessions" {
                        ForEach(appState.recentHistory.prefix(6)) { session in
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
                    } else if filteredItems.isEmpty {
                        Text(memorySearchText.isEmpty ? "No memories saved in this scope yet. Say \"Remember that...\" or add one above." : "No matching memories found.")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(filteredItems.prefix(8)) { item in
                            HStack(spacing: 6) {
                                Text(item.kind.rawValue.uppercased())
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.cyan)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.cyan.opacity(0.14))
                                    .cornerRadius(4)

                                Text(item.content)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .lineLimit(2)

                                Spacer()

                                Button(action: {
                                    appState.forgetMemoryFromUI(id: item.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.45))
                                }
                                .buttonStyle(.plain)
                                .help("Forget this memory")
                            }
                            .padding(6)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .onAppear {
            appState.refreshPhase1State()
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

// MARK: - Authentic Spotify Brand Icon
public struct SpotifyBrandIconView: View {
    public let size: CGFloat
    
    public init(size: CGFloat = 18) {
        self.size = size
    }
    
    public var body: some View {
        // Use NSWorkspace to get Spotify icon - works for any install location
        let spotifyIcon: NSImage? = {
            let ws = NSWorkspace.shared
            let spotifyPath = "/Applications/Spotify.app"
            if FileManager.default.fileExists(atPath: spotifyPath) {
                return ws.icon(forFile: spotifyPath)
            }
            // Fallback: check user Applications
            let userPath = (NSHomeDirectory() as NSString).appendingPathComponent("Applications/Spotify.app")
            if FileManager.default.fileExists(atPath: userPath) {
                return ws.icon(forFile: userPath)
            }
            return MacOSAppIconResolver.icon(for: "spotify")
        }()
        if let icon = spotifyIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            // Authentic Spotify brand logo vector fallback
            ZStack {
                Circle()
                    .fill(Color(red: 0.114, green: 0.843, blue: 0.376))
                    .frame(width: size, height: size)
                
                Canvas { context, sz in
                    let w = sz.width
                    let h = sz.height
                    let center = CGPoint(x: w * 0.45, y: h * 0.52)
                    let strokeColor = Color(red: 0.08, green: 0.08, blue: 0.08)
                    
                    var path1 = Path()
                    path1.addArc(center: CGPoint(x: center.x, y: center.y + h * 0.18), radius: w * 0.34, startAngle: .degrees(225), endAngle: .degrees(315), clockwise: false)
                    context.stroke(path1, with: .color(strokeColor), style: StrokeStyle(lineWidth: w * 0.09, lineCap: .round))
                    
                    var path2 = Path()
                    path2.addArc(center: CGPoint(x: center.x, y: center.y + h * 0.18), radius: w * 0.25, startAngle: .degrees(225), endAngle: .degrees(315), clockwise: false)
                    context.stroke(path2, with: .color(strokeColor), style: StrokeStyle(lineWidth: w * 0.08, lineCap: .round))
                    
                    var path3 = Path()
                    path3.addArc(center: CGPoint(x: center.x, y: center.y + h * 0.18), radius: w * 0.16, startAngle: .degrees(225), endAngle: .degrees(315), clockwise: false)
                    context.stroke(path3, with: .color(strokeColor), style: StrokeStyle(lineWidth: w * 0.07, lineCap: .round))
                }
                .frame(width: size, height: size)
            }
        }
    }
}

// MARK: - YouTube Brand Icon View
public struct YouTubeIconView: View {
    public let size: CGFloat

    public init(size: CGFloat = 18) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Color(red: 1.0, green: 0.0, blue: 0.0))
                .frame(width: size, height: size * 0.72)
            Canvas { context, sz in
                let tw = sz.width * 0.38
                let th = sz.height * 0.52
                let cx = sz.width / 2
                let cy = sz.height / 2
                var tri = Path()
                tri.move(to: CGPoint(x: cx - tw * 0.4, y: cy - th * 0.5))
                tri.addLine(to: CGPoint(x: cx + tw * 0.6, y: cy))
                tri.addLine(to: CGPoint(x: cx - tw * 0.4, y: cy + th * 0.5))
                tri.closeSubpath()
                context.fill(tri, with: .color(.white))
            }
            .frame(width: size, height: size * 0.72)
        }
        .frame(width: size, height: size)
    }
}
