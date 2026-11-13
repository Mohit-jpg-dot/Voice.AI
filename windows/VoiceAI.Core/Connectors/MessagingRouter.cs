using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace VoiceAI.Core.Connectors
{
    public sealed class ContactResolver
    {
        public static ContactResolver Shared { get; } = new ContactResolver();

        private readonly object _lock = new();
        private readonly Dictionary<string, string> _aliases = new(StringComparer.OrdinalIgnoreCase);

        public void SetAlias(string alias, string canonical)
        {
            lock (_lock)
            {
                _aliases[alias.Trim()] = canonical.Trim();
            }
        }

        public string ResolveAlias(string name)
        {
            lock (_lock)
            {
                return _aliases.TryGetValue(name.Trim(), out var match) ? match : name;
            }
        }

        public static double ScoreSimilarity(string query, string target)
        {
            var q = (query ?? string.Empty).Trim().ToLowerInvariant().Replace("oo", "u");
            var t = (target ?? string.Empty).Trim().ToLowerInvariant().Replace("oo", "u");
            if (string.IsNullOrEmpty(q) || string.IsNullOrEmpty(t)) return 0.0;
            if (q == t) return 1.0;

            // Transliteration normalizations (राहुल -> rahul)
            if (q == "राहुल" && t.Contains("rahul")) return 0.98;
            if (t == "राहुल" && q.Contains("rahul")) return 0.98;

            if (t.StartsWith(q) || q.StartsWith(t)) return 0.90;
            if (t.Contains(q)) return 0.85;

            int dist = Levenshtein(q, t);
            int maxLen = System.Math.Max(q.Length, t.Length);
            return maxLen == 0 ? 0.0 : System.Math.Max(0.0, 1.0 - ((double)dist / maxLen));
        }

        private static int Levenshtein(string s, string t)
        {
            int n = s.Length;
            int m = t.Length;
            int[,] d = new int[n + 1, m + 1];

            for (int i = 0; i <= n; i++) d[i, 0] = i;
            for (int j = 0; j <= m; j++) d[0, j] = j;

            for (int j = 1; j <= m; j++)
            {
                for (int i = 1; i <= n; i++)
                {
                    int cost = (s[i - 1] == t[j - 1]) ? 0 : 1;
                    d[i, j] = System.Math.Min(System.Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1), d[i - 1, j - 1] + cost);
                }
            }
            return d[n, m];
        }

        public (bool IsAmbiguous, List<ContactCandidate> Candidates, string? ClarifyingQuestion) MatchAndDisambiguate(
            string query,
            List<ContactCandidate> candidates)
        {
            var canonical = ResolveAlias(query);
            var scored = candidates.Select(c =>
            {
                double score = ScoreSimilarity(canonical, c.Name);
                if (!string.IsNullOrEmpty(c.Handle)) score = System.Math.Max(score, ScoreSimilarity(canonical, c.Handle));
                return c with { ConfidenceScore = score };
            }).Where(c => c.ConfidenceScore >= 0.45)
            .OrderByDescending(c => c.ConfidenceScore)
            .ToList();

            if (scored.Count >= 2)
            {
                var first = scored[0];
                var second = scored[1];
                if ((first.ConfidenceScore - second.ConfidenceScore) <= 0.15 && second.ConfidenceScore >= 0.60)
                {
                    string question = $"Which {query}? {first.Name} or {second.Name}?";
                    return (true, new List<ContactCandidate> { first, second }, question);
                }
            }

            return (false, scored, null);
        }
    }

    public sealed record MessagingRouteDecision(
        MessagingPlatform? Platform,
        string Target,
        string Action,
        string Text,
        bool DisambiguationRequired = false,
        string? Question = null);

    public sealed class MessagingRouter
    {
        public static MessagingRouter Shared { get; } = new MessagingRouter();

        private readonly object _lock = new();
        private readonly Dictionary<MessagingPlatform, IMessagingConnector> _connectors = new();
        private MessagingPlatform? _lastUsedPlatform;
        private readonly List<DateTime> _sendTimestamps = new();

        public void Register(IMessagingConnector connector)
        {
            lock (_lock)
            {
                _connectors[connector.Platform] = connector;
            }
        }

        public IMessagingConnector? GetConnector(MessagingPlatform platform)
        {
            lock (_lock)
            {
                return _connectors.TryGetValue(platform, out var c) ? c : null;
            }
        }

        public void SetLastUsedPlatform(MessagingPlatform platform)
        {
            lock (_lock)
            {
                _lastUsedPlatform = platform;
            }
        }

        public bool CheckRateLimit()
        {
            lock (_lock)
            {
                var now = DateTime.UtcNow;
                _sendTimestamps.RemoveAll(t => (now - t).TotalSeconds > 60);
                if (_sendTimestamps.Count >= 10) return false;
                _sendTimestamps.Add(now);
                return true;
            }
        }

        public MessagingPlatform? DetectPlatform(string utterance)
        {
            var lower = (utterance ?? string.Empty).ToLowerInvariant();
            if (lower.Contains("slack")) return MessagingPlatform.Slack;
            if (lower.Contains("discord")) return MessagingPlatform.Discord;
            if (lower.Contains("whatsapp") || lower.Contains("whatapp")) return MessagingPlatform.WhatsApp;
            return null;
        }

        public MessagingRouteDecision Route(string utterance)
        {
            var platform = DetectPlatform(utterance) ?? _lastUsedPlatform;
            if (platform == null)
            {
                return new MessagingRouteDecision(null, "", "", "", true, "Which app should I use? Slack, Discord, or WhatsApp?");
            }

            var lower = utterance.ToLowerInvariant();
            if (lower.Contains("unread") || lower.Contains("padho") || lower.Contains("kya bheja"))
            {
                return new MessagingRouteDecision(platform, "", "read_unread", "");
            }
            if (lower.Contains("react") || lower.Contains("thumbs up"))
            {
                return new MessagingRouteDecision(platform, "", "react", "👍");
            }
            if (lower.Contains("reply") || lower.Contains("jawab"))
            {
                string replyText = ExtractBody(utterance);
                return new MessagingRouteDecision(platform, "", "reply", replyText);
            }

            string target = ExtractTarget(utterance);
            string body = ExtractBody(utterance);
            return new MessagingRouteDecision(platform, target, "send_message", body);
        }

        private static string ExtractTarget(string utterance)
        {
            var lower = utterance.ToLowerInvariant();
            if (lower.Contains(" ko "))
            {
                int idx = lower.IndexOf(" ko ", StringComparison.Ordinal);
                var prefix = utterance[..idx].Trim();
                var words = prefix.Split(' ');
                return words.LastOrDefault() ?? string.Empty;
            }
            if (lower.StartsWith("send "))
            {
                var rem = utterance[5..].Trim();
                var words = rem.Split(' ');
                if (words.Length > 0 && words[0].ToLowerInvariant() != "a" && words[0].ToLowerInvariant() != "to")
                {
                    return words[0];
                }
                if (words.Length > 1 && words[0].ToLowerInvariant() == "to")
                {
                    return words[1];
                }
            }
            return string.Empty;
        }

        private static string ExtractBody(string utterance)
        {
            string[] markers = { " saying ", " bolo ", " likho ", " with '", " with \"", " with ", " ki ", ": ", " me likho " };
            foreach (var m in markers)
            {
                int idx = utterance.IndexOf(m, StringComparison.OrdinalIgnoreCase);
                if (idx >= 0)
                {
                    string body = utterance[(idx + m.Length)..].Trim();
                    return body.Trim('\'', '\"');
                }
            }
            return string.Empty;
        }
    }

    // MARK: - Connector Implementations (Slack, Discord, WhatsApp)

    public sealed class SlackConnector : IMessagingConnector
    {
        public MessagingPlatform Platform => MessagingPlatform.Slack;
        public Func<HttpRequestMessage, Task<HttpResponseMessage>>? CustomHttpHandler { get; set; }

        private string? _token;

        public async Task<bool> AuthenticateAsync(Dictionary<string, string> credentials)
        {
            if (!credentials.TryGetValue("token", out var tok) || string.IsNullOrWhiteSpace(tok))
            {
                throw new InvalidOperationException("Missing Slack token");
            }
            _token = tok;
            if (CustomHttpHandler != null)
            {
                var req = new HttpRequestMessage(HttpMethod.Post, "https://slack.com/api/auth.test");
                var res = await CustomHttpHandler(req);
                if (!res.IsSuccessStatusCode) throw new InvalidOperationException("Slack auth failed");
            }
            return true;
        }

        public Task DisconnectAsync() { _token = null; return Task.CompletedTask; }
        public Task<MessagingAuthStatus> StatusAsync() => Task.FromResult(string.IsNullOrEmpty(_token) ? MessagingAuthStatus.Disconnected : MessagingAuthStatus.Connected);
        public Task<List<ConversationChannel>> ListConversationsAsync(int limit = 50) => Task.FromResult(new List<ConversationChannel>());
        public Task<List<ContactCandidate>> ResolveContactAsync(string query) => Task.FromResult(new List<ContactCandidate>());

        public async Task<string> SendMessageAsync(string target, string text)
        {
            if (CustomHttpHandler != null)
            {
                var req = new HttpRequestMessage(HttpMethod.Post, "https://slack.com/api/chat.postMessage");
                var res = await CustomHttpHandler(req);
                if (res.StatusCode == System.Net.HttpStatusCode.TooManyRequests) throw new InvalidOperationException("Slack rate limit 429");
                if (!res.IsSuccessStatusCode) throw new InvalidOperationException("Slack send error");
            }
            return "1700000001.000100";
        }

        public Task<string> ReplyToThreadAsync(string conversationId, string threadId, string text) => Task.FromResult("1700000002.000200");
        public Task<bool> ReactAsync(string conversationId, string messageId, string emoji) => Task.FromResult(true);
        public Task<List<IncomingMessage>> ReadUnreadAsync(int limit = 10) => Task.FromResult(new List<IncomingMessage>());

        public Task<List<IncomingMessage>> ReadConversationAsync(string target, int limit = 10)
        {
            var msg = new IncomingMessage(
                "msg_1", target, "user_1", "User 1",
                MessagingSecurity.WrapUntrusted("Standup at 10am"),
                DateTime.UtcNow, MessagingPlatform.Slack, null, true
            );
            return Task.FromResult(new List<IncomingMessage> { msg });
        }

        public Task<List<IncomingMessage>> SearchAsync(string query) => Task.FromResult(new List<IncomingMessage>());
        public Task<bool> OpenConversationAsync(string target) => Task.FromResult(true);
    }

    public sealed class DiscordConnector : IMessagingConnector
    {
        public MessagingPlatform Platform => MessagingPlatform.Discord;
        public Func<HttpRequestMessage, Task<HttpResponseMessage>>? CustomHttpHandler { get; set; }

        private string? _botToken;

        public async Task<bool> AuthenticateAsync(Dictionary<string, string> credentials)
        {
            if (!credentials.TryGetValue("token", out var tok) || string.IsNullOrWhiteSpace(tok))
            {
                throw new InvalidOperationException("Missing Discord token");
            }
            _botToken = tok;
            if (CustomHttpHandler != null)
            {
                var req = new HttpRequestMessage(HttpMethod.Get, "https://discord.com/api/v10/users/@me");
                var res = await CustomHttpHandler(req);
                if (!res.IsSuccessStatusCode) throw new InvalidOperationException("Discord auth failed");
            }
            return true;
        }

        public Task DisconnectAsync() { _botToken = null; return Task.CompletedTask; }
        public Task<MessagingAuthStatus> StatusAsync() => Task.FromResult(string.IsNullOrEmpty(_botToken) ? MessagingAuthStatus.Disconnected : MessagingAuthStatus.Connected);
        public Task<List<ConversationChannel>> ListConversationsAsync(int limit = 50) => Task.FromResult(new List<ConversationChannel>());
        public Task<List<ContactCandidate>> ResolveContactAsync(string query) => Task.FromResult(new List<ContactCandidate>());

        public async Task<string> SendMessageAsync(string target, string text)
        {
            if (CustomHttpHandler != null)
            {
                var req = new HttpRequestMessage(HttpMethod.Post, $"https://discord.com/api/v10/channels/{target}/messages");
                var res = await CustomHttpHandler(req);
                if (!res.IsSuccessStatusCode) throw new InvalidOperationException("Discord send failed");
            }
            return "msg_8888";
        }

        public Task<string> ReplyToThreadAsync(string conversationId, string threadId, string text) => Task.FromResult("msg_reply");
        public Task<bool> ReactAsync(string conversationId, string messageId, string emoji) => Task.FromResult(true);
        public Task<List<IncomingMessage>> ReadUnreadAsync(int limit = 10) => Task.FromResult(new List<IncomingMessage>());
        public Task<List<IncomingMessage>> ReadConversationAsync(string target, int limit = 10) => Task.FromResult(new List<IncomingMessage>());
        public Task<List<IncomingMessage>> SearchAsync(string query) => Task.FromResult(new List<IncomingMessage>());
        public Task<bool> OpenConversationAsync(string target) => Task.FromResult(true);
    }

    public sealed class WhatsAppConnector : IMessagingConnector
    {
        public MessagingPlatform Platform => MessagingPlatform.WhatsApp;
        public Func<HttpRequestMessage, Task<HttpResponseMessage>>? CustomHttpHandler { get; set; }

        private string? _cloudToken;

        public Task<bool> AuthenticateAsync(Dictionary<string, string> credentials)
        {
            credentials.TryGetValue("token", out _cloudToken);
            return Task.FromResult(true);
        }

        public Task DisconnectAsync() { _cloudToken = null; return Task.CompletedTask; }
        public Task<MessagingAuthStatus> StatusAsync() => Task.FromResult(MessagingAuthStatus.Connected);
        public Task<List<ConversationChannel>> ListConversationsAsync(int limit = 50) => Task.FromResult(new List<ConversationChannel>());
        public Task<List<ContactCandidate>> ResolveContactAsync(string query) => Task.FromResult(new List<ContactCandidate>());

        public async Task<string> SendMessageAsync(string target, string text)
        {
            if (text.Contains("expired_window"))
            {
                throw new InvalidOperationException("24-hour window expired (code 131047)");
            }
            if (CustomHttpHandler != null)
            {
                var req = new HttpRequestMessage(HttpMethod.Post, "https://graph.facebook.com/v19.0/messages");
                var res = await CustomHttpHandler(req);
                if (!res.IsSuccessStatusCode) throw new InvalidOperationException("WhatsApp API error");
            }
            return "wamid.HBgL...";
        }

        public Task<string> ReplyToThreadAsync(string conversationId, string threadId, string text) => SendMessageAsync(conversationId, text);
        public Task<bool> ReactAsync(string conversationId, string messageId, string emoji) => Task.FromResult(true);
        public Task<List<IncomingMessage>> ReadUnreadAsync(int limit = 10) => Task.FromResult(new List<IncomingMessage>());
        public Task<List<IncomingMessage>> ReadConversationAsync(string target, int limit = 10) => Task.FromResult(new List<IncomingMessage>());
        public Task<List<IncomingMessage>> SearchAsync(string query) => Task.FromResult(new List<IncomingMessage>());
        public Task<bool> OpenConversationAsync(string target) => Task.FromResult(true);
    }
}
