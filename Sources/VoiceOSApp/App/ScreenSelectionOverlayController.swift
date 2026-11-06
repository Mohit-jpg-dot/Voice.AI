import AppKit
import SwiftUI
import VoiceOSCore

public final class ScreenSelectionOverlayController: NSWindowController {
    private let appState: AppState
    private var selectionTool: CircleSelectionTool = .lasso
    private var lassoPoints: [CGPoint] = []
    private var startPoint: CGPoint?
    
    public init(appState: AppState) {
        self.appState = appState
        
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = NSPanel(
            contentRect: screenRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        super.init(window: panel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func presentOverlay() {
        guard let window = self.window else { return }
        NSCursor.crosshair.push()
        window.orderFrontRegardless()
    }
    
    public func dismissOverlay() {
        NSCursor.pop()
        window?.orderOut(nil)
    }
    
    public func handleCompleteSelection(boundingBox: CGRect, points: [CGPoint], tool: CircleSelectionTool) {
        dismissOverlay()
        
        // Simulated OCR text from selected screen coordinates
        let rawOCR = "Things 3 — Project Feel Productive: Tasks review, thumbnail redesign concepts, and client timeline."
        let (cleanText, redactedCount) = RedactionRule.redactSensitiveData(from: rawOCR)
        
        let cropResult = ScreenCropResult(
            boundingBox: boundingBox,
            lassoPoints: points,
            toolUsed: tool,
            extractedOCRText: cleanText,
            accessibilityRole: "AXTable",
            redactedItemsCount: redactedCount
        )
        
        appState.completeCircleSelection(crop: cropResult)
    }
}

