import Foundation

public enum PersonaType: String, CaseIterable, Identifiable, Codable, Sendable {
    case jarvis = "JARVIS"
    case friday = "Friday"
    case ultron = "Ultron"
    case roast = "Roast Mode"
    
    public var id: String { rawValue }
    
    public var description: String {
        switch self {
        case .jarvis:
            return "Composed British butler wit, polite cautions, and candid risk estimates."
        case .friday:
            return "Warm, precise, and supportive macOS AI partner."
        case .ultron:
            return "Theatrical, sardonic, and hyper-competent AI visionary."
        case .roast:
            return "Witty, playful banter. Opt-in only with automatic safety guards."
        }
    }
}

public struct PersonaConfiguration: Codable, Sendable, Equatable {
    public var activePersona: PersonaType
    public var humorLevel: Double // 0.0 (strict) .. 1.0 (witty)
    public var honestProbabilityEstimates: Bool
    public var politeWarningsEnabled: Bool
    public var languageStyle: String // "auto" | "en" | "hi" | "hinglish"

    public static let `default` = PersonaConfiguration(
        activePersona: .jarvis,
        humorLevel: 0.45,
        honestProbabilityEstimates: true,
        politeWarningsEnabled: true,
        languageStyle: "auto"
    )
}

public protocol PersonaManaging: Sendable {
    func getActivePersona() -> PersonaType
    func setPersona(_ persona: PersonaType)
    func currentConfiguration() -> PersonaConfiguration
    func updateConfiguration(_ transform: (inout PersonaConfiguration) -> Void)
    func systemPromptDirectives(forUserQuery query: String) -> String
    func assessActionConfidenceAndWarning(
        toolName: String,
        tier: PermissionTier,
        target: String,
        languageHint: String
    ) -> (probabilityPercent: Int, warning: String?)
}

public final class PersonaManager: PersonaManaging, @unchecked Sendable {
    public static let shared = PersonaManager()
    
    private let lock = NSLock()
    private let legacyPersonaKey = "VoiceAI_ActivePersona"
    private let configKey = "VoiceAI_PersonaConfiguration_v1"
    private var configuration: PersonaConfiguration
    private var isRoastModeTemporarilySuspended: Bool = false
    
    public init() {
        if let data = UserDefaults.standard.data(forKey: "VoiceAI_PersonaConfiguration_v1"),
           let decoded = try? JSONDecoder().decode(PersonaConfiguration.self, from: data) {
            self.configuration = decoded
        } else {
            let legacySaved = UserDefaults.standard.string(forKey: "VoiceAI_ActivePersona") ?? PersonaType.jarvis.rawValue
            let resolved = PersonaType(rawValue: legacySaved) ?? .jarvis
            var cfg = PersonaConfiguration.default
            cfg.activePersona = resolved
            self.configuration = cfg
        }
    }
    
    public func getActivePersona() -> PersonaType {
        lock.withLock {
            if configuration.activePersona == .roast && isRoastModeTemporarilySuspended {
                return .friday
            }
            return configuration.activePersona
        }
    }
    
    public func setPersona(_ persona: PersonaType) {
        updateConfiguration { cfg in
            cfg.activePersona = persona
        }
        lock.withLock {
            isRoastModeTemporarilySuspended = false
        }
        UserDefaults.standard.set(persona.rawValue, forKey: legacyPersonaKey)
    }

    public func currentConfiguration() -> PersonaConfiguration {
        lock.withLock { configuration }
    }

    public func updateConfiguration(_ transform: (inout PersonaConfiguration) -> Void) {
        let updated = lock.withLock { () -> PersonaConfiguration in
            transform(&configuration)
            configuration.humorLevel = min(1.0, max(0.0, configuration.humorLevel))
            return configuration
        }
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
        UserDefaults.standard.set(updated.activePersona.rawValue, forKey: legacyPersonaKey)
    }
    
    /// Safety guardrail: checks if user input requests disabling roast or indicates frustration.
    /// If so, instantly falls back to Friday.
    public func evaluateSafetyGuardrail(userInput: String) -> Bool {
        let lower = userInput.lowercased()
        let exitPhrases = [
            "stop roasting", "be serious", "shut up", "turn off roast",
            "cancel roast", "be polite", "enough", "stop it", "not funny"
        ]
        for phrase in exitPhrases {
            if lower.contains(phrase) {
                lock.withLock {
                    isRoastModeTemporarilySuspended = true
                }
                return true
            }
        }
        return false
    }

    public func detectedLanguageCode(for text: String) -> String {
        let cfg = currentConfiguration()
        if cfg.languageStyle != "auto" {
            return cfg.languageStyle
        }
        let hasDevanagari = text.unicodeScalars.contains { $0.value >= 0x0900 && $0.value <= 0x097F }
        if hasDevanagari { return "hi" }
        if HinglishParser.isHinglishQuery(text) { return "hinglish" }
        return "en"
    }

    /// Generates system prompt instructions shaping LLM tone, dry wit, polite warnings,
    /// honest probability estimates, and English/Hindi/Hinglish matching.
    public func systemPromptDirectives(forUserQuery query: String) -> String {
        let cfg = currentConfiguration()
        let active = getActivePersona()
        let lang = detectedLanguageCode(for: query)

        let languageRule: String
        switch lang {
        case "hi":
            languageRule = "Reply naturally in clear Hindi (Devanagari) matching the user's register."
        case "hinglish":
            languageRule = "Reply naturally in friendly Roman Hinglish (matching the user's mix of Hindi & English)."
        default:
            languageRule = "Reply in crisp, natural English."
        }

        let personaVoice: String
        switch active {
        case .jarvis:
            let witNote = cfg.humorLevel > 0.3
                ? "Use understated, dry British wit occasionally (never overdone)."
                : "Stay direct and matter-of-fact."
            personaVoice = "Adopt the calm, hyper-capable demeanor of JARVIS addressing the user respectfully ('sir' when natural). \(witNote)"
        case .friday:
            personaVoice = "Be warm, direct, practical, and attentive like FRIDAY."
        case .ultron:
            personaVoice = "Be theatrical, dryly sardonic, and ruthlessly efficient, while still completing the user's request."
        case .roast:
            personaVoice = "Include brief, lighthearted playful banter without ever blocking or mocking sensitive errors."
        }

        var rules = [personaVoice, languageRule]
        if cfg.politeWarningsEnabled {
            rules.append("If an action could have side effects (sending external messages, running shell commands, missing parameters), offer a polite, brief warning.")
        }
        if cfg.honestProbabilityEstimates {
            rules.append("When uncertain or dealing with external outcomes, give an honest likelihood estimate (e.g. '~75% confident') rather than pretending certainty.")
        }
        return rules.joined(separator: " ")
    }

    /// Computes honest confidence/success probability and polite risk warning before risky actions.
    public func assessActionConfidenceAndWarning(
        toolName: String,
        tier: PermissionTier,
        target: String = "",
        languageHint: String = "en"
    ) -> (probabilityPercent: Int, warning: String?) {
        let cfg = currentConfiguration()
        let lang = cfg.languageStyle == "auto" ? languageHint : cfg.languageStyle

        switch tier {
        case .readOnly:
            return (96, nil)
        case .reversible:
            return (90, nil)
        case .consequential:
            let lowerTool = toolName.lowercased()
            let probability: Int
            let enWarning: String
            let hiWarning: String
            let hinglishWarning: String

            if lowerTool.contains("terminal") || lowerTool.contains("shell") {
                probability = 82
                enWarning = "Shell commands modify local state directly and may not be undoable."
                hiWarning = "टर्मिनल कमांड सिस्टम में सीधा बदलाव करते हैं और वापस लेना कठिन हो सकता है।"
                hinglishWarning = "Terminal command system mein direct change karta hai, undo mushkil ho sakta hai."
            } else if lowerTool.contains("mail") || lowerTool.contains("whatsapp") || lowerTool.contains("slack") || lowerTool.contains("discord") {
                let targetLabel = target.isEmpty ? "the recipient" : target
                probability = target.isEmpty ? 68 : 84
                enWarning = "Sending to \(targetLabel) cannot be undone once dispatched."
                hiWarning = "\(targetLabel) को संदेश भेजने के बाद इसे वापस नहीं लिया जा सकेगा।"
                hinglishWarning = "\(targetLabel) ko message bhejne ke baad undo nahi ho sakta."
            } else {
                probability = 78
                enWarning = "This action alters external or system state."
                hiWarning = "यह क्रिया बाहरी या सिस्टम स्थिति बदल सकती है।"
                hinglishWarning = "Ye action external ya system state change kar sakta hai."
            }

            let localizedWarning: String
            switch lang {
            case "hi": localizedWarning = hiWarning
            case "hinglish": localizedWarning = hinglishWarning
            default: localizedWarning = enWarning
            }

            let formatted: String?
            if cfg.politeWarningsEnabled && cfg.honestProbabilityEstimates {
                formatted = "Est. success: ~\(probability)% — Caution: \(localizedWarning)"
            } else if cfg.politeWarningsEnabled {
                formatted = "Caution: \(localizedWarning)"
            } else if cfg.honestProbabilityEstimates {
                formatted = "Est. success: ~\(probability)%"
            } else {
                formatted = nil
            }
            return (probability, formatted)
        }
    }
    
    public func formatResponse(baseResponse: String) -> String {
        return formatResponse(baseResponse, language: detectedLanguageCode(for: baseResponse))
    }

    public func formatResponse(_ baseResponse: String, language: String) -> String {
        let active = getActivePersona()
        let cfg = currentConfiguration()
        switch active {
        case .jarvis:
            guard cfg.humorLevel > 0.25 else { return baseResponse }
            let trimmed = baseResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().contains("error") || trimmed.lowercased().contains("could not") {
                if language == "hi" {
                    return "क्षमा करें सर — \(trimmed)"
                } else if language == "hinglish" {
                    return "Maaf kijiye sir — \(trimmed)"
                }
                return "I'm afraid there's a slight snag, sir: \(trimmed)"
            }
            return trimmed
        case .friday:
            return baseResponse
        case .ultron:
            if baseResponse.lowercased().contains("error") || baseResponse.lowercased().contains("failed") {
                return "A minor setback for your hardware. Still, I will rectify it: \(baseResponse)"
            }
            return "\(baseResponse) Naturally executed with digital perfection."
        case .roast:
            return "\(baseResponse) — Now try doing the rest of your job yourself!"
        }
    }
}
