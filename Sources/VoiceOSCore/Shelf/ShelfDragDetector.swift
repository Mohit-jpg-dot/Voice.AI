import Foundation
import AppKit

public final class ShelfDragDetector: @unchecked Sendable {
    public static let shared = ShelfDragDetector()

    private let lock = NSLock()
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var isDraggingActive: Bool = false
    public private(set) var isMonitoring: Bool = false
    public var onDragNearNotch: (@Sendable (NSScreen) -> Void)?

    public init() {}

    // MARK: - Hot Zone Geometry Computation (Clean, Deterministic, Multi-Display)
    public static func hotZone(for screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let hasPhysicalNotch = screen.safeAreaInsets.top > 20.0

        if hasPhysicalNotch {
            let notchWidth: CGFloat
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                notchWidth = frame.width - left.width - right.width + 4.0
            } else {
                notchWidth = 185.0
            }
            let notchHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 32.0

            // Hot zone extends 50pt to each side and 30pt downwards into screen
            let zoneWidth = notchWidth + 100.0
            let zoneHeight = notchHeight + 35.0
            let zoneX = frame.origin.x + (frame.width - zoneWidth) / 2.0
            let zoneY = frame.origin.y + frame.height - zoneHeight

            return CGRect(x: zoneX, y: zoneY, width: zoneWidth, height: zoneHeight)
        } else {
            // Notch-less display: top-center strip
            let zoneWidth: CGFloat = 260.0
            let zoneHeight: CGFloat = 42.0
            let zoneX = frame.origin.x + (frame.width - zoneWidth) / 2.0
            let zoneY = frame.origin.y + frame.height - zoneHeight

            return CGRect(x: zoneX, y: zoneY, width: zoneWidth, height: zoneHeight)
        }
    }

    public static func isPointInHotZone(_ point: CGPoint, screen: NSScreen) -> Bool {
        let zone = hotZone(for: screen)
        return zone.contains(point)
    }

    public static func targetScreen(for point: CGPoint) -> NSScreen? {
        return NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    }

    // MARK: - Drag Pasteboard Type Evaluation
    public static func hasAcceptableDragPayload(types: [NSPasteboard.PasteboardType]) -> Bool {
        let acceptable: Set<NSPasteboard.PasteboardType> = [
            .fileURL,
            .URL,
            .string,
            .tiff,
            .png,
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
            NSPasteboard.PasteboardType("Apple pasteboard promise receiver type")
        ]
        return types.contains(where: { acceptable.contains($0) })
    }

    public static func currentDragPasteboardHasAcceptablePayload() -> Bool {
        let pb = NSPasteboard(name: .drag)
        guard let types = pb.types, !types.isEmpty else { return false }
        return hasAcceptableDragPayload(types: types)
    }

    // MARK: - Global Drag Monitor (Zero CPU when idle)
    public func startMonitoring() {
        lock.lock()
        defer { lock.unlock() }

        guard !isMonitoring else { return }
        isMonitoring = true

        // 1. Global monitor: Only wakes when left mouse is dragging across the screen
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
        }

        // 2. Local monitor: For drags originating within the app itself
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
    }

    public func stopMonitoring() {
        lock.lock()
        defer { lock.unlock() }

        if let m = globalMouseMonitor {
            NSEvent.removeMonitor(m)
            globalMouseMonitor = nil
        }
        if let m = localMouseMonitor {
            NSEvent.removeMonitor(m)
            localMouseMonitor = nil
        }
        isMonitoring = false
        isDraggingActive = false
    }

    private func handleMouseEvent(_ event: NSEvent) {
        if event.type == .leftMouseUp {
            isDraggingActive = false
            return
        }

        guard event.type == .leftMouseDragged else { return }

        // Fast rejection: If no items on drag pasteboard, do nothing (zero extra cost)
        guard Self.currentDragPasteboardHasAcceptablePayload() else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = Self.targetScreen(for: mouseLocation) else { return }

        if Self.isPointInHotZone(mouseLocation, screen: screen) {
            if !isDraggingActive {
                isDraggingActive = true
                onDragNearNotch?(screen)
            }
        }
    }
}

