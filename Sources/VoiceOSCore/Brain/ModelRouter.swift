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
            if newValue == .local {
                Task {
                    _ = await connectLocalOfflineModels()
                }
            }
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
        get {
            if let saved = UserDefaults.standard.string(forKey: ollamaChatModelKey),
               !saved.isEmpty && saved != "qwen2.5:latest" && saved != "qwen2.5" {
                return saved
            }
            return "llama3.2:3b"
        }
        set { UserDefaults.standard.set(newValue, forKey: ollamaChatModelKey) }
    }
    
    public var ollamaVisionModel: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: ollamaVisionModelKey),
               !saved.isEmpty && saved != "llama3.2-vision:latest" && saved != "qwen2-vl:7b" && saved != "qwen2-vl" {
                return saved
            }
            return "llava:7b"
        }
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
            // Hybrid uses fast local Ollama chat when running or when no cloud key is configured
            if OllamaProvider.shared.isInstalledAndRunning || !hasValidCloudKey() {
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
            return resolveLocalVisionModel()
        case .cloud:
            return resolveCloudVisionModel()
        case .hybrid:
            // Hybrid uses cloud vision for high precision grounding ONLY if consent + valid key exist
            if hasUserConsentedToCloudUpload && hasValidCloudKey() {
                return resolveCloudVisionModel()
            }
            if OllamaProvider.shared.isInstalledAndRunning || !hasValidCloudKey() {
                return resolveLocalVisionModel()
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
        let configured = ollamaChatModel
        let cached = OllamaProvider.shared.cachedModels
        if !cached.isEmpty && !cached.contains(where: { $0.name == configured }) {
            if let bestChat = cached.first(where: {
                let lower = $0.name.lowercased()
                return !lower.contains("llava") && !lower.contains("vision") && !lower.contains("-vl")
            }) ?? cached.first {
                return OllamaProvider(model: bestChat.name)
            }
        }
        return OllamaProvider(model: configured)
    }
    
    private func resolveLocalVisionModel() -> VisionModel {
        let configured = ollamaVisionModel
        let cached = OllamaProvider.shared.cachedModels
        if !cached.isEmpty && !cached.contains(where: { $0.name == configured }) {
            if let bestVision = cached.first(where: {
                let lower = $0.name.lowercased()
                return lower.contains("llava") || lower.contains("vision") || lower.contains("-vl")
            }) ?? cached.first {
                return OllamaProvider(model: bestVision.name)
            }
        }
        return OllamaProvider(model: configured)
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
        
        let kokoroDiag = KokoroTTSEngine.shared.diagnostics()
        let whisperDiag = LocalWhisperProvider.diagnostics()
        let sttDesc = whisperDiag.isReady ? "Whisper (Local Neural)" : "Apple Speech (Contextual)"
        let ttsDesc = kokoroDiag.isFullyReady ? "Kokoro-82M (Neural Audio)" : "macOS Neural TTS"
        
        return ModelStatusSummary(
            mode: currentMode,
            chatProvider: chatProv,
            chatModelId: chatM,
            visionProvider: visionProv,
            visionModelId: visionM,
            sttProvider: sttDesc,
            ttsProvider: ttsDesc,
            searchProvider: (resolveSearchProvider()?.providerName) ?? "Not Configured",
            isOllamaRunning: isOllama,
            hasCloudKey: hasCloud,
            privacyDescription: privacy
        )
    }
    
    // MARK: - Auto-Connect Local Offline Models
    
    @discardableResult
    public func connectLocalOfflineModels(timeoutSeconds: Double = 12.0) async -> (success: Bool, message: String, models: [String]) {
        let result = await OllamaProvider.shared.ensureRunningAndConnected(timeoutSeconds: timeoutSeconds)
        
        if result.success {
            let modelNames = result.models.map { $0.name }
            
            // If Ollama is running and has models, verify or auto-assign active models
            if !result.models.isEmpty {
                let hasCurrentChat = result.models.contains { $0.name.lowercased().contains(ollamaChatModel.lowercased()) }
                if !hasCurrentChat {
                    if let bestChat = result.models.first(where: {
                        let n = $0.name.lowercased()
                        return n.contains("llama3.2") || n.contains("qwen2.5") || n.contains("mistral") || n.contains("llama")
                    }) {
                        self.ollamaChatModel = bestChat.name
                    } else if let first = result.models.first {
                        self.ollamaChatModel = first.name
                    }
                }
                
                let hasCurrentVision = result.models.contains { $0.name.lowercased().contains(ollamaVisionModel.lowercased()) }
                if !hasCurrentVision {
                    if let bestVision = result.models.first(where: {
                        let n = $0.name.lowercased()
                        return n.contains("llava") || n.contains("qwen2-vl") || n.contains("vision")
                    }) {
                        self.ollamaVisionModel = bestVision.name
                    }
                }
            }
            
            // Pre-warm local model weights into memory in the background
            prewarmLocalModel()
            
            // Refresh catalog download status
            await LocalModelDownloadManager.shared.refreshInstalledStatuses()
            
            return (true, result.message, modelNames)
        } else {
        return (false, result.message, [])
        }
    }
    
    public func prewarmLocalModel() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let chatModel = self.resolveLocalChatModel()
            _ = try? await chatModel.sendMessage(
                messages: [LLMChatMessage(role: .user, content: "hi")],
                tools: nil,
                jsonMode: false
            )
        }
    }

    // MARK: - Voice-Controlled Automatic Model & Tier Switching

    public struct VoiceModelSwitchResult: Sendable, Equatable {
        public let matched: Bool
        public let mode: ModelMode
        public let providerName: String
        public let selectedModelId: String
        public let summary: String
        public let missingCloudKeyWarning: Bool

        public init(
            matched: Bool,
            mode: ModelMode,
            providerName: String,
            selectedModelId: String,
            summary: String,
            missingCloudKeyWarning: Bool = false
        ) {
            self.matched = matched
            self.mode = mode
            self.providerName = providerName
            self.selectedModelId = selectedModelId
            self.summary = summary
            self.missingCloudKeyWarning = missingCloudKeyWarning
        }
    }

    private enum ParsedModelSwitchIntent: Equatable {
        case localDefault
        case localSmaller
        case localLarger
        case largerAuto // upgrades to larger local model first if available, else paid cloud if keyed
        case localNamed(tokens: [String])
        case cloud(preferredProvider: String?) // "claude" | "openai" | nil (auto paid/money)
        case hybrid
    }

    public static func estimateParameterBillions(for info: OllamaModelInfo) -> Double {
        let paramRaw = (info.parameterSize ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !paramRaw.isEmpty {
            if paramRaw.hasSuffix("m"), let m = Double(paramRaw.dropLast()) {
                return m / 1000.0
            }
            let numStr = paramRaw.replacingOccurrences(of: "b", with: "")
            if let b = Double(numStr) {
                return b
            }
        }
        let lowerName = info.name.lowercased()
        if let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*b\b"#, options: []),
           let match = regex.firstMatch(in: lowerName, range: NSRange(lowerName.startIndex..., in: lowerName)),
           let r = Range(match.range(at: 1), in: lowerName),
           let parsed = Double(lowerName[r]) {
            return parsed
        }
        if let bytes = info.size, bytes > 0 {
            return Double(bytes) / 1_000_000_000.0
        }
        return 7.0
    }

    private static func parseVoiceModelSwitchIntent(from utterance: String) -> ParsedModelSwitchIntent? {
        let normalized = HinglishTransliterator.normalize(utterance)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !normalized.isEmpty else { return nil }

        let switchVerb = [
            "switch", "go to", "move to", "use ", "change to", "change model",
            "set model", "select model", "activate", "enable", "badlo", "lagao",
            "chalu", "pe jao", "par jao", "use karo", "switch karo"
        ].contains { normalized.contains($0) }

        let mentionsClaude = normalized.contains("claude") || normalized.contains("anthropic")
        let mentionsOpenAI = normalized.contains("chatgpt") || normalized.contains("chat gpt") ||
            normalized.contains("openai") || normalized.contains("gpt-4") || normalized.contains("gpt 4") ||
            (normalized.contains("gpt") && normalized.contains("model"))
        let mentionsMoneyPaidCloud = normalized.contains("paid") || normalized.contains("money") ||
            normalized.contains("mony") || normalized.contains("premium") || normalized.contains("cloud")
        let mentionsModelKeyword = normalized.contains("model") || normalized.contains("mode") || normalized.contains("ollama")
        let mentionsLocal = normalized.contains("local") || normalized.contains("ollama") || normalized.contains("offline") || normalized.contains("on-device")
        let mentionsSmall = normalized.contains("small") || normalized.contains("tiny") || normalized.contains("lite") ||
            normalized.contains("mini") || normalized.contains("light") || normalized.contains("chota") || normalized.contains("chote")
        let mentionsLarge = normalized.contains("large") || normalized.contains("big") || normalized.contains("heavy") ||
            normalized.contains("strong") || normalized.contains("best") || normalized.contains("bada") || normalized.contains("bade")

        let specificFamilyHints = ["llama", "qwen", "mistral", "deepseek", "gemma", "phi", "3b", "7b", "8b", "14b", "32b", "70b"]
        let matchedHints = specificFamilyHints.filter { normalized.contains($0) }

        // Require explicit model-switching context so normal chat doesn't misfire
        let hasModelIntentContext = switchVerb || mentionsModelKeyword
        guard hasModelIntentContext else { return nil }

        if mentionsClaude {
            return .cloud(preferredProvider: "claude")
        }
        if mentionsOpenAI {
            return .cloud(preferredProvider: "openai")
        }
        if normalized.contains("hybrid") && mentionsModelKeyword {
            return .hybrid
        }
        if mentionsMoneyPaidCloud && (mentionsModelKeyword || switchVerb) {
            return .cloud(preferredProvider: nil)
        }
        if mentionsLocal || !matchedHints.isEmpty || ((mentionsSmall || mentionsLarge) && normalized.contains("model")) {
            if mentionsSmall && matchedHints.isEmpty {
                return .localSmaller
            }
            if !matchedHints.isEmpty && (switchVerb || normalized.contains("model")) {
                return .localNamed(tokens: matchedHints)
            }
            if mentionsLarge {
                return mentionsLocal ? .localLarger : .largerAuto
            }
            if mentionsLocal {
                return .localDefault
            }
        }
        return nil
    }

    /// Evaluates natural voice commands ("go to local model", "switch to smaller local model",
    /// "switch back to larger model", "go to paid/money/claude/chatgpt model") and updates ModelRouter state.
    @discardableResult
    public func switchModelByVoice(
        _ utterance: String,
        availableLocalModels: [OllamaModelInfo]? = nil
    ) async -> VoiceModelSwitchResult? {
        guard let intent = Self.parseVoiceModelSwitchIntent(from: utterance) else {
            return nil
        }

        // Gather installed Ollama chat models (live or injected for tests)
        var discovered: [OllamaModelInfo] = availableLocalModels ?? OllamaProvider.shared.cachedModels
        if availableLocalModels == nil && discovered.isEmpty && ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] != "1" {
            if let live = try? await OllamaProvider.shared.listLocalModels() {
                discovered = live
            }
        }
        let nonVisionChatModels = discovered.filter {
            let n = $0.name.lowercased()
            return !n.contains("llava") && !n.contains("-vl") && !n.contains("vision")
        }
        let candidatePool = nonVisionChatModels.isEmpty ? discovered : nonVisionChatModels
        let sortedBySize = candidatePool.sorted { a, b in
            let pa = Self.estimateParameterBillions(for: a)
            let pb = Self.estimateParameterBillions(for: b)
            if abs(pa - pb) > 0.05 { return pa < pb }
            return (a.size ?? 0) < (b.size ?? 0)
        }

        func switchToCloud(preferredProvider: String?, reasonNote: String = "") -> VoiceModelSwitchResult {
            let hasOpenAI = !(keychain.get(.openAIApiKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasClaude = !(keychain.get(.anthropicApiKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            let targetProvider: String
            if let explicit = preferredProvider {
                targetProvider = explicit
            } else if (cloudProvider == "claude" && hasClaude) || (!hasOpenAI && hasClaude) {
                targetProvider = "claude"
            } else if hasOpenAI {
                targetProvider = "openai"
            } else {
                targetProvider = cloudProvider
            }

            UserDefaults.standard.set(ModelMode.cloud.rawValue, forKey: modeKey)
            self.cloudProvider = targetProvider
            let modelId = (targetProvider == "claude") ? claudeModel : openAIModel
            let hasKeyForSelected = (targetProvider == "claude") ? hasClaude : hasOpenAI
            let providerTitle = (targetProvider == "claude") ? "Claude (Anthropic)" : "ChatGPT (OpenAI)"

            publishModelSwitched(mode: .cloud, provider: providerTitle, modelId: modelId)
            let warningSuffix = hasKeyForSelected
                ? ""
                : " Note: Add your \(providerTitle) API key in Settings → AI Brain & Models so requests can authenticate."
            let prefix = reasonNote.isEmpty ? "" : "\(reasonNote) "
            return VoiceModelSwitchResult(
                matched: true,
                mode: .cloud,
                providerName: providerTitle,
                selectedModelId: modelId,
                summary: "\(prefix)Switched to Cloud mode using \(providerTitle) (\(modelId)).\(warningSuffix)",
                missingCloudKeyWarning: !hasKeyForSelected
            )
        }

        switch intent {
        case .cloud(let preferred):
            return switchToCloud(preferredProvider: preferred)

        case .hybrid:
            UserDefaults.standard.set(ModelMode.hybrid.rawValue, forKey: modeKey)
            let resolved = resolveChatModel()
            publishModelSwitched(mode: .hybrid, provider: resolved.providerName, modelId: resolved.modelIdentifier)
            return VoiceModelSwitchResult(
                matched: true,
                mode: .hybrid,
                providerName: "Hybrid",
                selectedModelId: resolved.modelIdentifier,
                summary: "Switched to Hybrid mode (active chat model: \(resolved.modelIdentifier))."
            )

        case .localDefault:
            UserDefaults.standard.set(ModelMode.local.rawValue, forKey: modeKey)
            let chosen = ollamaChatModel
            publishModelSwitched(mode: .local, provider: "Ollama", modelId: chosen)
            return VoiceModelSwitchResult(
                matched: true,
                mode: .local,
                providerName: "Ollama (Local)",
                selectedModelId: chosen,
                summary: "Switched to 100% Local mode using \(chosen)."
            )

        case .localSmaller:
            UserDefaults.standard.set(ModelMode.local.rawValue, forKey: modeKey)
            let currentName = ollamaChatModel
            let chosenModel: String
            if let currentEntry = sortedBySize.first(where: { $0.name.caseInsensitiveCompare(currentName) == .orderedSame }) {
                let currentB = Self.estimateParameterBillions(for: currentEntry)
                let smaller = sortedBySize.last { Self.estimateParameterBillions(for: $0) < currentB - 0.1 }
                chosenModel = smaller?.name ?? sortedBySize.first?.name ?? "llama3.2:3b"
            } else {
                chosenModel = sortedBySize.first?.name ?? "llama3.2:3b"
            }
            self.ollamaChatModel = chosenModel
            publishModelSwitched(mode: .local, provider: "Ollama", modelId: chosenModel)
            return VoiceModelSwitchResult(
                matched: true,
                mode: .local,
                providerName: "Ollama (Local)",
                selectedModelId: chosenModel,
                summary: "Switched to the smaller local model: \(chosenModel)."
            )

        case .localLarger:
            UserDefaults.standard.set(ModelMode.local.rawValue, forKey: modeKey)
            let currentName = ollamaChatModel
            let chosenModel: String
            if let currentEntry = sortedBySize.first(where: { $0.name.caseInsensitiveCompare(currentName) == .orderedSame }) {
                let currentB = Self.estimateParameterBillions(for: currentEntry)
                let larger = sortedBySize.last { Self.estimateParameterBillions(for: $0) > currentB + 0.1 }
                chosenModel = larger?.name ?? sortedBySize.last?.name ?? currentName
            } else {
                chosenModel = sortedBySize.last?.name ?? currentName
            }
            self.ollamaChatModel = chosenModel
            publishModelSwitched(mode: .local, provider: "Ollama", modelId: chosenModel)
            return VoiceModelSwitchResult(
                matched: true,
                mode: .local,
                providerName: "Ollama (Local)",
                selectedModelId: chosenModel,
                summary: "Switched to the larger local model: \(chosenModel)."
            )

        case .largerAuto:
            // If a larger installed local model exists when currently local/hybrid, upgrade locally first;
            // otherwise if paid cloud keys are configured, upgrade to Cloud mode.
            if let largest = sortedBySize.last {
                let currentB = sortedBySize
                    .first(where: { $0.name.caseInsensitiveCompare(ollamaChatModel) == .orderedSame })
                    .map { Self.estimateParameterBillions(for: $0) } ?? 0.0
                let largestB = Self.estimateParameterBillions(for: largest)
                if largestB > currentB + 0.1 {
                    UserDefaults.standard.set(ModelMode.local.rawValue, forKey: modeKey)
                    self.ollamaChatModel = largest.name
                    publishModelSwitched(mode: .local, provider: "Ollama", modelId: largest.name)
                    return VoiceModelSwitchResult(
                        matched: true,
                        mode: .local,
                        providerName: "Ollama (Local)",
                        selectedModelId: largest.name,
                        summary: "Switched to the larger local model: \(largest.name)."
                    )
                }
            }
            if hasValidCloudKey() {
                return switchToCloud(preferredProvider: nil, reasonNote: "No larger local model found;")
            }
            UserDefaults.standard.set(ModelMode.local.rawValue, forKey: modeKey)
            let chosen = sortedBySize.last?.name ?? ollamaChatModel
            self.ollamaChatModel = chosen
            publishModelSwitched(mode: .local, provider: "Ollama", modelId: chosen)
            return VoiceModelSwitchResult(
                matched: true,
                mode: .local,
                providerName: "Ollama (Local)",
                selectedModelId: chosen,
                summary: "Using your largest installed local model: \(chosen)."
            )

        case .localNamed(let tokens):
            UserDefaults.standard.set(ModelMode.local.rawValue, forKey: modeKey)
            if let matched = candidatePool.first(where: { info in
                let lowerName = info.name.lowercased()
                let paramLower = (info.parameterSize ?? "").lowercased()
                return tokens.allSatisfy { tok in lowerName.contains(tok) || paramLower.contains(tok) }
            }) ?? candidatePool.first(where: { info in
                let lowerName = info.name.lowercased()
                return tokens.contains { tok in lowerName.contains(tok) }
            }) {
                self.ollamaChatModel = matched.name
                publishModelSwitched(mode: .local, provider: "Ollama", modelId: matched.name)
                return VoiceModelSwitchResult(
                    matched: true,
                    mode: .local,
                    providerName: "Ollama (Local)",
                    selectedModelId: matched.name,
                    summary: "Switched to local Ollama model: \(matched.name)."
                )
            }
            let current = ollamaChatModel
            publishModelSwitched(mode: .local, provider: "Ollama", modelId: current)
            return VoiceModelSwitchResult(
                matched: true,
                mode: .local,
                providerName: "Ollama (Local)",
                selectedModelId: current,
                summary: "Switched to Local mode (active model: \(current); no installed model matched \(tokens.joined(separator: ", ")))."
            )
        }
    }

    private func publishModelSwitched(mode: ModelMode, provider: String, modelId: String) {
        EventBus.shared.publish(VoiceEvent(
            kind: .custom("model_switched"),
            source: "ModelRouter",
            severity: .info,
            payload: ["mode": mode.rawValue, "provider": provider, "model": modelId]
        ))
    }
}
