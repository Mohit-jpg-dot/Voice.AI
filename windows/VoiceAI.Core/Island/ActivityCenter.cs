// Ported from islandcn, MIT License, Copyright (c) 2026 Leo. Modified for C#.
// Observable activity engine managing priority stacks, presentations, alerts, and safety lanes (.NET Core).

using System;
using System.Collections.Generic;
using System.Linq;

namespace VoiceAI.Core.Island
{
    public interface IIslandClock
    {
        double Now();
        Action Schedule(double delaySeconds, Action action);
    }

    public class SystemIslandClock : IIslandClock
    {
        public double Now() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0;
        public Action Schedule(double delaySeconds, Action action)
        {
            var cts = new System.Threading.CancellationTokenSource();
            System.Threading.Tasks.Task.Delay((int)(delaySeconds * 1000), cts.Token).ContinueWith(t =>
            {
                if (!cts.Token.IsCancellationRequested) action();
            });
            return () => cts.Cancel();
        }
    }

    public class MockIslandClock : IIslandClock
    {
        private double _currentTime = 1000.0;
        private readonly List<(Guid id, double dueTime, Action action)> _scheduled = new();
        private readonly object _lock = new();

        public double Now()
        {
            lock (_lock) return _currentTime;
        }

        public void Advance(double seconds)
        {
            List<(Guid id, double dueTime, Action action)> due;
            lock (_lock)
            {
                _currentTime += seconds;
                due = _scheduled.Where(s => s.dueTime <= _currentTime).ToList();
                _scheduled.RemoveAll(s => s.dueTime <= _currentTime);
            }
            foreach (var task in due)
            {
                task.action();
            }
        }

        public Action Schedule(double delaySeconds, Action action)
        {
            var id = Guid.NewGuid();
            lock (_lock)
            {
                _scheduled.Add((id, _currentTime + delaySeconds, action));
            }
            return () =>
            {
                lock (_lock) { _scheduled.RemoveAll(s => s.id == id); }
            };
        }
    }

    public class ActivityCenter
    {
        public static ActivityCenter Shared { get; } = new ActivityCenter();

        public ActivityCenter() {}

        public ActivityCenter(IIslandClock clock)
        {
            Clock = clock;
        }

        public ActivitySlotContent? GetResolvedLeading(Activity a)
        {
            if (a.IsSensitive && !ShowSensitivePreviews)
            {
                return ActivitySlotContent.FromText("•••");
            }
            return a.Content.Compact?.Leading;
        }

        private readonly List<Activity> _activities = new();
        private readonly Dictionary<string, string> _frontGroups = new();
        private int _nextOrder = 0;
        private readonly List<Action> _alertCancelActions = new();

        public IReadOnlyList<Activity> Activities => _activities.AsReadOnly();
        public IslandScene CurrentScene { get; private set; } = IslandScene.Idle;
        public bool IsExpanded { get; private set; }
        public string? ExpandedActivityId { get; private set; }
        public bool ShowSensitivePreviews { get; set; }
        public bool IsDNDActive { get; set; }
        public bool IsDictationActive { get; set; }
        public bool IsApprovalCardActive { get; set; }
        public IIslandClock Clock { get; set; } = new SystemIslandClock();

        public void Start(ActivityOptions options)
        {
            var existing = _activities.FirstOrDefault(a => a.Id == options.Id);
            if (existing != null)
            {
                Update(options.Id, new ActivityUpdate
                {
                    Compact = options.Content.Compact,
                    Minimal = options.Content.Minimal,
                    Expanded = options.Content.Expanded,
                    Label = options.Label,
                    Priority = options.Priority,
                    Alert = options.Alert
                });
                return;
            }

            var activity = new Activity
            {
                Id = options.Id,
                Label = options.Label ?? options.Id,
                Priority = options.Priority,
                Order = _nextOrder++,
                Content = options.Content,
                Group = options.Group,
                IsSensitive = options.IsSensitive,
                PersistsAcrossRestarts = options.PersistsAcrossRestarts,
                OnPress = options.OnPress
            };

            _activities.Add(activity);
            SortActivities();

            if (options.Priority == ActivityPriority.ConsequentialApproval || IsApprovalCardActive)
            {
                IsExpanded = true;
                ExpandedActivityId = options.Id;
            }

            RecomputeScene();

            if (options.Alert)
            {
                TriggerAlert(options.Id);
            }
        }

        public void Update(string id, ActivityUpdate update)
        {
            var existing = _activities.FirstOrDefault(a => a.Id == id);
            if (existing == null) return;

            if (existing.Priority != ActivityPriority.ConsequentialApproval && update.Priority.HasValue)
            {
                existing.Priority = update.Priority.Value;
            }
            if (!string.IsNullOrEmpty(update.Label)) existing.Label = update.Label;
            if (update.Compact != null) existing.Content.Compact = update.Compact;
            if (update.Minimal != null) existing.Content.Minimal = update.Minimal;
            if (update.Expanded != null) existing.Content.Expanded = update.Expanded;

            SortActivities();
            RecomputeScene();

            if (update.Alert == true)
            {
                TriggerAlert(id);
            }
        }

        public void End(string id)
        {
            var existing = _activities.FirstOrDefault(a => a.Id == id);
            if (existing == null) return;

            if (ExpandedActivityId == id)
            {
                ClearAlerts();
                IsExpanded = false;
                ExpandedActivityId = null;
            }

            _activities.Remove(existing);
            _frontGroups.Remove(id);
            RecomputeScene();
        }

        public void Expand(string? id = null)
        {
            if (IsApprovalCardActive)
            {
                var approval = _activities.FirstOrDefault(a => a.Priority == ActivityPriority.ConsequentialApproval);
                if (approval != null && id != null && id != approval.Id)
                {
                    return; // Locked to approval card
                }
            }

            var targetId = id ?? CurrentShownActivities().FirstOrDefault()?.Id;
            if (string.IsNullOrEmpty(targetId)) return;

            var target = _activities.FirstOrDefault(a => a.Id == targetId);
            if (target == null) return;

            ClearAlerts();
            IsExpanded = true;
            ExpandedActivityId = target.Id;
            RecomputeScene();
        }

        public void Collapse()
        {
            if (IsApprovalCardActive && ExpandedActivityId != null)
            {
                var active = _activities.FirstOrDefault(a => a.Id == ExpandedActivityId);
                if (active != null && active.Priority == ActivityPriority.ConsequentialApproval)
                {
                    return; // Approval card cannot be collapsed
                }
            }

            if (!IsExpanded) return;
            ClearAlerts();
            IsExpanded = false;
            ExpandedActivityId = null;
            RecomputeScene();
        }

        public void Reset()
        {
            ClearAlerts();
            _activities.Clear();
            _frontGroups.Clear();
            IsExpanded = false;
            ExpandedActivityId = null;
            CurrentScene = IslandScene.Idle;
        }

        public void RecomputeScene()
        {
            var shown = CurrentShownActivities();
            var expanded = IsExpanded ? _activities.FirstOrDefault(a => a.Id == ExpandedActivityId) : null;

            if (expanded != null)
            {
                CurrentScene = new IslandScene
                {
                    Presentation = IslandPresentationKind.Expanded,
                    ContentKey = $"expanded:{expanded.Id}",
                    Label = expanded.Label,
                    PrimaryId = expanded.Id
                };
                return;
            }

            if (shown.Count == 0)
            {
                CurrentScene = IslandScene.Idle;
                return;
            }

            if (shown.Count == 1)
            {
                var first = shown[0];
                CurrentScene = new IslandScene
                {
                    Presentation = IslandPresentationKind.Compact,
                    ContentKey = $"compact:{first.Id}",
                    Label = first.Label,
                    PrimaryId = first.Id
                };
                return;
            }

            var primary = shown[0];
            var secondary = shown[1];
            CurrentScene = new IslandScene
            {
                Presentation = IslandPresentationKind.Split,
                ContentKey = $"split:{primary.Id}:{secondary.Id}",
                Label = $"{primary.Label}, {secondary.Label}",
                PrimaryId = primary.Id,
                DetachedId = secondary.Id
            };
        }

        private void TriggerAlert(string id)
        {
            if (IsApprovalCardActive || _activities.Any(a => a.Priority == ActivityPriority.ConsequentialApproval))
            {
                return; // Suppressed during approval
            }
            if (IsDictationActive || IsDNDActive)
            {
                return; // Suppressed during dictation or DND
            }

            ClearAlerts();
            IsExpanded = true;
            ExpandedActivityId = id;
            RecomputeScene();

            var cancel = Clock.Schedule(5.975, () =>
            {
                if (ExpandedActivityId == id)
                {
                    IsExpanded = false;
                    ExpandedActivityId = null;
                    RecomputeScene();
                }
            });
            _alertCancelActions.Add(cancel);
        }

        private void ClearAlerts()
        {
            foreach (var cancel in _alertCancelActions) cancel();
            _alertCancelActions.Clear();
        }

        private void SortActivities()
        {
            _activities.Sort((a, b) =>
            {
                if (a.Priority != b.Priority) return b.Priority.CompareTo(a.Priority);
                return a.Order.CompareTo(b.Order);
            });
        }

        private List<Activity> CurrentShownActivities()
        {
            return _activities.Where(a =>
            {
                if (string.IsNullOrEmpty(a.Group)) return true;
                if (_frontGroups.TryGetValue(a.Group, out var forward))
                {
                    return a.Id == forward;
                }
                var firstInGroup = _activities.Where(x => x.Group == a.Group).OrderBy(x => x.Order).FirstOrDefault();
                return firstInGroup?.Id == a.Id;
            }).ToList();
        }
    }
}

