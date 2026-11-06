import Foundation

public enum PersonaType: String, CaseIterable, Identifiable, Codable, Sendable {
    case friday = "Friday"
    case ultron = "Ultron"
    case roast = "Roast Mode"
    
    public var id: String { rawValue }
    
    public var description: String {
        switch self {
        case .friday:
            return "Warm, precise, and supportive macOS AI partner."
        case .ultron:
            return "Theatrical, sardonic, and hyper-competent AI visionary."
        case .roast:
            return "Witty, playful banter. Opt-in only with automatic safety guards."
        }
    }
}

public final class PersonaManager: @unchecked Sendable {
    public static let shared = PersonaManager()
    
    private let lock = NSLock()
    private var currentPersona: PersonaType = .friday
    private var isRoastModeTemporarilySuspended: Bool = false
    
    public init() {
        let saved = UserDefaults.standard.string(forKey: "VoiceAI_ActivePersona") ?? "Friday"
        self.currentPersona = PersonaType(rawValue: saved) ?? .friday
    }
    
    public func getActivePersona() -> PersonaType {
        lock.lock()
        defer { lock.unlock() }
        if currentPersona == .roast && isRoastModeTemporarilySuspended {
            return .friday
        }
        return currentPersona
    }
    
    public func setPersona(_ persona: PersonaType) {
        lock.lock()
        defer { lock.unlock() }
        currentPersona = persona
        isRoastModeTemporarilySuspended = false
        UserDefaults.standard.set(persona.rawValue, forKey: "VoiceAI_ActivePersona")
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
                lock.lock()
                isRoastModeTemporarilySuspended = true
                lock.unlock()
                return true
            }
        }
        return false
    }
    
    public func formatResponse(baseResponse: String) -> String {
        let active = getActivePersona()
        switch active {
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

