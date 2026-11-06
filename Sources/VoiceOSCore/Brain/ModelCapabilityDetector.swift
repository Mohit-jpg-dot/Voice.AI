import Foundation
import AppKit

final class ChunkCollector: @unchecked Sendable {
    private var chunks: [String] = []
    private let lock = NSLock()
    
    func append(_ chunk: String) {
        lock.lock()
        chunks.append(chunk)
        lock.unlock()
    }
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return chunks.count
    }
    
    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return chunks.isEmpty
    }
}

/// Probes AI models with lightweight real calls to accurately detect their capabilities (streaming, tool calling, vision, JSON mode, speed).
public final class ModelCapabilityDetector: @unchecked Sendable {
    public static let shared = ModelCapabilityDetector()
    
    private let cacheLock = NSLock()
    private var profileCache: [String: CapabilityProfile] = [:]
    private let cacheKeyPrefix = "voiceos.capability.cache."
    
    private init() {
        loadCache()
    }
    
    private func getCached(key: String) -> CapabilityProfile? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = profileCache[key], Date().timeIntervalSince(cached.testedAt) < 3600 * 24 {
            return cached
        }
        return nil
    }
    
    private func setCached(key: String, profile: CapabilityProfile) {
        cacheLock.lock()
        profileCache[key] = profile
        cacheLock.unlock()
        saveCache()
    }
    
    // MARK: - Chat Probing
    
    /// Probes a chat model for streaming, tool calling, JSON mode, and tokens/sec.
    public func probeChat(model: ChatModel, forceRefresh: Bool = false) async -> CapabilityProfile {
        let cacheKey = "\(model.providerName):\(model.modelIdentifier)"
        
        if !forceRefresh, let cached = getCached(key: cacheKey) {
            return cached
        }
        
        var isStreaming = false
        var isToolCalling = false
        var isJsonMode = false
        var tokensPerSec: Double = 0.0
        var isSuccess = false
        var probeMsg = ""
        
        let startTime = Date()
        var tokenCount = 0
        
        // 1. Probe Streaming
        do {
            let messages = [
                LLMChatMessage(role: .system, content: "You are a test probe. Be extremely brief."),
                LLMChatMessage(role: .user, content: "Echo the word READY")
            ]
            
            let collector = ChunkCollector()
            let streamResponse = try await model.streamMessage(messages: messages, tools: nil) { chunk in
                collector.append(chunk)
            }
            
            isStreaming = !collector.isEmpty || !streamResponse.text.isEmpty
            tokenCount += streamResponse.usage?.completionTokens ?? max(collector.count, 2)
            isSuccess = true
            probeMsg = "Streaming verified (\(collector.count) chunks)."
        } catch {
            probeMsg = "Streaming probe failed: \(error.localizedDescription)"
        }
        
        // 2. Probe Tool Calling
        if isSuccess {
            do {
                let testTool = ToolDefinition(
                    name: "probe_ping",
                    description: "Tool used only to verify function calling capability.",
                    parametersJSON: "{\"type\": \"object\", \"properties\": {\"echo\": {\"type\": \"string\"}}, \"required\": [\"echo\"]}"
                )
                
                let toolMessages = [
                    LLMChatMessage(role: .system, content: "Call the probe_ping tool with echo='test_ok'."),
                    LLMChatMessage(role: .user, content: "Execute the tool probe_ping now.")
                ]
                
                let toolResp = try await model.sendMessage(messages: toolMessages, tools: [testTool], jsonMode: false)
                if !toolResp.toolCalls.isEmpty && toolResp.toolCalls.contains(where: { $0.name == "probe_ping" }) {
                    isToolCalling = true
                }
            } catch {
                // Tool calling might fail on models without tool support (e.g. small local models)
                isToolCalling = false
            }
        }
        
        // 3. Probe JSON Mode
        if isSuccess {
            do {
                let jsonMessages = [
                    LLMChatMessage(role: .system, content: "Respond ONLY in raw JSON with key 'status' set to 'ok'."),
                    LLMChatMessage(role: .user, content: "Produce JSON output.")
                ]
                let jsonResp = try await model.sendMessage(messages: jsonMessages, tools: nil, jsonMode: true)
                if jsonResp.text.contains("\"status\"") && jsonResp.text.contains("\"ok\"") {
                    isJsonMode = true
                }
            } catch {
                isJsonMode = false
            }
        }
        
        let elapsed = max(0.1, Date().timeIntervalSince(startTime))
        tokensPerSec = Double(tokenCount) / elapsed
        
        let contextLen = defaultContextLength(for: model.modelIdentifier)
        let cost = defaultEstimatedCost(for: model.modelIdentifier)
        
        let profile = CapabilityProfile(
            streaming: isStreaming,
            toolCalling: isToolCalling,
            vision: false, // Updated by vision probe
            jsonMode: isJsonMode,
            contextLength: contextLen,
            supportedLanguages: ["en", "hi", "hinglish", "es", "fr", "de", "ja", "zh"],
            speedTokensPerSec: (tokensPerSec * 10).rounded() / 10,
            estimatedCostPer1kTokens: cost,
            testedAt: Date(),
            probeSuccess: isSuccess,
            probeMessage: probeMsg
        )
        
        setCached(key: cacheKey, profile: profile)
        return profile
    }
    
    // MARK: - Vision Probing
    
    /// Probes a vision model with a tiny 16x16 test image to confirm real multimodal grounding.
    public func probeVision(model: VisionModel) async -> Bool {
        // Create 16x16 red image
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        img.unlockFocus()
        
        do {
            let response = try await model.analyzeImage(
                image: img,
                prompt: "What primary solid color is this square? Answer in one word (e.g. Red, Green, Blue).",
                tools: nil
            )
            let lower = response.text.lowercased()
            return lower.contains("red") || lower.contains("laal") || lower.contains("crimson")
        } catch {
            return false
        }
    }
    
    // MARK: - Helpers & Defaults
    
    private func defaultContextLength(for model: String) -> Int {
        let m = model.lowercased()
        if m.contains("gpt-4o") || m.contains("gpt-4-turbo") { return 128000 }
        if m.contains("claude-3-5") || m.contains("claude-3-opus") || m.contains("claude-3-sonnet") { return 200000 }
        if m.contains("gemini-1.5") || m.contains("gemini-2.0") { return 1000000 }
        if m.contains("qwen2.5") || m.contains("qwen3") { return 32768 }
        if m.contains("llama3.2") || m.contains("llama3.1") { return 128000 }
        return 8192
    }
    
    private func defaultEstimatedCost(for model: String) -> Double {
        let m = model.lowercased()
        if m.contains("gpt-4o-mini") { return 0.00015 }
        if m.contains("gpt-4o") { return 0.0025 }
        if m.contains("claude-3-5-sonnet") { return 0.003 }
        if m.contains("claude-3-5-haiku") { return 0.0008 }
        // Local / Ollama models are free!
        return 0.0
    }
    
    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: "voiceos.capability.profiles.v1"),
              let decoded = try? JSONDecoder().decode([String: CapabilityProfile].self, from: data) else {
            return
        }
        profileCache = decoded
    }
    
    private func saveCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let encoded = try? JSONEncoder().encode(profileCache) {
            UserDefaults.standard.set(encoded, forKey: "voiceos.capability.profiles.v1")
        }
    }
}
