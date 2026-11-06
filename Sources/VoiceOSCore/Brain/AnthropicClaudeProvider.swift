import Foundation
import AppKit

public final class AnthropicClaudeProvider: ChatModel, VisionModel, @unchecked Sendable {
    public let providerName = "Anthropic Claude"
    public var modelIdentifier: String
    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession
    
    public init(
        apiKey: String? = nil,
        model: String = "claude-3-5-sonnet-20241022",
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!
    ) {
        self.apiKey = apiKey ?? KeychainService.shared.get(.anthropicApiKey) ?? ""
        self.modelIdentifier = model
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
    }
    
    public func sendMessage(
        messages: [LLMChatMessage],
        tools: [ToolDefinition]?,
        jsonMode: Bool
    ) async throws -> ChatResponse {
        guard !apiKey.isEmpty else {
            throw BrainError.missingApiKey(provider: providerName)
        }
        
        let endpoint = baseURL.appendingPathComponent("messages")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (systemPrompt, claudeMessages) = formatMessages(messages)
        var bodyDict: [String: Any] = [
            "model": modelIdentifier,
            "max_tokens": 4096,
            "messages": claudeMessages,
            "stream": false
        ]
        
        if let system = systemPrompt, !system.isEmpty {
            bodyDict["system"] = system
        }
        
        if let tools = tools, !tools.isEmpty {
            bodyDict["tools"] = tools.compactMap { tool in
                if let data = tool.parametersJSON.data(using: .utf8),
                   let schema = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return [
                        "name": tool.name,
                        "description": tool.description,
                        "input_schema": schema
                    ]
                }
                return nil
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrainError.networkUnavailable
        }
        
        if httpResponse.statusCode == 401 { throw BrainError.invalidApiKey(provider: providerName) }
        if httpResponse.statusCode == 429 { throw BrainError.rateLimited(provider: providerName) }
        if !(200...299).contains(httpResponse.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw BrainError.requestFailed(statusCode: httpResponse.statusCode, message: msg)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentBlocks = json["content"] as? [[String: Any]] else {
            throw BrainError.decodingFailed(message: "Failed to parse Claude content blocks")
        }
        
        var fullText = ""
        var toolCalls: [ToolCall] = []
        
        for block in contentBlocks {
            let type = block["type"] as? String ?? ""
            if type == "text", let text = block["text"] as? String {
                fullText += text
            } else if type == "tool_use",
                      let id = block["id"] as? String,
                      let name = block["name"] as? String,
                      let input = block["input"] as? [String: Any],
                      let inputData = try? JSONSerialization.data(withJSONObject: input),
                      let inputJSON = String(data: inputData, encoding: .utf8) {
                toolCalls.append(ToolCall(id: id, name: name, argumentsJSON: inputJSON))
            }
        }
        
        var usage: TokenUsage? = nil
        if let usageDict = json["usage"] as? [String: Any] {
            usage = TokenUsage(
                promptTokens: usageDict["input_tokens"] as? Int ?? 0,
                completionTokens: usageDict["output_tokens"] as? Int ?? 0,
                totalTokens: (usageDict["input_tokens"] as? Int ?? 0) + (usageDict["output_tokens"] as? Int ?? 0)
            )
        }
        
        return ChatResponse(
            text: fullText,
            toolCalls: toolCalls,
            usage: usage,
            finishReason: json["stop_reason"] as? String
        )
    }
    
    public func streamMessage(
        messages: [LLMChatMessage],
        tools: [ToolDefinition]?,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> ChatResponse {
        guard !apiKey.isEmpty else {
            throw BrainError.missingApiKey(provider: providerName)
        }
        
        let endpoint = baseURL.appendingPathComponent("messages")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (systemPrompt, claudeMessages) = formatMessages(messages)
        var bodyDict: [String: Any] = [
            "model": modelIdentifier,
            "max_tokens": 4096,
            "messages": claudeMessages,
            "stream": true
        ]
        
        if let system = systemPrompt, !system.isEmpty {
            bodyDict["system"] = system
        }
        
        if let tools = tools, !tools.isEmpty {
            bodyDict["tools"] = tools.compactMap { tool in
                if let data = tool.parametersJSON.data(using: .utf8),
                   let schema = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return [
                        "name": tool.name,
                        "description": tool.description,
                        "input_schema": schema
                    ]
                }
                return nil
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrainError.networkUnavailable
        }
        
        if httpResponse.statusCode == 401 { throw BrainError.invalidApiKey(provider: providerName) }
        if httpResponse.statusCode == 429 { throw BrainError.rateLimited(provider: providerName) }
        
        var fullText = ""
        var toolCalls: [ToolCall] = []
        var currentToolId = ""
        var currentToolName = ""
        var currentToolArgs = ""
        
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data: ") else { continue }
            let payload = String(trimmed.dropFirst(6))
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            
            let eventType = json["type"] as? String ?? ""
            if eventType == "content_block_delta" {
                if let delta = json["delta"] as? [String: Any] {
                    if let text = delta["text"] as? String {
                        fullText += text
                        onChunk(text)
                    } else if let partialJson = delta["partial_json"] as? String {
                        currentToolArgs += partialJson
                    }
                }
            } else if eventType == "content_block_start" {
                if let block = json["content_block"] as? [String: Any],
                   let type = block["type"] as? String, type == "tool_use" {
                    currentToolId = block["id"] as? String ?? UUID().uuidString
                    currentToolName = block["name"] as? String ?? ""
                    currentToolArgs = ""
                }
            } else if eventType == "content_block_stop" {
                if !currentToolName.isEmpty {
                    toolCalls.append(ToolCall(id: currentToolId, name: currentToolName, argumentsJSON: currentToolArgs))
                    currentToolName = ""
                    currentToolArgs = ""
                }
            }
        }
        
        return ChatResponse(text: fullText, toolCalls: toolCalls)
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
            throw BrainError.decodingFailed(message: "Failed to compress image for Claude vision")
        }
        
        let visionMessage = LLMChatMessage(role: .user, content: prompt, imageDataList: [jpegData])
        let response = try await sendMessage(messages: [visionMessage], tools: tools, jsonMode: false)
        return VisionAnalysisResponse(text: response.text, groundedElements: [], suggestedAction: nil)
    }
    
    // MARK: - Formatters
    
    private func formatMessages(_ messages: [LLMChatMessage]) -> (system: String?, messages: [[String: Any]]) {
        var systemPrompt: String? = nil
        var formatted: [[String: Any]] = []
        
        for msg in messages {
            if msg.role == .system {
                systemPrompt = (systemPrompt == nil) ? msg.content : (systemPrompt! + "\n" + msg.content)
                continue
            }
            
            var contentBlocks: [[String: Any]] = []
            if !msg.content.isEmpty {
                contentBlocks.append(["type": "text", "text": msg.content])
            }
            if let images = msg.imageDataList {
                for imgData in images {
                    contentBlocks.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": imgData.base64EncodedString()
                        ]
                    ])
                }
            }
            if let calls = msg.toolCalls {
                for call in calls {
                    let inputObj = (try? JSONSerialization.jsonObject(with: call.argumentsJSON.data(using: .utf8) ?? Data())) ?? [:]
                    contentBlocks.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": inputObj
                    ])
                }
            }
            if msg.role == .tool {
                contentBlocks.append([
                    "type": "tool_result",
                    "tool_use_id": msg.toolCallId ?? "",
                    "content": msg.content
                ])
            }
            
            formatted.append([
                "role": msg.role == .tool ? "user" : (msg.role == .assistant ? "assistant" : "user"),
                "content": contentBlocks
            ])
        }
        
        return (systemPrompt, formatted)
    }
}
