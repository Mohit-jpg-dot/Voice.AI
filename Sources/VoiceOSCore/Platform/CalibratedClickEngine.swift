import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

/// Display-Scale Calibration & Window Elevation Click Engine
/// Resolves Retina point-vs-pixel coordinate mismatches and enforces safety ordering:
/// 1. Brings target window to frontmost focus layer.
/// 2. Waits for deterministic UI settle delay (150ms).
/// 3. Injects calibrated native CGEvent mouse sequences.
public final class CalibratedClickEngine: @unchecked Sendable {
    public static let shared = CalibratedClickEngine()
    
    private init() {}
    
    // MARK: - 1. Coordinate Calibration (Retina Points vs Pixels)
    
    public func calibrate(pixelPoint: CGPoint) -> CGPoint {
        let mainScreen = NSScreen.main
        let scaleFactor = mainScreen?.backingScaleFactor ?? 2.0
        let screenFrame = mainScreen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        
        // Convert Retina physical pixels to macOS logical points
        let calibratedX = pixelPoint.x / scaleFactor
        let calibratedY = pixelPoint.y / scaleFactor
        
        // Clamp to physical monitor display bounds
        let clampedX = max(0, min(screenFrame.width - 2, calibratedX))
        let clampedY = max(0, min(screenFrame.height - 2, calibratedY))
        
        return CGPoint(x: clampedX, y: clampedY)
    }
    
    // MARK: - 2. Window Elevation & Focus
    
    public func elevateWindow(targetApplication: String) async -> Bool {
        let workspace = NSWorkspace.shared
        let cleanTarget = targetApplication.lowercased().trimmingCharacters(in: .whitespaces)
        
        if let app = workspace.runningApplications.first(where: {
            $0.localizedName?.lowercased().contains(cleanTarget) == true ||
            $0.bundleIdentifier?.lowercased().contains(cleanTarget) == true
        }) {
            app.activate(options: [.activateIgnoringOtherApps])
            // Wait for macOS window server animation and focus settle
            try? await Task.sleep(nanoseconds: 160_000_000) // 160ms deterministic settle
            return true
        }
        
        // Attempt launching if not yet active
        if workspace.launchApplication(cleanTarget) {
            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms initial launch settle
            return true
        }
        
        return false
    }
    
    // MARK: - 3. Calibrated Click Execution
    
    public func click(at pixelPoint: CGPoint, targetApp: String? = nil) async throws {
        // Step 1: Elevate window if target is specified
        if let app = targetApp, !app.isEmpty {
            _ = await elevateWindow(targetApplication: app)
        }
        
        // Step 2: Calibrate Retina coordinates
        let pt = calibrate(pixelPoint: pixelPoint)
        
        // Step 3: Trigger visual click beacon ripple
        VisualCursorGuideEngine.shared.triggerClickFeedback(at: pt)
        
        // Step 4: Inject native CGEvent sequences with human-paced hold timing
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw NSError(domain: "CalibratedClickEngine", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize CGEventSource"])
        }
        
        // Mouse Move
        if let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left) {
            moveEvent.post(tap: .cghidEventTap)
        }
        try? await Task.sleep(nanoseconds: 35_000_000) // 35ms cursor position settle
        
        // Left Mouse Down
        if let downEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left) {
            downEvent.post(tap: .cghidEventTap)
        }
        try? await Task.sleep(nanoseconds: 60_000_000) // 60ms click duration
        
        // Left Mouse Up
        if let upEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left) {
            upEvent.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - 4. Keyboard Shortcuts & Keystrokes
    
    public func injectKeystroke(_ keyCombo: String) async {
        let lower = keyCombo.lowercased().trimmingCharacters(in: .whitespaces)
        var flags: CGEventFlags = []
        var keyCode: CGKeyCode = 0
        
        if lower.contains("shift") { flags.insert(.maskShift) }
        if lower.contains("command") || lower.contains("cmd") { flags.insert(.maskCommand) }
        if lower.contains("control") || lower.contains("ctrl") { flags.insert(.maskControl) }
        if lower.contains("option") || lower.contains("alt") { flags.insert(.maskAlternate) }
        
        // Key code mapping
        if lower.contains("a") { keyCode = 0 } // 'a' key
        else if lower.contains("space") { keyCode = 49 }
        else if lower.contains("return") || lower.contains("enter") { keyCode = 36 }
        else if lower.contains("tilde") || lower.contains("`") { keyCode = 50 }
        else if lower.contains("s") { keyCode = 1 }
        else { keyCode = 0 }
        
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        
        try? await Task.sleep(nanoseconds: 40_000_000)
        
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }
}

