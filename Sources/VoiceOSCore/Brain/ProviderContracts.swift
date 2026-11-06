import Foundation
import AppKit

// MARK: - Core Message & Tool Schemas

public enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct LLMChatMessage: Codable, Sendable {
    public let role: MessageRole
    public let content: String
    public let imageDataList: [Data]?
    public let toolCalls: [ToolCall]?
    public let toolCallId: String?
    
    public init(
        role: MessageRole,
        content: String,
        imageDataList: [Data]? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil
    ) {
        self.role = role
        self.content = content
        self.imageDataList = imageDataList
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

public struct ToolDefinition: Codable, Sendable {
    public let name: String
    public let description: String
    public let parametersJSON: String
    
    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }
}

public struct ToolCall: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let argumentsJSON: String
    
    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct TokenUsage: Codable, Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    
    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

public struct ChatResponse: Sendable {
    public let text: String
    public let toolCalls: [ToolCall]
    public let usage: TokenUsage?
    public let finishReason: String?
    
    public init(
        text: String,
        toolCalls: [ToolCall] = [],
        usage: TokenUsage? = nil,
        finishReason: String? = nil
    ) {
        self.text = text
        self.toolCalls = toolCalls
        self.usage = usage
        self.finishReason = finishReason
    }
}

// MARK: - Vision & Grounding Schemas

public struct GroundedUIElement: Codable, Sendable {
    public let label: String
    public let normalizedRect: CGRect // 0.0 ... 1.0 coordinates
    public let screenPoint: CGPoint    // Actual display coordinates
    public let confidence: Double
    
    public init(label: String, normalizedRect: CGRect, screenPoint: CGPoint, confidence: Double = 1.0) {
        self.label = label
        self.normalizedRect = normalizedRect
        self.screenPoint = screenPoint
        self.confidence = confidence
    }
}

public struct VisionAnalysisResponse: Sendable {
    public let text: String
    public let groundedElements: [GroundedUIElement]
    public let suggestedAction: String?
    public let rawResponseJSON: String?
    
    public init(
        text: String,
        groundedElements: [GroundedUIElement] = [],
        suggestedAction: String? = nil,
        rawResponseJSON: String? = nil
    ) {
        self.text = text
        self.groundedElements = groundedElements
        self.suggestedAction = suggestedAction
        self.rawResponseJSON = rawResponseJSON
    }
}

// MARK: - Voice & Search Schemas

public struct VoiceOption: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(provider):\(identifier)" }
    public let identifier: String
    public let name: String
    public let provider: String // "System", "OpenAI", "ElevenLabs", "Kokoro"
    public let language: String // "en-US", "hi-IN", "multilingual"
    public let isNeural: Bool
    
    public init(identifier: String, name: String, provider: String, language: String, isNeural: Bool) {
        self.identifier = identifier
        self.name = name
        self.provider = provider
        self.language = language
        self.isNeural = isNeural
    }
}

public struct SearchResultItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { url.absoluteString }
    public let title: String
    public let snippet: String
    public let url: URL
    public let publishedDate: String?
    
    public init(title: String, snippet: String, url: URL, publishedDate: String? = nil) {
        self.title = title
        self.snippet = snippet
        self.url = url
        self.publishedDate = publishedDate
    }
}

// MARK: - Capability Profile & Modes

public enum ModelMode: String, CaseIterable, Codable, Sendable {
    case cloud = "Cloud Mode (API Key)"
    case local = "Local Mode (Ollama On-Device)"
    case hybrid = "Hybrid Mode (Local Fast, Cloud Deep)"
    case googleSearch = "Google Search only (free, lightest)"
}

public enum AutonomyLevel: String, CaseIterable, Codable, Sendable {
    case showOnly = "Show Only (Point & Explain)"
    case stepByStep = "Step-by-Step (Confirm each action)"
    case autoRun = "Auto (Autonomous Execution)"
}

public struct CapabilityProfile: Codable, Sendable {
    public let streaming: Bool
    public let toolCalling: Bool
    public let vision: Bool
    public let jsonMode: Bool
    public let contextLength: Int
    public let supportedLanguages: [String]
    public let speedTokensPerSec: Double
    public let estimatedCostPer1kTokens: Double
    public let testedAt: Date
    public let probeSuccess: Bool
    public let probeMessage: String
    
    public init(
        streaming: Bool = false,
        toolCalling: Bool = false,
        vision: Bool = false,
        jsonMode: Bool = false,
        contextLength: Int = 4096,
        supportedLanguages: [String] = ["en"],
        speedTokensPerSec: Double = 0.0,
        estimatedCostPer1kTokens: Double = 0.0,
        testedAt: Date = Date(),
        probeSuccess: Bool = false,
        probeMessage: String = "Not probed"
    ) {
        self.streaming = streaming
        self.toolCalling = toolCalling
        self.vision = vision
        self.jsonMode = jsonMode
        self.contextLength = contextLength
        self.supportedLanguages = supportedLanguages
        self.speedTokensPerSec = speedTokensPerSec
        self.estimatedCostPer1kTokens = estimatedCostPer1kTokens
        self.testedAt = testedAt
        self.probeSuccess = probeSuccess
        self.probeMessage = probeMessage
    }
}

// MARK: - Pluggable Provider Protocols

public protocol ChatModel: Sendable {
    var providerName: String { get }
    var modelIdentifier: String { get }
    
    func sendMessage(
        messages: [LLMChatMessage],
        tools: [ToolDefinition]?,
        jsonMode: Bool
    ) async throws -> ChatResponse
    
    func streamMessage(
        messages: [LLMChatMessage],
        tools: [ToolDefinition]?,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> ChatResponse
}

public protocol VisionModel: Sendable {
    var providerName: String { get }
    var modelIdentifier: String { get }
    
    func analyzeImage(
        image: NSImage,
        prompt: String,
        tools: [ToolDefinition]?
    ) async throws -> VisionAnalysisResponse
}

public protocol SpeechToTextModel: Sendable {
    var providerName: String { get }
    
    func transcribe(
        audioData: Data,
        language: String?,
        promptHints: [String]
    ) async throws -> (text: String, detectedLanguage: String, confidence: Double)
}

public protocol TextToSpeechModel: Sendable {
    var providerName: String { get }
    
    func listAvailableVoices() async -> [VoiceOption]
    func synthesizeSpeech(text: String, voice: VoiceOption, speed: Float) async throws -> Data
}

public protocol SearchProvider: Sendable {
    var providerName: String { get }
    
    func search(query: String, maxResults: Int) async throws -> [SearchResultItem]
    func fetchPageContent(url: URL) async throws -> String
}

// MARK: - Common Brain Errors

public enum BrainError: LocalizedError, Sendable {
    case missingApiKey(provider: String)
    case invalidApiKey(provider: String)
    case quotaExceeded(provider: String)
    case rateLimited(provider: String)
    case networkUnavailable
    case ollamaNotRunning(url: String)
    case modelNotFound(name: String)
    case missingCapability(capability: String, model: String)
    case requestFailed(statusCode: Int, message: String)
    case decodingFailed(message: String)
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .missingApiKey(let p):
            return "Missing API key for \(p). Please configure it in Settings."
        case .invalidApiKey(let p):
            return "Invalid API key for \(p). Check your credentials."
        case .quotaExceeded(let p):
            return "\(p) quota exceeded or account balance depleted."
        case .rateLimited(let p):
            return "\(p) rate limit hit. Backing off."
        case .networkUnavailable:
            return "Network connection unavailable."
        case .ollamaNotRunning(let url):
            return "Ollama is not running at \(url). Please start Ollama or switch to Cloud mode."
        case .modelNotFound(let name):
            return "Model '\(name)' not found. Run 'ollama pull \(name)'."
        case .missingCapability(let cap, let m):
            return "Model '\(m)' does not support \(cap)."
        case .requestFailed(let code, let msg):
            return "Request failed (status \(code)): \(msg)"
        case .decodingFailed(let msg):
            return "Failed to parse model response: \(msg)"
        case .timeout:
            return "Request timed out."
        }
    }
}
