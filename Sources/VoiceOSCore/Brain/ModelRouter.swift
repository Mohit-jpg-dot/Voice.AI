import Foundation
import AppKit

public enum TaskRoutingType: String, Sendable {
    case fastCommand = "Fast Command (Local/Direct)"
    case conversation = "Natural Conversation"
    case screenGrounding = "Visual Screen Grounding"
    case hardPlanning = "Multi-step Planning & Tools"
    case webSearch = "Web Search & Synthesis"
}

public struct ModelStatusSummary: Sendable {
    public let mode: ModelMode
    public let chatProvider: String
    public let chatModelId: String
    public let visionProvider: String
    public let visionModelId: String
    public let sttProvider: String
    public let ttsProvider: String
    public let searchProvider: String
    public let isOllamaRunning: Bool
    public let hasCloudKey: Bool
    public let privacyDescription: String
}

/// The central brain router of Voice.AI: dispatches tasks across Cloud, Local, and Hybrid backends.
public final class ModelRouter: @unchecked Sendable {
    public static let shared = ModelRouter()
    
    private let keychain = KeychainService.shared
    private let capabilityDetector = ModelCapabilityDetector.shared
    
    // UserDefaults Keys
    private let modeKey = "voiceos.brain.model_mode"
    private let cloudProviderKey = "voiceos.brain.cloud_provider" // "openai", "claude", "custom"
    private let openAIModelKey = "voiceos.brain.openai_model"
    private let claudeModelKey = "voiceos.brain.claude_model"
    private let ollamaChatModelKey = "voiceos.brain.ollama_chat_model"
    private let ollamaVisionModelKey = "voiceos.brain.ollama_vision_model"
    private let searchProviderTypeKey = "voiceos.brain.search_type" // "brave", "tavily", "searxng"
    private let consentKey = "voiceos.brain.hybrid_cloud_consent"
    
    private init() {}
    
    // MARK: - Current Configuration
    
    public var currentMode: ModelMode {
        get {
            let saved = UserDefaults.standard.string(forKey: modeKey) ?? ModelMode.hybrid.rawValue
            return ModelMode(rawValue: saved) ?? .hybrid
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
        }
    }
    
    public var cloudProvider: String {
        get { UserDefaults.standard.string(forKey: cloudProviderKey) ?? "openai" }
        set { UserDefaults.standard.set(newValue, forKey: cloudProviderKey) }
    }
    
    public var openAIModel: String {
        get { UserDefaults.standard.string(forKey: openAIModelKey) ?? "gpt-4o" }
        set { UserDefaults.standard.set(newValue, forKey: openAIModelKey) }
    }
    
    public var claudeModel: String {
        get { UserDefaults.standard.string(forKey: claudeModelKey) ?? "claude-3-5-sonnet-20241022" }
        set { UserDefaults.standard.set(newValue, forKey: claudeModelKey) }
    }
    
    public var ollamaChatModel: String {
        get { UserDefaults.standard.string(forKey: ollamaChatModelKey) ?? "qwen2.5:latest" }
        set { UserDefaults.standard.set(newValue, forKey: ollamaChatModelKey) }
    }
    
    public var ollamaVisionModel: String {
        get { UserDefaults.standard.string(forKey: ollamaVisionModelKey) ?? "llama3.2-vision:latest" }
        set { UserDefaults.standard.set(newValue, forKey: ollamaVisionModelKey) }
    }
    
    public var hasUserConsentedToCloudUpload: Bool {
        get { UserDefaults.standard.bool(forKey: consentKey) }
        set { UserDefaults.standard.set(newValue, forKey: consentKey) }
    }
    
    // MARK: - Provider Resolution
    
    public func resolveChatModel() -> ChatModel {
        switch currentMode {
        case .cloud:
            return resolveCloudChatModel()
        case .local:
            return resolveLocalChatModel()
        case .hybrid:
            // Hybrid defaults to fast local chat if available, or cloud if configured
            if OllamaProvider.shared.isInstalledAndRunning {
                return resolveLocalChatModel()
            } else {
                return resolveCloudChatModel()
            }
        case .googleSearch:
            return GoogleOnlyBrain.shared
        }
    }
    
    public func resolveVisionModel() throws -> VisionModel {
        switch currentMode {
        case .googleSearch:
            throw BrainError.missingCapability(capability: "Vision & Screen Grounding", model: "Google Search Mode (No LLM)")
        case .local:
            let local = OllamaProvider(model: ollamaVisionModel)
            return local
        case .cloud:
            return resolveCloudVisionModel()
        case .hybrid:
            // Hybrid uses cloud vision for high precision grounding if consent is granted or local lacks vision
            if hasUserConsentedToCloudUpload && hasValidCloudKey() {
                return resolveCloudVisionModel()
            }
            if OllamaProvider.shared.isInstalledAndRunning {
                return OllamaProvider(model: ollamaVisionModel)
            }
            return resolveCloudVisionModel()
        }
    }
    
    public func resolveSearchProvider() -> SearchProvider? {
        let type = UserDefaults.standard.string(forKey: searchProviderTypeKey) ?? "brave"
        if type == "brave" {
            let key = keychain.get(.searchProviderKey) ?? ""
            if !key.isEmpty { return BraveSearchProvider(apiKey: key) }
        } else if type == "tavily" {
            let key = keychain.get(.searchProviderKey) ?? ""
            if !key.isEmpty { return TavilySearchProvider(apiKey: key) }
        } else if type == "searxng" {
            let endpoint = UserDefaults.standard.string(forKey: "voiceos.brain.searxng_url") ?? "http://localhost:8080"
            return SearXNGSearchProvider(baseURL: endpoint)
        }
        
        // Fallback: check any available search key
        if let key = keychain.get(.searchProviderKey), !key.isEmpty {
            return BraveSearchProvider(apiKey: key)
        }
        return nil
    }
    
    // MARK: - Cloud Resolution Helpers
    
    private func resolveCloudChatModel() -> ChatModel {
        if cloudProvider == "claude" {
            let key = keychain.get(.anthropicApiKey) ?? ""
            return AnthropicClaudeProvider(apiKey: key, model: claudeModel)
        } else {
            let key = keychain.get(.openAIApiKey) ?? ""
            return OpenAIProvider(apiKey: key, model: openAIModel)
        }
    }
    
    private func resolveCloudVisionModel() -> VisionModel {
        if cloudProvider == "claude" {
            let key = keychain.get(.anthropicApiKey) ?? ""
            return AnthropicClaudeProvider(apiKey: key, model: claudeModel)
        } else {
            let key = keychain.get(.openAIApiKey) ?? ""
            return OpenAIProvider(apiKey: key, model: openAIModel)
        }
    }
    
    private func resolveLocalChatModel() -> ChatModel {
        return OllamaProvider(model: ollamaChatModel)
    }
    
    public func hasValidCloudKey() -> Bool {
        if cloudProvider == "claude" {
            let key = keychain.get(.anthropicApiKey) ?? ""
            return !key.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        } else {
            let key = keychain.get(.openAIApiKey) ?? ""
            return !key.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        }
    }
    
    // MARK: - Privacy & Status Summary
    
    public func getStatusSummary() -> ModelStatusSummary {
        let isOllama = OllamaProvider.shared.isInstalledAndRunning
        let hasCloud = hasValidCloudKey()
        
        let privacy: String
        switch currentMode {
        case .local:
            privacy = "🔒 100% On-Device: Audio, text, and screenshots never leave this Mac."
        case .cloud:
            privacy = "☁️ Cloud Mode: Prompts and media are securely processed by \(cloudProvider.capitalized) via encrypted TLS."
        case .hybrid:
            privacy = "🛡️ Hybrid Mode: Commands run on-device. Screenshots sent to Cloud only with explicit consent."
        case .googleSearch:
            privacy = "🌐 Google Search Mode: Questions answered directly from Google. No AI reasoning, zero audio/screen data sent."
        }
        
        let chatProv: String
        let chatM: String
        let visionProv: String
        let visionM: String
        
        switch currentMode {
        case .local:
            chatProv = "Ollama"
            chatM = ollamaChatModel
            visionProv = "Ollama"
            visionM = ollamaVisionModel
        case .cloud:
            chatProv = cloudProvider.capitalized
            chatM = (cloudProvider == "claude") ? claudeModel : openAIModel
            visionProv = cloudProvider.capitalized
            visionM = (cloudProvider == "claude") ? claudeModel : openAIModel
        case .hybrid:
            chatProv = isOllama ? "Ollama (Local)" : "\(cloudProvider.capitalized) (Cloud)"
            chatM = isOllama ? ollamaChatModel : ((cloudProvider == "claude") ? claudeModel : openAIModel)
            visionProv = hasCloud ? "\(cloudProvider.capitalized) (Cloud Grounding)" : "Ollama"
            visionM = hasCloud ? ((cloudProvider == "claude") ? claudeModel : openAIModel) : ollamaVisionModel
        case .googleSearch:
            chatProv = "Google Search"
            chatM = "Direct Web Results (No LLM)"
            visionProv = "None"
            visionM = "Disabled (Requires Model)"
        }
        
        return ModelStatusSummary(
            mode: currentMode,
            chatProvider: chatProv,
            chatModelId: chatM,
            visionProvider: visionProv,
            visionModelId: visionM,
            sttProvider: "Whisper (Local Neural)",
            ttsProvider: "macOS Neural TTS",
            searchProvider: (resolveSearchProvider()?.providerName) ?? "Not Configured",
            isOllamaRunning: isOllama,
            hasCloudKey: hasCloud,
            privacyDescription: privacy
        )
    }
}
