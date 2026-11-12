import AppKit
@preconcurrency import ScreenCaptureKit
import Vision
import Foundation

public struct ScreenTextElement: Codable, Sendable, Equatable {
    public let text: String
    public let centerX: Double   // Normalized 0.0...1.0 (left -> right)
    public let centerY: Double   // Normalized 0.0...1.0 (top -> bottom)
    public let width: Double
    public let height: Double

    public init(text: String, centerX: Double, centerY: Double, width: Double = 0, height: Double = 0) {
        self.text = text
        self.centerX = centerX
        self.centerY = centerY
        self.width = width
        self.height = height
    }
}

public struct ScreenVisionAnalysis: Sendable {
    public let fullText: String
    public let recognizedBlocks: [String]
    public let recognizedElements: [ScreenTextElement]
    public let activeAppTitle: String?
    public let summary: String
    
    public init(
        fullText: String,
        recognizedBlocks: [String],
        recognizedElements: [ScreenTextElement] = [],
        activeAppTitle: String?,
        summary: String
    ) {
        self.fullText = fullText
        self.recognizedBlocks = recognizedBlocks
        self.recognizedElements = recognizedElements
        self.activeAppTitle = activeAppTitle
        self.summary = summary
    }
}

/// Offline, privacy-first screen vision using Apple's Vision framework (VNRecognizeTextRequest).
/// Extracts visible text from active windows and screen buffers to provide instant contextual awareness.
public final class ScreenVisionService: @unchecked Sendable {
    public static let shared = ScreenVisionService()
    
    public init() {}
    
    public func captureRegionAndAnalyze(globalAppKitRect: CGRect, activeAppName: String? = nil) async -> (analysis: ScreenVisionAnalysis, pngData: Data?) {
        let frontApp = activeAppName ?? NSWorkspace.shared.frontmostApplication?.localizedName ?? "Active App"
        let isTestEnv = ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1"
        if !isTestEnv && !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            let permMsg = "Screen Recording permission is required to read open windows in \(frontApp) (without it, macOS only exposes the desktop wallpaper). Enable Voice.AI in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen Voice.AI."
            return (
                ScreenVisionAnalysis(fullText: "", recognizedBlocks: [], activeAppTitle: frontApp, summary: permMsg),
                nil
            )
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? (NSScreen.main?.frame.height ?? 900)
        let cgRect = CGRect(
            x: globalAppKitRect.origin.x,
            y: primaryHeight - globalAppKitRect.origin.y - globalAppKitRect.height,
            width: max(1, globalAppKitRect.width),
            height: max(1, globalAppKitRect.height)
        )

        var capturedImage: CGImage?
        if #available(macOS 14.0, *) {
            if let fullDisplayImg = await captureViaScreenCaptureKit(target: "screen", sourceRect: cgRect) {
                capturedImage = fullDisplayImg
            }
        }
        if capturedImage == nil {
            capturedImage = CGWindowListCreateImage(
                cgRect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            )
        }

        guard let cgImage = capturedImage else {
            let fallback = ScreenVisionAnalysis(
                fullText: "",
                recognizedBlocks: [],
                activeAppTitle: frontApp,
                summary: "Selected region in \(frontApp) could not be captured. Please ensure Screen Recording permission is granted in System Settings."
            )
            return (fallback, nil)
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let pngData = bitmapRep.representation(using: .png, properties: [:])
        
        let analysis = await recognizeText(
            in: cgImage,
            frontApp: frontApp,
            recognitionLevel: .accurate,
            emptySummary: "Captured visual region from \(frontApp) (\(Int(globalAppKitRect.width))×\(Int(globalAppKitRect.height)) px).",
            populatedPrefix: "Captured from \(frontApp): ",
            errorSummary: "Captured region in \(frontApp)."
        )
        
        return (analysis, pngData)
    }

    public func captureAndAnalyzeScreen() async -> ScreenVisionAnalysis {
        return await captureFullScreenWithImage().analysis
    }

    /// Captures the active display or frontmost opened application window using ScreenCaptureKit (macOS 14+)
    /// so opened windows and current apps are always included rather than only desktop wallpaper.
    public func captureWindowOrScreenPNG(target: String = "screen") async -> (pngData: Data?, cgImage: CGImage?, appName: String, hasScreenPermission: Bool) {
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Active App"
        let isTestEnv = ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1"
        if !isTestEnv && !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            return (nil, nil, frontApp, false)
        }

        var cgImage: CGImage?
        if #available(macOS 14.0, *) {
            cgImage = await captureViaScreenCaptureKit(target: target, sourceRect: nil)
        }
        if cgImage == nil {
            let displayBounds = activeScreenDisplayBounds()
            cgImage = CGWindowListCreateImage(
                displayBounds,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            )
        }
        guard let image = cgImage else {
            return (nil, nil, frontApp, true)
        }
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        return (png, image, frontApp, true)
    }

    private func activeScreenDisplayBounds() -> CGRect {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let frontPID = frontPID,
           let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in list {
                let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
                guard ownerPID == frontPID, layer == 0,
                      let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                      let winRect = CGRect(dictionaryRepresentation: boundsDict),
                      winRect.width > 80 && winRect.height > 80 else { continue }
                for screen in NSScreen.screens {
                    if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                        let bounds = CGDisplayBounds(num.uint32Value)
                        if bounds.intersects(winRect) {
                            return bounds
                        }
                    }
                }
            }
        }
        return CGDisplayBounds(CGMainDisplayID())
    }

    @available(macOS 14.0, *)
    private func captureViaScreenCaptureKit(target: String, sourceRect: CGRect?) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let myPID = ProcessInfo.processInfo.processIdentifier
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let selfApps = content.applications.filter { $0.processID == myPID }

            let frontWindow: SCWindow? = content.windows.first { win in
                win.windowLayer == 0 &&
                win.isOnScreen &&
                win.frame.width > 120 &&
                win.frame.height > 120 &&
                win.owningApplication?.processID != myPID &&
                (frontPID == nil || win.owningApplication?.processID == frontPID)
            } ?? content.windows.first { win in
                win.windowLayer == 0 &&
                win.isOnScreen &&
                win.frame.width > 120 &&
                win.frame.height > 120 &&
                win.owningApplication?.processID != myPID &&
                win.owningApplication?.bundleIdentifier != "com.apple.finder"
            }

            if target == "window", sourceRect == nil, let win = frontWindow {
                let filter = SCContentFilter(desktopIndependentWindow: win)
                let cfg = SCStreamConfiguration()
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                cfg.width = max(1, Int(win.frame.width * scale))
                cfg.height = max(1, Int(win.frame.height * scale))
                cfg.showsCursor = false
                return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            }

            let targetDisplay: SCDisplay? = {
                if let win = frontWindow {
                    return content.displays.first(where: { $0.frame.intersects(win.frame) })
                }
                return content.displays.first
            }()
            guard let display = targetDisplay else { return nil }

            let filter = SCContentFilter(display: display, excludingApplications: selfApps, exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            if let rect = sourceRect, rect.width > 4, rect.height > 4 {
                cfg.sourceRect = CGRect(
                    x: rect.origin.x - display.frame.origin.x,
                    y: rect.origin.y - display.frame.origin.y,
                    width: rect.width,
                    height: rect.height
                )
                cfg.width = max(1, Int(rect.width * scale))
                cfg.height = max(1, Int(rect.height * scale))
            } else {
                cfg.width = max(1, Int(CGFloat(display.width) * scale))
                cfg.height = max(1, Int(CGFloat(display.height) * scale))
            }
            cfg.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        } catch {
            NSLog("[ScreenVisionService] ScreenCaptureKit fallback: %@", error.localizedDescription)
            return nil
        }
    }

    /// Captures the active display (including all opened windows & current app) along with PNG image data and Apple Vision OCR.
    public func captureFullScreenWithImage() async -> (analysis: ScreenVisionAnalysis, pngData: Data?) {
        let capture = await captureWindowOrScreenPNG(target: "screen")
        let frontApp = capture.appName
        if !capture.hasScreenPermission {
            let permMsg = "Screen Recording permission is required for Voice.AI to see your open windows (currently macOS hides windows and only shows your desktop wallpaper). Enable Voice.AI in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen Voice.AI."
            return (
                ScreenVisionAnalysis(fullText: "", recognizedBlocks: [], activeAppTitle: frontApp, summary: permMsg),
                nil
            )
        }
        guard let cgImage = capture.cgImage else {
            let fallback = ScreenVisionAnalysis(
                fullText: "",
                recognizedBlocks: [],
                activeAppTitle: frontApp,
                summary: "You are currently working in \(frontApp)."
            )
            return (fallback, nil)
        }

        let pngData = capture.pngData
        let analysis = await recognizeText(
            in: cgImage,
            frontApp: frontApp,
            recognitionLevel: .accurate,
            emptySummary: "Your active application is \(frontApp). No readable text was detected on the current display.",
            populatedPrefix: "You are currently viewing \(frontApp). Key content on screen: ",
            errorSummary: "I see your active window is \(frontApp)."
        )
        return (analysis, pngData)
    }

    private func recognizeText(
        in cgImage: CGImage,
        frontApp: String,
        recognitionLevel: VNRequestTextRecognitionLevel,
        emptySummary: String,
        populatedPrefix: String,
        errorSummary: String
    ) async -> ScreenVisionAnalysis {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: ScreenVisionAnalysis(
                        fullText: "",
                        recognizedBlocks: [],
                        activeAppTitle: frontApp,
                        summary: errorSummary
                    ))
                    return
                }
                
                var recognizedStrings: [String] = []
                var recognizedElements: [ScreenTextElement] = []
                recognizedStrings.reserveCapacity(observations.count)
                recognizedElements.reserveCapacity(observations.count)
                for obs in observations {
                    guard let candidate = obs.topCandidates(1).first else { continue }
                    let str = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !str.isEmpty else { continue }
                    recognizedStrings.append(str)
                    let box = obs.boundingBox
                    // Vision origin is bottom-left; flip Y to match top-down CGDisplay normalized space.
                    recognizedElements.append(ScreenTextElement(
                        text: str,
                        centerX: Double(box.midX),
                        centerY: Double(1.0 - box.midY),
                        width: Double(box.width),
                        height: Double(box.height)
                    ))
                }
                let combined = recognizedStrings.joined(separator: "\n")
                let preview = recognizedStrings.prefix(12).joined(separator: ", ")
                let summary = recognizedStrings.isEmpty ? emptySummary : "\(populatedPrefix)\(preview)"
                
                continuation.resume(returning: ScreenVisionAnalysis(
                    fullText: combined,
                    recognizedBlocks: recognizedStrings,
                    recognizedElements: recognizedElements,
                    activeAppTitle: frontApp,
                    summary: summary
                ))
            }
            
            request.recognitionLevel = recognitionLevel
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
                        summary: errorSummary
                    ))
                }
            }
        }
    }

    // MARK: - Phase 2 Vision-Language Screen Understanding (VLM + On-Device OCR)

    public struct ScreenVisionQuestionResult: Sendable, Equatable {
        public let answer: String
        public let targetButtonLabel: String?
        public let suggestedActionPrompt: String?
        public let usedVLM: Bool
        public let providerLabel: String
        public let privacyBadge: String

        public init(
            answer: String,
            targetButtonLabel: String? = nil,
            suggestedActionPrompt: String? = nil,
            usedVLM: Bool,
            providerLabel: String,
            privacyBadge: String
        ) {
            self.answer = answer
            self.targetButtonLabel = targetButtonLabel
            self.suggestedActionPrompt = suggestedActionPrompt
            self.usedVLM = usedVLM
            self.providerLabel = providerLabel
            self.privacyBadge = privacyBadge
        }
    }

    public func understandScreenQuestion(
        pngData: Data?,
        ocrText: String,
        appName: String,
        question: String,
        allowCloudOptIn: Bool? = nil
    ) async -> ScreenVisionQuestionResult {
        let safeOCR = SecretRedactor.redact(ocrText).trimmingCharacters(in: .whitespacesAndNewlines)
        let qClean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveQuestion = qClean.isEmpty ? "Explain what is visible on screen." : qClean
        let lowerQ = effectiveQuestion.lowercased()

        let mode = ModelRouter.shared.currentMode
        let cloudConsent = allowCloudOptIn ?? ModelRouter.shared.hasUserConsentedToCloudUpload
        let canUseVLM: Bool = {
            switch mode {
            case .googleSearch:
                return false
            case .local:
                return true
            case .cloud:
                return true
            case .hybrid:
                return cloudConsent || OllamaProvider.shared.isInstalledAndRunning
            }
        }()

        let isCloudVision = (mode == .cloud || (mode == .hybrid && cloudConsent && !OllamaProvider.shared.isInstalledAndRunning))
        let privacyBadge = isCloudVision ? "Cloud VLM (Opt-in)" : "On-Device Private"

        // 1. Attempt Vision-Language Model when permitted and not in dry-run test mode
        let env = ProcessInfo.processInfo.environment
        if canUseVLM,
           env["VOICE_AI_TEST_MODE"] != "1",
           let pngData = pngData,
           let nsImage = NSImage(data: pngData),
           let visionModel = try? ModelRouter.shared.resolveVisionModel() {
            let vlmPrompt = """
            Inspect this captured region from \(appName).
            OCR extracted text:
            \(safeOCR.isEmpty ? "(none)" : String(safeOCR.prefix(1200)))

            Question: \(effectiveQuestion)
            If asking which button to click, explicitly name the exact visible button label and why.
            If asking what an error means, explain the root cause and concrete fix in 2-3 sentences.
            """
            if let resp = try? await visionModel.analyzeImage(image: nsImage, prompt: vlmPrompt, tools: nil) {
                let text = SecretRedactor.redact(resp.text).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    let button = Self.extractLikelyButton(from: "\(text)\n\(safeOCR)")
                    return ScreenVisionQuestionResult(
                        answer: text,
                        targetButtonLabel: button,
                        suggestedActionPrompt: button.map { "Click '\($0)'" },
                        usedVLM: true,
                        providerLabel: "\(visionModel.providerName) (\(visionModel.modelIdentifier))",
                        privacyBadge: privacyBadge
                    )
                }
            }
        }

        // 2. Deterministic On-Device OCR + UI Heuristic Diagnostic Fallback
        return Self.diagnoseFromOCRAndQuestion(
            safeOCR: safeOCR,
            appName: appName,
            questionLower: lowerQ,
            privacyBadge: privacyBadge
        )
    }

    public static func diagnoseFromOCRAndQuestion(
        safeOCR: String,
        appName: String,
        questionLower: String,
        privacyBadge: String = "On-Device Private"
    ) -> ScreenVisionQuestionResult {
        let likelyButton = extractLikelyButton(from: safeOCR)
        let isErrorQuery = questionLower.contains("error") || questionLower.contains("fail") ||
            questionLower.contains("exception") || questionLower.contains("crash") || questionLower.contains("kya galat")
        let isButtonQuery = questionLower.contains("which button") || questionLower.contains("what button") ||
            questionLower.contains("click") || questionLower.contains("dabau") || questionLower.contains("press")

        if isButtonQuery {
            if let btn = likelyButton {
                return ScreenVisionQuestionResult(
                    answer: "Recommended button in \(appName): click **\(btn)** — it is the primary actionable control visible in this selection.",
                    targetButtonLabel: btn,
                    suggestedActionPrompt: "Click '\(btn)'",
                    usedVLM: false,
                    providerLabel: "Apple Vision OCR + UI Heuristic",
                    privacyBadge: privacyBadge
                )
            }
            return ScreenVisionQuestionResult(
                answer: safeOCR.isEmpty
                    ? "No clickable button text was detected in the selected \(appName) region. Try circling the toolbar or dialog footer."
                    : "Detected text in \(appName): \(safeOCR.prefix(240)). Specify the button label you'd like clicked.",
                targetButtonLabel: nil,
                suggestedActionPrompt: nil,
                usedVLM: false,
                providerLabel: "Apple Vision OCR",
                privacyBadge: privacyBadge
            )
        }

        if isErrorQuery {
            let errSnippet = extractErrorDiagnosis(from: safeOCR)
            return ScreenVisionQuestionResult(
                answer: errSnippet,
                targetButtonLabel: likelyButton,
                suggestedActionPrompt: likelyButton.map { "Click '\($0)'" },
                usedVLM: false,
                providerLabel: "Apple Vision OCR Diagnostic",
                privacyBadge: privacyBadge
            )
        }

        let summary = safeOCR.isEmpty
            ? "Visual region captured from \(appName). Enable Ollama VLM or Cloud Opt-in Vision in Settings for pixel-level inspection."
            : "Captured from \(appName): \(safeOCR.prefix(380))"
        return ScreenVisionQuestionResult(
            answer: summary,
            targetButtonLabel: likelyButton,
            suggestedActionPrompt: likelyButton.map { "Click '\($0)'" },
            usedVLM: false,
            providerLabel: "Apple Vision OCR",
            privacyBadge: privacyBadge
        )
    }

    public static func extractLikelyButton(from text: String) -> String? {
        let candidates = [
            "Retry", "Continue", "Approve", "Allow", "Save", "Submit", "Install",
            "Update", "Rebuild", "Run", "Confirm", "Apply", "Open", "Fix", "Next", "Done", "OK"
        ]
        let lower = text.lowercased()
        for label in candidates {
            if lower.range(of: "\\b\(label.lowercased())\\b", options: .regularExpression) != nil {
                return label
            }
        }
        return nil
    }

    private static func extractErrorDiagnosis(from ocr: String) -> String {
        guard !ocr.isEmpty else {
            return "No error text was captured in this selection. Re-circle around the red banner or terminal stack trace."
        }
        let lower = ocr.lowercased()
        if lower.contains("permission") || lower.contains("eperm") || lower.contains("not permitted") || lower.contains("eacces") {
            return "Error Diagnosis: Permission denied (`\(ocr.prefix(140))`). Grant the required macOS Accessibility/Sandbox/File permission or check file ownership."
        }
        if lower.contains("timeout") || lower.contains("could not connect") || lower.contains("econnrefused") || lower.contains("-1003") {
            return "Error Diagnosis: Network/local service connection failure (`\(ocr.prefix(140))`). Verify the target server or local daemon (e.g. Ollama) is running and reachable."
        }
        if lower.contains("not found") || lower.contains("enoent") || lower.contains("404") || lower.contains("no such file") {
            return "Error Diagnosis: Missing file or endpoint (`\(ocr.prefix(140))`). Confirm the path, URL, or resource identifier exists."
        }
        if lower.contains("syntax") || lower.contains("unexpected token") || lower.contains("missing argument") || lower.contains("type") {
            return "Error Diagnosis: Code/syntax or type mismatch (`\(ocr.prefix(160))`). Inspect the highlighted line and argument labels."
        }
        return "Error Summary from screen: \(ocr.prefix(240))."
    }
}

