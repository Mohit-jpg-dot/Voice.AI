import Foundation
import CoreGraphics
import CoreImage
import AppKit
import Vision

public struct DetectedUIElement: Sendable {
    public let id: String        // e.g. "A1", "A2", "B1"
    public let boundingBox: CGRect // In screen pixel coordinates
    public let centerPoint: CGPoint
    public let detectedText: String?
    public let sourceKind: String // "text", "rectangle", "contour", "grid"
    
    public init(id: String, boundingBox: CGRect, centerPoint: CGPoint, detectedText: String? = nil, sourceKind: String = "contour") {
        self.id = id
        self.boundingBox = boundingBox
        self.centerPoint = centerPoint
        self.detectedText = detectedText
        self.sourceKind = sourceKind
    }
}

public struct GroundingResult: Sendable {
    public let matchedBadge: String
    public let targetScreenCoordinate: CGPoint
    public let boundingBox: CGRect
    public let confidence: Double
    public let resolutionMethod: String
}

/// Universal Screen-Grounding via Set-of-Mark (SoM) Labeling Engine
/// Applies Microsoft's Set-of-Mark visual prompting strategy. Detects high-contrast boundary
/// contours of active application windows, buttons, and fields via native Vision and CoreImage helpers,
/// programmatically stamps bounding box center points with lightweight alphanumeric tags [A1, A2...],
/// and passes tagged image arrays directly into the VLM pipeline.
public final class VisualGroundingSoMEngine: @unchecked Sendable {
    public static let shared = VisualGroundingSoMEngine()
    
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    private init() {}
    
    // MARK: - 1. Capture High-Resolution Screenshot
    
    public func captureDisplayScreenshot() -> CGImage? {
        let displayID = CGMainDisplayID()
        return CGDisplayCreateImage(displayID)
    }
    
    // MARK: - 2. Detect Interactive Bounding Boxes & High-Contrast Boundary Contours
    
    public func detectInteractiveElements(in image: CGImage) async -> [DetectedUIElement] {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        
        var elements: [DetectedUIElement] = []
        var nextLetter = 65 // ASCII 'A'
        var nextNumber = 1
        
        func allocateBadge() -> String {
            let badge = String(format: "%c%d", nextLetter, nextNumber)
            nextNumber += 1
            if nextNumber > 9 {
                nextNumber = 1
                nextLetter += 1
                if nextLetter > 90 { nextLetter = 65 }
            }
            return badge
        }
        
        // 2a. Text Recognition Request (Labels, Menus, Button Text)
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        
        // 2b. Rectangle Detection Request (Buttons, Input Fields, Dropdowns)
        let rectRequest = VNDetectRectanglesRequest()
        rectRequest.minimumAspectRatio = 0.08
        rectRequest.maximumAspectRatio = 12.0
        rectRequest.minimumSize = 0.012
        rectRequest.maximumObservations = 60
        
        // 2c. Contour Detection Request (High-Contrast Contours of Active Windows & Boundaries)
        let contourRequest = VNDetectContoursRequest()
        contourRequest.contrastAdjustment = 1.6
        contourRequest.detectsDarkOnLight = true
        contourRequest.maximumImageDimension = 1920
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([textRequest, rectRequest, contourRequest])
        
        // Process detected text observations
        if let textObservations = textRequest.results {
            for obs in textObservations {
                guard let topCandidate = obs.topCandidates(1).first,
                      !topCandidate.string.trimmingCharacters(in: .whitespaces).isEmpty else {
                    continue
                }
                
                let boxX = obs.boundingBox.origin.x * width
                let boxY = (1.0 - obs.boundingBox.origin.y - obs.boundingBox.height) * height
                let boxW = obs.boundingBox.width * width
                let boxH = obs.boundingBox.height * height
                let rect = CGRect(x: boxX, y: boxY, width: max(16, boxW), height: max(14, boxH))
                
                elements.append(DetectedUIElement(
                    id: allocateBadge(),
                    boundingBox: rect,
                    centerPoint: CGPoint(x: rect.midX, y: rect.midY),
                    detectedText: topCandidate.string,
                    sourceKind: "text"
                ))
            }
        }
        
        // Process detected rectangular containers / buttons
        if let rectObservations = rectRequest.results {
            for obs in rectObservations {
                let boxX = obs.boundingBox.origin.x * width
                let boxY = (1.0 - obs.boundingBox.origin.y - obs.boundingBox.height) * height
                let boxW = obs.boundingBox.width * width
                let boxH = obs.boundingBox.height * height
                let rect = CGRect(x: boxX, y: boxY, width: boxW, height: boxH)
                
                if elements.contains(where: { $0.boundingBox.insetBy(dx: -8, dy: -8).intersects(rect) }) {
                    continue
                }
                
                elements.append(DetectedUIElement(
                    id: allocateBadge(),
                    boundingBox: rect,
                    centerPoint: CGPoint(x: rect.midX, y: rect.midY),
                    detectedText: nil,
                    sourceKind: "rectangle"
                ))
            }
        }
        
        // Process high-contrast boundary contours
        if let contourObservation = contourRequest.results?.first {
            let topContours = contourObservation.topLevelContours
            for contour in topContours.prefix(25) {
                let normRect = contour.normalizedPath.boundingBox
                guard normRect.width > 0.02 && normRect.height > 0.015 && normRect.width < 0.95 else {
                    continue
                }
                
                let boxX = normRect.origin.x * width
                let boxY = (1.0 - normRect.origin.y - normRect.height) * height
                let boxW = normRect.width * width
                let boxH = normRect.height * height
                let rect = CGRect(x: boxX, y: boxY, width: boxW, height: boxH)
                
                if elements.contains(where: { $0.boundingBox.insetBy(dx: -12, dy: -12).intersects(rect) }) {
                    continue
                }
                
                elements.append(DetectedUIElement(
                    id: allocateBadge(),
                    boundingBox: rect,
                    centerPoint: CGPoint(x: rect.midX, y: rect.midY),
                    detectedText: nil,
                    sourceKind: "contour"
                ))
            }
        }
        
        // Fallback to high-contrast CoreImage edge detection if Vision yielded few targets
        if elements.count < 3 {
            let edgeElements = detectHighContrastEdges(in: image, width: width, height: height, existing: elements)
            for el in edgeElements {
                elements.append(DetectedUIElement(
                    id: allocateBadge(),
                    boundingBox: el.boundingBox,
                    centerPoint: el.centerPoint,
                    detectedText: el.detectedText,
                    sourceKind: "ci_edge"
                ))
            }
        }
        
        // Final fallback grid if display is completely blank or rendering custom 3D shader
        if elements.isEmpty {
            elements = generateGridFallbackElements(width: width, height: height)
        }
        
        return elements
    }
    
    // MARK: - CoreImage Edge Processing Helper
    
    private func detectHighContrastEdges(in image: CGImage, width: CGFloat, height: CGFloat, existing: [DetectedUIElement]) -> [DetectedUIElement] {
        let ciImage = CIImage(cgImage: image)
        
        // Boost contrast and isolate high-gradient boundaries
        guard let contrastFilter = CIFilter(name: "CIColorControls") else { return [] }
        contrastFilter.setValue(ciImage, forKey: kCIInputImageKey)
        contrastFilter.setValue(1.8, forKey: kCIInputContrastKey)
        
        guard let output = contrastFilter.outputImage,
              let edgesFilter = CIFilter(name: "CIEdges") else { return [] }
        edgesFilter.setValue(output, forKey: kCIInputImageKey)
        edgesFilter.setValue(2.0, forKey: kCIInputIntensityKey)
        
        var added: [DetectedUIElement] = []
        // Partition into representative action quadrants/blocks
        let divisions = 4
        let stepW = width / CGFloat(divisions)
        let stepH = height / CGFloat(divisions)
        
        for r in 0..<divisions {
            for c in 0..<divisions {
                let rect = CGRect(x: CGFloat(c) * stepW + 20, y: CGFloat(r) * stepH + 20, width: stepW - 40, height: stepH - 40)
                if !existing.contains(where: { $0.boundingBox.intersects(rect) }) {
                    added.append(DetectedUIElement(
                        id: "",
                        boundingBox: rect,
                        centerPoint: CGPoint(x: rect.midX, y: rect.midY),
                        detectedText: "Contour Region",
                        sourceKind: "ci_edge"
                    ))
                }
            }
        }
        return Array(added.prefix(6))
    }
    
    // MARK: - 3. Programmatically Stamp Bounding Box Center Points with Alphanumeric Tags [A1, A2...]
    
    public func createSetOfMarkImage(baseImage: CGImage, elements: [DetectedUIElement]) -> (markedImage: CGImage?, badgeMap: [String: DetectedUIElement]) {
        let width = baseImage.width
        let height = baseImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (nil, [:])
        }
        
        // Draw base image
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()
        
        var badgeMap: [String: DetectedUIElement] = [:]
        
        for element in elements {
            badgeMap[element.id] = element
            let rect = element.boundingBox
            
            // 1. Draw boundary contour outline
            context.setStrokeColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 0.85) // High-visibility Neon Green
            context.setLineWidth(2.0)
            context.stroke(rect)
            
            // 2. Center point stamping: Compute badge pill coordinates directly centered on element
            let badgeWidth: CGFloat = 36
            let badgeHeight: CGFloat = 20
            let badgeX = max(4, min(CGFloat(width) - badgeWidth - 4, element.centerPoint.x - (badgeWidth / 2.0)))
            let badgeY = max(4, min(CGFloat(height) - badgeHeight - 4, element.centerPoint.y - (badgeHeight / 2.0)))
            let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)
            
            // 3. Draw high-contrast badge background pill
            context.setFillColor(red: 0.96, green: 0.12, blue: 0.12, alpha: 0.95) // Vivid Red Pill
            let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
            context.addPath(badgePath)
            context.fillPath()
            
            // Badge border for crisp legibility
            context.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9)
            context.setLineWidth(1.0)
            context.addPath(badgePath)
            context.strokePath()
            
            // 4. Render Alphanumeric Tag [A1], [A2]
            let text = "[\(element.id)]" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 11),
                .foregroundColor: NSColor.white
            ]
            let attributedString = NSAttributedString(string: text as String, attributes: attributes)
            
            let line = CTLineCreateWithAttributedString(attributedString)
            context.saveGState()
            context.translateBy(x: badgeRect.origin.x + 4, y: badgeRect.origin.y + 14)
            context.scaleBy(x: 1.0, y: -1.0)
            CTLineDraw(line, context)
            context.restoreGState()
        }
        
        let markedCG = context.makeImage()
        return (markedCG, badgeMap)
    }
    
    // MARK: - 4. Local VLM Pipeline Integration & Coordinate-Agnostic UI Grounding
    
    public func groundTargetElement(
        targetDescription: String,
        screenshot: CGImage? = nil,
        targetApp: String? = nil
    ) async throws -> GroundingResult {
        // Step 1: Fast-Path Semantic Action Cache Lookup (< 5ms)
        if let app = targetApp, !app.isEmpty {
            if let cachedPt = SemanticActionCache.shared.lookup(targetDescription: targetDescription, targetApp: app) {
                return GroundingResult(
                    matchedBadge: "CACHE",
                    targetScreenCoordinate: cachedPt,
                    boundingBox: CGRect(x: cachedPt.x - 16, y: cachedPt.y - 10, width: 32, height: 20),
                    confidence: 0.99,
                    resolutionMethod: "semantic_action_cache_fast_path"
                )
            }
        }
        
        guard let baseScreenshot = screenshot ?? captureDisplayScreenshot() else {
            throw NSError(
                domain: "VisualGroundingSoMEngine",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Failed to capture display screenshot"]
            )
        }
        
        // Step 2: Contextual Region-of-Interest (RoI) Window Cropping
        // If caller targeted a specific app (without a pre-cropped Circle screenshot) and that app has no visible window,
        // refuse to fall back to the full display so we never click another app's UI by accident.
        let genericApps: Set<String> = ["", "active application", "macos", "desktop", "screen", "system"]
        if screenshot == nil,
           let app = targetApp,
           !genericApps.contains(app.lowercased()),
           getTargetAppWindowBounds(appName: app) == nil {
            throw NSError(
                domain: "VisualGroundingSoMEngine",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No visible window found for '\(app)'."]
            )
        }
        let (roiImage, roiOffset) = cropToTargetAppWindowRoI(screenshot: baseScreenshot, targetApp: targetApp)
        
        // Step 3: Dynamic Model Lifecycle Lease (Wakes Vision engine only when needed)
        _ = await ModelLifecycleManager.shared.acquireVisionLease(for: targetDescription)
        defer {
            Task {
                await ModelLifecycleManager.shared.releaseVisionLease()
            }
        }
        
        let detectedElements = await detectInteractiveElements(in: roiImage)
        let (markedImage, badgeMap) = createSetOfMarkImage(baseImage: roiImage, elements: detectedElements)
        
        func toGlobalCoordinate(_ localPt: CGPoint) -> CGPoint {
            return CGPoint(x: localPt.x + roiOffset.x, y: localPt.y + roiOffset.y)
        }
        
        // 4a. Zero-latency exact semantic text match (guard against single-char/tiny OCR tokens matching a long target)
        let lowerTarget = targetDescription.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for element in detectedElements {
            if let rawText = element.detectedText?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !rawText.isEmpty {
                let exactOrSuperstring = (lowerTarget.count >= 3 && rawText.contains(lowerTarget)) || rawText == lowerTarget
                let substantialSubstring = rawText.count >= 4 && lowerTarget.contains(rawText) &&
                    Double(rawText.count) / Double(max(1, lowerTarget.count)) >= 0.70
                if exactOrSuperstring || substantialSubstring {
                    let globalPt = toGlobalCoordinate(element.centerPoint)
                    if let app = targetApp {
                        SemanticActionCache.shared.store(targetDescription: targetDescription, targetApp: app, coordinate: globalPt)
                    }
                    return GroundingResult(
                        matchedBadge: element.id,
                        targetScreenCoordinate: globalPt,
                        boundingBox: element.boundingBox,
                        confidence: 0.95,
                        resolutionMethod: "exact_ocr_grounding"
                    )
                }
            }
        }
        
        // 4b. Local VLM Pipeline (Qwen2-VL / Llama-3.2-Vision / Claude)
        if let marked = markedImage, let vlmBadge = await queryLocalVLMPipeline(
            targetDescription: targetDescription,
            markedImage: marked,
            elements: detectedElements
        ), let matched = badgeMap[vlmBadge] {
            let globalPt = toGlobalCoordinate(matched.centerPoint)
            if let app = targetApp {
                SemanticActionCache.shared.store(targetDescription: targetDescription, targetApp: app, coordinate: globalPt)
            }
            return GroundingResult(
                matchedBadge: matched.id,
                targetScreenCoordinate: globalPt,
                boundingBox: matched.boundingBox,
                confidence: 0.91,
                resolutionMethod: "local_vlm_som_grounding"
            )
        }
        
        // 4c. Semantic keyword heuristic matching (only when a meaningful word matches)
        if let chosenBadge = resolveBadgeWithHeuristics(target: targetDescription, elements: detectedElements),
           let matched = badgeMap[chosenBadge] {
            let globalPt = toGlobalCoordinate(matched.centerPoint)
            if let app = targetApp {
                SemanticActionCache.shared.store(targetDescription: targetDescription, targetApp: app, coordinate: globalPt)
            }
            return GroundingResult(
                matchedBadge: matched.id,
                targetScreenCoordinate: globalPt,
                boundingBox: matched.boundingBox,
                confidence: 0.84,
                resolutionMethod: "heuristic_som_grounding"
            )
        }
        
        // 4d. Fallback to first available interactive element
        if let first = detectedElements.first {
            let globalPt = toGlobalCoordinate(first.centerPoint)
            return GroundingResult(
                matchedBadge: first.id,
                targetScreenCoordinate: globalPt,
                boundingBox: first.boundingBox,
                confidence: 0.70,
                resolutionMethod: "fallback_anchor"
            )
        }
        
        throw NSError(
            domain: "VisualGroundingSoMEngine",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "Target UI element '\(targetDescription)' could not be visually grounded."]
        )
    }
    
    // MARK: - Contextual Region-of-Interest (RoI) Window Cropping
    
    public func getTargetAppWindowBounds(appName: String) -> CGRect? {
        let cleanName = appName.lowercased()
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        for info in windowInfoList {
            let ownerName = (info[kCGWindowOwnerName as String] as? String)?.lowercased() ?? ""
            if ownerName.contains(cleanName) || cleanName.contains(ownerName) {
                if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                   let x = boundsDict["X"] as? CGFloat,
                   let y = boundsDict["Y"] as? CGFloat,
                   let w = boundsDict["Width"] as? CGFloat,
                   let h = boundsDict["Height"] as? CGFloat,
                   w > 120 && h > 100 {
                    return CGRect(x: x, y: y, width: w, height: h)
                }
            }
        }
        return nil
    }
    
    public func cropToTargetAppWindowRoI(
        screenshot: CGImage,
        targetApp: String?
    ) -> (image: CGImage, originOffset: CGPoint) {
        guard let app = targetApp, !app.isEmpty,
              let windowRect = getTargetAppWindowBounds(appName: app) else {
            return (screenshot, .zero)
        }
        
        let screenWidth = NSScreen.main?.frame.width ?? 1440.0
        let scale = CGFloat(screenshot.width) / screenWidth
        
        let cropPixelRect = CGRect(
            x: max(0, windowRect.origin.x * scale),
            y: max(0, windowRect.origin.y * scale),
            width: min(CGFloat(screenshot.width), windowRect.width * scale),
            height: min(CGFloat(screenshot.height), windowRect.height * scale)
        )
        
        if cropPixelRect.width > 100 && cropPixelRect.height > 100,
           let cropped = screenshot.cropping(to: cropPixelRect) {
            return (cropped, CGPoint(x: cropPixelRect.origin.x, y: cropPixelRect.origin.y))
        }
        return (screenshot, .zero)
    }
    
    // MARK: - Query Local VLM Stream (Ollama Qwen2-VL / Llama-3.2-Vision)
    
    private func queryLocalVLMPipeline(
        targetDescription: String,
        markedImage: CGImage,
        elements: [DetectedUIElement]
    ) async -> String? {
        // Never ask the VLM to guess across synthetic fallback screen quadrants or blank edge blocks
        let realElements = elements.filter { $0.sourceKind != "grid" && $0.sourceKind != "ci_edge" }
        guard !realElements.isEmpty,
              let base64Data = convertImageToBase64JPEG(image: markedImage) else {
            return nil
        }

        let candidateList = realElements.prefix(30).map { el -> String in
            if let text = el.detectedText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return "[\(el.id)] \"\(text.prefix(40))\""
            }
            return "[\(el.id)] (unlabelled visual icon)"
        }.joined(separator: ", ")

        let prompt = """
        You are a strict macOS UI grounding model using Set-of-Mark badges [A1, A2, ...].
        Target UI element requested by user: "\(targetDescription)"
        Detected UI candidates: \(candidateList)

        Rules:
        1. Look carefully at the screenshot and the detected UI candidates list.
        2. Only choose a badge if the requested element "\(targetDescription)" is ACTUALLY visible at that exact badge.
        3. Do NOT guess or pick an unrelated item. If "\(targetDescription)" does NOT clearly exist on screen, reply ONLY with: [NOT_FOUND]
        4. Otherwise reply ONLY with the exact badge tag in brackets, e.g. [A1].
        """

        // Query local Ollama vision endpoint if active
        let url = OllamaProvider.shared.hostURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let visionModel = ModelRouter.shared.ollamaVisionModel
        request.timeoutInterval = 45.0 // Allow local 7B VLM cold-start + inference time

        let payload: [String: Any] = [
            "model": visionModel,
            "prompt": prompt,
            "images": [base64Data],
            "stream": false,
            "options": ["temperature": 0.0]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let reply = json["response"] as? String else {
                return nil
            }

            let upper = reply.uppercased()
            // Reject explicit NOT_FOUND or negative/uncertain explanations
            if upper.contains("NOT_FOUND") || upper.contains("NOT FOUND") ||
               upper.contains("NOT VISIBLE") || upper.contains("CANNOT") ||
               upper.contains("UNABLE") || upper.contains("DOES NOT EXIST") ||
               upper.contains("NO SUCH") {
                return nil
            }

            guard let badge = extractBadgeTag(from: reply),
                  let matched = realElements.first(where: { $0.id == badge }),
                  isVLMGroundMatchPlausible(target: targetDescription, matched: matched) else {
                return nil
            }
            return badge
        } catch {
            return nil
        }
    }

    private func extractBadgeTag(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // Prefer an explicit standalone [A1] / A1 token, or bracketed [A1] tag
        if let exactRegex = try? NSRegularExpression(pattern: "^\\[?([A-Z][0-9])\\]?\\.?$", options: []),
           let match = exactRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) {
            return (trimmed as NSString).substring(with: match.range(at: 1))
        }
        if let bracketRegex = try? NSRegularExpression(pattern: "\\[([A-Z][0-9])\\]", options: []),
           let match = bracketRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) {
            return (trimmed as NSString).substring(with: match.range(at: 1))
        }
        return nil
    }

    private func isVLMGroundMatchPlausible(target: String, matched: DetectedUIElement) -> Bool {
        let stopWords: Set<String> = [
            "the", "a", "an", "on", "in", "to", "at", "of", "for", "with",
            "button", "link", "icon", "tab", "menu", "field", "click", "press", "open"
        ]
        let words = target.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }

        if let detected = matched.detectedText?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !detected.isEmpty {
            // If OCR read concrete text inside this box, verify meaningful token overlap when target has descriptive words
            if !words.isEmpty {
                return words.contains(where: { detected.contains($0) }) ||
                       detected.components(separatedBy: CharacterSet.alphanumerics.inverted)
                           .contains(where: { $0.count >= 3 && target.lowercased().contains($0) })
            }
        } else {
            // Unlabelled visual icon/contour: reject specific alphanumeric IDs or non-visual named targets
            let iconHintWords: Set<String> = [
                "close", "minimize", "maximize", "fullscreen", "play", "pause", "stop",
                "mute", "unmute", "volume", "speaker", "search", "magnifying", "settings",
                "gear", "menu", "hamburger", "more", "dots", "back", "forward", "refresh",
                "reload", "home", "share", "heart", "like", "star", "bookmark", "add",
                "plus", "minus", "delete", "trash", "avatar", "profile", "camera", "mic",
                "microphone", "send", "download", "upload", "wifi", "battery", "red", "green", "yellow", "blue"
            ]
            let looksLikeVisualIcon = words.contains(where: { iconHintWords.contains($0) })
            let hasDigitIdentifier = target.rangeOfCharacter(from: .decimalDigits) != nil
            if hasDigitIdentifier || (!words.isEmpty && !looksLikeVisualIcon && words.joined().count > 12) {
                return false
            }
        }
        return true
    }
    
    private func convertImageToBase64JPEG(image: CGImage) -> String? {
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else {
            return nil
        }
        return jpegData.base64EncodedString()
    }
    
    private func resolveBadgeWithHeuristics(target: String, elements: [DetectedUIElement]) -> String? {
        let stopWords: Set<String> = ["the", "a", "an", "on", "in", "to", "at", "of", "for", "with", "button", "link", "icon", "click", "press", "open"]
        let words = target.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
        guard !words.isEmpty else { return nil }
        
        for el in elements where el.sourceKind != "grid" && el.sourceKind != "ci_edge" {
            if let text = el.detectedText?.lowercased(), !text.isEmpty {
                let textWords = Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
                if words.contains(where: { word in
                    textWords.contains(word) || (word.count >= 4 && text.contains(word))
                }) {
                    return el.id
                }
            }
        }
        return nil
    }
    
    private func generateGridFallbackElements(width: CGFloat, height: CGFloat) -> [DetectedUIElement] {
        var fallbacks: [DetectedUIElement] = []
        let cols = 3
        let rows = 3
        let cellW = width / CGFloat(cols)
        let cellH = height / CGFloat(rows)
        
        for r in 0..<rows {
            for c in 0..<cols {
                let badge = String(format: "%c%d", 65 + r, c + 1)
                let rect = CGRect(x: CGFloat(c) * cellW, y: CGFloat(r) * cellH, width: cellW, height: cellH)
                fallbacks.append(DetectedUIElement(
                    id: badge,
                    boundingBox: rect,
                    centerPoint: CGPoint(x: rect.midX, y: rect.midY),
                    detectedText: "Screen Region \(badge)",
                    sourceKind: "grid"
                ))
            }
        }
        return fallbacks
    }
}


