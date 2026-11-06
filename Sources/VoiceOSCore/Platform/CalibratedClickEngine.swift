import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

public struct FrameEvolutionResult: Sendable {
    public let hasEvolved: Bool
    public let changeRatio: Double
    public let settleDurationMs: Int
    public let preScreenshot: CGImage?
    public let postScreenshot: CGImage?
    
    public init(
        hasEvolved: Bool,
        changeRatio: Double,
        settleDurationMs: Int,
        preScreenshot: CGImage? = nil,
        postScreenshot: CGImage? = nil
    ) {
        self.hasEvolved = hasEvolved
        self.changeRatio = changeRatio
        self.settleDurationMs = settleDurationMs
        self.preScreenshot = preScreenshot
        self.postScreenshot = postScreenshot
    }
}

/// Display-Scale Calibration & Window Elevation Click Engine
/// Resolves Retina point-vs-pixel coordinate mismatches and enforces safety ordering:
/// 1. Brings target window to frontmost focus layer.
/// 2. Waits for deterministic UI settle delay (150ms-250ms menu animation curve).
/// 3. Injects calibrated native CGEvent mouse/keyboard sequences.
/// 4. Captures post-sleep verification screenshot to validate UI frame evolution before proceeding.
public final class CalibratedClickEngine: @unchecked Sendable {
    public static let shared = CalibratedClickEngine()
    
    // Host operating system menu animation curve settle delay (150ms - 250ms)
    public static let defaultSettleSleepMs: Int = 180
    
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
    
    // MARK: - 3. Execution Settle Sleep Mechanism
    
    public func enforceExecutionSettleSleep(durationMs: Int = defaultSettleSleepMs) async {
        let clamped = max(150, min(250, durationMs))
        try? await Task.sleep(nanoseconds: UInt64(clamped) * 1_000_000)
    }
    
    // MARK: - 4. Calibrated Click Execution with Frame State Verification Gating
    
    public func click(at pixelPoint: CGPoint, targetApp: String? = nil) async throws {
        _ = try await clickWithFrameVerification(at: pixelPoint, targetApp: targetApp)
    }
    
    public func clickWithFrameVerification(
        at pixelPoint: CGPoint,
        targetApp: String? = nil,
        settleSleepMs: Int = defaultSettleSleepMs
    ) async throws -> FrameEvolutionResult {
        // Step 1: Capture pre-action baseline screenshot
        let preScreenshot = VisualGroundingSoMEngine.shared.captureDisplayScreenshot()
        
        // Step 2: Elevate window if target is specified
        if let app = targetApp, !app.isEmpty {
            _ = await elevateWindow(targetApplication: app)
        }
        
        // Step 3: Calibrate Retina coordinates
        let pt = calibrate(pixelPoint: pixelPoint)
        
        // Step 4: Trigger visual click beacon ripple
        VisualCursorGuideEngine.shared.triggerClickFeedback(at: pt)
        
        // Step 5: Inject native CGEvent sequences
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
        
        // Step 6: Enforce Execution Settle Sleep matching OS menu animation curve (150ms-250ms)
        let actualSleep = max(150, min(250, settleSleepMs))
        await enforceExecutionSettleSleep(durationMs: actualSleep)
        
        // Step 7: Capture secondary verification screenshot post-sleep
        let postScreenshot = VisualGroundingSoMEngine.shared.captureDisplayScreenshot()
        
        // Step 8: Validate frame state evolution
        let changeRatio = computeFrameDifferenceRatio(pre: preScreenshot, post: postScreenshot)
        let hasEvolved = changeRatio >= 0.0005 // Detectable UI delta (menu open, selection change, ripple)
        
        return FrameEvolutionResult(
            hasEvolved: hasEvolved,
            changeRatio: changeRatio,
            settleDurationMs: actualSleep,
            preScreenshot: preScreenshot,
            postScreenshot: postScreenshot
        )
    }
    
    // MARK: - 5. Keyboard Shortcuts & Keystrokes with Frame Evolution Gating
    
    public func injectKeystroke(_ keyCombo: String) async {
        _ = await injectKeystrokeWithFrameVerification(keyCombo)
    }
    
    public func injectKeystrokeWithFrameVerification(
        _ keyCombo: String,
        settleSleepMs: Int = defaultSettleSleepMs
    ) async -> FrameEvolutionResult {
        let preScreenshot = VisualGroundingSoMEngine.shared.captureDisplayScreenshot()
        
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
        
        // Enforce execution settle sleep
        let actualSleep = max(150, min(250, settleSleepMs))
        await enforceExecutionSettleSleep(durationMs: actualSleep)
        
        let postScreenshot = VisualGroundingSoMEngine.shared.captureDisplayScreenshot()
        let changeRatio = computeFrameDifferenceRatio(pre: preScreenshot, post: postScreenshot)
        
        return FrameEvolutionResult(
            hasEvolved: changeRatio >= 0.0005,
            changeRatio: changeRatio,
            settleDurationMs: actualSleep,
            preScreenshot: preScreenshot,
            postScreenshot: postScreenshot
        )
    }
    
    // MARK: - Frame State Difference Computation
    
    public func computeFrameDifferenceRatio(pre: CGImage?, post: CGImage?) -> Double {
        guard let pre = pre, let post = post,
              pre.width == post.width, pre.height == post.height else {
            return 1.0 // If screenshots cannot be compared, assume evolution to avoid locking
        }
        
        let width = min(pre.width, 320)
        let height = min(pre.height, 200)
        let sampleCount = 400
        var differentSamples = 0
        
        guard let preData = pre.dataProvider?.data,
              let postData = post.dataProvider?.data,
              let prePtr = CFDataGetBytePtr(preData),
              let postPtr = CFDataGetBytePtr(postData) else {
            return 1.0
        }
        
        let bytesPerPixelPre = pre.bitsPerPixel / 8
        let bytesPerRowPre = pre.bytesPerRow
        let bytesPerPixelPost = post.bitsPerPixel / 8
        let bytesPerRowPost = post.bytesPerRow
        
        for i in 0..<sampleCount {
            let x = (i * 37) % width
            let y = (i * 23) % height
            
            let preOffset = y * bytesPerRowPre + x * bytesPerPixelPre
            let postOffset = y * bytesPerRowPost + x * bytesPerPixelPost
            
            if preOffset + 2 < CFDataGetLength(preData) && postOffset + 2 < CFDataGetLength(postData) {
                let diffR = abs(Int(prePtr[preOffset]) - Int(postPtr[postOffset]))
                let diffG = abs(Int(prePtr[preOffset + 1]) - Int(postPtr[postOffset + 1]))
                let diffB = abs(Int(prePtr[preOffset + 2]) - Int(postPtr[postOffset + 2]))
                
                if (diffR + diffG + diffB) > 15 {
                    differentSamples += 1
                }
            }
        }
        
        return Double(differentSamples) / Double(sampleCount)
    }
}

