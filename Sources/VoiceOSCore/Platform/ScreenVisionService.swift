import AppKit
import Vision
import Foundation

public struct ScreenVisionAnalysis: Sendable {
    public let fullText: String
    public let recognizedBlocks: [String]
    public let activeAppTitle: String?
    public let summary: String
    
    public init(fullText: String, recognizedBlocks: [String], activeAppTitle: String?, summary: String) {
        self.fullText = fullText
        self.recognizedBlocks = recognizedBlocks
        self.activeAppTitle = activeAppTitle
        self.summary = summary
    }
}

/// Offline, privacy-first screen vision using Apple's Vision framework (VNRecognizeTextRequest).
/// Extracts visible text from active windows and screen buffers to provide instant contextual awareness.
public final class ScreenVisionService: @unchecked Sendable {
    public static let shared = ScreenVisionService()
    
    public init() {}
    
    public func captureAndAnalyzeScreen() async -> ScreenVisionAnalysis {
        // 1. Detect frontmost user application
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Active App"
        
        // 2. Capture the main screen using CGWindowListCreateImage
        let mainDisplayID = CGMainDisplayID()
        let displayBounds = CGDisplayBounds(mainDisplayID)
        
        guard let cgImage = CGWindowListCreateImage(
            displayBounds,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            return ScreenVisionAnalysis(
                fullText: "",
                recognizedBlocks: [],
                activeAppTitle: frontApp,
                summary: "You are currently working in \(frontApp)."
            )
        }
        
        // 3. Perform offline text recognition via VNRecognizeTextRequest
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: ScreenVisionAnalysis(
                        fullText: "",
                        recognizedBlocks: [],
                        activeAppTitle: frontApp,
                        summary: "I see your active window is \(frontApp)."
                    ))
                    return
                }
                
                let recognizedStrings = observations.compactMap {
                    $0.topCandidates(1).first?.string
                }
                
                let combined = recognizedStrings.joined(separator: "\n")
                let preview = recognizedStrings.prefix(12).joined(separator: ", ")
                let summary: String
                if recognizedStrings.isEmpty {
                    summary = "Your active application is \(frontApp). No readable text was detected on the current display."
                } else {
                    summary = "You are currently viewing \(frontApp). Key content on screen: \(preview)..."
                }
                
                continuation.resume(returning: ScreenVisionAnalysis(
                    fullText: combined,
                    recognizedBlocks: recognizedStrings,
                    activeAppTitle: frontApp,
                    summary: summary
                ))
            }
            
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: ScreenVisionAnalysis(
                        fullText: "",
                        recognizedBlocks: [],
                        activeAppTitle: frontApp,
                        summary: "You are currently in \(frontApp)."
                    ))
                }
            }
        }
    }
}

