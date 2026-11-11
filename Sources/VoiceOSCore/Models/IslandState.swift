import Foundation
import CoreGraphics

public enum IslandPresentationState: Equatable, Sendable {
    case resting // attached to notch, minimal state indicator
    case hoverExpanded // expanded due to pointer hover
    case voiceCompact(VoiceTriggerMode) // compact transcription state
    case approvalExpanded(AgentAction) // auto-expanded for action confirmation
    case circleToAskActive // selection overlay active on screen
    case selectionReview(ScreenCropResult) // showing selected crop in island
    case pinned // pinned open by user
}

public enum CircleSelectionTool: String, CaseIterable, Codable, Sendable {
    case lasso = "Freehand Lasso"
    case rectangle = "Drag Rectangle"
    case elementSnap = "Element Snap"
    case fullWindow = "Whole Window"
}

public struct ScreenCropResult: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let boundingBox: CGRect
    public let lassoPoints: [CGPoint]
    public let toolUsed: CircleSelectionTool
    public let extractedOCRText: String
    public let accessibilityRole: String?
    public let redactedItemsCount: Int
    public let capturedImagePNGData: Data?
    public let sourceAppName: String?
    public let timestamp: Date
    
    public init(
        id: UUID = UUID(),
        boundingBox: CGRect,
        lassoPoints: [CGPoint] = [],
        toolUsed: CircleSelectionTool = .lasso,
        extractedOCRText: String,
        accessibilityRole: String? = nil,
        redactedItemsCount: Int = 0,
        capturedImagePNGData: Data? = nil,
        sourceAppName: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.lassoPoints = lassoPoints
        self.toolUsed = toolUsed
        self.extractedOCRText = extractedOCRText
        self.accessibilityRole = accessibilityRole
        self.redactedItemsCount = redactedItemsCount
        self.capturedImagePNGData = capturedImagePNGData
        self.sourceAppName = sourceAppName
        self.timestamp = timestamp
    }
}

public struct RedactionRule: Sendable {
    public static func redactSensitiveData(from text: String) -> (cleanText: String, count: Int) {
        var count = 0
        var result = text
        
        // Regex patterns for API keys, passwords, credit card numbers
        let patterns: [(regex: String, replacement: String)] = [
            (#"sk-[a-zA-Z0-9]{32,}"#, "[REDACTED_API_KEY]"),
            (#"ghp_[a-zA-Z0-9]{36}"#, "[REDACTED_GITHUB_TOKEN]"),
            (#"\b(?:\d{4}[-\s]?){3}\d{4}\b"#, "[REDACTED_CARD_NUMBER]"),
            (#"(?i)(password|secret|passwd|token)\s*[:=]\s*['"]?[^\s'"]{4,}['"]?"#, "$1: [REDACTED_SECRET]")
        ]
        
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p.regex) {
                let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
                if !matches.isEmpty {
                    count += matches.count
                    result = regex.stringByReplacingMatches(
                        in: result,
                        range: NSRange(result.startIndex..., in: result),
                        withTemplate: p.replacement
                    )
                }
            }
        }
        
        return (result, count)
    }
}

public struct BrainSuggestion: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let prompt: String
    public let isAction: Bool

    public init(id: UUID = UUID(), title: String, prompt: String, isAction: Bool = false) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.isAction = isAction
    }
}

