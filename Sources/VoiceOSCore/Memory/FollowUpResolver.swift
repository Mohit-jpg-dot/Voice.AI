import Foundation

public struct FollowUpResolution: Sendable, Equatable {
    public let originalText: String
    public let rewrittenText: String
    public let wasRewritten: Bool
    public let disambiguationQuestion: String?
    public let confidence: Double
    public let resolutionNote: String?
    
    public init(
        originalText: String,
        rewrittenText: String,
        wasRewritten: Bool,
        disambiguationQuestion: String? = nil,
        confidence: Double = 1.0,
        resolutionNote: String? = nil
    ) {
        self.originalText = originalText
        self.rewrittenText = rewrittenText
        self.wasRewritten = wasRewritten
        self.disambiguationQuestion = disambiguationQuestion
        self.confidence = confidence
        self.resolutionNote = resolutionNote
    }
}

public final class FollowUpResolver: @unchecked Sendable {
    public static let shared = FollowUpResolver()
    
    private init() {}
    
    /// Resolves follow-ups deterministically against the provided ConversationState.
    public func resolve(
        userText: String,
        state: ConversationStateRecord
    ) -> FollowUpResolution {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return FollowUpResolution(originalText: userText, rewrittenText: userText, wasRewritten: false)
        }
        
        let lower = trimmed.lowercased()
        
        // 1. Repetition ("again", "dobara", "phir se", "wahi dobara karo", "repeat that")
        if let repeated = resolveRepetition(lower: lower, original: trimmed, state: state) {
            return repeated
        }
        
        // 2. Analogy ("do the same for X", "same for X", "yahi X ke liye karo")
        if let analogy = resolveAnalogy(lower: lower, original: trimmed, state: state) {
            return analogy
        }
        
        // 3. Ordinal / Index references ("the second one", "dusra wala", "last one", "aakhri")
        if let indexRes = resolveIndexReference(lower: lower, original: trimmed, state: state) {
            return indexRes
        }
        
        // 4. Pronoun and demonstrative references ("send that to David", "isko bhej do", "open that pdf", "use delete karo")
        if let pronounRes = resolvePronounReference(lower: lower, original: trimmed, state: state) {
            return pronounRes
        }
        
        // Standalone utterance without follow-up references
        return FollowUpResolution(originalText: trimmed, rewrittenText: trimmed, wasRewritten: false)
    }
    
    // MARK: - 1. Repetition Resolver
    
    private func resolveRepetition(lower: String, original: String, state: ConversationStateRecord) -> FollowUpResolution? {
        let repetitionPhrases = [
            "again", "do it again", "run it again", "repeat", "repeat that",
            "phir se", "phir se karo", "dobara", "dobara karo", "wahi dobara karo",
            "ek baar aur", "once more"
        ]
        
        let isExactRepetition = repetitionPhrases.contains(where: { lower == $0 || lower == $0 + "." })
        guard isExactRepetition, let lastAction = state.lastAction else {
            return nil
        }
        
        let targetPart = lastAction.target.map { " on \($0)" } ?? ""
        let rewrite = "\(lastAction.toolName)\(targetPart)"
        let note = "Resolved repetition trigger to last action `\(lastAction.toolName)`"
        
        return FollowUpResolution(
            originalText: original,
            rewrittenText: rewrite,
            wasRewritten: true,
            disambiguationQuestion: nil,
            confidence: 0.95,
            resolutionNote: note
        )
    }
    
    // MARK: - 2. Analogy Resolver ("do the same for X")
    
    private func resolveAnalogy(lower: String, original: String, state: ConversationStateRecord) -> FollowUpResolution? {
        guard let lastAction = state.lastAction else { return nil }
        
        // English patterns: "do the same for <target>", "same for <target>"
        if lower.hasPrefix("do the same for ") {
            let target = String(original.dropFirst("do the same for ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let rewrite = "\(lastAction.toolName) for \(target)"
            return FollowUpResolution(
                originalText: original,
                rewrittenText: rewrite,
                wasRewritten: true,
                confidence: 0.9,
                resolutionNote: "Transferred last action `\(lastAction.toolName)` to \(target)"
            )
        }
        
        if lower.hasPrefix("same for ") {
            let target = String(original.dropFirst("same for ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let rewrite = "\(lastAction.toolName) for \(target)"
            return FollowUpResolution(
                originalText: original,
                rewrittenText: rewrite,
                wasRewritten: true,
                confidence: 0.9,
                resolutionNote: "Transferred last action `\(lastAction.toolName)` to \(target)"
            )
        }
        
        // Hindi / Hinglish patterns: "yahi <target> ke liye karo", "wahi <target> par karo"
        if lower.contains("ke liye karo") || lower.contains("par karo") {
            let parts = original.components(separatedBy: CharacterSet.whitespaces)
            if let yahiIdx = parts.firstIndex(where: { $0.lowercased() == "yahi" || $0.lowercased() == "wahi" }),
               let karoIdx = parts.firstIndex(where: { $0.lowercased() == "karo" }),
               karoIdx > yahiIdx + 1 {
                let targetWords = parts[(yahiIdx + 1)..<karoIdx].filter {
                    let w = $0.lowercased()
                    return w != "ke" && w != "liye" && w != "par" && w != "pe"
                }
                let target = targetWords.joined(separator: " ")
                if !target.isEmpty {
                    let rewrite = "\(lastAction.toolName) for \(target)"
                    return FollowUpResolution(
                        originalText: original,
                        rewrittenText: rewrite,
                        wasRewritten: true,
                        confidence: 0.9,
                        resolutionNote: "Transferred last action `\(lastAction.toolName)` to Hinglish target \(target)"
                    )
                }
            }
        }
        
        return nil
    }
    
    // MARK: - 3. Ordinal / Index Reference Resolver
    
    private func resolveIndexReference(lower: String, original: String, state: ConversationStateRecord) -> FollowUpResolution? {
        guard !state.lastResultList.isEmpty else { return nil }
        
        var targetIndex: Int? = nil
        var matchedPattern: String = ""
        
        // 1st / first / pehla
        let firstPatterns = ["the first one", "first one", "1st one", "first", "1st", "pehla", "pehla wala", "pehli"]
        // 2nd / second / dusra
        let secondPatterns = ["the second one", "second one", "2nd one", "second", "2nd", "dusra", "dusra wala", "doosra", "dusri"]
        // 3rd / third / teesra
        let thirdPatterns = ["the third one", "third one", "3rd one", "third", "3rd", "teesra", "teesra wala", "tisra", "teesri"]
        // 4th / fourth / chautha
        let fourthPatterns = ["the fourth one", "fourth one", "4th one", "fourth", "4th", "chautha", "chautha wala"]
        // 5th / fifth / paanchwa
        let fifthPatterns = ["the fifth one", "fifth one", "5th one", "fifth", "5th", "paanchwa", "panchwa"]
        // Last / aakhri
        let lastPatterns = ["the last one", "last one", "previous one", "last", "aakhri", "aakhri wala", "akhri", "antim"]
        
        for p in firstPatterns where lower.contains(p) { targetIndex = 1; matchedPattern = p; break }
        if targetIndex == nil { for p in secondPatterns where lower.contains(p) { targetIndex = 2; matchedPattern = p; break } }
        if targetIndex == nil { for p in thirdPatterns where lower.contains(p) { targetIndex = 3; matchedPattern = p; break } }
        if targetIndex == nil { for p in fourthPatterns where lower.contains(p) { targetIndex = 4; matchedPattern = p; break } }
        if targetIndex == nil { for p in fifthPatterns where lower.contains(p) { targetIndex = 5; matchedPattern = p; break } }
        if targetIndex == nil { for p in lastPatterns where lower.contains(p) { targetIndex = state.lastResultList.count; matchedPattern = p; break } }
        
        guard let idx = targetIndex, let item = state.itemAtIndex(idx) else {
            return nil
        }
        
        // Replace matched pattern with the item title or identifier
        let replacement = item.identifier.isEmpty ? item.title : item.identifier
        let rewritten = replaceFirstMatch(in: original, targetPattern: matchedPattern, with: replacement)
        
        return FollowUpResolution(
            originalText: original,
            rewrittenText: rewritten,
            wasRewritten: true,
            disambiguationQuestion: nil,
            confidence: 0.98,
            resolutionNote: "Resolved index \(idx) ('\(matchedPattern)') to '\(item.title)'"
        )
    }
    
    // MARK: - 4. Pronoun and Demonstrative Resolver
    
    private func resolvePronounReference(lower: String, original: String, state: ConversationStateRecord) -> FollowUpResolution? {
        // Specific Kind Demonstratives: "that pdf", "that document", "that file", "that folder", "that person"
        let specificKindTriggers: [(trigger: String, kind: EntityKind)] = [
            ("that pdf", .file), ("that doc", .file), ("that document", .file),
            ("that file", .file), ("us file", .file), ("woh file", .file),
            ("that folder", .folder), ("us folder", .folder),
            ("that person", .person), ("him", .person), ("her", .person),
            ("that link", .url), ("that url", .url), ("that website", .url),
            ("that app", .app), ("that application", .app)
        ]
        
        for item in specificKindTriggers {
            if lower.contains(item.trigger) {
                let candidates = state.entities.filter { $0.kind == item.kind }
                if candidates.count >= 2 {
                    // Check if two candidates have high/ambiguous salience
                    let topTwo = Array(candidates.prefix(2))
                    if abs(topTwo[0].salience - topTwo[1].salience) < 0.15 {
                        let question = "Did you mean \(topTwo[0].name) or \(topTwo[1].name)?"
                        return FollowUpResolution(
                            originalText: original,
                            rewrittenText: original,
                            wasRewritten: false,
                            disambiguationQuestion: question,
                            confidence: 0.5,
                            resolutionNote: "Ambiguous references between multiple candidates"
                        )
                    }
                }
                
                if let best = candidates.first {
                    let rewrite = replaceFirstMatch(in: original, targetPattern: item.trigger, with: best.name)
                    return FollowUpResolution(
                        originalText: original,
                        rewrittenText: rewrite,
                        wasRewritten: true,
                        confidence: 0.92,
                        resolutionNote: "Resolved '\(item.trigger)' to entity '\(best.name)' (\(best.kind.rawValue))"
                    )
                }
            }
        }
        
        // General Demonstratives & Hinglish Pronouns:
        // "send that to David", "open that", "delete it", "isko bhej do", "use kholo", "isse chhota karo"
        let generalTriggers = [
            "that", "it", "this",
            "isko", "isse", "use", "usse", "ye", "yeh", "woh", "wo", "wahi"
        ]
        
        for g in generalTriggers {
            // Check for whole word match
            if hasWholeWord(in: lower, word: g) {
                // If there was an active result list, default to top or last result
                if let firstResult = state.lastResultList.first {
                    let rewrite = replaceWord(in: original, word: g, with: firstResult.title)
                    return FollowUpResolution(
                        originalText: original,
                        rewrittenText: rewrite,
                        wasRewritten: true,
                        confidence: 0.88,
                        resolutionNote: "Resolved general pronoun '\(g)' to recent result '\(firstResult.title)'"
                    )
                }
                
                // Otherwise check most salient entity
                if let salient = state.mostSalientEntity() {
                    let rewrite = replaceWord(in: original, word: g, with: salient.name)
                    return FollowUpResolution(
                        originalText: original,
                        rewrittenText: rewrite,
                        wasRewritten: true,
                        confidence: 0.85,
                        resolutionNote: "Resolved general pronoun '\(g)' to salient entity '\(salient.name)'"
                    )
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Helpers
    
    private func hasWholeWord(in text: String, word: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
    
    private func replaceWord(in text: String, word: String, with replacement: String) -> String {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
        }
        return text
    }
    
    private func replaceFirstMatch(in text: String, targetPattern: String, with replacement: String) -> String {
        if let range = text.range(of: targetPattern, options: .caseInsensitive) {
            var mutable = text
            mutable.replaceSubrange(range, with: replacement)
            return mutable
        }
        return text
    }
}
