import AppKit
import SwiftUI
import VoiceOSCore

/// Window controller managing the First-Run Setup window for Voice.AI.
public final class SetupWindowController: NSObject, NSWindowDelegate {
    public static let shared = SetupWindowController()
    
    private var window: NSWindow?
    private var onFinishedCallback: (() -> Void)?
    
    public override init() {
        super.init()
    }
    
    public func showSetupWindow(appState: AppState, onFinished: @escaping () -> Void) {
        self.onFinishedCallback = onFinished
        
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let setupWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        setupWindow.center()
        setupWindow.titleVisibility = .hidden
        setupWindow.titlebarAppearsTransparent = true
        setupWindow.isOpaque = false
        setupWindow.backgroundColor = .clear
        setupWindow.delegate = self
        setupWindow.isMovableByWindowBackground = true
        
        let flowView = SetupFlowView(appState: appState) { [weak self] in
            self?.completeSetup()
        }
        
        setupWindow.contentView = NSHostingView(rootView: flowView)
        setupWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        self.window = setupWindow
    }
    
    public func completeSetup() {
        window?.orderOut(nil)
        window = nil
        onFinishedCallback?()
    }
    
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return true
    }
}

