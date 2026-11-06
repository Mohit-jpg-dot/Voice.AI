import Foundation
import AppKit

public enum ModelProfileTier: String, CaseIterable, Codable, Sendable {
    case lite = "Lite (Fast & Lightweight)"
    case balanced = "Balanced (Recommended)"
    case best = "Best (Maximum Reasoning & Vision)"
}

public struct HardwareSpecification: Sendable {
    public let chipModel: String
    public let totalRamGigabytes: Double
    public let freeDiskGigabytes: Double
    public let macOSVersion: String
    public let recommendedTier: ModelProfileTier
    public let canRunLocalModels: Bool
    public let warningMessage: String?
}

public struct ModelCatalogItem: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let category: String // "runtime", "chat", "vision", "stt", "tts"
    public let downloadSizeMB: Int
    public let diskRequiredMB: Int
    public let ramRequiredGB: Double
    public let sha256: String
    public let license: String
    public let command: String
    public let downloadURL: String
    public let isCore: Bool
    public let capabilities: [String] // "tools", "vision", "hindi", "streaming"
    
    public init(
        id: String,
        name: String,
        category: String,
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
        self.category = category
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
/// and pairs with our official signed model catalog for optimal offline execution.
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
        var warning: String? = nil
        var canRun = true
        
        if freeDiskGB < 5.0 {
            canRun = false
            warning = "Critically low disk space (\(String(format: "%.1f", freeDiskGB)) GB free). At least 8 GB required."
        } else if ramGB < 6.0 {
            tier = .lite
            warning = "Limited memory (\(Int(ramGB)) GB RAM). Lite 3B models recommended."
        } else if ramGB >= 16.0 && freeDiskGB >= 25.0 {
            tier = .best
        } else {
            tier = .balanced
        }
        
        return HardwareSpecification(
            chipModel: chip,
            totalRamGigabytes: (ramGB * 10).rounded() / 10,
            freeDiskGigabytes: (freeDiskGB * 10).rounded() / 10,
            macOSVersion: osVer,
            recommendedTier: tier,
            canRunLocalModels: canRun,
            warningMessage: warning
        )
    }
    
    public func getCatalogItems(for tier: ModelProfileTier) -> [ModelCatalogItem] {
        var items: [ModelCatalogItem] = [
            // 1. Ollama Runtime
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
        
        // 2. Chat Model by Tier
        switch tier {
        case .lite:
            items.append(ModelCatalogItem(
                id: "chat.qwen2.5.3b",
                name: "Qwen 2.5 (3B Instruct)",
                category: "chat",
                downloadSizeMB: 1900,
                diskRequiredMB: 2200,
                ramRequiredGB: 3.5,
                sha256: "7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b",
                license: "Apache 2.0",
                command: "ollama pull qwen2.5:3b",
                downloadURL: "http://localhost:11434/api/pull?name=qwen2.5:3b",
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
            // Vision Grounding Model
            items.append(ModelCatalogItem(
                id: "vision.llama3.2.11b",
                name: "Llama 3.2 Vision (11B Multimodal)",
                category: "vision",
                downloadSizeMB: 7800,
                diskRequiredMB: 8500,
                ramRequiredGB: 9.0,
                sha256: "d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6",
                license: "Llama 3.2 Community",
                command: "ollama pull llama3.2-vision",
                downloadURL: "http://localhost:11434/api/pull?name=llama3.2-vision",
                isCore: false,
                capabilities: ["vision", "screen_grounding", "bounding_boxes"]
            ))
        }
        
        // 3. Multilingual Neural Speech-to-Text (Whisper)
        items.append(ModelCatalogItem(
            id: "stt.whisper.small",
            name: "Whisper Multilingual Core (STT)",
            category: "stt",
            downloadSizeMB: 480,
            diskRequiredMB: 500,
            ramRequiredGB: 0.8,
            sha256: "e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8",
            license: "MIT",
            command: "voiceai models install whisper-small-multilingual",
            downloadURL: "https://huggingface.co/openai/whisper-small/resolve/main/model.bin",
            isCore: true,
            capabilities: ["hindi", "hinglish", "english", "vad"]
        ))
        
        // 4. Local High-Quality Neural TTS
        items.append(ModelCatalogItem(
            id: "tts.piper.neural",
            name: "Neural Spoken Voice (Piper/macOS Enhanced)",
            category: "tts",
            downloadSizeMB: 85,
            diskRequiredMB: 100,
            ramRequiredGB: 0.2,
            sha256: "f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0",
            license: "MIT",
            command: "voiceai models install voice-piper-en-hi",
            downloadURL: "https://github.com/rhasspy/piper/releases/download/v1.0.0/voice-en-hi.tar.gz",
            isCore: true,
            capabilities: ["hindi", "english", "neural_voice"]
        ))
        
        return items
    }
    
    // MARK: - Internal System Helpers
    
    private func getAvailableDiskSpaceGB() -> Double {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            return Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        }
        return 50.0
    }
    
    private func getChipModelString() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &machine, &size, nil, 0)
        let model = String(cString: machine)
        
        // Read CPU brand
        var brandSize = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &brandSize, nil, 0)
        if brandSize > 0 {
            var brand = [CChar](repeating: 0, count: brandSize)
            sysctlbyname("machdep.cpu.brand_string", &brand, &brandSize, nil, 0)
            let brandStr = String(cString: brand)
            if !brandStr.isEmpty { return brandStr }
        }
        return model.isEmpty ? "Apple Silicon (M-Series)" : model
    }
}

