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
    
    public var isInstalledAndRunning: Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = ["-s", "-m", "1.5", "\(hostURL.absoluteString)/api/tags"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }
    
    public init(
        model: String = "llama3.2:3b",
        host: String? = nil
    ) {
        let configuredHost = host ?? KeychainService.shared.get(.ollamaHost) ?? "http://localhost:11434"
        self.hostURL = URL(string: configuredHost) ?? URL(string: "http://localhost:11434")!
        self.modelIdentifier = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        config.timeoutIntervalForResource = 120.0
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
    
    /// Launches the Ollama application or background daemon process
    public func launchOllamaDaemon() {
        // A. If Ollama.app exists, launch via NSWorkspace
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.ollama.ollama") {
            NSWorkspace.shared.openApplication(at: appUrl, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else if FileManager.default.fileExists(atPath: "/Applications/Ollama.app") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ollama.app"))
        }
        
        // B. Also attempt launching the CLI daemon process in the background
        DispatchQueue.global(qos: .userInitiated).async {
            let possiblePaths = [
                "/usr/local/bin/ollama",
                "/opt/homebrew/bin/ollama",
                "/usr/bin/ollama"
            ]
            let resolvedBin = possiblePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
            guard let bin = resolvedBin else { return }
            
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
    
    public func listLocalModels() async throws -> [OllamaModelInfo] {
        let endpoint = hostURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw BrainError.ollamaNotRunning(url: hostURL.absoluteString)
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelsArray = json["models"] as? [[String: Any]] else {
                return []
            }
            
            return modelsArray.compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                let size = dict["size"] as? Int64
                let details = dict["details"] as? [String: Any]
                let paramSize = details?["parameter_size"] as? String
                let quant = details?["quantization_level"] as? String
                let modAt = dict["modified_at"] as? String
                return OllamaModelInfo(name: name, size: size, parameterSize: paramSize, quantizationLevel: quant, modifiedAt: modAt)
            }
        } catch {
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
            "stream": false
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
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw BrainError.ollamaNotRunning(url: hostURL.absoluteString)
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
        } catch let err as BrainError {
            throw err
        } catch {
            throw BrainError.ollamaNotRunning(url: hostURL.absoluteString)
        }
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
            "stream": true
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
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw BrainError.ollamaNotRunning(url: hostURL.absoluteString)
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
