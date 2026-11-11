import AppKit
import Combine
import SwiftUI
import VoiceOSCore

/// Custom panel that permits key input only when the sidebar is expanded so the Search field works
/// without stealing focus from user applications while collapsed.
private final class HistorySidebarPanel: NSPanel {
    var allowsKeyFocus: Bool = false

    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }
}

private struct LeftEdgeTriggerHandleView: View {
    let onOpen: () -> Void
    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(isHovering ? 0.85 : 0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(isHovering ? 0.30 : 0.14), lineWidth: 1)
                    )
                if isHovering {
                    VStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(.white)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.60))
                        .frame(width: 3, height: 30)
                }
            }
            .frame(width: isHovering ? 20 : 14, height: 76)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.20, dampingFraction: 0.8), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Click left edge to open History (⌘H)")
    }
}

/// Manages the left-edge screen handle and dynamic ChatGPT-style floating History Sidebar.
public final class HistorySidebarWindowController {
    private let appState: AppState
    private let edgeHandlePanel: HistorySidebarPanel
    private let sidebarPanel: HistorySidebarPanel
    private var cancellables = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?

    public init(appState: AppState) {
        self.appState = appState

        let handleRect = Self.edgeHandleFrame()
        let handle = HistorySidebarPanel(
            contentRect: handleRect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        handle.allowsKeyFocus = false
        handle.isFloatingPanel = true
        handle.isOpaque = false
        handle.backgroundColor = .clear
        handle.hasShadow = false
        handle.level = .mainMenu + 2
        handle.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        handle.appearance = NSAppearance(named: .darkAqua)
        handle.contentView = NSHostingView(
            rootView: LeftEdgeTriggerHandleView { [weak appState] in
                DispatchQueue.main.async {
                    appState?.isHistoryDrawerOpen = true
                }
            }
        )
        self.edgeHandlePanel = handle

        let drawerRect = Self.sidebarFrame()
        let drawer = HistorySidebarPanel(
            contentRect: drawerRect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        drawer.allowsKeyFocus = true
        drawer.isFloatingPanel = true
        drawer.isOpaque = false
        drawer.backgroundColor = .clear
        drawer.hasShadow = false
        drawer.level = .mainMenu + 2
        drawer.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        drawer.appearance = NSAppearance(named: .darkAqua)
        drawer.contentView = NSHostingView(rootView: HistoryDrawerView(appState: appState))
        self.sidebarPanel = drawer

        // Show left-edge peek handle immediately on launch
        edgeHandlePanel.orderFrontRegardless()

        appState.$isHistoryDrawerOpen
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOpen in
                self?.updatePresentation(isOpen: isOpen)
            }
            .store(in: &cancellables)
    }

    deinit {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func updatePresentation(isOpen: Bool) {
        if isOpen {
            let rect = Self.sidebarFrame()
            sidebarPanel.setFrame(rect, display: true)
            edgeHandlePanel.orderOut(nil)
            sidebarPanel.alphaValue = 0.0
            sidebarPanel.orderFrontRegardless()
            sidebarPanel.makeKey()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                sidebarPanel.animator().alphaValue = 1.0
            }
            installOutsideClickMonitor()
        } else {
            removeOutsideClickMonitor()
            sidebarPanel.orderOut(nil)
            edgeHandlePanel.setFrame(Self.edgeHandleFrame(), display: true)
            edgeHandlePanel.orderFrontRegardless()
        }
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            if !self.appState.isHistorySidebarPinned && self.appState.isHistoryDrawerOpen {
                let mouseLoc = NSEvent.mouseLocation
                if !self.sidebarPanel.frame.contains(mouseLoc) {
                    DispatchQueue.main.async {
                        self.appState.isHistoryDrawerOpen = false
                    }
                }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private static func edgeHandleFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: visible.minX, y: visible.midY - 38, width: 22, height: 76)
    }

    private static func sidebarFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let height = min(660, max(420, visible.height - 96))
        let y = visible.midY - (height / 2.0)
        return NSRect(x: visible.minX + 10, y: y, width: 280, height: height)
    }
}
