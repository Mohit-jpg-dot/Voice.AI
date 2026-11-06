import Foundation

/// Fast, bidirectional transliterator and normalizer between Devanagari script and Roman Hinglish.
/// Converts Devanagari speech recognition outputs (e.g., "व्हाट्सएप खोलो") to standardized Roman Hinglish,
/// and handles phonetic variations so intent parsers and tool dispatchers recognize commands uniformly.
public enum HinglishTransliterator {
    
    // Core phonetic character mappings from Devanagari to Roman
    private static let devanagariToRomanMap: [(String, String)] = [
        // Multi-character conjuncts and frequent words first
        ("व्हाट्सएप", "whatsapp"),
        ("वॉट्सएप", "whatsapp"),
        ("व्हाट्सऐप", "whatsapp"),
        ("स्पॉटिफ़ाई", "spotify"),
        ("स्पॉटिफाई", "spotify"),
        ("स्पॉटीफाई", "spotify"),
        ("क्रोम", "chrome"),
        ("सफ़ारी", "safari"),
        ("सफारी", "safari"),
        ("यूट्यूब", "youtube"),
        ("गूगल", "google"),
        ("टर्मिनल", "terminal"),
        ("फ़ाइंडर", "finder"),
        ("फाइंडर", "finder"),
        ("स्क्रीनशॉट", "screenshot"),
        ("स्क्रीन", "screen"),
        ("मैसेज", "message"),
        ("संदेश", "message"),
        ("गाना", "gana"),
        ("गाने", "gaane"),
        ("गीत", "gana"),
        ("खोलो", "kholo"),
        ("खोल", "khol"),
        ("चलाओ", "chalao"),
        ("चला", "chala"),
        ("बजाओ", "bajao"),
        ("बजा", "baja"),
        ("लगाओ", "lagao"),
        ("लगा", "laga"),
        ("करो", "karo"),
        ("कर", "kar"),
        ("दो", "do"),
        ("दीजिये", "dijiye"),
        ("दीजिए", "dijiye"),
        ("रोक", "rok"),
        ("रोको", "roko"),
        ("बंद", "band"),
        ("बन्द", "band"),
        ("वॉल्यूम", "volume"),
        ("आवाज़", "aawaz"),
        ("आवाज", "aawaz"),
        ("कम", "kam"),
        ("ज्यादा", "zyada"),
        ("बढ़ाओ", "badhao"),
        ("बढ़ा", "badha"),
        ("घटाओ", "ghatao"),
        ("लिखो", "likho"),
        ("लिख", "likh"),
        ("भेजो", "bhejo"),
        ("भेज", "bhej"),
        ("ढूंढो", "dhoondo"),
        ("खोजो", "khojo"),
        ("नया", "naya"),
        ("टैब", "tab"),
        ("विंडो", "window"),
        ("नोट्स", "notes"),
        ("नोट", "note"),
        ("सेटिंग्स", "settings"),
        ("कैलेंडर", "calendar"),
        ("तस्वीर", "photo"),
        ("फोटो", "photo"),
        ("राहुल", "rahul"),
        ("अमित", "amit"),
        ("पूजा", "pooja"),
        ("प्रिया", "priya"),
        ("रोहन", "rohan"),
        ("अरिजीत", "arijit"),
        ("सिंह", "singh"),
        
        // Common postpositions & connectives
        ("को", "ko"),
        ("पे", "pe"),
        ("पर", "par"),
        ("में", "mein"),
        ("से", "se"),
        ("कि", "ki"),
        ("की", "ki"),
        ("है", "hai"),
        ("हूँ", "hoon"),
        ("हूं", "hoon"),
        ("मैं", "main"),
        ("ले लो", "le lo"),
        ("कम कर दो", "kam kar do"),
        ("बढ़ाओ", "badhao"),
        ("रोक दो", "rok do"),
        
        // Vowels
        ("अ", "a"), ("आ", "aa"), ("इ", "i"), ("ई", "ee"), ("उ", "u"), ("ऊ", "oo"),
        ("ए", "e"), ("ऐ", "ai"), ("ओ", "o"), ("औ", "au"), ("ऋ", "ri"),
        
        // Consonants
        ("क", "k"), ("ख", "kh"), ("ग", "g"), ("घ", "gh"), ("ङ", "ng"),
        ("च", "ch"), ("छ", "chh"), ("ज", "j"), ("झ", "jh"), ("ञ", "nya"),
        ("ट", "t"), ("ठ", "th"), ("ड", "d"), ("ढ", "dh"), ("ण", "n"),
        ("त", "t"), ("थ", "th"), ("द", "d"), ("ध", "dh"), ("न", "n"),
        ("प", "p"), ("फ", "ph"), ("ब", "b"), ("भ", "bh"), ("म", "m"),
        ("य", "y"), ("र", "r"), ("ल", "l"), ("व", "v"), ("श", "sh"),
        ("ष", "sh"), ("स", "s"), ("ह", "h"),
        ("क़", "q"), ("ख़", "kh"), ("ग़", "gh"), ("ज़", "z"), ("ड़", "d"),
        ("ढ़", "dh"), ("फ़", "f"),
        
        // Matras
        ("ा", "a"), ("ि", "i"), ("ी", "i"), ("ु", "u"), ("ू", "oo"),
        ("े", "e"), ("ै", "ai"), ("ो", "o"), ("ौ", "au"),
        ("्", ""), ("ं", "n"), ("ः", "h"), ("ँ", "n"), ("़", "")
    ]
    
    /// Normalizes any input query by transliterating Devanagari to Roman text and canonicalizing Hinglish verbs/terms
    public static func normalize(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }
        
        // If query contains Devanagari characters, transliterate them
        if containsDevanagari(result) {
            result = devanagariToRoman(result)
        }
        
        result = canonicalizeRomanHinglish(result)
        return result
    }
    
    /// Returns true if the string contains any Devanagari Unicode code points
    public static func containsDevanagari(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // Devanagari Unicode Block: U+0900 to U+097F
            if scalar.value >= 0x0900 && scalar.value <= 0x097F {
                return true
            }
        }
        return false
    }
    
    /// Transliterates Devanagari text into Romanized phonetic text
    public static func devanagariToRoman(_ text: String) -> String {
        var str = text
        for (dev, rom) in devanagariToRomanMap {
            str = str.replacingOccurrences(of: dev, with: rom)
        }
        // Remove lingering zero-width joiners or unmapped marks
        str = str.replacingOccurrences(of: "\u{200D}", with: "")
        str = str.replacingOccurrences(of: "\u{200C}", with: "")
        return str
    }
    
    /// Helper to replace occurrences respecting word boundaries
    private static func replaceWordBoundaries(in text: String, target: String, with replacement: String) -> String {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: target) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text.replacingOccurrences(of: target, with: replacement, options: .caseInsensitive)
        }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }

    /// Canonicalizes Roman Hinglish phonetic variations and slang to standard forms
    public static func canonicalizeRomanHinglish(_ text: String) -> String {
        var lower = text.lowercased()
        
        // Common app name misspellings / phonetic transcriptions
        let appReplacements: [(String, String)] = [
            ("what's up", "whatsapp"),
            ("what sap", "whatsapp"),
            ("whatsup", "whatsapp"),
            ("whats app", "whatsapp"),
            ("whatapp", "whatsapp"),
            ("watsapp", "whatsapp"),
            ("spot if i", "spotify"),
            ("spotifay", "spotify"),
            ("spoti fy", "spotify"),
            ("youtune", "youtube"),
            ("youtub", "youtube"),
            ("youtue", "youtube"),
            ("you tube", "youtube"),
            ("u tube", "youtube"),
            ("hinid", "hindi"),
            ("doreamon", "doraemon"),
            ("goo gle", "google"),
            ("goo gle chrome", "google chrome"),
            ("chrom", "chrome"),
            ("safari browser", "safari")
        ]
        
        for (mis, can) in appReplacements {
            lower = replaceWordBoundaries(in: lower, target: mis, with: can)
        }
        
        // Normalize Hindi verb compound forms & common slang abbreviations (e.g. "klo" -> "kholo", "khol do" -> "kholo")
        let verbReplacements: [(String, String)] = [
            ("klo", "kholo"),
            ("kldo", "kholo"),
            ("khol do", "kholo"),
            ("khol de", "kholo"),
            ("khol na", "kholo"),
            ("kholna", "kholo"),
            ("khol", "kholo"),
            ("open karo", "kholo"),
            ("open kr do", "kholo"),
            ("open kro", "kholo"),
            ("chalu karo", "chalao"),
            ("chala do", "chalao"),
            ("chala de", "chalao"),
            ("bajao", "chalao"),
            ("baja do", "chalao"),
            ("laga do", "chalao"),
            ("laga de", "chalao"),
            ("play karo", "chalao"),
            ("lagao", "chalao"),
            ("laga", "chalao"),
            ("gaane", "gana"),
            ("gaana", "gana"),
            ("band kar do", "band karo"),
            ("rok do", "pause"),
            ("pause karo", "pause"),
            ("aawaz", "volume"),
            ("awaz", "volume"),
            ("dheemi karo", "kam karo"),
            ("dheema karo", "kam karo"),
            ("tez karo", "badhao"),
            ("bada do", "badhao"),
            ("likh do", "likho"),
            ("bhej do", "bhejo"),
            ("sandesh", "message"),
            ("naya tab khol do", "open_tab"),
            ("naya tab kholo", "open_tab"),
            ("screen shot", "screenshot")
        ]
        
        for (phrase, can) in verbReplacements {
            lower = replaceWordBoundaries(in: lower, target: phrase, with: can)
        }
        
        // Strip informal conversation fillers (e.g. "bro", "bhai", "yaar", "dude", "please", "plz", "zara")
        let fillers = ["bro", "bhai", "yaar", "dude", "buddy", "please", "plz", "zara", "na", "re", "beta", "dost"]
        for f in fillers {
            lower = replaceWordBoundaries(in: lower, target: f, with: "")
        }
        
        // Collapse multiple whitespace
        let components = lower.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return components.joined(separator: " ")
    }
}
