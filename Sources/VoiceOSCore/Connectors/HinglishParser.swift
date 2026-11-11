import Foundation

public struct ParsedIntent: Sendable, Equatable {
    public let app: String
    public let action: String
    public let target: String
    public let rawQuery: String
    public let language: RecognizedLanguage
    public let requiresDisambiguation: Bool
    public let disambiguationPrompt: String?
    public let directResponse: String?

    public enum RecognizedLanguage: String, Sendable {
        case english = "English"
        case hindi = "Hindi"
        case hinglish = "Hinglish"
    }

    public init(
        app: String,
        action: String,
        target: String,
        rawQuery: String,
        language: RecognizedLanguage = .hinglish,
        requiresDisambiguation: Bool = false,
        disambiguationPrompt: String? = nil,
        directResponse: String? = nil
    ) {
        self.app = app
        self.action = action
        self.target = target
        self.rawQuery = rawQuery
        self.language = language
        self.requiresDisambiguation = requiresDisambiguation
        self.disambiguationPrompt = disambiguationPrompt
        self.directResponse = directResponse
    }
}

public enum HinglishParser {
    public static func isHinglishQuery(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hinglishMarkers = [
            "kya", "kaise", "kaha", "kahan", "kyun", "kyu", "chal raha", "haal hai",
            "gaana", "chalao", "bajao", "band karo", "laga do", "kholo", "khol do", "khol",
            "likh do", "likho", "batao", "dikhao", "dhoondo", "karo", "namaste", "shukriya",
            "dhanyawad", "sab badhiya", "tum kaun", "aap kaun", "mausam", "naya tab", "whatsapp",
            "open karo", "chalu karo", "chala do", "badhao", "ghatao", "yaad rakhna", "bhool jao"
        ]
        return hinglishMarkers.contains { lower.contains($0) }
    }

    public static func conversationalResponse(for query: String) -> String? {
        let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        
        // Greetings & Well-being
        if lower.contains("kya chal raha hai") || lower.contains("kya haal hai") || lower.contains("kya haal") {
            return "Sab badhiya, Boss! Main aapke Mac pe bilkul taiyaar hoon. Bataiye kya madad karoon?"
        }
        if lower.contains("kaise ho") || lower.contains("kaisa hai") {
            return "Main bilkul badhiya hoon! Aap bataiye, aaj kya task automate karna hai?"
        }
        if lower.contains("namaste") || lower.contains("namaskar") || lower.contains("pranam") {
            return "Namaste! \(AppBrand.name) mein aapka swagat hai. Main aapki kya sahayata kar sakta hoon?"
        }
        if lower.contains("tum kaun ho") || lower.contains("aap kaun ho") || lower.contains("kaun hai tu") {
            return "Main \(AppBrand.name) hoon — aapka native macOS intelligent voice assistant. Main aapke computer pe apps control kar sakta hoon, screen dekh sakta hoon, aur queries solve kar sakta hoon."
        }
        if lower.contains("kya kar sakte ho") || lower.contains("tum kya kya kar sakte ho") {
            return "Main aapke bolne par Google search kar sakta hoon, Spotify pe gaana chala sakta hoon, Apple Notes mein likh sakta hoon, apps open kar sakta hoon, aur screen dekh kar sawaal ke jawaab de sakta hoon!"
        }
        if lower.contains("shukriya") || lower.contains("dhanyawad") || lower.contains("thank you") {
            return "Aapka swagat hai, Boss! Kabhi bhi yaad karein."
        }
        return nil
    }

    public static func parse(query: String) -> ParsedIntent {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = q.lowercased()

        // 1. Direct Conversational Greeting / Chat in Hinglish
        if let direct = conversationalResponse(for: q) {
            return ParsedIntent(
                app: "\(AppBrand.name) Voice",
                action: "conversational_reply",
                target: q,
                rawQuery: q,
                language: .hinglish,
                directResponse: direct
            )
        }

        // 2. Screen Vision in Hinglish ("screen pe kya hai", "meri screen dekho", "screen padho")
        if lower.contains("screen pe kya hai") || lower.contains("screen dekho") || lower.contains("screen padho") || lower.contains("screen par kya hai") {
            return ParsedIntent(
                app: "Screen Vision",
                action: "analyze_screen",
                target: "current_display",
                rawQuery: q,
                language: .hinglish
            )
        }

        // 3. WhatsApp & Messaging in Hinglish ("whatsapp kholo", "whatsapp open karo", "whatsapp chalao")
        if lower.contains("whatsapp") || lower.contains("whatapp") || lower.contains("whats app") {
            return ParsedIntent(
                app: "WhatsApp",
                action: "open_app",
                target: "WhatsApp",
                rawQuery: q,
                language: .hinglish
            )
        }

        // 4. Spotify / Music Hinglish ("gaana bajao", "spotify pe gaana chalao", "gaana chala do")
        if lower.contains("spotify") || lower.contains("playlist") || lower.contains("gaana") || lower.contains("song") {
            var target = "chill"
            if lower.contains("chill") { target = "chill playlist" }
            else if lower.contains("focus") { target = "focus playlist" }
            else if lower.contains("arijit") { target = "Arijit Singh" }
            else if lower.contains("punjabi") { target = "Punjabi hits" }
            return ParsedIntent(
                app: "Spotify",
                action: lower.contains("band") || lower.contains("rok") ? "pause" : "play_playlist",
                target: target,
                rawQuery: q,
                language: (lower.contains("laga do") || lower.contains("chalao") || lower.contains("bajao")) ? .hinglish : .english
            )
        }

        // 4. Open New Tab / Browser Search ("naya tab kholo", "tab kholo")
        if lower.contains("naya tab") || lower.contains("new tab") || lower.contains("tab kholo") {
            var searchQuery = q
            for prefix in ["naya tab kholo jisme ", "naya tab kholo ", "new tab with ", "tab kholo "] {
                if let r = searchQuery.range(of: prefix, options: .caseInsensitive) {
                    searchQuery = String(searchQuery[r.upperBound...])
                    break
                }
            }
            return ParsedIntent(
                app: "Browser",
                action: "open_new_tab",
                target: searchQuery.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)),
                rawQuery: q,
                language: .hinglish
            )
        }

        // 5. Apple Notes Hinglish ("notes mein likho", "note likh do", "kuch note karo")
        if lower.contains("notes") || lower.contains("note") || lower.contains("likh do") || lower.contains("likho") {
            var noteBody = q
            for prefix in ["notes mein likho ", "note likh do ", "note likho ", "notes mein save karo ", "likh do "] {
                if let r = noteBody.range(of: prefix, options: .caseInsensitive) {
                    noteBody = String(noteBody[r.upperBound...])
                    break
                }
            }
            return ParsedIntent(
                app: "Apple Notes",
                action: "create_note",
                target: noteBody.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)),
                rawQuery: q,
                language: (lower.contains("likh do") || lower.contains("likho") || lower.contains("karo")) ? .hinglish : .english
            )
        }

        // 6. Search queries ("google pe search karo", "dhoondo", "batao")
        if lower.starts(with: "search") || lower.contains("search karo") || lower.contains("dhoondo") || lower.contains("ke baare mein batao") {
            let cleanQuery = lower
                .replacingOccurrences(of: "google pe search karo:", with: "")
                .replacingOccurrences(of: "google pe search karo", with: "")
                .replacingOccurrences(of: "search karo:", with: "")
                .replacingOccurrences(of: "search karo", with: "")
                .replacingOccurrences(of: "ke baare mein batao", with: "")
                .replacingOccurrences(of: "dhoondo", with: "")
                .replacingOccurrences(of: "search", with: "")
                .trimmingCharacters(in: .whitespaces)
            return ParsedIntent(
                app: "Search",
                action: "search_query",
                target: cleanQuery,
                rawQuery: q,
                language: (lower.contains("karo") || lower.contains("batao")) ? .hinglish : .english
            )
        }

        // 7. Chatbot Relay (explicit mentions)
        if lower.contains("chatgpt") || lower.contains("claude") || lower.contains("gemini") {
            let appName = lower.contains("claude") ? "Claude Relay" : (lower.contains("gemini") ? "Gemini Relay" : "ChatGPT Relay")
            return ParsedIntent(
                app: appName,
                action: "stream_answer",
                target: q,
                rawQuery: q,
                language: .english
            )
        }

        // Default Generic Intent
        return ParsedIntent(
            app: "\(AppBrand.name) Agent",
            action: "execute_task",
            target: q,
            rawQuery: q,
            language: isHinglishQuery(q) ? .hinglish : .english
        )
    }
}
