import Foundation
import AVFoundation
import AppKit

/// Manages voice discovery, auditioning (in English and Hindi), and voice persistence for Voice.AI.
public final class VoiceAuditionManager: NSObject, @unchecked Sendable, AVSpeechSynthesizerDelegate {
    public static let shared = VoiceAuditionManager()
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private let selectedVoiceKey = "voiceos.selected_voice_id"
    
    public override init() {
        super.init()
        speechSynthesizer.delegate = self
    }
    
    // MARK: - Voice Discovery
    
    /// Lists all available system voices and cloud voices based on user keys.
    public func listAllAvailableVoices() -> [VoiceOption] {
        var results: [VoiceOption] = []
        
        // 0. Local Kokoro-82M Neural Voice (if ready)
        if KokoroTTSEngine.shared.diagnostics().isFullyReady {
            results.append(VoiceOption(
                identifier: "af_heart",
                name: "Kokoro Heart (Local Neural)",
                provider: "Kokoro",
                language: "en-US",
                isNeural: true
            ))
        }
        
        // 1. macOS System Voices (AVSpeechSynthesisVoice)
        let systemVoices = AVSpeechSynthesisVoice.speechVoices()
        for v in systemVoices {
            // Prioritize English and Hindi/Indian locales
            let lang = v.language
            let isRelevant = lang.starts(with: "en") || lang.starts(with: "hi")
            if isRelevant {
                let isEnhanced = v.quality == .enhanced || v.name.lowercased().contains("enhanced") || v.name.lowercased().contains("siri")
                let option = VoiceOption(
                    identifier: v.identifier,
                    name: "\(v.name) (\(v.language))",
                    provider: "macOS System",
                    language: v.language,
                    isNeural: isEnhanced
                )
                results.append(option)
            }
        }
        
        // 2. OpenAI Voices (if API key exists)
        if ModelRouter.shared.hasValidCloudKey() {
            let openAIVoices = [
                ("alloy", "Alloy (Neutral & Crisp)"),
                ("echo", "Echo (Warm & Grounded)"),
                ("fable", "Fable (British & Expressive)"),
                ("onyx", "Onyx (Deep & Authoritative)"),
                ("nova", "Nova (Bright & Friendly)"),
                ("shimmer", "Shimmer (Clear & Natural)")
            ]
            for (id, name) in openAIVoices {
                results.append(VoiceOption(
                    identifier: id,
                    name: name,
                    provider: "OpenAI Cloud TTS",
                    language: "multilingual",
                    isNeural: true
                ))
            }
        }
        
        // Sort: neural / enhanced first, then by name
        return results.sorted {
            if $0.isNeural != $1.isNeural {
                return $0.isNeural && !$1.isNeural
            }
            return $0.name < $1.name
        }
    }
    
    // MARK: - Selected Voice Management
    
    public var selectedVoiceIdentifier: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: selectedVoiceKey), !saved.isEmpty {
                return saved
            }
            // Default to a high quality English voice or system default
            return AVSpeechSynthesisVoice.speechVoices().first(where: {
                $0.language.starts(with: "en") && $0.quality == .enhanced
            })?.identifier ?? AVSpeechSynthesisVoice(language: "en-US")?.identifier ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: selectedVoiceKey)
        }
    }
    
    // MARK: - Audition Playback
    
    public func stopAudition() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        KokoroTTSEngine.shared.stop()
    }
    
    /// Auditions a voice by speaking a curated, natural sentence in either English or Hindi.
    public func auditionVoice(voice: VoiceOption, language: String = "en") async throws {
        stopAudition()
        
        let sampleText: String
        if language.lowercased().starts(with: "hi") {
            sampleText = "Namaste! Main Voice.AI hoon. Aapke Mac par har kaam mein madad karne ke liye taiyaar."
        } else {
            sampleText = "Hello! I am Voice.AI, your high-performance macOS companion. Ready to assist."
        }
        
        if voice.provider == "Kokoro" {
            await withCheckedContinuation { continuation in
                KokoroTTSEngine.shared.speak(text: sampleText, voice: voice.identifier) { _ in
                    continuation.resume()
                }
            }
        } else if voice.provider == "OpenAI Cloud TTS" {
            // Synthesize via OpenAI Provider
            let openAI = OpenAIProvider(apiKey: KeychainService.shared.get(.openAIApiKey) ?? "")
            let mp3Data = try await openAI.synthesizeSpeech(text: sampleText, voice: voice, speed: 1.0)
            
            await MainActor.run {
                do {
                    self.audioPlayer = try AVAudioPlayer(data: mp3Data)
                    self.audioPlayer?.play()
                } catch {
                    print("[VoiceAudition] Playback error: \(error)")
                }
            }
        } else {
            // Synthesize via AVSpeechSynthesizer
            let utterance = AVSpeechUtterance(string: sampleText)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = 1.0
            
            if let avVoice = AVSpeechSynthesisVoice(identifier: voice.identifier) {
                utterance.voice = avVoice
            } else if language.lowercased().starts(with: "hi") {
                utterance.voice = AVSpeechSynthesisVoice(language: "hi-IN")
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            }
            
            await MainActor.run {
                self.speechSynthesizer.speak(utterance)
            }
        }
    }
}
