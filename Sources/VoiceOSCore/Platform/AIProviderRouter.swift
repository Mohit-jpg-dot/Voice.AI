import Foundation
import AppKit

public enum AIProvider: String, CaseIterable, Codable, Sendable {
    case chatgpt = "ChatGPT"
    case claude = "Claude"
    case gemini = "Gemini"
    
    public var iconName: String {
        switch self {
        case .chatgpt: return "sparkles"
        case .claude: return "brain.head.profile"
        case .gemini: return "sparkles.rectangle.stack"
        }
    }
    
    public func url(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch self {
        case .chatgpt:
            return URL(string: "https://chatgpt.com/?q=\(encoded)")
        case .claude:
            return URL(string: "https://claude.ai/new?q=\(encoded)")
        case .gemini:
            return URL(string: "https://gemini.google.com/app?q=\(encoded)")
        }
    }
}

public struct ComplexTaskRouteResult: Sendable {
    public let isComplex: Bool
    public let provider: AIProvider
    public let cleanPrompt: String
    public let url: URL?
    public let summary: String
    
    public init(isComplex: Bool, provider: AIProvider, cleanPrompt: String, url: URL?, summary: String) {
        self.isComplex = isComplex
        self.provider = provider
        self.cleanPrompt = cleanPrompt
        self.url = url
        self.summary = summary
    }
}

/// Detects complex coding, architectural, reasoning, and multi-step tasks,
/// and routes them to leading frontier models (ChatGPT, Claude, Gemini).
public final class AIProviderRouter: @unchecked Sendable {
    public static let shared = AIProviderRouter()
    
    // User preferred AI provider for complex queries (persisted in UserDefaults)
    public var defaultProvider: AIProvider {
        get {
            if let saved = UserDefaults.standard.string(forKey: "VoiceOS_PreferredAIProvider"),
               let provider = AIProvider(rawValue: saved) {
                return provider
            }
            return .chatgpt
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "VoiceOS_PreferredAIProvider")
        }
    }
    
    public init() {}
    
    public func evaluateAndRoute(transcript: String) -> ComplexTaskRouteResult? {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let lower = text.lowercased()
        
        // 1. Check for explicit AI provider mentions
        var targetProvider = self.defaultProvider
        var hasExplicitProvider = false
        
        if lower.contains("claude") {
            targetProvider = .claude
            hasExplicitProvider = true
        } else if lower.contains("gemini") {
            targetProvider = .gemini
            hasExplicitProvider = true
        } else if lower.contains("chatgpt") || lower.contains("chat gpt") || lower.contains("openai") {
            targetProvider = .chatgpt
            hasExplicitProvider = true
        }
        
        // 2. Check for coding or programming intent
        let codingKeywords = [
            "code", "coding", "program", "script", "python", "swift",
            "javascript", "typescript", "react", "html", "css", "sql",
            "algorithm", "function", "class", "component", "debug",
            "error in code", "regex", "api", "refactor", "unit test",
            "git", "dockerfile", "terminal script", "write a function",
            "write code", "fix the bug", "implement a", "how to write in"
        ]
        
        let hasCodingIntent = codingKeywords.contains { lower.contains($0) }
        
        // 3. Check for advanced reasoning or creative generation
        let advancedReasoningKeywords = [
            "write an essay", "draft a proposal", "architecture design",
            "system design", "explain quantum", "complex analysis",
            "deep dive", "solve equation", "mathematical proof",
            "business plan", "step-by-step tutorial", "write an article"
        ]
        
        let hasAdvancedReasoning = advancedReasoningKeywords.contains { lower.contains($0) }
        
        guard hasExplicitProvider || hasCodingIntent || hasAdvancedReasoning else {
            return nil
        }
        
        // Clean the prompt to extract the core task
        let cleanPrompt = extractCorePrompt(from: text)
        let deepLinkURL = targetProvider.url(for: cleanPrompt.isEmpty ? text : cleanPrompt)
        
        let summary: String
        if hasCodingIntent {
            summary = "Routing coding task to \(targetProvider.rawValue): \"\(cleanPrompt.prefix(40))...\""
        } else {
            summary = "Dispatched query to \(targetProvider.rawValue)"
        }
        
        return ComplexTaskRouteResult(
            isComplex: true,
            provider: targetProvider,
            cleanPrompt: cleanPrompt,
            url: deepLinkURL,
            summary: summary
        )
    }
    
    private func extractCorePrompt(from text: String) -> String {
        var str = text
        let phrasesToRemove = [
            "ask chatgpt to ", "ask chatgpt ", "in chatgpt ", "chatgpt ",
            "ask claude to ", "ask claude ", "in claude ", "claude ",
            "ask gemini to ", "ask gemini ", "in gemini ", "gemini ",
            "can you please ", "can you ", "help me ", "i want you to "
        ]
        
        for p in phrasesToRemove {
            if let range = str.range(of: p, options: .caseInsensitive) {
                str.removeSubrange(range)
            }
        }
        return str.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

