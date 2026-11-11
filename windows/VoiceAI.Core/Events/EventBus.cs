using System;
using System.Collections.Generic;
using VoiceAI.Core.Security;

namespace VoiceAI.Core.Events
{
    public enum VoiceEventSeverity
    {
        Info,
        Notice,
        Warning,
        Critical
    }

    public enum SystemEventKind
    {
        BatteryChanged,
        CpuMemoryPressure,
        CalendarUpcoming,
        BuildStatusChanged,
        ToolInvoked,
        ApprovalRequested,
        ApprovalResolved,
        MemoryUpdated,
        Custom
    }

    public sealed record VoiceEvent(
        Guid Id,
        SystemEventKind Kind,
        string CustomKind,
        string Source,
        DateTime TimestampUtc,
        VoiceEventSeverity Severity,
        IReadOnlyDictionary<string, string> Payload
    )
    {
        public static VoiceEvent Create(
            SystemEventKind kind,
            string source,
            IReadOnlyDictionary<string, string>? payload = null,
            VoiceEventSeverity severity = VoiceEventSeverity.Info,
            string customKind = "")
        {
            var safePayload = payload != null
                ? SecretRedactor.RedactDictionary(payload)
                : new Dictionary<string, string>();
            return new VoiceEvent(Guid.NewGuid(), kind, customKind, source, DateTime.UtcNow, severity, safePayload);
        }
    }

    public interface IEventBus
    {
        void Publish(VoiceEvent evt);
        Guid Subscribe(SystemEventKind? filter, Action<VoiceEvent> handler);
        void Unsubscribe(Guid subscriptionId);
        IReadOnlyList<VoiceEvent> RecentEvents(int limit = 50);
    }

    /// <summary>
    /// Thread-safe cross-platform event bus for proactive monitors, tool lifecycle, and safety approvals.
    /// </summary>
    public sealed class EventBus : IEventBus
    {
        public static EventBus Shared { get; } = new EventBus();

        private sealed record Subscription(Guid Id, SystemEventKind? Filter, Action<VoiceEvent> Handler);

        private readonly object _lock = new();
        private readonly Dictionary<Guid, Subscription> _subscriptions = new();
        private readonly List<VoiceEvent> _history = new();
        private const int MaxHistoryCapacity = 200;

        public void Publish(VoiceEvent evt)
        {
            List<Action<VoiceEvent>> matched = new();
            lock (_lock)
            {
                _history.Add(evt);
                if (_history.Count > MaxHistoryCapacity)
                {
                    _history.RemoveRange(0, _history.Count - MaxHistoryCapacity);
                }
                foreach (var sub in _subscriptions.Values)
                {
                    if (sub.Filter == null || sub.Filter == evt.Kind)
                    {
                        matched.Add(sub.Handler);
                    }
                }
            }

            foreach (var handler in matched)
            {
                handler(evt);
            }
        }

        public Guid Subscribe(SystemEventKind? filter, Action<VoiceEvent> handler)
        {
            var id = Guid.NewGuid();
            lock (_lock)
            {
                _subscriptions[id] = new Subscription(id, filter, handler);
            }
            return id;
        }

        public void Unsubscribe(Guid subscriptionId)
        {
            lock (_lock)
            {
                _subscriptions.Remove(subscriptionId);
            }
        }

        public IReadOnlyList<VoiceEvent> RecentEvents(int limit = 50)
        {
            if (limit <= 0) return Array.Empty<VoiceEvent>();
            lock (_lock)
            {
                int skip = System.Math.Max(0, _history.Count - limit);
                return _history.GetRange(skip, _history.Count - skip);
            }
        }
    }
}

