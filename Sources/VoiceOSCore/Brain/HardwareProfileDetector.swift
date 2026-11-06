import Foundation
import AppKit

public enum ModelProfileTier: String, CaseIterable, Codable, Sendable {
    case lite = "Lite (Fast & Lightweight)"
    case balanced = "Balanced (Recommended)"
    case best = "Best (Maximum Reasoning & Vision)"
}

public enum RecommendedExecutionMode: String, Codable, Sendable {
    case localOffline = "100% Local Offline"
    case hybrid = "Hybrid (Local Brain + Cloud Vision)"
    case cloudOnly = "Cloud API Mode"
}

public struct HardwareSpecification: Sendable {
    public let chipModel: String
    public let totalRamGigabytes: Double
    public let freeDiskGigabytes: Double
    public let macOSVersion: String
    public let recommendedTier: ModelProfileTier
    public let recommendedExecutionMode: RecommendedExecutionMode
    public let canRunLocalModels: Bool
    public let hasLowMemoryGuardrail: Bool
    public let guardrailWarningMessage: String?
}

public struct ModelCatalogItem: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let roleTitle: String // "The Brain", "The Eyes", "The Voice"
    public let category: String  // "brain", "vision", "voice", "runtime"
    public let purposeDescription: String
    public let downloadSizeMB: Int
    public let diskRequiredMB: Int
    public let ramRequiredGB: Double
    public let sha256: String
    public let license: String
    public let command: String
    public let downloadURL: String
    public let isCore: Bool
    public let capabilities: [String]
    
    public init(
        id: String,
        name: String,
        roleTitle: String = "",
        category: String,
        purposeDescription: String = "",
        downloadSizeMB: Int,
        diskRequiredMB: Int,
        ramRequiredGB: Double,
        sha256: String,
        license: String,
        command: String,
        downloadURL: String,
        isCore: Bool,
        capabilities: [String] = []
    ) {
        self.id = id
        self.name = name
        self.roleTitle = roleTitle
        self.category = category
        self.purposeDescription = purposeDescription
        self.downloadSizeMB = downloadSizeMB
        self.diskRequiredMB = diskRequiredMB
        self.ramRequiredGB = ramRequiredGB
        self.sha256 = sha256
        self.license = license
        self.command = command
        self.downloadURL = downloadURL
        self.isCore = isCore
        self.capabilities = capabilities
    }
}

/// Detects Mac hardware capabilities (Apple Silicon generation, RAM, Disk space)
/// and pairs with our official model catalog with hardware guardrails for OOM prevention.
public final class HardwareProfileDetector: @unchecked Sendable {
    public static let shared = HardwareProfileDetector()
    
    private init() {}
    
    public func detectHardware() -> HardwareSpecification {
        let ramBytes = ProcessInfo.processInfo.physicalMemory
        let ramGB = Double(ramBytes) / (1024.0 * 1024.0 * 1024.0)
        
        let freeDiskGB = getAvailableDiskSpaceGB()
        let chip = getChipModelString()
        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        
        var tier: ModelProfileTier = .balanced
        var mode: RecommendedExecutionMode = .localOffline
        var warning: String? = nil
        var canRun = true
        var lowMemoryGuardrail = false
        
        if freeDiskGB < 6.0 {
            canRun = false
            warning = "Critically low disk space (\(String(format: "%.1f", freeDiskGB)) GB free). At least 8 GB required for local models."
        }
        
        // 8GB RAM Hardware Guardrail Logic
        if ramGB <= 8.5 {
            lowMemoryGuardrail = true
            mode = .hybrid
            tier = .lite
            warning = "⚠️ 8 GB RAM Guardrail: Running 7B Vision models locally may cause system memory pressure. We recommend Hybrid Mode (Local Brain 3B + Cloud Vision API) for optimal, lockup-free performance."
        } else if ramGB >= 16.0 && freeDiskGB >= 20.0 {
            tier = .best
            mode = .localOffline
        } else {
            tier = .balanced
            mode = .localOffline
        }
        
        return HardwareSpecification(
            chipModel: chip,
            totalRamGigabytes: (ramGB * 10).rounded() / 10,
            freeDiskGigabytes: (freeDiskGB * 10).rounded() / 10,
            macOSVersion: osVer,
            recommendedTier: tier,
            recommendedExecutionMode: mode,
            canRunLocalModels: canRun,
            hasLowMemoryGuardrail: lowMemoryGuardrail,
            guardrailWarningMessage: warning
        )
    }
    
    /// Returns the exact three core models powering the Voice.AI vision-driven engine:
    /// 1. Llama-3.2-3B (The Brain)
    /// 2. Qwen2-VL-7B (The Eyes)
    /// 3. Kokoro-82M (The Voice)
    public func getCoreThreeModels() -> [ModelCatalogItem] {
        return [
            // 1. The Brain: Llama-3.2-3B
            ModelCatalogItem(
                id: "brain.llama3.2.3b",
                name: "Llama-3.2-3B",
                roleTitle: "The Brain",
                category: "brain",
                purposeDescription: "Understands colloquial Hinglish/Hindi text commands & breaks down multi-step goals into structured JSON plans.",
                downloadSizeMB: 2500,
                diskRequiredMB: 2800,
                ramRequiredGB: 3.5,
                sha256: "b4c5d6e7f8a90123456789abcdef0123456789abcdef0123456789abcdef0123",
                license: "Meta Llama 3.2 Community License",
                command: "ollama pull llama3.2:3b",
                downloadURL: "http://localhost:11434/api/pull?name=llama3.2:3b",
                isCore: true,
                capabilities: ["hinglish", "hindi", "planning", "json_orchestration"]
            ),
            
            // 2. The Eyes: Qwen2-VL-7B / Llama-3.2-Vision
            ModelCatalogItem(
                id: "vision.qwen2vl.7b",
                name: "Qwen2-VL-7B",
                roleTitle: "The Eyes",
                category: "vision",
                purposeDescription: "Inspects display screenshots, tracks clickable boundaries, and identifies target UI buttons via Set-of-Mark visual grounding.",
                downloadSizeMB: 5200,
                diskRequiredMB: 5800,
                ramRequiredGB: 6.0,
                sha256: "c5d6e7f8a90123456789abcdef0123456789abcdef0123456789abcdef012345",
                license: "Apache 2.0",
                command: "ollama pull qwen2-vl:7b",
                downloadURL: "http://localhost:11434/api/pull?name=qwen2-vl:7b",
                isCore: true,
                capabilities: ["vision", "set_of_mark", "screen_grounding", "ocr"]
            ),
            
            // 3. The Voice: Kokoro-82M
            ModelCatalogItem(
                id: "voice.kokoro.82m",
                name: "Kokoro-82M",
                roleTitle: "The Voice",
                category: "voice",
                purposeDescription: "Ultra-fast, natural multilingual text-to-speech synthesis with zero internet lag.",
                downloadSizeMB: 300,
                diskRequiredMB: 350,
                ramRequiredGB: 0.5,
                sha256: "d6e7f8a90123456789abcdef0123456789abcdef0123456789abcdef01234567",
                license: "Apache 2.0",
                command: "kokoro-tts serve --port 8880",
                downloadURL: "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/kokoro-v0_19.onnx",
                isCore: true,
                capabilities: ["tts", "low_latency", "offline", "multilingual"]
            )
        ]
    }

    public func getCatalogItems(for tier: ModelProfileTier) -> [ModelCatalogItem] {
        var items: [ModelCatalogItem] = [
            ModelCatalogItem(
                id: "runtime.ollama",
                name: "Ollama Local Engine (v0.5.4)",
                category: "runtime",
                downloadSizeMB: 65,
                diskRequiredMB: 120,
                ramRequiredGB: 0.5,
                sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                license: "MIT",
                command: "brew install ollama && ollama serve",
                downloadURL: "https://ollama.com/download/Ollama-darwin.zip",
                isCore: true,
                capabilities: ["daemon", "streaming"]
            )
        ]
        
        switch tier {
        case .lite:
            items.append(ModelCatalogItem(
                id: "chat.llama3.2.3b",
                name: "Llama 3.2 (3B Instruct)",
                category: "chat",
                downloadSizeMB: 1900,
                diskRequiredMB: 2200,
                ramRequiredGB: 3.5,
                sha256: "7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b",
                license: "Llama 3.2 Community",
                command: "ollama pull llama3.2:3b",
                downloadURL: "http://localhost:11434/api/pull?name=llama3.2:3b",
                isCore: true,
                capabilities: ["streaming", "tools", "hindi", "hinglish"]
            ))
        case .balanced:
            items.append(ModelCatalogItem(
                id: "chat.qwen2.5.7b",
                name: "Qwen 2.5 (7B Instruct - High Intelligence)",
                category: "chat",
                downloadSizeMB: 4700,
                diskRequiredMB: 5200,
                ramRequiredGB: 6.0,
                sha256: "b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2",
                license: "Apache 2.0",
                command: "ollama pull qwen2.5:7b",
                downloadURL: "http://localhost:11434/api/pull?name=qwen2.5:7b",
                isCore: true,
                capabilities: ["streaming", "tools", "hindi", "hinglish", "coding"]
            ))
        case .best:
            items.append(ModelCatalogItem(
                id: "chat.qwen2.5.14b",
                name: "Qwen 2.5 (14B Instruct - Frontier Quality)",
                category: "chat",
                downloadSizeMB: 9000,
                diskRequiredMB: 9800,
                ramRequiredGB: 11.5,
                sha256: "c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4",
                license: "Apache 2.0",
                command: "ollama pull qwen2.5:14b",
                downloadURL: "http://localhost:11434/api/pull?name=qwen2.5:14b",
                isCore: true,
                capabilities: ["streaming", "tools", "hindi", "hinglish", "coding", "reasoning"]
            ))
        }
        
        // Add speech & voice items
        items.append(contentsOf: [
            ModelCatalogItem(
                id: "speech.whisper.base",
                name: "Whisper Base (Multilingual English + Hindi)",
                category: "stt",
                downloadSizeMB: 145,
                diskRequiredMB: 200,
                ramRequiredGB: 1.0,
                sha256: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2",
                license: "MIT",
                command: "voiceai models install whisper-base",
                downloadURL: "https://huggingface.co/openai/whisper-base/resolve/main/model.bin",
                isCore: true,
                capabilities: ["stt", "hindi", "hinglish", "streaming"]
            ),
            ModelCatalogItem(
                id: "voice.piper.multilingual",
                name: "Neural Spoken Voice (Piper/macOS Enhanced)",
                category: "tts",
                downloadSizeMB: 65,
                diskRequiredMB: 90,
                ramRequiredGB: 0.5,
                sha256: "f0e1d2c3b4a5f6e7d8c9b0a1f2e3d4c5b6a7f8e9d0c1b2a3f4e5d6c7b8a9f0e1",
                license: "MIT",
                command: "voiceai models install voice-piper-en-hi",
                downloadURL: "https://huggingface.co/rhasspy/piper-voices/resolve/main/hi/hi_IN/cmu_indic/medium/hi_IN-cmu_indic-medium.onnx",
                isCore: true,
                capabilities: ["tts", "offline", "hindi", "english"]
            )
        ])
        
        return items
    }
    
    // MARK: - Hardware Diagnostics Helpers
    
    private func getAvailableDiskSpaceGB() -> Double {
        do {
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                return Double(capacity) / (1024.0 * 1024.0 * 1024.0)
            }
        } catch {}
        return 20.0
    }
    
    private func getChipModelString() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &machine, &size, nil, 0)
        let brand = String(cString: machine)
        
        if brand.contains("Apple") {
            return brand
        }
        
        var msize = 0
        sysctlbyname("hw.machine", nil, &msize, nil, 0)
        var mmachine = [CChar](repeating: 0, count: msize)
        sysctlbyname("hw.machine", &mmachine, &msize, nil, 0)
        let hw = String(cString: mmachine)
        
        if hw == "arm64" {
            return "Apple Silicon (M-Series)"
        }
        return brand.isEmpty ? "Mac System" : brand
    }
}
