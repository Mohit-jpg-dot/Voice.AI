using System;
using System.Collections.Generic;
using System.Linq;
using VoiceAI.Core.Events;
using VoiceAI.Core.Security;

namespace VoiceAI.Core.Proactive
{
    public enum ProactiveRuleKind
    {
        LowBattery,
        HighCpuMemory,
        FailedBuild,
        CalendarConflict,
        ImportantEmail
    }

    public sealed record ProactiveRuleConfig(
        string Id,
        ProactiveRuleKind Kind,
        string Title,
        bool IsEnabled,
        double Threshold,
        double CooldownSeconds);

    public sealed record ProactiveAlert(
        string Id,
        string RuleId,
        ProactiveRuleKind Kind,
        string Title,
        string Message,
        VoiceEventSeverity Severity,
        string? SuggestedPrompt,
        DateTimeOffset CreatedAt,
        bool IsDismissed = false);

    public interface IProactiveRuleEngine
    {
        IReadOnlyList<ProactiveRuleConfig> AllRules();
        void UpdateRule(ProactiveRuleConfig rule);
        void SetRuleEnabled(string id, bool enabled);
        IReadOnlyList<ProactiveAlert> ActiveAlerts(bool includeDismissed = false);
        void DismissAlert(string id);
        ProactiveAlert? EvaluateEvent(VoiceEvent ev);
    }

    /// <summary>
    /// Rate-limited, user-configurable EventBus rules engine raising proactive alerts for
    /// low battery, high CPU/memory pressure, failed builds, calendar conflicts, and VIP emails.
    /// </summary>
    public sealed class ProactiveRulesEngine : IProactiveRuleEngine
    {
        public static ProactiveRulesEngine Shared { get; } = new ProactiveRulesEngine(EventBus.Shared);

        private readonly object _lock = new();
        private readonly EventBus _eventBus;
        private readonly Func<DateTimeOffset> _nowProvider;
        private readonly List<ProactiveRuleConfig> _rules;
        private readonly List<ProactiveAlert> _alerts = new();
        private readonly Dictionary<string, DateTimeOffset> _lastFiredAt = new();

        public ProactiveRulesEngine(EventBus eventBus, Func<DateTimeOffset>? nowProvider = null)
        {
            _eventBus = eventBus;
            _nowProvider = nowProvider ?? (() => DateTimeOffset.UtcNow);
            _rules = new List<ProactiveRuleConfig>
            {
                new("rule_low_battery", ProactiveRuleKind.LowBattery, "Low Battery Alert (< 20%)", true, 20, 600),
                new("rule_high_cpu_memory", ProactiveRuleKind.HighCpuMemory, "High CPU / Memory Load (> 85%)", true, 85, 300),
                new("rule_failed_build", ProactiveRuleKind.FailedBuild, "Failed Build Notification", true, 1, 120),
                new("rule_calendar_conflict", ProactiveRuleKind.CalendarConflict, "Calendar Conflict Warning", true, 15, 600),
                new("rule_important_email", ProactiveRuleKind.ImportantEmail, "Important Email Alert", true, 1, 300)
            };
        }

        public IReadOnlyList<ProactiveRuleConfig> AllRules()
        {
            lock (_lock) return _rules.ToList();
        }

        public void UpdateRule(ProactiveRuleConfig rule)
        {
            lock (_lock)
            {
                int idx = _rules.FindIndex(r => r.Id == rule.Id);
                if (idx >= 0) _rules[idx] = rule;
                else _rules.Add(rule);
            }
        }

        public void SetRuleEnabled(string id, bool enabled)
        {
            lock (_lock)
            {
                int idx = _rules.FindIndex(r => r.Id == id);
                if (idx >= 0) _rules[idx] = _rules[idx] with { IsEnabled = enabled };
            }
        }

        public IReadOnlyList<ProactiveAlert> ActiveAlerts(bool includeDismissed = false)
        {
            lock (_lock)
            {
                return includeDismissed ? _alerts.ToList() : _alerts.Where(a => !a.IsDismissed).ToList();
            }
        }

        public void DismissAlert(string id)
        {
            lock (_lock)
            {
                int idx = _alerts.FindIndex(a => a.Id == id);
                if (idx >= 0) _alerts[idx] = _alerts[idx] with { IsDismissed = true };
            }
        }

        public ProactiveAlert? EvaluateEvent(VoiceEvent ev)
        {
            var candidate = BuildCandidate(ev);
            if (candidate == null) return null;

            var now = _nowProvider();
            lock (_lock)
            {
                var rule = _rules.FirstOrDefault(r => r.Id == candidate.RuleId && r.IsEnabled);
                if (rule == null) return null;

                if (_lastFiredAt.TryGetValue(rule.Id, out var last) &&
                    (now - last).TotalSeconds < rule.CooldownSeconds)
                {
                    return null;
                }

                _lastFiredAt[rule.Id] = now;
                _alerts.Insert(0, candidate);
                if (_alerts.Count > 50) _alerts.RemoveRange(50, _alerts.Count - 50);
            }

            _eventBus.Publish(VoiceEvent.Create(
                SystemEventKind.Custom,
                "ProactiveRulesEngine",
                new Dictionary<string, string>
                {
                    ["event"] = "proactive_alert_raised",
                    ["rule_id"] = candidate.RuleId,
                    ["title"] = candidate.Title
                },
                candidate.Severity));

            return candidate;
        }

        private ProactiveAlert? BuildCandidate(VoiceEvent ev)
        {
            var now = _nowProvider();
            List<ProactiveRuleConfig> activeRules;
            lock (_lock) activeRules = _rules.ToList();

            if (ev.Kind == SystemEventKind.BatteryChanged)
            {
                var rule = activeRules.FirstOrDefault(r => r.Kind == ProactiveRuleKind.LowBattery && r.IsEnabled);
                if (rule == null) return null;
                ev.Payload.TryGetValue("level", out var raw);
                ev.Payload.TryGetValue("charging", out var charging);
                if (string.Equals(charging, "true", StringComparison.OrdinalIgnoreCase)) return null;
                if (double.TryParse((raw ?? "").Replace("%", "").Trim(), out double pct) && pct <= rule.Threshold)
                {
                    return new ProactiveAlert(Guid.NewGuid().ToString(), rule.Id, ProactiveRuleKind.LowBattery,
                        $"Battery at {(int)pct}%", $"Low power ({(int)pct}%). Connect charger.",
                        VoiceEventSeverity.Warning, "Check battery status", now);
                }
            }
            else if (ev.Kind == SystemEventKind.CpuMemoryPressure)
            {
                var rule = activeRules.FirstOrDefault(r => r.Kind == ProactiveRuleKind.HighCpuMemory && r.IsEnabled);
                if (rule == null) return null;
                ev.Payload.TryGetValue("cpu", out var cpuRaw);
                ev.Payload.TryGetValue("memory", out var memRaw);
                double.TryParse((cpuRaw ?? "0").Replace("%", ""), out double cpu);
                double.TryParse((memRaw ?? "0").Replace("%", ""), out double mem);
                double peak = System.Math.Max(cpu, mem);
                if (peak >= rule.Threshold)
                {
                    return new ProactiveAlert(Guid.NewGuid().ToString(), rule.Id, ProactiveRuleKind.HighCpuMemory,
                        $"High Resource Load ({(int)peak}%)", $"CPU/RAM usage reached {(int)peak}%.",
                        VoiceEventSeverity.Warning, "Show top processes", now);
                }
            }
            else if (ev.Kind == SystemEventKind.BuildStatusChanged)
            {
                var rule = activeRules.FirstOrDefault(r => r.Kind == ProactiveRuleKind.FailedBuild && r.IsEnabled);
                if (rule == null) return null;
                ev.Payload.TryGetValue("status", out var status);
                if (string.Equals(status, "failed", StringComparison.OrdinalIgnoreCase))
                {
                    ev.Payload.TryGetValue("project", out var proj);
                    ev.Payload.TryGetValue("error", out var err);
                    return new ProactiveAlert(Guid.NewGuid().ToString(), rule.Id, ProactiveRuleKind.FailedBuild,
                        SecretRedactor.Redact($"Build Failed: {proj ?? ev.Source}"),
                        SecretRedactor.Redact(err ?? "Inspect build logs."),
                        VoiceEventSeverity.Warning, "Explain build failure", now);
                }
            }
            else if (ev.Kind == SystemEventKind.CalendarUpcoming)
            {
                var rule = activeRules.FirstOrDefault(r => r.Kind == ProactiveRuleKind.CalendarConflict && r.IsEnabled);
                if (rule == null) return null;
                ev.Payload.TryGetValue("conflict", out var conflict);
                if (string.Equals(conflict, "true", StringComparison.OrdinalIgnoreCase))
                {
                    ev.Payload.TryGetValue("events", out var desc);
                    return new ProactiveAlert(Guid.NewGuid().ToString(), rule.Id, ProactiveRuleKind.CalendarConflict,
                        "Calendar Conflict Detected", SecretRedactor.Redact(desc ?? "Overlapping calendar meetings."),
                        VoiceEventSeverity.Notice, "Summarize today's calendar", now);
                }
            }
            else if (ev.Kind == SystemEventKind.Custom)
            {
                var rule = activeRules.FirstOrDefault(r => r.Kind == ProactiveRuleKind.ImportantEmail && r.IsEnabled);
                if (rule == null) return null;
                ev.Payload.TryGetValue("type", out var t);
                if (string.Equals(t, "email_arrived", StringComparison.OrdinalIgnoreCase) &&
                    ev.Payload.TryGetValue("important", out var imp) &&
                    string.Equals(imp, "true", StringComparison.OrdinalIgnoreCase))
                {
                    ev.Payload.TryGetValue("sender", out var sender);
                    ev.Payload.TryGetValue("subject", out var subj);
                    return new ProactiveAlert(Guid.NewGuid().ToString(), rule.Id, ProactiveRuleKind.ImportantEmail,
                        SecretRedactor.Redact($"Important Email from {sender ?? "Sender"}"),
                        SecretRedactor.Redact(subj ?? "New priority email"),
                        VoiceEventSeverity.Notice, "Summarize recent emails", now);
                }
            }
            return null;
        }
    }
}

