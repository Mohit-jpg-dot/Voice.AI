import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

public struct TutorialStep: Sendable {
    public let stepNumber: Int
    public let description: String
    public let targetCoordinate: CGPoint?
    public let targetElementName: String?
    public let actionType: ActionType
    
    public enum ActionType: Sendable {
        case pointAndHighlight
        case click
        case drag(to: CGPoint)
        case shortcut(keys: String)
    }
}

public struct TutorialPlan: Sendable {
    public let appName: String
    public let taskTitle: String
    public let summary: String
    public let steps: [TutorialStep]
}

/// Autonomous Screen Tutor & Visual Cursor Guide Engine
/// Steers the cursor smoothly, points an animated beacon arrow directly at target UI elements,
/// and clicks/drags autonomously to demonstrate operations in Blender, VS Code, and desktop apps.
public final class VisualCursorGuideEngine: @unchecked Sendable {
    public static let shared = VisualCursorGuideEngine()
    
    // Callbacks to UI overlay
    public var onPointerMoved: ((CGPoint, String?) -> Void)?
    public var onClickFeedbackTriggered: ((CGPoint) -> Void)?
    public var onPointerDismissRequested: (() -> Void)?
    public var onTutorialCompleted: (() -> Void)?
    
    public init() {}
    
    public func triggerClickFeedback(at point: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            self?.onClickFeedbackTriggered?(point)
        }
    }
    
    public func dismissPointer() {
        DispatchQueue.main.async { [weak self] in
            self?.onPointerDismissRequested?()
        }
    }
    
    // MARK: - App Tutorial Resolution (Blender, VS Code, macOS)
    
    public func resolveTutorial(
        query: String,
        frontmostApp: String,
        liveScreenSummary: String? = nil,
        detectedKeywords: [String] = []
    ) -> TutorialPlan {
        let lower = query.lowercased()
        let screenRect = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let midX = screenRect.midX
        let midY = screenRect.midY
        
        // 1. Blender Operations
        if lower.contains("blender") || frontmostApp.lowercased().contains("blender") {
            if lower.contains("bone") || lower.contains("hide") || lower.contains("skeleton") {
                return TutorialPlan(
                    appName: "Blender",
                    taskTitle: "Hide / Unhide Armature Bones in Blender",
                    summary: "In Blender, bone visibility is controlled in the Armature Object Data Properties tab or by selecting the bone in Pose Mode and pressing 'H'.",
                    steps: [
                        TutorialStep(
                            stepNumber: 1,
                            description: "Select the Armature in the 3D Viewport or Outliner.",
                            targetCoordinate: CGPoint(x: screenRect.maxX - 180, y: screenRect.minY + 200),
                            targetElementName: "Outliner: Armature",
                            actionType: .pointAndHighlight
                        ),
                        TutorialStep(
                            stepNumber: 2,
                            description: "Click Object Data Properties (green running man icon) in the Properties panel on the right.",
                            targetCoordinate: CGPoint(x: screenRect.maxX - 160, y: screenRect.minY + 380),
                            targetElementName: "Properties: Object Data",
                            actionType: .click
                        ),
                        TutorialStep(
                            stepNumber: 3,
                            description: "Navigate to Viewport Display and toggle Bone Visibility off, or press 'H' to hide selected bones.",
                            targetCoordinate: CGPoint(x: screenRect.maxX - 140, y: screenRect.minY + 520),
                            targetElementName: "Viewport Display: Bones Toggle",
                            actionType: .click
                        )
                    ]
                )
            }
            if lower.contains("animate") || lower.contains("keyframe") {
                return TutorialPlan(
                    appName: "Blender",
                    taskTitle: "Animate an Object with Keyframes in Blender",
                    summary: "To animate in Blender: select the object, move to the desired frame on the Timeline, press 'I' to insert a Keyframe (Location/Rotation), and change frames.",
                    steps: [
                        TutorialStep(
                            stepNumber: 1,
                            description: "Click on the 3D Viewport to select your object.",
                            targetCoordinate: CGPoint(x: midX, y: midY),
                            targetElementName: "3D Viewport Object",
                            actionType: .click
                        ),
                        TutorialStep(
                            stepNumber: 2,
                            description: "Position cursor on the bottom Timeline bar to set the initial animation frame.",
                            targetCoordinate: CGPoint(x: midX, y: screenRect.maxY - 80),
                            targetElementName: "Timeline Playhead",
                            actionType: .click
                        ),
                        TutorialStep(
                            stepNumber: 3,
                            description: "Press 'I' on your keyboard to insert a Location & Rotation keyframe.",
                            targetCoordinate: CGPoint(x: midX, y: midY),
                            targetElementName: "Insert Keyframe Menu",
                            actionType: .shortcut(keys: "I")
                        )
                    ]
                )
            }
            
            // General Blender 3D Viewport & Modeling / Visualization
            return TutorialPlan(
                appName: "Blender",
                taskTitle: "Blender 3D Viewport & Modeling Visualization",
                summary: "In Blender, select your active object in the 3D Viewport center, use the Properties panel on the right for modifiers and materials, and press Z for Viewport Shading.",
                steps: [
                    TutorialStep(
                        stepNumber: 1,
                        description: "Select the primary object in the 3D Viewport center.",
                        targetCoordinate: CGPoint(x: midX, y: midY),
                        targetElementName: "3D Viewport Center",
                        actionType: .click
                    ),
                    TutorialStep(
                        stepNumber: 2,
                        description: "Inspect Modifiers & Object Properties in the right panel.",
                        targetCoordinate: CGPoint(x: screenRect.maxX - 160, y: screenRect.minY + 360),
                        targetElementName: "Properties & Modifiers Panel",
                        actionType: .pointAndHighlight
                    ),
                    TutorialStep(
                        stepNumber: 3,
                        description: "Switch to Material Preview or Rendered Shading in the top-right viewport header.",
                        targetCoordinate: CGPoint(x: screenRect.maxX - 240, y: screenRect.minY + 110),
                        targetElementName: "Viewport Shading Controls",
                        actionType: .click
                    )
                ]
            )
        }
        
        // 2. VS Code Operations
        if lower.contains("vscode") || lower.contains("code") || frontmostApp.lowercased().contains("code") {
            if lower.contains("new file") || lower.contains("java") || lower.contains("create") {
                return TutorialPlan(
                    appName: "Visual Studio Code",
                    taskTitle: "Create and Configure a New File in VS Code",
                    summary: "Creating a new file in VS Code via File menu or ⌘N, then saving with appropriate file extension.",
                    steps: [
                        TutorialStep(
                            stepNumber: 1,
                            description: "Click File in the menu bar.",
                            targetCoordinate: CGPoint(x: 120, y: 14),
                            targetElementName: "Menu Bar: File",
                            actionType: .click
                        ),
                        TutorialStep(
                            stepNumber: 2,
                            description: "Click 'New File...' or press ⌘N.",
                            targetCoordinate: CGPoint(x: 140, y: 40),
                            targetElementName: "New File",
                            actionType: .click
                        ),
                        TutorialStep(
                            stepNumber: 3,
                            description: "Select file type or type file name.",
                            targetCoordinate: CGPoint(x: midX, y: 120),
                            targetElementName: "File Input QuickPick",
                            actionType: .pointAndHighlight
                        )
                    ]
                )
            }
        }
        
        // 3. Live Screen-Aware Guidance
        let effectiveApp = frontmostApp.isEmpty || frontmostApp.lowercased().contains("voice") ? "macOS" : frontmostApp
        let summaryText: String
        if let liveSummary = liveScreenSummary, !liveSummary.isEmpty {
            summaryText = "Based on your screen in \(effectiveApp): \(liveSummary)"
        } else {
            summaryText = "Looking at your active screen in \(effectiveApp). Here is how to complete this action step-by-step."
        }
        
        return TutorialPlan(
            appName: effectiveApp,
            taskTitle: "Live Screen Step-by-Step Guidance",
            summary: summaryText,
            steps: [
                TutorialStep(
                    stepNumber: 1,
                    description: "Focus on the primary control area in \(effectiveApp).",
                    targetCoordinate: CGPoint(x: midX, y: midY - 100),
                    targetElementName: "Active Workspace",
                    actionType: .pointAndHighlight
                ),
                TutorialStep(
                    stepNumber: 2,
                    description: "Execute the action using the recommended toolbar control.",
                    targetCoordinate: CGPoint(x: midX, y: midY),
                    targetElementName: "Target Action Element",
                    actionType: .click
                )
            ]
        )
    }
    
    // MARK: - Autonomous Cursor Steering & Action Execution
    
    /// Smoothly moves cursor across screen using bezier curve interpolation, warps hardware cursor and posts CGEvent
    public func moveCursorSmoothly(to destination: CGPoint, duration: TimeInterval = 0.4) async {
        let currentPos = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 900
        let startPoint = CGPoint(x: currentPos.x, y: screenHeight - currentPos.y)
        let steps = 25
        let delayPerStep = duration / Double(steps)
        
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            // Ease-in-out curve
            let easedT = t < 0.5 ? 2.0 * t * t : -1.0 + (4.0 - 2.0 * t) * t
            let x = startPoint.x + (destination.x - startPoint.x) * CGFloat(easedT)
            let y = startPoint.y + (destination.y - startPoint.y) * CGFloat(easedT)
            let point = CGPoint(x: x, y: y)
            
            // Physically warp macOS hardware mouse cursor position
            CGWarpMouseCursorPosition(point)
            
            // Post event to move cursor physically
            if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
                moveEvent.post(tap: .cghidEventTap)
            }
            
            // Notify UI overlay to position glowing beacon
            DispatchQueue.main.async { [weak self] in
                self?.onPointerMoved?(point, nil)
            }
            
            try? await Task.sleep(nanoseconds: UInt64(delayPerStep * 1_000_000_000))
        }
    }
    
    /// Autonomously executes a tutorial step: steering cursor, pointing arrow, and clicking
    public func executeStep(_ step: TutorialStep) async {
        if let target = step.targetCoordinate {
            // 1. Move cursor smoothly to target
            await moveCursorSmoothly(to: target, duration: 0.4)
            
            // 2. Perform action
            switch step.actionType {
            case .click:
                _ = AccessibilityControlEngine.shared.postClick(at: target)
                triggerClickFeedback(at: target)
                try? await Task.sleep(nanoseconds: 250_000_000)
                dismissPointer()
            case .drag(let destination):
                // Mouse down at start
                if let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: target, mouseButton: .left) {
                    down.setIntegerValueField(.mouseEventClickState, value: 1)
                    down.post(tap: .cghidEventTap)
                }
                await moveCursorSmoothly(to: destination, duration: 0.5)
                // Mouse up at destination
                if let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: destination, mouseButton: .left) {
                    up.setIntegerValueField(.mouseEventClickState, value: 1)
                    up.post(tap: .cghidEventTap)
                }
                triggerClickFeedback(at: destination)
                try? await Task.sleep(nanoseconds: 250_000_000)
                dismissPointer()
            case .pointAndHighlight:
                try? await Task.sleep(nanoseconds: 800_000_000)
                dismissPointer()
            case .shortcut:
                try? await Task.sleep(nanoseconds: 300_000_000)
                dismissPointer()
            }
        }
    }
    
    /// Guides the entire tutorial plan sequentially with speech & visual pointers
    public func guideThroughPlan(_ plan: TutorialPlan, onStepNarrated: @escaping (String) -> Void) async {
        for step in plan.steps {
            let stepText = "Step \(step.stepNumber): \(step.description)"
            onStepNarrated(stepText)
            await executeStep(step)
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        DispatchQueue.main.async { [weak self] in
            self?.onTutorialCompleted?()
        }
    }
}

