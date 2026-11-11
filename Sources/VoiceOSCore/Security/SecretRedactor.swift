import Foundation

/// Centralized secret and PII scrubbing utility used across logs, encrypted chat history,
/// event bus payloads, and the persistent semantic MemoryStore.
public enum SecretRedactor {
    private static let patternReplacements: [(pattern: String, replacement: String)] = [
        // Anthropic / OpenAI keys
        (#"sk-ant-[A-Za-z0-9_-]{12,}"#, "[REDACTED_API_KEY]"),
        (#"sk-[A-Za-z0-9_-]{20,}"#, "[REDACTED_API_KEY]"),
        // Google API keys (AIza...)
        (#"AIza[0-9A-Za-z_-]{20,}"#, "[REDACTED_API_KEY]"),
        // Notion internal integration secrets
        (#"\b(?:secret|ntn)_[A-Za-z0-9]{16,}"#, "[REDACTED_API_KEY]"),
        // GitHub tokens
        (#"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}"#, "[REDACTED_API_KEY]"),
        (#"github_pat_[A-Za-z0-9_]{20,}"#, "[REDACTED_API_KEY]"),
        // Slack tokens & Slack/Discord webhooks
        (#"\bxox[baprs]-[A-Za-z0-9-]{12,}"#, "[REDACTED_API_KEY]"),
        (#"https://hooks\.slack\.com/services/[A-Za-z0-9/_-]+"#, "[REDACTED_WEBHOOK]"),
        (#"https://discord(?:app)?\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+"#, "[REDACTED_WEBHOOK]"),
        // Bearer tokens & generic key=value / secret=value assignments
        (#"Bearer\s+[A-Za-z0-9._~+/-]{8,}"#, "Bearer [REDACTED_TOKEN]"),
        (#"(?i)(api[_-]?key|secret|token|password)\s*[:=]\s*[^\s,;\"'&]{8,}"#, "$1=[REDACTED_API_KEY]"),
        // Payment card numbers
        (#"\b(?:\d[ -]*?){13,16}\b"#, "[REDACTED_CARD]")
    ]

    public static func redact(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        for entry in patternReplacements {
            if let regex = try? NSRegularExpression(pattern: entry.pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: entry.replacement)
            }
        }
        return result
    }

    public static func redactDictionary(_ dict: [String: String]) -> [String: String] {
        var clean: [String: String] = [:]
        clean.reserveCapacity(dict.count)
        for (key, value) in dict {
            let lowerKey = key.lowercased()
            if lowerKey.contains("api_key") || lowerKey.contains("apikey") || lowerKey.contains("secret") ||
               lowerKey.contains("password") || lowerKey.contains("authorization") || lowerKey.contains("bearer") ||
               lowerKey == "token" || lowerKey.hasSuffix("_token") {
                clean[key] = "[REDACTED_API_KEY]"
            } else {
                clean[key] = redact(value)
            }
        }
        return clean
    }
}

