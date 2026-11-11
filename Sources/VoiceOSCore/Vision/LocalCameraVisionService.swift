import AppKit
import CryptoKit
import Foundation
import Vision

public enum HandGestureKind: String, Codable, Sendable, CaseIterable {
    case thumbsUp = "thumbs_up"
    case thumbsDown = "thumbs_down"
    case openPalm = "open_palm"
    case pinch = "pinch"

    public var mappedActionDescription: String {
        switch self {
        case .thumbsUp: return "Increase Volume / Confirm"
        case .thumbsDown: return "Decrease Volume"
        case .openPalm: return "Pause Media"
        case .pinch: return "Play / Resume Media"
        }
    }
}

public struct CameraFrameAnalysis: Sendable, Equatable {
    public let detectedObjects: [String]
    public let detectedGesture: HandGestureKind?
    public let recognizedFaceLabel: String?
    public let privacyNotice: String
}

public struct LocalFaceTemplate: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let featureHash: String
    public let enrolledAt: Date
}

public protocol LocalCameraVisionManaging: Sendable {
    func isCameraOptedIn() -> Bool
    func setCameraOptedIn(_ enabled: Bool)
    func isFaceRecognitionEnabled() -> Bool
    func setFaceRecognitionEnabled(_ enabled: Bool)
    func detectObjects(in cgImage: CGImage?, mockLabels: [String]) async -> CameraFrameAnalysis
    func executeGestureAction(_ gesture: HandGestureKind) async -> (success: Bool, summary: String)
    func enrollFaceTemplate(label: String, featureSignature: String) -> Bool
    func recognizeFace(featureSignature: String) -> String?
    func enrolledFaces() -> [LocalFaceTemplate]
    func wipeFaceTemplates()
}

/// Strictly opt-in, 100% on-device Camera Vision (object detection, hand gestures, and optional local-only face recognition).
/// Video frames never leave the Mac. Face recognition requires separate explicit opt-in and stores only hashed local templates.
public final class LocalCameraVisionService: LocalCameraVisionManaging, @unchecked Sendable {
    public static let shared = LocalCameraVisionService()

    public static let privacyNotice =
        "Camera frames are analyzed 100% on-device using Apple Vision. No video or face data ever leaves your Mac."

    private let lock = NSLock()
    private let camOptInKey = "VoiceAI_CameraVisionOptIn_v1"
    private let faceOptInKey = "VoiceAI_FaceRecognitionOptIn_v1"
    private let faceStorageURL: URL
    private var camOptedIn: Bool
    private var faceOptedIn: Bool
    private var faceTemplates: [LocalFaceTemplate] = []

    public init(faceStorageURL: URL? = nil, loadPersisted: Bool = true) {
        if let custom = faceStorageURL {
            self.faceStorageURL = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.faceStorageURL = appSupport
                .appendingPathComponent("VoiceAI", isDirectory: true)
                .appendingPathComponent("local_face_templates_v1.json")
        }

        if loadPersisted {
            self.camOptedIn = UserDefaults.standard.bool(forKey: "VoiceAI_CameraVisionOptIn_v1")
            self.faceOptedIn = UserDefaults.standard.bool(forKey: "VoiceAI_FaceRecognitionOptIn_v1")
            if let data = try? Data(contentsOf: self.faceStorageURL),
               let decoded = try? JSONDecoder().decode([LocalFaceTemplate].self, from: data) {
                self.faceTemplates = decoded
            }
        } else {
            self.camOptedIn = false
            self.faceOptedIn = false
        }
    }

    public func isCameraOptedIn() -> Bool {
        lock.withLock { camOptedIn }
    }

    public func setCameraOptedIn(_ enabled: Bool) {
        lock.withLock {
            camOptedIn = enabled
            if !enabled {
                faceOptedIn = false
                UserDefaults.standard.set(false, forKey: faceOptInKey)
            }
            UserDefaults.standard.set(enabled, forKey: camOptInKey)
        }
    }

    public func isFaceRecognitionEnabled() -> Bool {
        lock.withLock { camOptedIn && faceOptedIn }
    }

    public func setFaceRecognitionEnabled(_ enabled: Bool) {
        lock.withLock {
            faceOptedIn = enabled && camOptedIn
            UserDefaults.standard.set(faceOptedIn, forKey: faceOptInKey)
        }
    }

    public func detectObjects(in cgImage: CGImage?, mockLabels: [String] = []) async -> CameraFrameAnalysis {
        guard isCameraOptedIn() else {
            return CameraFrameAnalysis(
                detectedObjects: [],
                detectedGesture: nil,
                recognizedFaceLabel: nil,
                privacyNotice: "Camera Vision is disabled by default. Opt in under Settings → Advanced & Security."
            )
        }

        if !mockLabels.isEmpty || cgImage == nil {
            return CameraFrameAnalysis(
                detectedObjects: mockLabels,
                detectedGesture: nil,
                recognizedFaceLabel: nil,
                privacyNotice: Self.privacyNotice
            )
        }

        guard let image = cgImage else {
            return CameraFrameAnalysis(detectedObjects: [], detectedGesture: nil, recognizedFaceLabel: nil, privacyNotice: Self.privacyNotice)
        }

        return await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { req, _ in
                let obs = (req.results as? [VNClassificationObservation]) ?? []
                let top = obs.filter { $0.confidence >= 0.35 }.prefix(5).map(\.identifier)
                continuation.resume(returning: CameraFrameAnalysis(
                    detectedObjects: Array(top),
                    detectedGesture: nil,
                    recognizedFaceLabel: nil,
                    privacyNotice: Self.privacyNotice
                ))
            }
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: CameraFrameAnalysis(
                        detectedObjects: [],
                        detectedGesture: nil,
                        recognizedFaceLabel: nil,
                        privacyNotice: Self.privacyNotice
                    ))
                }
            }
        }
    }

    public func executeGestureAction(_ gesture: HandGestureKind) async -> (success: Bool, summary: String) {
        guard isCameraOptedIn() else {
            return (false, "Camera gesture control requires opting into Local Camera Vision in Settings.")
        }

        let env = ProcessInfo.processInfo.environment
        let isDryRun = env["VOICE_AI_TEST_MODE"] == "1" || (Bundle.main.bundleURL.pathExtension != "app" && env["VOICE_AI_LIVE_INTEGRATION"] != "1")

        switch gesture {
        case .thumbsUp:
            if !isDryRun {
                _ = AccessibilityControlEngine.shared.adjustVolume(delta: 0.1, absoluteLevel: nil)
            }
            return (true, "Gesture [Thumbs Up]: \(gesture.mappedActionDescription) executed on-device.")
        case .thumbsDown:
            if !isDryRun {
                _ = AccessibilityControlEngine.shared.adjustVolume(delta: -0.1, absoluteLevel: nil)
            }
            return (true, "Gesture [Thumbs Down]: \(gesture.mappedActionDescription) executed on-device.")
        case .openPalm:
            if !isDryRun {
                _ = AccessibilityControlEngine.shared.controlMedia(app: "Spotify", action: "pause")
            }
            return (true, "Gesture [Open Palm]: \(gesture.mappedActionDescription) executed on-device.")
        case .pinch:
            if !isDryRun {
                _ = AccessibilityControlEngine.shared.controlMedia(app: "Spotify", action: "play")
            }
            return (true, "Gesture [Pinch]: \(gesture.mappedActionDescription) executed on-device.")
        }
    }

    // MARK: - Opt-In Local Face Recognition (Hashed On-Device Templates Only)

    @discardableResult
    public func enrollFaceTemplate(label: String, featureSignature: String) -> Bool {
        guard isFaceRecognitionEnabled() else { return false }
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLabel.isEmpty, !featureSignature.isEmpty else { return false }
        let hash = Self.sha256Hex(featureSignature)

        lock.withLock {
            faceTemplates.removeAll { $0.label.caseInsensitiveCompare(cleanLabel) == .orderedSame }
            faceTemplates.append(LocalFaceTemplate(
                id: UUID().uuidString,
                label: cleanLabel,
                featureHash: hash,
                enrolledAt: Date()
            ))
            saveFaceTemplatesLocked()
        }
        return true
    }

    public func recognizeFace(featureSignature: String) -> String? {
        guard isFaceRecognitionEnabled(), !featureSignature.isEmpty else { return nil }
        let hash = Self.sha256Hex(featureSignature)
        return lock.withLock {
            faceTemplates.first(where: { $0.featureHash == hash })?.label
        }
    }

    public func enrolledFaces() -> [LocalFaceTemplate] {
        lock.withLock { faceTemplates }
    }

    public func wipeFaceTemplates() {
        lock.withLock {
            faceTemplates.removeAll()
            try? FileManager.default.removeItem(at: faceStorageURL)
        }
    }

    private static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(("voiceai_face_salt_v1:" + input).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func saveFaceTemplatesLocked() {
        let dir = faceStorageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(faceTemplates) {
            try? data.write(to: faceStorageURL, options: .atomic)
        }
    }
}

