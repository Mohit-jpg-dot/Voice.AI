import Foundation
import AppKit

public struct OllamaModelInfo: Identifiable, Codable, Sendable {
    public var id: String { name }
    public let name: String
    public let size: Int64?
    public let parameterSize: String?
    public let quantizationLevel: String?
    public let modifiedAt: String?
    
    public init(name: String, size: Int64? = nil, parameterSize: String? = nil, quantizationLevel: String? = nil, modifiedAt: String? = nil) {
        self.name = name
        self.size = size
        self.parameterSize = parameterSize
        self.quantizationLevel = quantizationLevel
        self.modifiedAt = modifiedAt
    }
}

public final class OllamaProvider: ChatModel, VisionModel, @unchecked Sendable {
    public static let shared = OllamaProvider()
    
    public let providerName = "Ollama"
    public var modelIdentifier: String
    public var hostURL: URL
    private let session: URLSession
    private let healthLock = NSLock()
    private var _cachedRunning: Bool = false
    private var _lastHealthCheck: Date = .distantPast
    private var _cachedModels: [OllamaModelInfo] = []
    private static let autoWakeLock = NSLock()
    private static var lastAutoWakeAttempt: Date = .distantPast
    
    public var isInstalledAndRunning: Bool {
        healthLock.lock()
        let age = Date().timeIntervalSince(_lastHealthCheck)
        let cached = _cachedRunning
        healthLock.unlock()
        
        if age < 10.0 {
            return cached
        }
        
        if Thread.isMainThread {
            // Never block UI main thread with synchronous Process/curl; refresh asynchronously
            Task.detached(priority: .utility) { [weak self] in
                _ = await self?.isRunning()
            }
            return cached
        }
        
        // Off main thread: fast non-Process URLSession probe
        let semaphore = DispatchSemaphore(value: 0)
        var reachable = false
        let endpoint = hostURL.appendingPathComponent("api/tags")
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = 1.0
        let task = session.dataTask(with: req) { _, response, _ in
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                reachable = true
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 1.2)
        
        healthLock.lock()
        _cachedRunning = reachable
        _lastHealthCheck = Date()
        healthLock.unlock()
        return reachable
    }
    
    public init(
        model: String = "llama3.2:3b",
        host: String? = nil
    ) {
        let configuredHost = host ?? KeychainService.shared.get(.ollamaHost) ?? "http://localhost:11434"
        self.hostURL = URL(string: configuredHost) ?? URL(string: "http://localhost:11434")!
        self.modelIdentifier = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120.0
        config.timeoutIntervalForResource = 300.0
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Health & Tag Discovery
    
    public var isOllamaInstalledOnSystem: Bool {
        if FileManager.default.fileExists(atPath: "/Applications/Ollama.app") { return true }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.ollama.ollama") != nil { return true }
        let paths = ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama", "/usr/bin/ollama"]
        return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }
    
    public func isRunning() async -> Bool {
        do {
            _ = try await listLocalModels()
            return true
        } catch {
            return false
        }
    }
    
    /// Launches the Ollama application or background daemon process (never both simultaneously to avoid port 11434 races)
    public func launchOllamaDaemon() {
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.ollama.ollama") {
            NSWorkspace.shared.openApplication(at: appUrl, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            return
        }
        if FileManager.default.fileExists(atPath: "/Applications/Ollama.app") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ollama.app"))
            return
        }
        
        // Fallback: CLI daemon only when Ollama.app is absent
        DispatchQueue.global(qos: .userInitiated).async {
            let possiblePaths = [
                "/usr/local/bin/ollama",
                "/opt/homebrew/bin/ollama",
                "/usr/bin/ollama"
            ]
            guard let bin = possiblePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
            
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: bin)
            proc.arguments = ["serve"]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            try? proc.run()
        }
    }
    
    /// Ensures Ollama daemon is running, launching it if necessary, and waits for it to become ready
    @discardableResult
    public func ensureRunningAndConnected(timeoutSeconds: Double = 12.0) async -> (success: Bool, message: String, models: [OllamaModelInfo]) {
        // 1. Fast check if already running
        if let models = try? await listLocalModels() {
            return (true, "Ollama is running with \(models.count) local model(s) discovered.", models)
        }
        
        // 2. Launch Ollama app or daemon
        launchOllamaDaemon()
        
        // 3. Poll until responsive
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeoutSeconds {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            if let models = try? await listLocalModels() {
                return (true, "Connected to Ollama! Discovered \(models.count) local model(s).", models)
            }
        }
        
        if let models = try? await listLocalModels() {
            return (true, "Connected to Ollama! Discovered \(models.count) local model(s).", models)
        }
        
        return (false, "Could not connect to Ollama at \(hostURL.absoluteString). Please verify Ollama is installed.", [])
    }
    
    public var cachedModels: [OllamaModelInfo] {
        healthLock.lock()
        defer { healthLock.unlock() }
        return _cachedModels
    }
    
    public func listLocalModels() async throws -> [OllamaModelInfo] {
        let endpoint = hostURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 4.0
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                healthLock.lock()
                _cachedRunning = false
                _lastHealthCheck = Date()
                healthLock.unlock()
                throw BrainError.ollamaNotRunning(url: hostURL.absoluteString)
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelsArray = json["models"] as? [[String: Any]] else {
                healthLock.lock()
                _cachedRunning = true
                _lastHealthCheck = Date()
                _cachedModels = []
                healthLock.unlock()
                return []
            }
            
            let parsed: [OllamaModelInfo] = modelsArray.compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                let size = dict["size"] as? Int64
                let details = dict["details"] as? [String: Any]
                let paramSize = details?["parameter_size"] as? String
                let quant = details?["quantization_level"] as? String
                let modAt = dict["modified_at"] as? String
                return OllamaModelInfo(name: name, size: size, parameterSize: paramSize, quantizationLevel: quant, modifiedAt: modAt)
            }
            
            healthLock.lock()
            _cachedRunning = true
            _lastHealthCheck = Date()
            _cachedModels = parsed
            healthLock.unlock()
            
            return parsed
        } catch {
            healthLock.lock()
            _cachedRunning = false
            _lastHealthCheck = Date()
            healthLock.unlock()
            throw BrainError.ollamaNotRunning(url: hostURL.absoluteString)
        }
    }
    
    public func pullModel(name: String, onProgress: @escaping @Sendable (Double, String) -> Void) async throws {
        let endpoint = hostURL.appendingPathComponent("api/pull")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 7200.0 // 2 hours for large model pulls
        
        let body: [String: Any] = ["name": name, "stream": true]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let pullConfig = URLSessionConfiguration.default
        pullConfig.timeoutIntervalForRequest = 3600.0
        pullConfig.timeoutIntervalForResource = 7200.0
        let pullSession = URLSession(configuration: pullConfig)
        
        let (bytes, response) = try await pullSession.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw BrainError.ollamaNotRunning(url: hostURL.absoluteString)
        }
        
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            
            if let errorMsg = json["error"] as? String {
                throw NSError(domain: "OllamaError", code: 404, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
            
            let status = json["status"] as? String ?? "downloading"
            
            let totalVal: Double
            if let num = json["total"] as? NSNumber {
                totalVal = num.doubleValue
            } else if let d = json["total"] as? Double {
                totalVal = d
            } else {
                totalVal = 0.0
            }
            
            let completedVal: Double
            if let num = json["completed"] as? NSNumber {
                completedVal = num.doubleValue
            } else if let d = json["completed"] as? Double {
                completedVal = d
            } else {
                completedVal = 0.0
            }
            
            let pct = totalVal > 0 ? min(1.0, max(0.0, completedVal / totalVal)) : 0.0
            onProgress(pct, status)
        }
    }
    
    // MARK: - ChatModel
    
    public func sendMessage(
        messages: [LLMChatMessage],
        tools: [ToolDefinition]?,
        jsonMode: Bool
    ) async throws -> ChatResponse {
        let endpoint = hostURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var bodyDict: [String: Any] = [
            "model": modelIdentifier,
            "messages": formatMessages(messages),
            "stream": false,
            "keep_alive": "15m",
            "options": [
                "num_ctx": 2048,
                "num_predict": jsonMode ? 280 : 300,
                "temperature": jsonMode ? 0.1 : 0.6
            ]
        ]
        
        if jsonMode {
            bodyDict["format"] = "json"
        }
        
        if let tools = tools, !tools.isEmpty {
            bodyDict["tools"] = tools.compactMap { tool in
                if let data = tool.parametersJSON.data(using: .utf8),
                   let schema = try? JSONSerialization.jsonObject(with: data) {
                    return [
                        "type": "function",
                        "function": [
                            "name": tool.name,
                            "description": tool.description,
                            "parameters": schema
                        ]
                    ]
                }
                return nil
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
        
        var data: Data
        var response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // If Ollama daemon wasn't awake yet, start/wait once cleanly and retry
            let nsErr = error as NSError
            let isConnErr = nsErr.domain == NSURLErrorDomain &&
                (nsErr.code == NSURLErrorCannotConnectToHost ||
                 nsErr.code == NSURLErrorNetworkConnectionLost ||
                 nsErr.code == NSURLErrorCannotFindHost)
            if isConnErr && isOllamaInstalledOnSystem {
                let shouldAutoWake: Bool = {
                    Self.autoWakeLock.lock()
                    defer { Self.autoWakeLock.unlock() }
                    if Date().timeIntervalSince(Self.lastAutoWakeAttempt) > 20.0 {
                        Self.lastAutoWakeAttempt = Date()
                        return true
                    }
                    return false
                }()
                if shouldAutoWake, (await ensureRunningAndConnected(timeoutSeconds: 4.0)).success {
                    do {
                        (data, response) = try await session.data(for: request)
                    } catch {
                        throw BrainError.ollamaNotRunning(url: hostURL.absoluteString)
                    }
                } else {
                    throw BrainError.ollamaNotRunning(url: hostURL.absoluteString)
                }
            } else {
                throw BrainError.ollamaNotRunning(url: hostURL.absoluteString)
            }
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrainError.ollamaNotRunning(url: hostURL.absoluteString)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errMsg = (errJson?["error"] as? String) ?? (String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)")
            if httpResponse.statusCode == 404 || errMsg.lowercased().contains("not found") {
                throw BrainError.modelNotFound(name: modelIdentifier)
            }
            throw BrainError.requestFailed(statusCode: httpResponse.statusCode, message: errMsg)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any] else {
            throw BrainError.decodingFailed(message: "Failed to parse Ollama message")
        }
        
        let text = message["content"] as? String ?? ""
        var toolCalls: [ToolCall] = []
        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            for (idx, call) in rawCalls.enumerated() {
                let fn = call["function"] as? [String: Any]
                let name = fn?["name"] as? String ?? "tool"
                let args = fn?["arguments"] as? [String: Any] ?? [:]
                let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
                let argsJSON = String(data: argsData, encoding: .utf8) ?? "{}"
                toolCalls.append(ToolCall(id: "call_\(idx)", name: name, argumentsJSON: argsJSON))
            }
        }
        
        let promptTokens = json["prompt_eval_count"] as? Int ?? 0
        let evalTokens = json["eval_count"] as? Int ?? 0
        let usage = TokenUsage(promptTokens: promptTokens, completionTokens: evalTokens, totalTokens: promptTokens + evalTokens)
        
        return ChatResponse(text: text, toolCalls: toolCalls, usage: usage)
    }
    
    public func streamMessage(
        messages: [LLMChatMessage],
        tools: [ToolDefinition]?,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> ChatResponse {
        let endpoint = hostURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var bodyDict: [String: Any] = [
            "model": modelIdentifier,
            "messages": formatMessages(messages),
            "stream": true,
            "keep_alive": "15m",
            "options": [
                "num_ctx": 2048,
                "num_predict": 320,
                "temperature": 0.6
            ]
        ]
        
        if let tools = tools, !tools.isEmpty {
            bodyDict["tools"] = tools.compactMap { tool in
                if let data = tool.parametersJSON.data(using: .utf8),
                   let schema = try? JSONSerialization.jsonObject(with: data) {
                    return [
                        "type": "function",
                        "function": [
                            "name": tool.name,
                            "description": tool.description,
                            "parameters": schema
                        ]
                    ]
                }
                return nil
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
        
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BrainError.ollamaNotRunning(url: hostURL.absoluteString)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 404 {
                    throw BrainError.modelNotFound(name: modelIdentifier)
                }
                throw BrainError.requestFailed(statusCode: httpResponse.statusCode, message: "Ollama returned status \(httpResponse.statusCode)")
            }
            
            var fullText = ""
            var toolCalls: [ToolCall] = []
            
            for try await line in bytes.lines {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                
                if let message = json["message"] as? [String: Any] {
                    if let content = message["content"] as? String, !content.isEmpty {
                        fullText += content
                        onChunk(content)
                    }
                    if let rawCalls = message["tool_calls"] as? [[String: Any]] {
                        for (idx, call) in rawCalls.enumerated() {
                            let fn = call["function"] as? [String: Any]
                            let name = fn?["name"] as? String ?? "tool"
                            let args = fn?["arguments"] as? [String: Any] ?? [:]
                            let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
                            let argsJSON = String(data: argsData, encoding: .utf8) ?? "{}"
                            toolCalls.append(ToolCall(id: "call_\(idx)", name: name, argumentsJSON: argsJSON))
                        }
                    }
                }
            }
            return ChatResponse(text: fullText, toolCalls: toolCalls)
        } catch let err as BrainError {
            throw err
        } catch {
            throw BrainError.ollamaNotRunning(url: hostURL.absoluteString)
        }
    }
    
    // MARK: - VisionModel
    
    public func analyzeImage(
        image: NSImage,
        prompt: String,
        tools: [ToolDefinition]?
    ) async throws -> VisionAnalysisResponse {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw BrainError.decodingFailed(message: "Failed to compress image for Ollama vision")
        }
        
        let visionMessage = LLMChatMessage(role: .user, content: prompt, imageDataList: [jpegData])
        let response = try await sendMessage(messages: [visionMessage], tools: tools, jsonMode: false)
        return VisionAnalysisResponse(text: response.text, groundedElements: [], suggestedAction: nil)
    }
    
    // MARK: - Formatters
    
    private func formatMessages(_ messages: [LLMChatMessage]) -> [[String: Any]] {
        return messages.map { msg in
            var dict: [String: Any] = [
                "role": msg.role.rawValue,
                "content": msg.content
            ]
            if let images = msg.imageDataList, !images.isEmpty {
                dict["images"] = images.map { $0.base64EncodedString() }
            }
            return dict
        }
    }
}
