import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoiceOSCore

/// Custom NSHostingView that strictly gates hit-testing to the physical/active visible notch bounds.
/// When the cursor or a mouse event is outside the active visible notch shape (e.g. transparent 640x210 areas),
/// hitTest returns nil so macOS passes clicks, scrolls, and hovers straight through to underlying applications.
/// During active drag operations near the notch, hitTest accepts the drag so items can be dropped directly into the Shelf.
public final class NotchHostingView<Content: View>: NSHostingView<Content> {
    public weak var notchPanel: NotchPanel?

    @MainActor public required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes(NotchPanel.supportedDragTypes)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(NotchPanel.supportedDragTypes)
    }
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let panel = notchPanel, !panel.visibleNotchBounds.isEmpty else {
            return super.hitTest(point)
        }
        
        // 1. Strictly check if point is inside the active visible notch shape
        if panel.visibleNotchBounds.contains(point) {
            return super.hitTest(point)
        }

        // 2. When a drag is active over the window and point is in the hot-zone, accept hit-test
        if panel.isDragActiveOverWindow && panel.isPointInDragHotZone(point) {
            return self
        }
        
        return nil
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    // MARK: - Forward NSDraggingDestination to panel
    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return notchPanel?.draggingEntered(sender) ?? []
    }

    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return notchPanel?.draggingUpdated(sender) ?? []
    }

    public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        notchPanel?.draggingExited(sender)
    }

    public override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        return notchPanel?.prepareForDragOperation(sender) ?? false
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        return notchPanel?.performDragOperation(sender) ?? false
    }
}

/// Fixed-size non-resizing panel for the Voice.AI Notch.
/// Window size is permanently 700x560.
/// Window frame NEVER resizes or animates origin, guaranteeing 120fps stutter-free physics.
/// Acts as a native NSDraggingDestination to automatically open the Shelf when dragging items near the notch.
public final class NotchPanel: NSPanel, NSDraggingDestination {
    public static let supportedDragTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .string,
        .tiff,
        .png,
        .rtf,
        .html,
        .pdf,
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        NSPasteboard.PasteboardType("Apple pasteboard promise receiver type"),
        NSPasteboard.PasteboardType("com.apple.finder.node"),
        NSPasteboard.PasteboardType(UTType.item.identifier),
        NSPasteboard.PasteboardType(UTType.content.identifier),
        NSPasteboard.PasteboardType(UTType.data.identifier)
    ]

    /// Conditional key focus: true ONLY when user focuses the typing field.
    public var allowsKeyFocus: Bool = false
    
    /// Bounding rectangle of the visible notch content within window coordinates for strict click-through testing.
    public var visibleNotchBounds: NSRect = .zero

    /// Bounding rectangle of the notch hot-zone (within window coordinates) where dragging near notch expands the shelf.
    public var dragHotZoneBounds: NSRect = .zero
    
    /// Tracks if an active drag session is hovering over the hot-zone.
    public var isDragOverHotZone: Bool = false
    
    /// Tracks if drag tracking is active anywhere over the window.
    public var isDragActiveOverWindow: Bool = false

    /// Callbacks invoked on drag events
    public var onDragEnterHotZone: (() -> Void)?
    public var onDragExitHotZone: (() -> Void)?
    public var onPerformDrop: ((NSPasteboard) -> Bool)?

    public func isPointInDragHotZone(_ point: NSPoint) -> Bool {
        return !dragHotZoneBounds.isEmpty && dragHotZoneBounds.contains(point)
    }
    
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

        // Register for all dragged types
        registerForDraggedTypes(Self.supportedDragTypes)
    }
    
    public override var canBecomeKey: Bool {
        allowsKeyFocus
    }
    
    public override var canBecomeMain: Bool {
        false
    }

    // MARK: - NSDraggingDestination (Automatic Shelf Opening & Drop Receiving)
    public func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard ShelfStore.shared.settings.isEnabled && ShelfStore.shared.settings.autoOpenOnDragNearNotch else {
            return []
        }

        let types = sender.draggingPasteboard.types ?? []
        guard ShelfDragDetector.hasAcceptableDragPayload(types: types) || !types.isEmpty else {
            return []
        }

        isDragActiveOverWindow = true
        let point = sender.draggingLocation

        if isPointInDragHotZone(point) || visibleNotchBounds.contains(point) {
            isDragOverHotZone = true
            onDragEnterHotZone?()
            return NSEvent.modifierFlags.contains(.option) ? .move : .copy
        }
        return []
    }

    public func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard ShelfStore.shared.settings.isEnabled && ShelfStore.shared.settings.autoOpenOnDragNearNotch else {
            return []
        }

        let point = sender.draggingLocation
        if isPointInDragHotZone(point) || visibleNotchBounds.contains(point) {
            if !isDragOverHotZone {
                isDragOverHotZone = true
                onDragEnterHotZone?()
            }
            return NSEvent.modifierFlags.contains(.option) ? .move : .copy
        } else {
            if isDragOverHotZone {
                isDragOverHotZone = false
                onDragExitHotZone?()
            }
            return []
        }
    }

    public func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isDragActiveOverWindow = false
        isDragOverHotZone = false
        onDragExitHotZone?()
    }

    public func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        return true
    }

    public func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let point = sender.draggingLocation
        isDragActiveOverWindow = false
        isDragOverHotZone = false

        guard isPointInDragHotZone(point) || visibleNotchBounds.contains(point) else {
            return false
        }

        return onPerformDrop?(sender.draggingPasteboard) ?? false
    }
}
