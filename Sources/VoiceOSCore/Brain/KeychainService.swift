import Foundation
import Security

/// Secure macOS Keychain service for storing AI credentials.
/// Keys are stored under service "ai.voice.app" and never logged or serialized to disk.
public final class KeychainService: @unchecked Sendable {
    public static let shared = KeychainService()
    
    private let service = "ai.voice.app"
    private let cacheLock = NSLock()
    private var inMemoryCache: [String: String] = [:]
    
    public init() {}
    
    // Standard credential keys
    public enum Key: String, CaseIterable {
        case openAIApiKey = "openai_api_key"
        case anthropicApiKey = "anthropic_api_key"
        case geminiApiKey = "gemini_api_key"
        case customOpenAIBaseURL = "custom_openai_base_url"
        case customOpenAIApiKey = "custom_openai_api_key"
        case searchProviderKey = "search_provider_key"
        case searchProviderType = "search_provider_type"
        case ollamaHost = "ollama_host"
        case selectedChatModel = "selected_chat_model"
        case selectedVisionModel = "selected_vision_model"
        case googleSearchApiKey = "google_search_api_key"
        case googleSearchEngineId = "google_search_engine_id"
    }
    
    public func set(_ value: String, for key: Key) {
        set(value, for: key.rawValue)
    }
    
    public func get(_ key: Key) -> String? {
        return get(key.rawValue)
    }
    
    public func delete(_ key: Key) {
        delete(key.rawValue)
    }
    
    public func set(_ value: String, for keyName: String) {
        cacheLock.lock()
        inMemoryCache[keyName] = value
        cacheLock.unlock()
        
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return }
        
        // Remove existing item if present
        deleteFromKeychain(keyName)
        
        if trimmed.isEmpty {
            return
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true
        ]
        
        SecItemAdd(query as CFDictionary, nil)
    }
    
    public func get(_ keyName: String) -> String? {
        cacheLock.lock()
        if let cached = inMemoryCache[keyName] {
            cacheLock.unlock()
            return cached.isEmpty ? nil : cached
        }
        cacheLock.unlock()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data, let string = String(data: data, encoding: .utf8) {
            let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
            cacheLock.lock()
            inMemoryCache[keyName] = clean
            cacheLock.unlock()
            return clean.isEmpty ? nil : clean
        }
        
        return nil
    }
    
    public func delete(_ keyName: String) {
        cacheLock.lock()
        inMemoryCache.removeValue(forKey: keyName)
        cacheLock.unlock()
        deleteFromKeychain(keyName)
    }
    
    private func deleteFromKeychain(_ keyName: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyName,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    /// Clears memory cache (useful for privacy resets)
    public func clearMemoryCache() {
        cacheLock.lock()
        inMemoryCache.removeAll()
        cacheLock.unlock()
    }
}

