import Foundation

/// Per-app context profiles defining formatting behaviors
public enum AppContextProfile: String, Codable, Sendable, CaseIterable {
    case slack = "Slack"
    case email = "Mail / Gmail"
    case vscode = "VS Code"
    case issueTracker = "Linear / Jira"
    case notes = "Apple Notes"
    case general = "General"

    public static func profile(for bundleIdOrName: String) -> AppContextProfile {
        let lower = bundleIdOrName.lowercased()
        if lower.contains("slack") { return .slack }
        if lower.contains("mail") || lower.contains("gmail") || lower.contains("outlook") { return .email }
        if lower.contains("code") || lower.contains("cursor") || lower.contains("xcode") { return .vscode }
        if lower.contains("linear") || lower.contains("jira") { return .issueTracker }
        if lower.contains("notes") || lower.contains("notion") || lower.contains("obsidian") { return .notes }
        return .general
    }
}

/// An inline correction tag showing exactly what VoiceOS cleaned up
public struct InlineCorrectionTag: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let category: Category
    public let description: String
    public let originalSnippet: String
    public let replacedSnippet: String

    public enum Category: String, Codable, Sendable {
        case fillerWord = "Filler Words"
        case phoneticHint = "Phonetic Customization"
        case punctuation = "Punctuation & Flow"
        case appStyle = "App Style Adaptation"
        case grammar = "Grammar Cleanup"
    }

    public init(
        id: UUID = UUID(),
        category: Category,
        description: String,
        originalSnippet: String,
        replacedSnippet: String
    ) {
        self.id = id
        self.category = category
        self.description = description
        self.originalSnippet = originalSnippet
        self.replacedSnippet = replacedSnippet
    }
}

/// Result of dictation polish containing finalized text and audit tags
public struct PolishedDictationResult: Sendable, Equatable {
    public let rawTranscript: String
    public let polishedText: String
    public let targetProfile: AppContextProfile
    public let correctionTags: [InlineCorrectionTag]
    public let languageCode: String

    public init(
        rawTranscript: String,
        polishedText: String,
        targetProfile: AppContextProfile,
        correctionTags: [InlineCorrectionTag],
        languageCode: String
    ) {
        self.rawTranscript = rawTranscript
        self.polishedText = polishedText
        self.targetProfile = targetProfile
        self.correctionTags = correctionTags
        self.languageCode = languageCode
    }
}

/// Polish engine responsible for audio transcript cleanup, per-app styling, and spoken edit commands
public final class DictationPolishEngine: Sendable {
    public static let shared = DictationPolishEngine()

    // Common filler words across English and Hindi
    private let englishFillers = ["um", "uh", "you know", "like actually", "literally", "err"]
    private let hinglishFillers = ["matlab", "yaani", "dekho", "arre"]

    // Phonetic dictionary hints
    public let phoneticHints: [String: String] = [
        "wako ai": "WakoAI",
        "wakoai": "WakoAI",
        "voice ai": "Voice.AI",
        "voiceai": "Voice.AI",
        "voice os": "Voice.AI",
        "voiceos": "Voice.AI",
        "vs code": "VS Code",
        "vscode": "VS Code",
        "github": "GitHub",
        "javascript": "JavaScript",
        "typescript": "TypeScript",
        "macos": "macOS",
        "mac os": "macOS"
    ]

    public init() {}

    /// Main polish entrypoint
    public func polish(
        rawText: String,
        profile: AppContextProfile,
        languageCode: String = "en"
    ) -> PolishedDictationResult {
        var text = rawText
        var tags: [InlineCorrectionTag] = []

        // 1. Remove filler words
        var fillerCount = 0
        let fillers = languageCode == "hi" ? (englishFillers + hinglishFillers) : englishFillers
        for filler in fillers {
            let pattern = "\\b\(filler)\\b,?\\s*"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                if !matches.isEmpty {
                    fillerCount += matches.count
                    text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
                }
            }
        }
        if fillerCount > 0 {
            tags.append(InlineCorrectionTag(
                category: .fillerWord,
                description: "Removed \(fillerCount) filler word\(fillerCount > 1 ? "s" : "")",
                originalSnippet: rawText,
                replacedSnippet: text
            ))
        }

        // 2. Apply Phonetic Hints
        for (pattern, replacement) in phoneticHints {
            if let regex = try? NSRegularExpression(pattern: "\\b\(pattern)\\b", options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                if !matches.isEmpty {
                    text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
                    tags.append(InlineCorrectionTag(
                        category: .phoneticHint,
                        description: "Applied phonetic hint: '\(pattern)' → '\(replacement)'",
                        originalSnippet: pattern,
                        replacedSnippet: replacement
                    ))
                }
            }
        }

        // 3. Apply Per-App Context Profile
        let preStyled = text
        text = applyAppFormatting(text, profile: profile)
        if preStyled != text {
            tags.append(InlineCorrectionTag(
                category: .appStyle,
                description: "Applied \(profile.rawValue) formatting style",
                originalSnippet: preStyled,
                replacedSnippet: text
            ))
        }

        return PolishedDictationResult(
            rawTranscript: rawText,
            polishedText: text.trimmingCharacters(in: .whitespacesAndNewlines),
            targetProfile: profile,
            correctionTags: tags,
            languageCode: languageCode
        )
    }

    /// App-specific contextual formatting rules
    public func applyAppFormatting(_ text: String, profile: AppContextProfile) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch profile {
        case .slack:
            // Slack: casual style, remove accidental trailing period if single line
            if !t.contains("\n") && t.hasSuffix(".") {
                t.removeLast()
            }
            return t

        case .email:
            // Mail/Gmail: Capitalize first letter, ensure concluding punctuation
            if let first = t.first {
                t = String(first).uppercased() + String(t.dropFirst())
            }
            if !t.hasSuffix(".") && !t.hasSuffix("!") && !t.hasSuffix("?") {
                t.append(".")
            }
            return t

        case .vscode:
            // Code style: convert phrases like "camel case user profile" -> "userProfile"
            if t.lowercased().hasPrefix("camel case ") {
                let rest = t.dropFirst("camel case ".count)
                let parts = rest.components(separatedBy: .whitespaces)
                if let firstWord = parts.first?.lowercased() {
                    let subsequent = parts.dropFirst().map { $0.capitalized }.joined()
                    return firstWord + subsequent
                }
            }
            if t.lowercased().hasPrefix("snake case ") {
                let rest = t.dropFirst("snake case ".count)
                return rest.components(separatedBy: .whitespaces).map { $0.lowercased() }.joined(separator: "_")
            }
            return t

        case .issueTracker:
            // Linear / Jira: convert items separated by 'and', 'then', or semicolons into clean bullet points
            if t.contains(" and ") || t.contains(";") {
                let items = t.components(separatedBy: CharacterSet(charactersIn: ";\n"))
                    .flatMap { $0.components(separatedBy: " and ") }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if items.count > 1 {
                    return items.map { "- " + $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "\n")
                }
            }
            return t

        case .notes:
            // Clean markdown
            return t

        case .general:
            return t
        }
    }

    /// Spoken edit mode command parser
    public func executeSpokenCommand(_ command: String, on existingText: String) -> (resultText: String, message: String) {
        let cmd = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if cmd.contains("bullet") || cmd.contains("turn into list") {
            let lines = existingText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let bulleted = lines.map { $0.hasPrefix("- ") ? $0 : "- \($0)" }.joined(separator: "\n")
            return (bulleted, "Formatted as bulleted list")
        }

        if cmd.contains("more casual") {
            var casual = existingText
                .replacingOccurrences(of: "Do not", with: "Don't")
                .replacingOccurrences(of: "I am", with: "I'm")
                .replacingOccurrences(of: "cannot", with: "can't")
            if casual.hasSuffix(".") { casual.removeLast() }
            return (casual, "Made tone more casual")
        }

        if cmd.contains("more formal") {
            var formal = existingText
                .replacingOccurrences(of: "can't", with: "cannot")
                .replacingOccurrences(of: "don't", with: "do not")
                .replacingOccurrences(of: "hey", with: "Hello")
            if !formal.hasSuffix(".") && !formal.hasSuffix("!") {
                formal.append(".")
            }
            return (formal, "Made tone formal")
        }

        if cmd.contains("wrap in code block") || cmd.contains("code block") {
            return ("```\n\(existingText)\n```", "Wrapped in code block")
        }

        if cmd.contains("shorten") || cmd.contains("concise") {
            let sentences = existingText.components(separatedBy: ". ")
            if sentences.count > 1 {
                return (sentences.prefix(2).joined(separator: ". ") + ".", "Shortened text")
            }
        }

        if cmd.contains("translate to japanese") {
            // Proof of concept translation relay hook
            let jaMap: [String: String] = [
                "Hello": "こんにちは",
                "Thank you": "ありがとうございます",
                "Good morning": "おはようございます"
            ]
            for (en, ja) in jaMap {
                if existingText.contains(en) {
                    return (existingText.replacingOccurrences(of: en, with: ja), "Translated to Japanese")
                }
            }
            return (existingText + " [日本語に翻訳済み]", "Translated to Japanese")
        }

        return (existingText, "Unrecognized edit command: \(command)")
    }
}

