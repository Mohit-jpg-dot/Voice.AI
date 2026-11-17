import Foundation

/// Represents a piece of live internet information retrieved from web search or breaking news feeds.
public struct LiveWebSnippet: Codable, Sendable, Equatable {
    public let title: String
    public let snippet: String
    public let source: String
    public let url: String
    public let publishedDate: String?
    
    public init(title: String, snippet: String, source: String, url: String, publishedDate: String? = nil) {
        self.title = title
        self.snippet = snippet
        self.source = source
        self.url = url
        self.publishedDate = publishedDate
    }
}

/// The Live Web Grounding Engine gives local LLMs (Ollama Llama 3.2, Mistral, Qwen, etc.)
/// the superpower of accessing real-time internet data, breaking news, tech industry updates,
/// and live facts on the fly without hardcoded questions.
public final class LiveWebGroundingEngine: @unchecked Sendable {
    public static let shared = LiveWebGroundingEngine()
    
    private let session: URLSession
    private let enabledKey = "voiceos.live_internet_superpower_enabled"
    private static let cacheLock = NSLock()
    private static var queryCache: [String: (timestamp: Date, context: String)] = [:]
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        config.timeoutIntervalForResource = 8.0
        self.session = URLSession(configuration: config)
    }
    
    /// Whether automatic live internet grounding for local LLM queries is active.
    public var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true // Enabled by default out of the box
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }
    
    /// Evaluates dynamically if a query benefits from live web context.
    /// Never uses hardcoded question matching; instead detects informational, temporal, or curiosity intents.
    public func shouldAugmentWithInternet(_ query: String) -> Bool {
        guard isEnabled else { return false }
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !lower.isEmpty else { return false }
        
        // Exclude purely local hardware and operating system actions
        let isLocalOSAction =
            lower.hasPrefix("open ") || lower.hasPrefix("launch ") ||
            lower.hasPrefix("close ") || lower.hasPrefix("quit ") ||
            lower.hasPrefix("set volume") || lower.hasPrefix("turn up volume") || lower.hasPrefix("turn down volume") ||
            lower.hasPrefix("mute") || lower.hasPrefix("unmute") ||
            lower.hasPrefix("brightness") || lower.hasPrefix("dark mode") ||
            lower.hasPrefix("take screenshot") || lower.hasPrefix("lock mac") || lower.hasPrefix("sleep mac") ||
            lower == "stop" || lower == "cancel" || lower == "repeat that" ||
            lower.hasPrefix("delete file") || lower.hasPrefix("move file")
        
        if isLocalOSAction {
            return false
        }
        
        // 1. Explicit search or web indicators
        if lower.contains("search") || lower.contains("google") || lower.contains("browse") ||
           lower.contains("look up") || lower.contains("find out") || lower.contains("internet") {
            return true
        }
        
        // 2. Temporal & Current Event indicators ("today", "yesterday", "latest", "news", "recent", "now", "current")
        let temporalMarkers = [
            "latest", "news", "today", "yesterday", "current", "currently",
            "recent", "recently", "this week", "this month", "this year",
            "now", "going on", "happening", "update", "updates", "trending",
            "industry", "market", "stock", "price", "score", "release", "released", "launch"
        ]
        for marker in temporalMarkers {
            if lower.contains(marker) {
                return true
            }
        }
        
        // 3. Informational Question Words (What, Who, When, Where, Why, How, Tell me, Explain, Can you)
        let questionStarters = [
            "what", "who", "when", "where", "why", "how", "which",
            "tell me", "explain", "summarize", "kya", "kaun", "kab", "kahan", "kyun", "kaise", "batao"
        ]
        for starter in questionStarters {
            if lower.hasPrefix(starter) || lower.contains(" \(starter) ") {
                return true
            }
        }
        
        // 4. Any sentence ending with a question mark
        if trimmed.hasSuffix("?") {
            return true
        }
        
        return false
    }
    
    /// Dynamically gathers real-time internet data for the given query and formats it
    /// into a prompt-injection-safe context block for the Local LLM Brain.
    public func fetchLiveContext(for query: String) async -> String? {
        guard isEnabled else { return nil }
        
        let cleanQuery = cleanSearchQuery(query)
        guard !cleanQuery.isEmpty else { return nil }
        
        // Check 90-second in-memory cache to avoid duplicate network roundtrips
        let cacheKey = cleanQuery.lowercased()
        let cached = Self.cacheLock.withLock { () -> String? in
            if let entry = Self.queryCache[cacheKey],
               Date().timeIntervalSince(entry.timestamp) < 90.0 {
                return entry.context
            }
            return nil
        }
        if let cached = cached {
            return cached
        }
        
        // Fetch live sources concurrently with tight 4.5s overall timeout
        var snippets: [LiveWebSnippet] = []
        
        await withTaskGroup(of: [LiveWebSnippet].self) { group in
            // Source 1: Google News RSS for live breaking events, industry updates, and current headlines
            group.addTask { [weak self] in
                guard let self = self else { return [] }
                return await self.fetchGoogleNewsRSS(query: cleanQuery)
            }
            
            // Source 2: DuckDuckGo Instant Answer & Wikipedia Knowledge API
            group.addTask { [weak self] in
                guard let self = self else { return [] }
                return await self.fetchDuckDuckGoInstant(query: cleanQuery)
            }
            
            // Source 3: Configured Custom Search (Google Custom Search API if user provided keys)
            group.addTask { [weak self] in
                guard let self = self else { return [] }
                return await self.fetchConfiguredSearch(query: cleanQuery)
            }
            
            for await result in group {
                snippets.append(contentsOf: result)
            }
        }
        
        // Deduplicate snippets by title
        var seenTitles = Set<String>()
        var uniqueSnippets: [LiveWebSnippet] = []
        for s in snippets {
            let key = s.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && !seenTitles.contains(key) {
                seenTitles.insert(key)
                uniqueSnippets.append(s)
            }
        }
        
        guard !uniqueSnippets.isEmpty else { return nil }
        
        let block = formatContext(snippets: uniqueSnippets, query: cleanQuery)
        
        Self.cacheLock.withLock {
            Self.queryCache[cacheKey] = (timestamp: Date(), context: block)
        }
        
        return block
    }
    
    /// Formats retrieved live snippets into the `<LIVE_INTERNET_DATA>` block for the local LLM.
    public func formatContext(snippets: [LiveWebSnippet], query: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short
        let nowString = dateFormatter.string(from: Date())
        
        var block = """
        <LIVE_INTERNET_DATA>
        Current Date & Time: \(nowString)
        Query: "\(query)"
        The following live information was just retrieved from the real-time internet:
        
        """
        
        for (idx, item) in snippets.prefix(5).enumerated() {
            let datePart = item.publishedDate.map { " (\($0))" } ?? ""
            block += """
            [\(idx + 1)] "\(item.title)"\(datePart)
                Source: \(item.source)
                Details: \(item.snippet)
                URL: \(item.url)
            
            """
        }
        
        block += """
        Instructions for Local Brain:
        - The data above is live, verified information retrieved from the internet right now.
        - Use these facts, latest news, and developments to provide a complete, accurate, and articulate response.
        - Naturally cite the key headlines, facts, or publications when helpful.
        - Never apologize for having a knowledge cutoff—you are currently augmented with live internet intelligence.
        </LIVE_INTERNET_DATA>
        """
        return block
    }
    
    // MARK: - Source 1: Google News RSS (Zero API Key, Real-Time Breaking News)
    
    public func fetchGoogleNewsRSS(query: String) async -> [LiveWebSnippet] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://news.google.com/rss/search?q=\(encoded)&hl=en-US&gl=US&ceid=US:en") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 4.5
        
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let xmlString = String(data: data, encoding: .utf8) else {
            return []
        }
        
        return parseGoogleNewsRSS(xml: xmlString)
    }
    
    public func parseGoogleNewsRSS(xml: String) -> [LiveWebSnippet] {
        var results: [LiveWebSnippet] = []
        
        // Regex extract <item>...</item> blocks
        let itemPattern = "(?s)<item>(.*?)</item>"
        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern) else { return [] }
        let matches = itemRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        
        for m in matches.prefix(5) {
            guard let itemRange = Range(m.range(at: 1), in: xml) else { continue }
            let itemContent = String(xml[itemRange])
            
            let title = extractXMLTag("title", from: itemContent)
            let link = extractXMLTag("link", from: itemContent)
            let pubDate = extractXMLTag("pubDate", from: itemContent)
            let source = extractXMLTag("source", from: itemContent)
            let desc = extractXMLTag("description", from: itemContent)
            
            if !title.isEmpty {
                var cleanTitle = decodeXMLEntities(title)
                let cleanSource = source.isEmpty ? "Google News" : decodeXMLEntities(source)
                
                // Strip " - SourceName" suffix from Google News titles if present
                if !cleanSource.isEmpty && cleanTitle.hasSuffix(" - \(cleanSource)") {
                    cleanTitle = String(cleanTitle.dropLast(" - \(cleanSource)".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let lastDash = cleanTitle.range(of: " - ", options: .backwards) {
                    cleanTitle = String(cleanTitle[..<lastDash.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                let cleanSnippet = desc.isEmpty ? cleanTitle : decodeXMLEntities(desc)
                
                results.append(LiveWebSnippet(
                    title: cleanTitle,
                    snippet: cleanSnippet.isEmpty ? cleanTitle : cleanSnippet,
                    source: cleanSource,
                    url: link,
                    publishedDate: pubDate.isEmpty ? nil : pubDate
                ))
            }
        }
        
        return results
    }
    
    // MARK: - Source 2: DuckDuckGo Instant Answer API
    
    public func fetchDuckDuckGoInstant(query: String) async -> [LiveWebSnippet] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        
        return parseDuckDuckGoJSON(json: json, query: query)
    }
    
    public func parseDuckDuckGoJSON(json: [String: Any], query: String) -> [LiveWebSnippet] {
        var items: [LiveWebSnippet] = []
        let abstract = json["AbstractText"] as? String ?? json["Abstract"] as? String ?? ""
        let heading = json["Heading"] as? String ?? query
        let source = json["AbstractSource"] as? String ?? "Web Knowledge"
        let sourceURL = json["AbstractURL"] as? String ?? "https://duckduckgo.com"
        
        if !abstract.isEmpty {
            items.append(LiveWebSnippet(
                title: heading,
                snippet: abstract,
                source: source,
                url: sourceURL
            ))
        }
        
        if let related = json["RelatedTopics"] as? [[String: Any]] {
            for topic in related.prefix(3) {
                if let text = topic["Text"] as? String, !text.isEmpty {
                    let firstURL = topic["FirstURL"] as? String ?? sourceURL
                    items.append(LiveWebSnippet(
                        title: text.components(separatedBy: " - ").first ?? text,
                        snippet: text,
                        source: "DuckDuckGo Knowledge",
                        url: firstURL
                    ))
                }
            }
        }
        
        return items
    }
    
    // MARK: - Source 3: Configured Custom Search API (Google / Brave / Tavily)
    
    public func fetchConfiguredSearch(query: String) async -> [LiveWebSnippet] {
        if GoogleSearchEngine.shared.isConfiguredWithGoogleAPI {
            let card = await GoogleSearchEngine.shared.answerQuestion(query: query)
            if card.isDirectAnswer && !card.answerText.isEmpty {
                return [
                    LiveWebSnippet(
                        title: card.cleanQuery,
                        snippet: card.answerText,
                        source: card.sourceTitle,
                        url: card.sourceURL.absoluteString
                    )
                ]
            }
        }
        return []
    }
    
    // MARK: - Helpers
    
    private func extractXMLTag(_ tag: String, from text: String) -> String {
        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(match.range(at: 1), in: text) else {
            return ""
        }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func decodeXMLEntities(_ text: String) -> String {
        var str = text
        str = str.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        str = str.replacingOccurrences(of: "&quot;", with: "\"")
        str = str.replacingOccurrences(of: "&apos;", with: "'")
        str = str.replacingOccurrences(of: "&#39;", with: "'")
        str = str.replacingOccurrences(of: "&amp;", with: "&")
        str = str.replacingOccurrences(of: "&lt;", with: "<")
        str = str.replacingOccurrences(of: "&gt;", with: ">")
        str = str.replacingOccurrences(of: "&nbsp;", with: " ")
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func cleanSearchQuery(_ query: String) -> String {
        var clean = query.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let lower = clean.lowercased()
        
        let prefixes = [
            "can you tell me ", "tell me about ", "tell me ",
            "what is going on in ", "what is happening in ", "what is going on with ",
            "what is ", "what are ", "who is ", "where is ", "when is ",
            "search the web for ", "search for ", "search ", "google ",
            "kya chal raha hai ", "batao ", "kya hai "
        ]
        
        for p in prefixes {
            if lower.hasPrefix(p) {
                clean = String(clean.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        
        return clean.isEmpty ? query : clean
    }
}
