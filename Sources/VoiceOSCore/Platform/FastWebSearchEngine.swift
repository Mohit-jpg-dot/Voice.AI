import Foundation

public struct WebSearchAnswerResult: Sendable {
    public let query: String
    public let answer: String
    public let sourceTitle: String
    public let searchURL: URL
    
    public init(query: String, answer: String, sourceTitle: String = "Google Search", searchURL: URL) {
        self.query = query
        self.answer = answer
        self.sourceTitle = sourceTitle
        self.searchURL = searchURL
    }
}

/// Blazing fast web search & instant answer extractor.
/// Queries search endpoints via URLSession with a 3-second timeout,
/// parses featured snippets, entity definitions, and knowledge abstracts.
public final class FastWebSearchEngine: @unchecked Sendable {
    public static let shared = FastWebSearchEngine()
    
    private let session: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3.5
        config.timeoutIntervalForResource = 4.0
        self.session = URLSession(configuration: config)
    }
    
    public func searchAndAnswer(query: String) async -> WebSearchAnswerResult {
        let card = await GoogleSearchEngine.shared.answerQuestion(query: query)
        return WebSearchAnswerResult(
            query: card.cleanQuery,
            answer: card.answerText,
            sourceTitle: "\(card.sourceTitle) (\(card.methodLabel))",
            searchURL: card.sourceURL
        )
    }
    
    private func fetchDuckDuckGoAnswer(query: String) async -> String? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("\(AppBrand.name)/\(AppBrand.version) (Macintosh; Apple Silicon)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            
            if let answer = json["Answer"] as? String, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cleanSnippetText(answer)
            }
            if let abstract = json["AbstractText"] as? String, !abstract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cleanSnippetText(abstract)
            }
            if let definition = json["Definition"] as? String, !definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cleanSnippetText(definition)
            }
        } catch {
            return nil
        }
        return nil
    }
    
    private func fetchDuckDuckGoSnippet(query: String) async -> String? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            
            let pattern = "<a class=\"result__snippet\"[^>]*>([\\s\\S]*?)</a>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            
            let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..<html.endIndex, in: html))
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    let raw = String(html[range])
                    let cleaned = cleanSnippetText(raw)
                    if cleaned.count > 20 {
                        // Return first 2 sentences for concise natural speech
                        let sentences = cleaned.components(separatedBy: ". ")
                        if sentences.count > 1 {
                            return sentences.prefix(2).joined(separator: ". ") + "."
                        }
                        return cleaned
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    private func fetchWikipediaSummary(query: String) async -> String? {
        let entity = query
            .replacingOccurrences(of: "what is ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "who is ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: " ", with: "_")
        
        guard let encoded = entity.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("\(AppBrand.name)/\(AppBrand.version) (contact@voice.ai)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let extract = json["extract"] as? String, !extract.isEmpty else {
                return nil
            }
            return cleanSnippetText(extract)
        } catch {
            return nil
        }
    }
    
    private func cleanSearchQuery(_ raw: String) -> String {
        var q = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let prefixes = [
            "search google for ", "search for ", "search ",
            "google for ", "google ",
            "find out ", "look up ", "tell me about ", "tell me "
        ]
        for p in prefixes {
            if q.lowercased().hasPrefix(p) {
                q = String(q.dropFirst(p.count))
                break
            }
        }
        return q.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func cleanSnippetText(_ text: String) -> String {
        var str = text
            .replacingOccurrences(of: "<b>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "</b>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "...", with: "")
        
        // Remove footnotes like [1], [a]
        let regex = try? NSRegularExpression(pattern: "\\[[0-9a-zA-Z]+\\]", options: [])
        if let regex = regex {
            str = regex.stringByReplacingMatches(in: str, options: [], range: NSRange(str.startIndex..<str.endIndex, in: str), withTemplate: "")
        }
        
        while str.contains("  ") {
            str = str.replacingOccurrences(of: "  ", with: " ")
        }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

