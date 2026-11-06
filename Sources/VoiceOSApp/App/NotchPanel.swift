import AppKit
import SwiftUI
import VoiceOSCore

/// Custom NSHostingView that strictly gates hit-testing to the physical/active visible notch bounds.
/// When the cursor or a mouse event is outside the active visible notch shape (e.g. transparent 640x210 areas),
/// hitTest returns nil so macOS passes clicks, scrolls, and hovers straight through to underlying applications.
public final class NotchHostingView<Content: View>: NSHostingView<Content> {
    public weak var notchPanel: NotchPanel?
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let panel = notchPanel, !panel.visibleNotchBounds.isEmpty else {
            return super.hitTest(point)
        }
        
        // Strictly check if point is inside the active visible notch shape
        if !panel.visibleNotchBounds.contains(point) {
            return nil
        }
        
        return super.hitTest(point)
    }
}

/// Fixed-size non-resizing panel for the Voice.AI Notch.
/// Window size is permanently 640x210 (open size 640x190 + 20pt shadow padding).
/// Window frame NEVER resizes or animates origin, guaranteeing 120fps stutter-free physics.
public final class NotchPanel: NSPanel {
    /// Conditional key focus: true ONLY when user focuses the typing field.
    public var allowsKeyFocus: Bool = false
    
    /// Bounding rectangle of the visible notch content within window coordinates for strict click-through testing.
    public var visibleNotchBounds: NSRect = .zero
    
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
        
        // Window level above menu bar
        level = .mainMenu + 3
        
        // Appear on all spaces and auxiliary screens
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
}
