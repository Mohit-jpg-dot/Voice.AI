using System;
using System.Collections.Generic;

namespace VoiceAI.Core.Platform
{
    public enum IntegrationConnectionStatus
    {
        NotConnected,
        Connecting,
        Connected,
        NeedsAttention,
        ComingSoon
    }

    public enum StepStatus
    {
        Pending,
        InProgress,
        Done,
        NeedsAttention
    }

    public sealed class IntegrationScope
    {
        public string Name { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;

        public IntegrationScope(string name, string reason)
        {
            Name = name;
            Reason = reason;
        }
    }

    public sealed class SetupDescriptor
    {
        public string Id { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public List<string> Features { get; set; } = new();
        public List<IntegrationScope> Scopes { get; set; } = new();
        public List<string> ConnectionMethods { get; set; } = new();
        public IntegrationConnectionStatus Status { get; set; } = IntegrationConnectionStatus.NotConnected;

        public SetupDescriptor(string id, string name, string category, List<string> features, List<IntegrationScope> scopes, List<string> methods, IntegrationConnectionStatus status = IntegrationConnectionStatus.NotConnected)
        {
            Id = id;
            Name = name;
            Category = category;
            Features = features;
            Scopes = scopes;
            ConnectionMethods = methods;
            Status = status;
        }
    }

    public static class IntegrationSetupRegistry
    {
        public static List<SetupDescriptor> GetAllDescriptors()
        {
            return new List<SetupDescriptor>
            {
                new SetupDescriptor(
                    "mail", "Email (Gmail & Apple Mail)", "Productivity",
                    new List<string> { "Draft inside Notch Pill", "Voice dictation", "Background draft sync" },
                    new List<IntegrationScope> { new IntegrationScope("gmail.compose", "Draft and send emails") },
                    new List<string> { "Mail.app", "Google OAuth PKCE" },
                    IntegrationConnectionStatus.Connected
                ),
                new SetupDescriptor(
                    "slack", "Slack", "Messaging",
                    new List<string> { "Send channel messages", "Direct messages", "Thread replies" },
                    new List<IntegrationScope> { new IntegrationScope("chat:write", "Post to Slack") },
                    new List<string> { "Slack OAuth v2", "Incoming Webhook" },
                    IntegrationConnectionStatus.Connected
                ),
                new SetupDescriptor(
                    "discord", "Discord", "Messaging",
                    new List<string> { "Post to servers", "Thread replies" },
                    new List<IntegrationScope> { new IntegrationScope("Bot Token", "Official Discord bot") },
                    new List<string> { "Discord Bot Token" },
                    IntegrationConnectionStatus.Connected
                ),
                new SetupDescriptor(
                    "whatsapp", "WhatsApp", "Messaging",
                    new List<string> { "Send voice-drafted WhatsApp messages" },
                    new List<IntegrationScope> { new IntegrationScope("Accessibility", "Drive desktop app safely") },
                    new List<string> { "WhatsApp Desktop", "WhatsApp Business Cloud API" },
                    IntegrationConnectionStatus.Connected
                )
            };
        }
    }
}

