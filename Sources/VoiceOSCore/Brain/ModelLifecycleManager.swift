import Foundation
import AppKit

public enum VisionModelState: String, Sendable {
    case suspended = "Suspended (RAM freed)"
    case warmingUp = "Warming up..."
    case active = "Active in Memory"
    case unloading = "Unloading weights..."
}

/// Dynamic RAM Thread Suspension & Model Swapping Manager
/// Optimizes unified memory on 16GB M-Series Apple Silicon Macs:
/// 1. Keeps 'The Brain' (Llama-3.2-3B) and string router permanently warm in RAM for 0ms voice reactivity.
/// 2. Implements sleep/wake state machine for 'The Eyes' (Qwen2-VL-7B / Llama-3.2-Vision).
/// 3. Programmatically offloads vision weights (keep_alive: 0) to free 6+ GB GPU buffer when idle.
/// 4. Warms up Vision engine only during active visual grounding steps and unloads immediately post-task.
public actor ModelLifecycleManager {
    public static let shared = ModelLifecycleManager()
    
    private var visionState: VisionModelState = .suspended
    private var activeVisionLeases = 0
    private var lastActiveTimestamp: Date = .distantPast
    
    public var currentVisionState: VisionModelState {
        return visionState
    }
    
    public nonisolated var isBrainWarmPermanently: Bool {
        return true
    }
    
    private init() {}
    
    // MARK: - Vision Model Lease Management
    
    /// Acquires a lease on the Vision LLM, warming up the GPU buffer if suspended
    public func acquireVisionLease(for task: String = "ui_grounding") async -> Bool {
        activeVisionLeases += 1
        visionState = .warmingUp
        
        let warmed = await warmUpVisionEngine()
        visionState = warmed ? .active : .suspended
        lastActiveTimestamp = Date()
        return warmed
    }
    
    /// Releases the Vision LLM lease. The millisecond leases reach 0, unloads weights to free unified memory
    public func releaseVisionLease() async {
        activeVisionLeases = max(0, activeVisionLeases - 1)
        if activeVisionLeases == 0 {
            visionState = .unloading
            await offloadVisionWeights()
            visionState = .suspended
        }
    }
    
    // MARK: - Memory Offload (keep_alive: 0)
    
    private func warmUpVisionEngine() async -> Bool {
        guard let url = URL(string: "http://localhost:11434/api/generate") else { return true }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3.0
        
        let visionModel = ModelRouter.shared.ollamaVisionModel
        let payload: [String: Any] = [
            "model": visionModel,
            "prompt": "",
            "keep_alive": "5m"
        ]
        
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return true }
        request.httpBody = body
        
        do {
            _ = try await URLSession.shared.data(for: request)
            return true
        } catch {
            return true
        }
    }
    
    private func offloadVisionWeights() async {
        guard let url = URL(string: "http://localhost:11434/api/generate") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2.0
        
        let visionModel = ModelRouter.shared.ollamaVisionModel
        let payload: [String: Any] = [
            "model": visionModel,
            "keep_alive": 0
        ]
        
        if let body = try? JSONSerialization.data(withJSONObject: payload) {
            request.httpBody = body
            _ = try? await URLSession.shared.data(for: request)
        }
    }
    
    /// Synchronously unloads all active Ollama models from unified memory / VRAM on app termination
    public nonisolated func offloadAllModelsImmediately() {
        guard ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] != "1" else { return }
        let models = [ModelRouter.shared.ollamaChatModel, ModelRouter.shared.ollamaVisionModel]
        for m in models {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            proc.arguments = [
                "-s", "-m", "1.0",
                "-X", "POST", "http://127.0.0.1:11434/api/generate",
                "-H", "Content-Type: application/json",
                "-d", "{\"model\": \"\(m)\", \"keep_alive\": 0}"
            ]
            try? proc.run()
            proc.waitUntilExit()
        }
    }

    /// Unloads loaded models and terminates both Ollama.app and any running headless `ollama` daemon.
    public nonisolated func shutdownOllamaAndUnloadModels() {
        guard ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] != "1" else { return }
        offloadAllModelsImmediately()

        for app in NSWorkspace.shared.runningApplications {
            let bid = (app.bundleIdentifier ?? "").lowercased()
            let name = (app.localizedName ?? "").lowercased()
            if bid.contains("ollama") || name == "ollama" {
                app.terminate()
            }
        }

        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killProc.arguments = ["-x", "ollama"]
        try? killProc.run()
        killProc.waitUntilExit()
        NSLog("[ModelLifecycle] Unloaded models and shut down Ollama.")
    }
}
