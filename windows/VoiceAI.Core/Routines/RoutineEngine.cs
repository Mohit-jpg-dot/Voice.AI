using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using VoiceAI.Core.Events;
using VoiceAI.Core.Tools;

namespace VoiceAI.Core.Routines
{
    public sealed record VoiceRoutineStep(string Title, string ActionPrompt, PermissionTier Tier);

    public sealed record VoiceRoutine(
        string Id,
        string Name,
        IReadOnlyList<string> TriggerPhrases,
        bool IsEnabled,
        bool IsBuiltIn,
        IReadOnlyList<VoiceRoutineStep> Steps);

    public interface IRoutineEngine
    {
        IReadOnlyList<VoiceRoutine> AllRoutines();
        void SaveRoutine(VoiceRoutine routine);
        bool DeleteCustomRoutine(string id);
        VoiceRoutine? MatchRoutine(string utterance);
        Task<(bool Success, string Summary)> RunRoutineAsync(
            VoiceRoutine routine,
            Func<VoiceRoutineStep, Task<string>> stepExecutor);
    }

    /// <summary>
    /// Built-in JARVIS protocols ("good morning", "focus mode", "house party protocol")
    /// and editable multi-step user macros for Windows VoiceAI.Core.
    /// </summary>
    public sealed class RoutineEngine : IRoutineEngine
    {
        public static RoutineEngine Shared { get; } = new RoutineEngine();

        private readonly object _lock = new();
        private readonly List<VoiceRoutine> _routines;

        public RoutineEngine()
        {
            _routines = new List<VoiceRoutine>
            {
                new(
                    "builtin_good_morning",
                    "Good Morning Briefing",
                    new[] { "good morning", "morning briefing", "subah ka briefing", "suprabhat" },
                    true,
                    true,
                    new[]
                    {
                        new VoiceRoutineStep("Weather", "check today's weather", PermissionTier.ReadOnly),
                        new VoiceRoutineStep("Calendar", "check today's calendar", PermissionTier.ReadOnly),
                        new VoiceRoutineStep("Unread Mail", "check unread email", PermissionTier.ReadOnly),
                        new VoiceRoutineStep("News", "latest headlines", PermissionTier.ReadOnly)
                    }),
                new(
                    "builtin_focus_mode",
                    "Focus Mode Protocol",
                    new[] { "focus mode", "deep work mode", "focus protocol", "padhai mode" },
                    true,
                    true,
                    new[]
                    {
                        new VoiceRoutineStep("Pause Media", "pause music", PermissionTier.Reversible),
                        new VoiceRoutineStep("Dark Mode", "enable dark mode", PermissionTier.Reversible)
                    }),
                new(
                    "builtin_house_party",
                    "House Party Protocol",
                    new[] { "house party protocol", "wrap up for the day", "kaam khatam" },
                    true,
                    true,
                    new[]
                    {
                        new VoiceRoutineStep("Pause Media", "pause music", PermissionTier.Reversible),
                        new VoiceRoutineStep("Save Daily Note", "save wrap up note", PermissionTier.Reversible)
                    })
            };
        }

        public IReadOnlyList<VoiceRoutine> AllRoutines()
        {
            lock (_lock) return _routines.ToList();
        }

        public void SaveRoutine(VoiceRoutine routine)
        {
            lock (_lock)
            {
                int idx = _routines.FindIndex(r => r.Id == routine.Id);
                if (idx >= 0) _routines[idx] = routine;
                else _routines.Add(routine);
            }
        }

        public bool DeleteCustomRoutine(string id)
        {
            lock (_lock)
            {
                return _routines.RemoveAll(r => r.Id == id && !r.IsBuiltIn) > 0;
            }
        }

        public VoiceRoutine? MatchRoutine(string utterance)
        {
            if (string.IsNullOrWhiteSpace(utterance)) return null;
            string lower = utterance.Trim().ToLowerInvariant();
            lock (_lock)
            {
                foreach (var r in _routines.Where(r => r.IsEnabled))
                {
                    foreach (var trigger in r.TriggerPhrases)
                    {
                        string t = trigger.Trim().ToLowerInvariant();
                        if (!string.IsNullOrEmpty(t) && lower.Contains(t))
                        {
                            return r;
                        }
                    }
                }
            }
            return null;
        }

        public async Task<(bool Success, string Summary)> RunRoutineAsync(
            VoiceRoutine routine,
            Func<VoiceRoutineStep, Task<string>> stepExecutor)
        {
            var outputs = new List<string>();
            foreach (var step in routine.Steps)
            {
                string stepResult = await stepExecutor(step);
                outputs.Add($"{step.Title}: {stepResult}");
            }

            EventBus.Shared.Publish(VoiceEvent.Create(
                SystemEventKind.ToolInvoked,
                "RoutineEngine",
                new Dictionary<string, string> { ["routine"] = routine.Name, ["steps"] = routine.Steps.Count.ToString() }));

            return (true, string.Join("\n", outputs));
        }
    }
}

