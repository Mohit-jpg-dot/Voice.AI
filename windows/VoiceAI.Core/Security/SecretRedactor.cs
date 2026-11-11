using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace VoiceAI.Core.Security
{
    /// Centralized secret and PII redactor shared across chat history, logs, event payloads, and memory storage.
    public static class SecretRedactor
    {
        private static readonly (Regex Regex, string Replacement)[] Rules = new[]
        {
            (new Regex(@"sk-ant-[A-Za-z0-9_-]{12,}", RegexOptions.Compiled), "[REDACTED_API_KEY]"),
            (new Regex(@"sk-[A-Za-z0-9_-]{20,}", RegexOptions.Compiled), "[REDACTED_API_KEY]"),
            (new Regex(@"AIza[0-9A-Za-z_-]{20,}", RegexOptions.Compiled), "[REDACTED_API_KEY]"),
            (new Regex(@"\b(?:secret|ntn)_[A-Za-z0-9]{16,}", RegexOptions.Compiled), "[REDACTED_API_KEY]"),
            (new Regex(@"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}", RegexOptions.Compiled), "[REDACTED_API_KEY]"),
            (new Regex(@"github_pat_[A-Za-z0-9_]{20,}", RegexOptions.Compiled), "[REDACTED_API_KEY]"),
            (new Regex(@"\bxox[baprs]-[A-Za-z0-9-]{12,}", RegexOptions.Compiled), "[REDACTED_API_KEY]"),
            (new Regex(@"https://hooks\.slack\.com/services/[A-Za-z0-9/_-]+", RegexOptions.Compiled), "[REDACTED_WEBHOOK]"),
            (new Regex(@"https://discord(?:app)?\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+", RegexOptions.Compiled), "[REDACTED_WEBHOOK]"),
            (new Regex(@"Bearer\s+[A-Za-z0-9._~+/-]{8,}", RegexOptions.Compiled), "Bearer [REDACTED_TOKEN]"),
            (new Regex(@"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b", RegexOptions.Compiled), "[REDACTED_JWT]"),
            (new Regex(@"(?i)(api[_-]?key|secret|token|password)\s*[:=]\s*[^\s,;""'&]{8,}", RegexOptions.Compiled), "$1=[REDACTED_API_KEY]"),
            (new Regex(@"\b(?:\d[ -]*?){13,16}\b", RegexOptions.Compiled), "[REDACTED_CARD]")
        };

        public static string Redact(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            string current = text;
            foreach (var (regex, replacement) in Rules)
            {
                current = regex.Replace(current, replacement);
            }
            return current;
        }

        public static Dictionary<string, string> RedactDictionary(IReadOnlyDictionary<string, string> dict)
        {
            var result = new Dictionary<string, string>(dict.Count);
            foreach (var kv in dict)
            {
                string lower = kv.Key.ToLowerInvariant();
                if (lower.Contains("api_key") || lower.Contains("apikey") || lower.Contains("secret") ||
                    lower.Contains("password") || lower.Contains("authorization") || lower.Contains("bearer") ||
                    lower == "token" || lower.EndsWith("_token"))
                {
                    result[kv.Key] = "[REDACTED_API_KEY]";
                }
                else
                {
                    result[kv.Key] = Redact(kv.Value);
                }
            }
            return result;
        }
    }
}

