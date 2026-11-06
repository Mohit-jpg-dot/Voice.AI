import AppKit
import SwiftUI
import VoiceOSCore

/// Window controller managing the standalone Model Setup & Settings Dashboard for Voice.AI.
public final class ModelSetupWindowController: NSObject, NSWindowDelegate {
    public static let shared = ModelSetupWindowController()
    
    private var window: NSWindow?
    
    public override init() {
        super.init()
    }
    
    public func showWindow() {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let setupWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        setupWindow.center()
        setupWindow.title = "Voice.AI — Model Setup & Settings"
        setupWindow.titleVisibility = .visible
        setupWindow.titlebarAppearsTransparent = true
        setupWindow.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)
        setupWindow.delegate = self
        setupWindow.isMovableByWindowBackground = true
        setupWindow.minSize = NSSize(width: 800, height: 600)
        
        let dashboardView = ModelSetupDashboardView()
        setupWindow.contentView = NSHostingView(rootView: dashboardView)
        setupWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        self.window = setupWindow
    }
    
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return true
    }
}

