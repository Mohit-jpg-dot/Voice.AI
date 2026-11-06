import Foundation

public final class BraveSearchProvider: SearchProvider, @unchecked Sendable {
    public let providerName = "Brave Search"
    private let apiKey: String
    private let session: URLSession
    
    public init(apiKey: String? = nil) {
        self.apiKey = apiKey ?? KeychainService.shared.get(.searchProviderKey) ?? ""
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        self.session = URLSession(configuration: config)
    }
    
    public func search(query: String, maxResults: Int = 5) async throws -> [SearchResultItem] {
        guard !apiKey.isEmpty else {
            throw BrainError.missingApiKey(provider: providerName)
        }
        
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "\(min(20, maxResults))")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            if code == 401 { throw BrainError.invalidApiKey(provider: providerName) }
            if code == 429 { throw BrainError.rateLimited(provider: providerName) }
            throw BrainError.requestFailed(statusCode: code, message: "Brave search failed")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = json["web"] as? [String: Any],
              let results = web["results"] as? [[String: Any]] else {
            return []
        }
        
        return results.compactMap { dict in
            guard let title = dict["title"] as? String,
                  let urlStr = dict["url"] as? String,
                  let url = URL(string: urlStr) else { return nil }
            let desc = dict["description"] as? String ?? ""
            let pageAge = dict["page_age"] as? String
            return SearchResultItem(title: title, snippet: desc, url: url, publishedDate: pageAge)
        }
    }
    
    public func fetchPageContent(url: URL) async throws -> String {
        return try await WebPageFetcher.shared.fetchAndSanitize(url: url)
    }
}

public final class TavilySearchProvider: SearchProvider, @unchecked Sendable {
    public let providerName = "Tavily Search"
    private let apiKey: String
    private let session: URLSession
    
    public init(apiKey: String? = nil) {
        self.apiKey = apiKey ?? KeychainService.shared.get(.searchProviderKey) ?? ""
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        self.session = URLSession(configuration: config)
    }
    
    public func search(query: String, maxResults: Int = 5) async throws -> [SearchResultItem] {
        guard !apiKey.isEmpty else {
            throw BrainError.missingApiKey(provider: providerName)
        }
        
        let url = URL(string: "https://api.tavily.com/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "api_key": apiKey,
            "query": query,
            "max_results": maxResults,
            "search_depth": "basic",
            "include_answer": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            if code == 401 { throw BrainError.invalidApiKey(provider: providerName) }
            if code == 429 { throw BrainError.rateLimited(provider: providerName) }
            throw BrainError.requestFailed(statusCode: code, message: "Tavily search failed")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        
        return results.compactMap { dict in
            guard let title = dict["title"] as? String,
                  let urlStr = dict["url"] as? String,
                  let url = URL(string: urlStr) else { return nil }
            let content = dict["content"] as? String ?? ""
            let publishedDate = dict["published_date"] as? String
            return SearchResultItem(title: title, snippet: content, url: url, publishedDate: publishedDate)
        }
    }
    
    public func fetchPageContent(url: URL) async throws -> String {
        return try await WebPageFetcher.shared.fetchAndSanitize(url: url)
    }
}

public final class SearXNGSearchProvider: SearchProvider, @unchecked Sendable {
    public let providerName = "SearXNG (Local / Self-Hosted)"
    public var hostURL: URL
    private let session: URLSession
    
    public init(hostURL: URL = URL(string: "http://localhost:8080")!) {
        self.hostURL = hostURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        self.session = URLSession(configuration: config)
    }
    
    public convenience init(baseURL: String) {
        let url = URL(string: baseURL) ?? URL(string: "http://localhost:8080")!
        self.init(hostURL: url)
    }
    
    public func search(query: String, maxResults: Int = 5) async throws -> [SearchResultItem] {
        var components = URLComponents(url: hostURL.appendingPathComponent("search"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json")
        ]
        
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw BrainError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: "SearXNG search failed")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        
        return results.prefix(maxResults).compactMap { dict in
            guard let title = dict["title"] as? String,
                  let urlStr = dict["url"] as? String,
                  let url = URL(string: urlStr) else { return nil }
            let content = dict["content"] as? String ?? ""
            return SearchResultItem(title: title, snippet: content, url: url)
        }
    }
    
    public func fetchPageContent(url: URL) async throws -> String {
        return try await WebPageFetcher.shared.fetchAndSanitize(url: url)
    }
}

/// Prompt-injection safe web page reader.
/// Fetches HTML, strips scripts/styles/tags, truncates text to safe limits,
/// and labels content as untrusted input.
public final class WebPageFetcher: @unchecked Sendable {
    public static let shared = WebPageFetcher()
    private let session: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        self.session = URLSession(configuration: config)
    }
    
    public func sanitizeHtml(_ html: String, url: URL? = nil, maxCharacters: Int = 4000) -> String {
        var clean = html
        clean = clean.replacingOccurrences(of: "(?s)<script.*?</script>", with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "(?s)<style.*?</style>", with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "&nbsp;", with: " ")
        clean = clean.replacingOccurrences(of: "&amp;", with: "&")
        clean = clean.replacingOccurrences(of: "&quot;", with: "\"")
        clean = clean.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let safeLength = min(clean.count, maxCharacters)
        let truncated = String(clean.prefix(safeLength))
        
        return """
        [BEGIN UNTRUSTED WEBPAGE DATA FROM: \(url?.absoluteString ?? "Web Source")]
        \(truncated)
        [END UNTRUSTED WEBPAGE DATA]
        """
    }
    
    public func fetchAndSanitize(url: URL, maxCharacters: Int = 4000) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BrainError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: "Could not fetch webpage")
        }
        
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw BrainError.decodingFailed(message: "Failed to decode webpage text")
        }
        
        return sanitizeHtml(html, url: url, maxCharacters: maxCharacters)
    }
}
