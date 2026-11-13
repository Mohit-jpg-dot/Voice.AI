using System;
using System.Collections.Generic;
using System.Linq;

namespace VoiceAI.Core.Connectors
{
    public enum EmailCapabilityStatus
    {
        CanSendAndRead,
        CanSendOnly,
        CanOnlyDraft,
        CannotSend
    }

    public static class EmailAddressHelper
    {
        private static readonly Dictionary<string, string> DigitWords = new(StringComparer.OrdinalIgnoreCase)
        {
            ["zero"] = "0", ["oh"] = "0",
            ["one"] = "1", ["two"] = "2", ["three"] = "3", ["four"] = "4",
            ["five"] = "5", ["six"] = "6", ["seven"] = "7", ["eight"] = "8", ["nine"] = "9"
        };

        public static string? NormalizeSpokenAddress(string raw)
        {
            var trimmed = (raw ?? string.Empty).Trim();
            if (string.IsNullOrEmpty(trimmed)) return null;

            if (!trimmed.Contains(' ') && trimmed.Contains('@'))
            {
                var lowered = trimmed.ToLowerInvariant();
                return IsValidEmail(lowered) ? lowered : null;
            }

            var tokens = trimmed.ToLowerInvariant()
                .Replace(",", " ")
                .Split(new[] { ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);

            var parts = new List<string>();
            for (int i = 0; i < tokens.Length; i++)
            {
                var tok = tokens[i];
                if (tok == "at" || tok == "attherate")
                {
                    if (i + 2 < tokens.Length && tokens[i + 1] == "the" && tokens[i + 2] == "rate")
                    {
                        parts.Add("@");
                        i += 2;
                        continue;
                    }
                    parts.Add("@");
                }
                else if (tok == "dot" || tok == "period" || tok == "point")
                {
                    parts.Add(".");
                }
                else if (tok == "underscore" || tok == "under_score")
                {
                    parts.Add("_");
                }
                else if (tok == "dash" || tok == "hyphen" || tok == "minus")
                {
                    parts.Add("-");
                }
                else if (tok == "plus")
                {
                    parts.Add("+");
                }
                else if (DigitWords.TryGetValue(tok, out var digit))
                {
                    parts.Add(digit);
                }
                else
                {
                    parts.Add(tok);
                }
            }

            var joined = string.Concat(parts).Trim('.', ',', ';', ':', '!', '?', '\'', '"', '<', '>', '(', ')');
            return IsValidEmail(joined) ? joined : null;
        }

        public static bool IsValidEmail(string email)
        {
            var trimmed = (email ?? string.Empty).Trim();
            if (string.IsNullOrEmpty(trimmed) || trimmed.Contains(' ')) return false;
            var parts = trimmed.Split('@');
            if (parts.Length != 2) return false;
            var local = parts[0];
            var domain = parts[1];
            if (string.IsNullOrEmpty(local) || local.StartsWith('.') || local.EndsWith('.') || local.Contains("..")) return false;
            if (!domain.Contains('.') || domain.StartsWith('.') || domain.EndsWith('.') || domain.Contains("..")) return false;
            var tld = domain.Split('.').Last();
            if (tld.Length < 2) return false;

            const string localChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-";
            const string domainChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-";
            return local.All(c => localChars.Contains(c)) && domain.All(c => domainChars.Contains(c));
        }

        public static string CanonicalAddress(string email)
        {
            var lower = (email ?? string.Empty).Trim().ToLowerInvariant();
            var parts = lower.Split('@', 2);
            if (parts.Length != 2) return lower;
            var local = parts[0];
            var domain = parts[1];
            if (domain == "gmail.com" || domain == "googlemail.com")
            {
                var plusIdx = local.IndexOf('+');
                if (plusIdx >= 0) local = local.Substring(0, plusIdx);
            }
            return $"{local}@{domain}";
        }

        public static int LevenshteinDistance(string a, string b)
        {
            var s1 = a.ToLowerInvariant();
            var s2 = b.ToLowerInvariant();
            if (s1.Length == 0) return s2.Length;
            if (s2.Length == 0) return s1.Length;
            var prev = Enumerable.Range(0, s2.Length + 1).ToArray();
            for (int i = 1; i <= s1.Length; i++)
            {
                var curr = new int[s2.Length + 1];
                curr[0] = i;
                for (int j = 1; j <= s2.Length; j++)
                {
                    var cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
                    curr[j] = global::System.Math.Min(global::System.Math.Min(prev[j] + 1, curr[j - 1] + 1), prev[j - 1] + cost);
                }
                prev = curr;
            }
            return prev[s2.Length];
        }
    }

    public sealed class EmailDraftModel
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public List<string> To { get; set; } = new();
        public List<string> Cc { get; set; } = new();
        public List<string> Bcc { get; set; } = new();
        public string Subject { get; set; } = string.Empty;
        public string Body { get; set; } = string.Empty;
        public string? ThreadId { get; set; }
        public string? InReplyToHeader { get; set; }
        public string? ReferencesHeader { get; set; }
        public bool IsReplyAll { get; set; }
        public bool IsForward { get; set; }
        public bool RequiresConsequentialApproval => true;
    }

    public enum WatchRuleType
    {
        Thread,
        Sender
    }

    public sealed class WatchRuleModel
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public WatchRuleType Type { get; set; }
        public string? ThreadId { get; set; }
        public string? NormalizedSenderAddress { get; set; }
        public bool IsActive { get; set; } = true;

        public bool Matches(string fromAddress, string messageThreadId, bool isFromMe)
        {
            if (!IsActive || isFromMe) return false;
            return Type switch
            {
                WatchRuleType.Thread => !string.IsNullOrEmpty(ThreadId) && messageThreadId == ThreadId,
                WatchRuleType.Sender => !string.IsNullOrEmpty(NormalizedSenderAddress) &&
                    EmailAddressHelper.CanonicalAddress(fromAddress) == EmailAddressHelper.CanonicalAddress(NormalizedSenderAddress),
                _ => false
            };
        }
    }
}
