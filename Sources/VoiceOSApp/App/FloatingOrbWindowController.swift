import AppKit
import SwiftUI
import VoiceOSCore

public final class FloatingOrbWindowController: NSWindowController {
    private let appState: AppState
    private var initialDragOrigin: NSPoint = .zero
    
    public init(appState: AppState) {
        self.appState = appState
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        
        super.init(window: panel)
        
        setupContent()
        restorePosition()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupContent() {
        guard let panel = window else { return }
        
        var startOrigin = NSPoint.zero
        
        let orbView = FloatingOrbView(
            appState: appState,
            onTogglePanel: { [weak self] in
                self?.appState.toggleMainWindow()
            },
            onDragChanged: { [weak self] translation in
                guard let self = self, let win = self.window else { return }
                if startOrigin == .zero {
                    startOrigin = win.frame.origin
                }
                let newX = startOrigin.x + translation.width
                let newY = startOrigin.y - translation.height
                win.setFrameOrigin(NSPoint(x: newX, y: newY))
            },
            onDragEnded: { [weak self] _ in
                guard let self = self, let win = self.window else { return }
                startOrigin = .zero
                UserDefaults.standard.set(Double(win.frame.origin.x), forKey: "VoiceAI_Orb_X")
                UserDefaults.standard.set(Double(win.frame.origin.y), forKey: "VoiceAI_Orb_Y")
            }
        )
        
        panel.contentView = NSHostingView(rootView: orbView)
    }
    
    private func restorePosition() {
        guard let screen = NSScreen.main, let win = window else { return }
        
        let savedX = UserDefaults.standard.double(forKey: "VoiceAI_Orb_X")
        let savedY = UserDefaults.standard.double(forKey: "VoiceAI_Orb_Y")
        
        if savedX > 0 && savedY > 0 {
            win.setFrameOrigin(NSPoint(x: savedX, y: savedY))
        } else {
            // Default position: floating on lower right side above the dock
            let defaultX = screen.visibleFrame.maxX - 84
            let defaultY = screen.visibleFrame.minY + 96
            win.setFrameOrigin(NSPoint(x: defaultX, y: defaultY))
        }
    }
    
    public func setVisibility(_ visible: Bool) {
        if visible {
            window?.orderFrontRegardless()
        } else {
            window?.orderOut(nil)
        }
    }
}

