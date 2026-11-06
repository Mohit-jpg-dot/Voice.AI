import Foundation
import AppKit

public final class OpenAIProvider: ChatModel, VisionModel, SpeechToTextModel, TextToSpeechModel, @unchecked Sendable {
    public let providerName = "OpenAI"
    public var modelIdentifier: String
    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession
    
    public init(
        apiKey: String? = nil,
        model: String = "gpt-4o",
        baseURL: URL = URL(string: "https://api.openai.com/v1")!
    ) {
        self.apiKey = apiKey ?? KeychainService.shared.get(.openAIApiKey) ?? ""
        self.modelIdentifier = model
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - ChatModel
    
    public func sendMessage(
        messages: [LLMChatMessage],
        tools: [ToolDefinition]?,
        jsonMode: Bool
    ) async throws -> ChatResponse {
        guard !apiKey.isEmpty else {
            throw BrainError.missingApiKey(provider: providerName)
        }
        
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var bodyDict: [String: Any] = [
            "model": modelIdentifier,
            "messages": formatMessages(messages),
            "stream": false
        ]
        
        if jsonMode {
            bodyDict["response_format"] = ["type": "json_object"]
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
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw BrainError.decodingFailed(message: "Failed to parse OpenAI choices")
        }
        
        let textContent = message["content"] as? String ?? ""
        var toolCalls: [ToolCall] = []
        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            for call in rawCalls {
                if let id = call["id"] as? String,
                   let fn = call["function"] as? [String: Any],
                   let name = fn["name"] as? String,
                   let args = fn["arguments"] as? String {
                    toolCalls.append(ToolCall(id: id, name: name, argumentsJSON: args))
                }
            }
        }
        
        var usage: TokenUsage? = nil
        if let usageDict = json["usage"] as? [String: Any] {
            usage = TokenUsage(
                promptTokens: usageDict["prompt_tokens"] as? Int ?? 0,
                completionTokens: usageDict["completion_tokens"] as? Int ?? 0,
                totalTokens: usageDict["total_tokens"] as? Int ?? 0
            )
        }
        
        return ChatResponse(
            text: textContent,
            toolCalls: toolCalls,
            usage: usage,
            finishReason: firstChoice["finish_reason"] as? String
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
        
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
        
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrainError.networkUnavailable
        }
        if httpResponse.statusCode == 401 { throw BrainError.invalidApiKey(provider: providerName) }
        if httpResponse.statusCode == 429 { throw BrainError.rateLimited(provider: providerName) }
        if !(200...299).contains(httpResponse.statusCode) {
            throw BrainError.requestFailed(statusCode: httpResponse.statusCode, message: "SSE failed")
        }
        
        var fullText = ""
        var toolCalls: [ToolCall] = []
        var partialToolArgs: [Int: (id: String, name: String, args: String)] = [:]
        
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data: ") else { continue }
            let payload = String(trimmed.dropFirst(6))
            if payload == "[DONE]" { break }
            
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any] else { continue }
            
            if let content = delta["content"] as? String, !content.isEmpty {
                fullText += content
                onChunk(content)
            }
            
            if let rawToolCalls = delta["tool_calls"] as? [[String: Any]] {
                for item in rawToolCalls {
                    let index = item["index"] as? Int ?? 0
                    let id = item["id"] as? String ?? partialToolArgs[index]?.id ?? UUID().uuidString
                    let fn = item["function"] as? [String: Any]
                    let name = fn?["name"] as? String ?? partialToolArgs[index]?.name ?? ""
                    let chunkArgs = fn?["arguments"] as? String ?? ""
                    
                    let prevArgs = partialToolArgs[index]?.args ?? ""
                    partialToolArgs[index] = (id: id, name: name, args: prevArgs + chunkArgs)
                }
            }
        }
        
        for (_, entry) in partialToolArgs.sorted(by: { $0.key < $1.key }) {
            toolCalls.append(ToolCall(id: entry.id, name: entry.name, argumentsJSON: entry.args))
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
            throw BrainError.decodingFailed(message: "Could not encode image to JPEG")
        }
        
        let visionMessage = LLMChatMessage(
            role: .user,
            content: prompt,
            imageDataList: [jpegData]
        )
        
        let response = try await sendMessage(messages: [visionMessage], tools: tools, jsonMode: false)
        return VisionAnalysisResponse(
            text: response.text,
            groundedElements: parseGroundedElements(from: response.text),
            suggestedAction: nil
        )
    }
    
    // MARK: - SpeechToTextModel (Whisper-1)
    
    public func transcribe(
        audioData: Data,
        language: String?,
        promptHints: [String]
    ) async throws -> (text: String, detectedLanguage: String, confidence: Double) {
        guard !apiKey.isEmpty else {
            throw BrainError.missingApiKey(provider: providerName)
        }
        
        let endpoint = baseURL.appendingPathComponent("audio/transcriptions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        func appendFormField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        appendFormField(name: "model", value: "whisper-1")
        if let lang = language, lang != "auto" {
            appendFormField(name: "language", value: lang)
        }
        if !promptHints.isEmpty {
            appendFormField(name: "prompt", value: promptHints.joined(separator: ", "))
        }
        appendFormField(name: "response_format", value: "verbose_json")
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw BrainError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: "Whisper failed")
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let text = json["text"] as? String ?? ""
            let detectedLang = json["language"] as? String ?? (language ?? "en")
            return (text: text, detectedLanguage: detectedLang, confidence: 0.95)
        }
        
        return (text: "", detectedLanguage: "en", confidence: 0.0)
    }
    
    // MARK: - TextToSpeechModel (tts-1)
    
    public func listAvailableVoices() async -> [VoiceOption] {
        return [
            VoiceOption(identifier: "alloy", name: "Alloy (Neutral & Warm)", provider: providerName, language: "multilingual", isNeural: true),
            VoiceOption(identifier: "echo", name: "Echo (Deep Male)", provider: providerName, language: "multilingual", isNeural: true),
            VoiceOption(identifier: "fable", name: "Fable (Expressive British)", provider: providerName, language: "multilingual", isNeural: true),
            VoiceOption(identifier: "onyx", name: "Onyx (Authoritative Male)", provider: providerName, language: "multilingual", isNeural: true),
            VoiceOption(identifier: "nova", name: "Nova (Sweet & Engaging)", provider: providerName, language: "multilingual", isNeural: true),
            VoiceOption(identifier: "shimmer", name: "Shimmer (Clear & Crisp)", provider: providerName, language: "multilingual", isNeural: true)
        ]
    }
    
    public func synthesizeSpeech(text: String, voice: VoiceOption, speed: Float) async throws -> Data {
        guard !apiKey.isEmpty else {
            throw BrainError.missingApiKey(provider: providerName)
        }
        let endpoint = baseURL.appendingPathComponent("audio/speech")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "tts-1",
            "input": text,
            "voice": voice.identifier,
            "speed": min(2.0, max(0.5, speed))
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw BrainError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: "TTS failed")
        }
        return data
    }
    
    // MARK: - Formatters
    
    private func formatMessages(_ messages: [LLMChatMessage]) -> [[String: Any]] {
        return messages.map { msg in
            var dict: [String: Any] = ["role": msg.role.rawValue]
            
            if let images = msg.imageDataList, !images.isEmpty {
                var contentParts: [[String: Any]] = []
                if !msg.content.isEmpty {
                    contentParts.append(["type": "text", "text": msg.content])
                }
                for imgData in images {
                    let b64 = imgData.base64EncodedString()
                    contentParts.append([
                        "type": "image_url",
                        "image_url": ["url": "data:image/jpeg;base64,\(b64)"]
                    ])
                }
                dict["content"] = contentParts
            } else {
                dict["content"] = msg.content
            }
            
            if let calls = msg.toolCalls, !calls.isEmpty {
                dict["tool_calls"] = calls.map { call in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            "arguments": call.argumentsJSON
                        ]
                    ]
                }
            }
            if let toolId = msg.toolCallId {
                dict["tool_call_id"] = toolId
            }
            return dict
        }
    }
    
    private func parseGroundedElements(from text: String) -> [GroundedUIElement] {
        // Attempts to extract bounding box coordinates from text e.g. [0.2, 0.4, 0.6, 0.8] or normalized coords
        var elements: [GroundedUIElement] = []
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        
        let pattern = #"\[(\d+\.?\d*),\s*(\d+\.?\d*),\s*(\d+\.?\d*),\s*(\d+\.?\d*)\]"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for m in matches {
                let x = Double(nsText.substring(with: m.range(at: 1))) ?? 0.5
                let y = Double(nsText.substring(with: m.range(at: 2))) ?? 0.5
                let w = Double(nsText.substring(with: m.range(at: 3))) ?? 0.1
                let h = Double(nsText.substring(with: m.range(at: 4))) ?? 0.1
                
                let normRect = CGRect(x: x, y: y, width: w, height: h)
                let screenPoint = CGPoint(x: screen.width * CGFloat(x + w / 2), y: screen.height * CGFloat(y + h / 2))
                elements.append(GroundedUIElement(label: "Target", normalizedRect: normRect, screenPoint: screenPoint))
            }
        }
        return elements
    }
}
