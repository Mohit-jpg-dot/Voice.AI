using System;
using System.Collections.Generic;
using VoiceAI.Core.Events;

namespace VoiceAI.Core.Companion
{
    public sealed record PairedPhone(string Id, string Name);

    public interface IPhoneCompanionCoordinator
    {
        string BeginPairing();
        (PairedPhone? Device, string? Token) CompletePairing(string name, string pin);
        bool Authenticate(string deviceId, string token);
        void EnqueueApproval(string id, string title, Action<bool> resolver);
        bool RespondToApproval(string id, string deviceId, string token, bool approved);
    }

    /// <summary>
    /// PIN pairing, bearer-token authentication, and remote approval bridge for the Windows Phone Companion.
    /// </summary>
    public sealed class PhoneCompanionCoordinator : IPhoneCompanionCoordinator
    {
        public static PhoneCompanionCoordinator Shared { get; } = new PhoneCompanionCoordinator();

        private readonly object _lock = new();
        private string? _pendingPin;
        private readonly Dictionary<string, string> _tokens = new();
        private readonly Dictionary<string, Action<bool>> _approvals = new();

        public string BeginPairing()
        {
            string pin = Random.Shared.Next(100000, 999999).ToString();
            lock (_lock) _pendingPin = pin;
            return pin;
        }

        public (PairedPhone? Device, string? Token) CompletePairing(string name, string pin)
        {
            lock (_lock)
            {
                if (_pendingPin == null || _pendingPin != pin || string.IsNullOrWhiteSpace(name))
                    return (null, null);
                _pendingPin = null;
                var dev = new PairedPhone(Guid.NewGuid().ToString(), name.Trim());
                string tok = "comp_" + Guid.NewGuid().ToString("N");
                _tokens[dev.Id] = tok;
                return (dev, tok);
            }
        }

        public bool Authenticate(string deviceId, string token)
        {
            lock (_lock)
            {
                return _tokens.TryGetValue(deviceId, out var expected) && expected == token;
            }
        }

        public void EnqueueApproval(string id, string title, Action<bool> resolver)
        {
            lock (_lock) _approvals[id] = resolver;
            EventBus.Shared.Publish(VoiceEvent.Create(
                SystemEventKind.ApprovalRequested,
                "PhoneCompanionCoordinator",
                new Dictionary<string, string> { ["request_id"] = id, ["title"] = title },
                VoiceEventSeverity.Notice));
        }

        public bool RespondToApproval(string id, string deviceId, string token, bool approved)
        {
            if (!Authenticate(deviceId, token)) return false;
            Action<bool>? cb;
            lock (_lock)
            {
                if (!_approvals.Remove(id, out cb)) return false;
            }
            cb(approved);
            return true;
        }
    }
}

