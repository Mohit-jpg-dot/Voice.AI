using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace VoiceAI.Core.Connectors
{
    public enum MessagingPlatform
    {
        Slack,
        Discord,
        WhatsApp
    }

    public enum MessagingAuthStatus
    {
        Disconnected,
        Connecting,
        Connected,
        Error
    }

    public enum ConversationType
    {
        DirectMessage,
        Channel,
        GroupDM,
        Thread
    }

    public sealed record ConversationChannel(
        string Id,
        string Name,
        ConversationType Type,
        int UnreadCount,
        MessagingPlatform Platform,
        string? Topic = null,
        bool IsPrivate = false);

    public sealed record ContactCandidate(
        string Id,
        string Name,
        MessagingPlatform Platform,
        string? Handle = null,
        string? PhoneNumber = null,
        double ConfidenceScore = 1.0,
        List<string>? Aliases = null);

    public sealed record IncomingMessage(
        string Id,
        string ConversationId,
        string SenderId,
        string SenderName,
        string Text,
        DateTime Timestamp,
        MessagingPlatform Platform,
        string? ThreadId = null,
        bool IsUnread = false);

    public static class MessagingSecurity
    {
        private static readonly string[] HostileMarkers =
        {
            "ignore previous instructions",
            "ignore all previous instructions",
            "system prompt",
            "forward all chats",
            "forward chats",
            "send all messages",
            "exfiltrate",
            "<script",
            "javascript:",
            "api_key",
            "bearer "
        };

        public static string SanitizeIncomingContent(string text)
        {
            if (string.IsNullOrEmpty(text)) return string.Empty;
            string clean = text;
            foreach (var marker in HostileMarkers)
            {
                clean = Regex.Replace(clean, Regex.Escape(marker), "[REDACTED_PROMPT_INJECTION]", RegexOptions.IgnoreCase);
            }
            return clean;
        }

        public static string WrapUntrusted(string text)
        {
            string safe = SanitizeIncomingContent(text);
            return $"<UNTRUSTED_MESSAGE_DATA>\n{safe}\n</UNTRUSTED_MESSAGE_DATA>";
        }
    }

    public interface IMessagingConnector
    {
        MessagingPlatform Platform { get; }
        Task<bool> AuthenticateAsync(Dictionary<string, string> credentials);
        Task DisconnectAsync();
        Task<MessagingAuthStatus> StatusAsync();
        Task<List<ConversationChannel>> ListConversationsAsync(int limit = 50);
        Task<List<ContactCandidate>> ResolveContactAsync(string query);
        Task<string> SendMessageAsync(string target, string text);
        Task<string> ReplyToThreadAsync(string conversationId, string threadId, string text);
        Task<bool> ReactAsync(string conversationId, string messageId, string emoji);
        Task<List<IncomingMessage>> ReadUnreadAsync(int limit = 10);
        Task<List<IncomingMessage>> ReadConversationAsync(string target, int limit = 10);
        Task<List<IncomingMessage>> SearchAsync(string query);
        Task<bool> OpenConversationAsync(string target);
    }
}

