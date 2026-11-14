import AppKit
import SwiftUI
import Combine
import VoiceOSCore

public final class NotchHUDWindowController: NSWindowController {
    public static let panelWindowWidth: CGFloat = 700.0
    public static let panelWindowHeight: CGFloat = 560.0

    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: Any?

    public static func targetNotchScreen() -> NSScreen {
        // 1. Locate screen with MacBook physical notch (safeAreaInsets.top > 20)
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 20 }) {
            return notched
        }
        // 2. Fallback to main display or first display
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    public init(appState: AppState) {
        self.appState = appState
        
        let screen = Self.targetNotchScreen()
        let screenFrame = screen.frame
        let windowWidth = Self.panelWindowWidth   // 640
        let windowHeight = Self.panelWindowHeight // 380
        
        let targetX = screenFrame.origin.x + (screenFrame.width / 2.0) - (windowWidth / 2.0)
        let targetY = screenFrame.origin.y + screenFrame.height - windowHeight
        
        let panel = NotchPanel(
            contentRect: NSRect(x: targetX, y: targetY, width: windowWidth, height: windowHeight)
        )
        
        let hostingView = NotchHostingView(rootView: NotchGlassIslandView(appState: appState))
        hostingView.notchPanel = panel
        panel.contentView = hostingView
        
        // Initialize strict visible bounds to resting hardware notch pill
        let initialWidth = Self.calculateClosedNotchWidth(for: screen)
        let initialHeight = Self.calculateClosedNotchHeight(for: screen)
        panel.visibleNotchBounds = NSRect(
            x: (windowWidth - initialWidth) / 2.0,
            y: windowHeight - initialHeight,
            width: initialWidth,
            height: initialHeight
        )
        
        super.init(window: panel)
        
        setupShelfDragCallbacks(panel: panel)
        updateDragHotZoneBounds()
        positionUnderNotch()
        bindStateTransitions()
        observeScreenChanges()
    }

    private func setupShelfDragCallbacks(panel: NotchPanel) {
        panel.onDragEnterHotZone = { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.appState.isShelfDragTargetHovered = true
                if self.appState.activeNotchTab != .shelf || self.appState.islandState == .resting {
                    withAnimation(NotchAnimations.openSpring) {
                        self.appState.activeNotchTab = .shelf
                        self.appState.setHoverExpanded(true)
                    }
                }
            }
        }

        panel.onDragExitHotZone = { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.appState.isShelfDragTargetHovered = false
            }
        }

        panel.onPerformDrop = { [weak self] pasteboard in
            guard let self = self else { return false }
            self.appState.isShelfDragTargetHovered = false

            Task {
                let results = await ShelfDropController.shared.processPasteboard(pasteboard, sourceAppName: "NotchDrop")
                await MainActor.run {
                    if !results.isEmpty {
                        BoringSoundEngine.shared.playNotchOpen()
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        NotificationCenter.default.post(name: NSNotification.Name("VoiceOS.ShelfItemsUpdated"), object: nil)

                        if ShelfStore.shared.settings.closeAfterDrop {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                withAnimation(NotchAnimations.closeSpring) {
                                    self.appState.setHoverExpanded(false)
                                }
                            }
                        }
                    }
                }
            }
            return true
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func bindStateTransitions() {
        // 1. Observe Dynamic Content Sizing (adjusts space based on response or answer)
        appState.$dynamicNotchSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                guard let self = self, let panel = self.window as? NotchPanel else { return }
                guard self.appState.islandState != .resting || self.appState.isMediaExpanded else { return }
                let windowWidth = Self.panelWindowWidth
                let windowHeight = Self.panelWindowHeight
                let visibleX = (windowWidth - size.width) / 2.0
                let visibleY = windowHeight - size.height
                panel.visibleNotchBounds = NSRect(x: visibleX, y: visibleY, width: size.width, height: size.height)
            }
            .store(in: &cancellables)

        // 2. Observe Island State Transitions (open / closed / voice / pin)
        appState.$islandState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self, let panel = self.window as? NotchPanel else { return }
                
                let screen = Self.targetNotchScreen()
                let windowWidth = Self.panelWindowWidth
                let windowHeight = Self.panelWindowHeight
                
                let isClosed: Bool
                let visibleWidth: CGFloat
                let visibleHeight: CGFloat
                
                switch state {
                case .resting:
                    isClosed = !self.appState.isMediaExpanded
                    if self.appState.isNotchMediaDisplayEnabled && self.appState.isMediaExpanded {
                        visibleWidth = 460.0
                        visibleHeight = 195.0
                    } else if self.appState.isNotchMediaDisplayEnabled, let m = self.appState.currentMedia, m.isPlaying {
                        visibleWidth = Self.calculateClosedNotchWidth(for: screen) + 100.0
                        visibleHeight = Self.calculateClosedNotchHeight(for: screen) + 6.0
                    } else {
                        visibleWidth = Self.calculateClosedNotchWidth(for: screen)
                        visibleHeight = Self.calculateClosedNotchHeight(for: screen)
                    }
                case .voiceCompact:
                    isClosed = false
                    let count = self.appState.currentTranscript.count
                    visibleWidth = count > 60 ? 560.0 : 480.0
                    visibleHeight = count > 60 ? 125.0 : 96.0
                default:
                    isClosed = false
                    // Dynamic size takes precedence if available
                    if self.appState.dynamicNotchSize.width > 0 && self.appState.dynamicNotchSize.height > 0 {
                        visibleWidth = self.appState.dynamicNotchSize.width
                        visibleHeight = self.appState.dynamicNotchSize.height
                    } else {
                        visibleWidth = NotchAnimations.openNotchSize.width
                        visibleHeight = NotchAnimations.openNotchSize.height
                    }
                }
                
                let visibleX = (windowWidth - visibleWidth) / 2.0
                let visibleY = windowHeight - visibleHeight
                panel.visibleNotchBounds = NSRect(x: visibleX, y: visibleY, width: visibleWidth, height: visibleHeight)
                
                // Haptic feedback on opening
                if !isClosed && state != .pinned {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                
                // Restore focus if closed
                if isClosed && panel.allowsKeyFocus {
                    panel.allowsKeyFocus = false
                    panel.resignKey()
                }
            }
            .store(in: &cancellables)
            
        // 2b. Observe Media Panel Expansion
        appState.$isMediaExpanded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] expanded in
                guard let self = self, let panel = self.window as? NotchPanel else { return }
                let screen = Self.targetNotchScreen()
                let windowWidth = Self.panelWindowWidth
                let windowHeight = Self.panelWindowHeight
                let visibleWidth: CGFloat
                let visibleHeight: CGFloat
                if expanded && self.appState.isNotchMediaDisplayEnabled {
                    visibleWidth = 460.0
                    visibleHeight = 195.0
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                } else if self.appState.islandState == .resting {
                    if self.appState.isNotchMediaDisplayEnabled, let m = self.appState.currentMedia, m.isPlaying {
                        visibleWidth = Self.calculateClosedNotchWidth(for: screen) + 100.0
                        visibleHeight = Self.calculateClosedNotchHeight(for: screen) + 6.0
                    } else {
                        visibleWidth = Self.calculateClosedNotchWidth(for: screen)
                        visibleHeight = Self.calculateClosedNotchHeight(for: screen)
                    }
                } else {
                    return
                }
                let visibleX = (windowWidth - visibleWidth) / 2.0
                let visibleY = windowHeight - visibleHeight
                panel.visibleNotchBounds = NSRect(x: visibleX, y: visibleY, width: visibleWidth, height: visibleHeight)
            }
            .store(in: &cancellables)
            
        // 3. Observe Current Media to adapt resting notch wings size
        appState.$currentMedia
            .receive(on: DispatchQueue.main)
            .sink { [weak self] media in
                guard let self = self, let panel = self.window as? NotchPanel else { return }
                guard self.appState.islandState == .resting else { return }
                let screen = Self.targetNotchScreen()
                let windowWidth = Self.panelWindowWidth
                let windowHeight = Self.panelWindowHeight
                let visibleWidth: CGFloat
                let visibleHeight: CGFloat
                if self.appState.isNotchMediaDisplayEnabled && self.appState.isMediaExpanded {
                    visibleWidth = 460.0
                    visibleHeight = 195.0
                } else if self.appState.isNotchMediaDisplayEnabled, let m = media, m.isPlaying {
                    visibleWidth = Self.calculateClosedNotchWidth(for: screen) + 100.0
                    visibleHeight = Self.calculateClosedNotchHeight(for: screen) + 6.0
                } else {
                    visibleWidth = Self.calculateClosedNotchWidth(for: screen)
                    visibleHeight = Self.calculateClosedNotchHeight(for: screen)
                }
                let visibleX = (windowWidth - visibleWidth) / 2.0
                let visibleY = windowHeight - visibleHeight
                panel.visibleNotchBounds = NSRect(x: visibleX, y: visibleY, width: visibleWidth, height: visibleHeight)
            }
            .store(in: &cancellables)
            
        // 3.5. Observe Notch Media Display Setting
        appState.$isNotchMediaDisplayEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self = self, let panel = self.window as? NotchPanel else { return }
                guard self.appState.islandState == .resting else { return }
                let screen = Self.targetNotchScreen()
                let windowWidth = Self.panelWindowWidth
                let windowHeight = Self.panelWindowHeight
                let visibleWidth: CGFloat
                let visibleHeight: CGFloat
                if enabled, let m = self.appState.currentMedia, m.isPlaying {
                    visibleWidth = Self.calculateClosedNotchWidth(for: screen) + 100.0
                    visibleHeight = Self.calculateClosedNotchHeight(for: screen) + 6.0
                } else {
                    visibleWidth = Self.calculateClosedNotchWidth(for: screen)
                    visibleHeight = Self.calculateClosedNotchHeight(for: screen)
                }
                let visibleX = (windowWidth - visibleWidth) / 2.0
                let visibleY = windowHeight - visibleHeight
                panel.visibleNotchBounds = NSRect(x: visibleX, y: visibleY, width: visibleWidth, height: visibleHeight)
            }
            .store(in: &cancellables)
            
        // 4. Observe Current Transcript while in voiceCompact to resize dynamically as user speaks
        appState.$currentTranscript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                guard let self = self, let panel = self.window as? NotchPanel else { return }
                if case .voiceCompact = self.appState.islandState {
                    let windowWidth = Self.panelWindowWidth
                    let windowHeight = Self.panelWindowHeight
                    let count = transcript.count
                    let visibleWidth: CGFloat = count > 60 ? 560.0 : 480.0
                    let visibleHeight: CGFloat = count > 60 ? 125.0 : 96.0
                    let visibleX = (windowWidth - visibleWidth) / 2.0
                    let visibleY = windowHeight - visibleHeight
                    panel.visibleNotchBounds = NSRect(x: visibleX, y: visibleY, width: visibleWidth, height: visibleHeight)
                }
            }
            .store(in: &cancellables)
            
        // Observe Conditional Key Focus for Typing Field
        appState.$isTypingFocused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] focused in
                guard let self = self, let panel = self.window as? NotchPanel else { return }
                panel.allowsKeyFocus = focused
                if focused {
                    panel.makeKey()
                }
            }
            .store(in: &cancellables)
    }
    
    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.positionUnderNotch()
        }
    }
    
    public func positionUnderNotch() {
        guard let window = self.window else { return }
        let screen = Self.targetNotchScreen()
        let screenFrame = screen.frame
        let windowWidth = Self.panelWindowWidth
        let windowHeight = Self.panelWindowHeight
        
        let targetX = screenFrame.origin.x + (screenFrame.width / 2.0) - (windowWidth / 2.0)
        let targetY = screenFrame.origin.y + screenFrame.height - windowHeight
        
        window.setFrameOrigin(NSPoint(x: targetX, y: targetY))
        updateDragHotZoneBounds()
    }

    public func updateDragHotZoneBounds() {
        let screen = Self.targetNotchScreen()
        let notchWidth = Self.calculateClosedNotchWidth(for: screen)
        let notchHeight = Self.calculateClosedNotchHeight(for: screen)
        let windowWidth = Self.panelWindowWidth
        let windowHeight = Self.panelWindowHeight

        // Generous, smooth hot-zone around notch: 70pt left/right, 50pt downwards
        let hotZoneWidth = notchWidth + 140.0
        let hotZoneHeight = notchHeight + 50.0
        let hotZoneX = (windowWidth - hotZoneWidth) / 2.0
        let hotZoneY = windowHeight - hotZoneHeight

        if let panel = self.window as? NotchPanel {
            panel.dragHotZoneBounds = NSRect(x: hotZoneX, y: hotZoneY, width: hotZoneWidth, height: hotZoneHeight)
        }
    }
    
    public static func calculateClosedNotchWidth(for screen: NSScreen = targetNotchScreen()) -> CGFloat {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return screen.frame.width - left.width - right.width + 4.0 // +4 for hardware seam alignment
        }
        return 185.0
    }
    
    public static func calculateClosedNotchHeight(for screen: NSScreen = targetNotchScreen()) -> CGFloat {
        return screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 32.0
    }
    
    public func calculateClosedNotchWidth() -> CGFloat {
        Self.calculateClosedNotchWidth()
    }
    
    public func calculateClosedNotchHeight() -> CGFloat {
        Self.calculateClosedNotchHeight()
    }
}
