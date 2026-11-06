import Foundation
import AppKit

/// Pluggable ChatModel implementation for "Google Search only" mode.
/// Satisfies the ChatModel protocol by resolving user questions through the
/// deterministic GoogleSearchEngine rather than a generative LLM.
public final class GoogleOnlyBrain: ChatModel, @unchecked Sendable {
    public static let shared = GoogleOnlyBrain()
    
    public let providerName: String = "Google Search (No LLM)"
    public let modelIdentifier: String = "google-search-direct-v1"
    
    public init() {}
    
    public var capabilityProfile: CapabilityProfile {
        return CapabilityProfile(
            streaming: true,
            toolCalling: false,
            vision: false,
            jsonMode: false,
            contextLength: 2048,
            supportedLanguages: ["en", "hi"],
            speedTokensPerSec: 0,
            estimatedCostPer1kTokens: 0,
            testedAt: Date(),
            probeSuccess: true,
            probeMessage: "Google Search Engine Active (No LLM, zero parameters)"
        )
    }
    
    public func sendMessage(
        messages: [LLMChatMessage],
        tools: [ToolDefinition]? = nil,
        jsonMode: Bool = false
    ) async throws -> ChatResponse {
        // Find latest user prompt
        guard let lastUserMsg = messages.last(where: { $0.role == .user }) else {
            throw BrainError.decodingFailed(message: "No user message provided to Google Search.")
        }
        
        let card = await GoogleSearchEngine.shared.answerQuestion(query: lastUserMsg.content)
        
        var formatted = "\"\(card.answerText)\""
        formatted += "\n\n— \(card.sourceTitle) (\(card.methodLabel))"
        formatted += "\n🔗 \(card.sourceURL.absoluteString)"
        formatted += "\n⚡ Retrieved in \(card.retrievalTimeMs)ms"
        
        if !card.relatedLinks.isEmpty {
            formatted += "\n\nRelated Links:"
            for link in card.relatedLinks.prefix(3) {
                formatted += "\n• [\(link.title)](\(link.url.absoluteString))"
            }
        }
        
        return ChatResponse(
            text: formatted,
            toolCalls: [],
            usage: TokenUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0),
            finishReason: "stop"
        )
    }
    
    public func streamMessage(
        messages: [LLMChatMessage],
        tools: [ToolDefinition]? = nil,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> ChatResponse {
        let response = try await sendMessage(messages: messages, tools: tools)
        
        // Deliver streaming chunks smoothly
        let words = response.text.components(separatedBy: " ")
        for (i, word) in words.enumerated() {
            let chunk = (i == words.count - 1) ? word : "\(word) "
            onChunk(chunk)
            try? await Task.sleep(nanoseconds: 12_000_000)
        }
        
        return response
    }
}

