import AppKit
import SwiftUI
import Combine
import VoiceOSCore

/// Custom click-through hosting view for the left-edge History Sidebar panel.
public final class HistorySidebarHostingView<Content: View>: NSHostingView<Content> {
    public weak var sidebarPanel: HistorySidebarPanel?

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let panel = sidebarPanel, !panel.visibleSidebarBounds.isEmpty else {
            return super.hitTest(point)
        }
        if !panel.visibleSidebarBounds.contains(point) {
            return nil
        }
        return super.hitTest(point)
    }
}

/// Floating left-edge NSPanel for the collapsible History Sidebar pill, scrollable thread list,
/// and ChatGPT-style active session conversation viewer.
public final class HistorySidebarPanel: NSPanel {
    public var allowsKeyFocus: Bool = false
    public var visibleSidebarBounds: NSRect = .zero

    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        isReleasedWhenClosed = false
        hasShadow = false
        level = .floating
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
        appearance = NSAppearance(named: .darkAqua)
    }

    public override var canBecomeKey: Bool {
        allowsKeyFocus
    }

    public override var canBecomeMain: Bool {
        false
    }

    public override func cancelOperation(_ sender: Any?) {
        allowsKeyFocus = false
        resignKey()
        NotificationCenter.default.post(name: .voiceAIHistorySidebarEscapePressed, object: nil)
    }
}

public extension Notification.Name {
    static let voiceAIHistorySidebarEscapePressed = Notification.Name("VoiceAIHistorySidebarEscapePressed")
}

/// Manages positioning, click-through hit-testing, and keyboard focus for the left-edge History Sidebar.
public final class HistorySidebarWindowController: NSWindowController {
    public static let panelWidth: CGFloat = 716.0
    public static let collapsedPillWidth: CGFloat = 32.0
    public static let collapsedPillHeight: CGFloat = 96.0

    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: Any?
    private var escapeObserver: Any?
    private var currentPanelHeight: CGFloat = 580.0

    public static func targetScreen() -> NSScreen {
        NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    public init(appState: AppState) {
        self.appState = appState
        let screen = Self.targetScreen()
        let visible = screen.visibleFrame
        let height = min(620.0, max(460.0, visible.height * 0.72))
        self.currentPanelHeight = height

        let originX = screen.frame.origin.x
        let originY = visible.midY - (height / 2.0)

        let panel = HistorySidebarPanel(
            contentRect: NSRect(x: originX, y: originY, width: Self.panelWidth, height: height)
        )

        let hostingView = HistorySidebarHostingView(
            rootView: HistoryDrawerView(appState: appState)
        )
        hostingView.sidebarPanel = panel
        panel.contentView = hostingView

        super.init(window: panel)

        updatePanelHitBoundsAndFocus(
            isOpen: appState.isHistoryDrawerOpen,
            hasSessionOpen: appState.selectedConversation != nil
        )
        bindState()
        observeSystemEvents()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let screenObserver = screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let escapeObserver = escapeObserver {
            NotificationCenter.default.removeObserver(escapeObserver)
        }
    }

    public func positionAtLeftEdge() {
        guard let panel = window as? HistorySidebarPanel else { return }
        let screen = Self.targetScreen()
        let visible = screen.visibleFrame
        let height = min(620.0, max(460.0, visible.height * 0.72))
        self.currentPanelHeight = height
        let originX = screen.frame.origin.x
        let originY = visible.midY - (height / 2.0)
        panel.setFrame(NSRect(x: originX, y: originY, width: Self.panelWidth, height: height), display: true)
        updatePanelHitBoundsAndFocus(
            isOpen: appState.isHistoryDrawerOpen,
            hasSessionOpen: appState.selectedConversation != nil
        )
    }

    private func bindState() {
        appState.$isHistoryDrawerOpen
            .combineLatest(appState.$selectedConversation)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOpen, selectedSession in
                self?.updatePanelHitBoundsAndFocus(
                    isOpen: isOpen,
                    hasSessionOpen: selectedSession != nil
                )
            }
            .store(in: &cancellables)
    }

    private func observeSystemEvents() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.positionAtLeftEdge()
        }

        escapeObserver = NotificationCenter.default.addObserver(
            forName: .voiceAIHistorySidebarEscapePressed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.appState.selectedConversation != nil {
                self.appState.selectedConversation = nil
            } else if self.appState.isHistoryDrawerOpen {
                self.appState.isHistoryDrawerOpen = false
            }
        }
    }

    private func updatePanelHitBoundsAndFocus(isOpen: Bool, hasSessionOpen: Bool) {
        guard let panel = window as? HistorySidebarPanel else { return }
        let h = currentPanelHeight

        if !isOpen {
            let pillY = (h - Self.collapsedPillHeight) / 2.0
            panel.visibleSidebarBounds = NSRect(
                x: 0,
                y: pillY,
                width: Self.collapsedPillWidth,
                height: Self.collapsedPillHeight
            )
            panel.allowsKeyFocus = false
            if panel.isKeyWindow {
                panel.resignKey()
            }
        } else {
            let activeWidth: CGFloat = hasSessionOpen ? 706.0 : 308.0
            panel.visibleSidebarBounds = NSRect(x: 0, y: 0, width: activeWidth, height: h)
            panel.allowsKeyFocus = true
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }
}

