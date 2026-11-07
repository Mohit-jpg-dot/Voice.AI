import Foundation

/// Unified Config Store replicating `electron-store` for VoiceOS.
/// Reads and writes `config.json` at `~/Library/Application Support/VoiceOS/config.json`.
/// Defaults directly match APP-SECRET.md line 118:
/// Onboarding progress, auth, settings, keyboard shortcuts, microphone selection,
/// theme, agent voice, integrations, MCP servers, native action toggles, profile, and knowledge state.
public final class VoiceOSConfigStore: @unchecked Sendable {
    public static let shared = VoiceOSConfigStore()
    
    private let lock = NSLock()
    private var storeData: [String: Any] = [:]
    private let fileURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let voiceOSDir = appSupport.appendingPathComponent("VoiceOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: voiceOSDir, withIntermediateDirectories: true)
        self.fileURL = voiceOSDir.appendingPathComponent("config.json")
        loadDefaults()
        readFromFile()
    }
    
    private func loadDefaults() {
        // Documented default entries from APP-SECRET.md line 118, 137, 262
        storeData = [
            "onboarding": [
                "completed": false,
                "step": "welcome",
                "introPresented": true
            ],
            "auth": [
                "isSelfHosted": false,
                "isAuthenticated": false
            ],
            "settings": [
                "shareUserData": false,
                "launchAtLogin": true,
                "startInBackground": true,
                "showInDock": true,
                "autoPaste": true,
                "soundEnabled": true,
                "muteMicOnStartup": false,
                "selectedMicrophone": "default",
                "language": "auto",
                "isShortcutGloballyEnabled": true
            ],
            "keyboardShortcuts": [
                "dictation": ["fn"],
                "agent": ["control-left"],
                "handsFree": ["fn", "fn_fast"]
            ],
            "theme": "dark",
            "agentVoice": "natural_neural_female",
            "integrations": [],
            "customMcpServers": [],
            "nativeActionToggles": [
                "allowAccessibilityClick": true,
                "allowTextInjection": true,
                "allowMediaControl": true,
                "allowAppLaunch": true
            ],
            "profile": [
                "firstName": "",
                "lastName": "",
                "email": ""
            ],
            "knowledgeState": [:]
        ]
    }
    
    private func readFromFile() {
        lock.lock()
        defer { lock.unlock() }
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            writeToFile()
            return
        }
        
        // Deep merge with defaults
        for (k, v) in json {
            storeData[k] = v
        }
    }
    
    private func writeToFile() {
        guard let data = try? JSONSerialization.data(withJSONObject: storeData, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }
    
    // MARK: - Public Accessors
    
    public func get(_ key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return storeData[key]
    }
    
    public func set(_ key: String, value: Any) {
        lock.lock()
        defer { lock.unlock() }
        storeData[key] = value
        writeToFile()
    }
    
    public func delete(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        storeData.removeValue(forKey: key)
        writeToFile()
    }
    
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        loadDefaults()
        writeToFile()
    }
    
    public func getAll() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return storeData
    }
}

