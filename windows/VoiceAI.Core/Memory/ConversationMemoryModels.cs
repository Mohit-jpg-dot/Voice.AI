using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace VoiceAI.Core.Memory
{
    public enum EntityKind
    {
        Person,
        File,
        Folder,
        App,
        Url,
        Date,
        Place,
        Document,
        Project,
        Other
    }

    public sealed class ConversationEntity
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string Name { get; set; }
        public EntityKind Kind { get; set; }
        public double Salience { get; set; } = 1.0;
        public DateTime LastMentionedAtUtc { get; set; } = DateTime.UtcNow;
        public Dictionary<string, string> Metadata { get; set; } = new();

        public ConversationEntity(string name, EntityKind kind, double salience = 1.0)
        {
            Name = name;
            Kind = kind;
            Salience = System.Math.Clamp(salience, 0.0, 1.0);
        }
    }

    public sealed class ResultListItem
    {
        public int Index { get; set; } // 1-based index (1, 2, 3...)
        public string Title { get; set; }
        public string? Subtitle { get; set; }
        public string Identifier { get; set; }
        public EntityKind Kind { get; set; }

        public ResultListItem(int index, string title, string identifier, EntityKind kind = EntityKind.File, string? subtitle = null)
        {
            Index = index;
            Title = title;
            Identifier = identifier;
            Kind = kind;
            Subtitle = subtitle;
        }
    }

    public sealed class ConversationStateRecord
    {
        public string SessionId { get; set; }
        public string? CurrentTopic { get; set; }
        public List<ConversationEntity> Entities { get; set; } = new();
        public List<ResultListItem> LastResultList { get; set; } = new();
        public string? LastActionTool { get; set; }
        public string? LastActionTarget { get; set; }
        public bool LastActionSuccess { get; set; }
        public string? FrontmostApp { get; set; }
        public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;

        public ConversationStateRecord(string sessionId)
        {
            SessionId = sessionId;
        }

        public void DecaySalience(double decayFactor = 0.85, double pruneThreshold = 0.15)
        {
            foreach (var ent in Entities)
            {
                ent.Salience *= decayFactor;
            }
            Entities.RemoveAll(e => e.Salience < pruneThreshold);
            UpdatedAtUtc = DateTime.UtcNow;
        }

        public void MentionEntity(string name, EntityKind kind)
        {
            if (string.IsNullOrWhiteSpace(name)) return;
            var existing = Entities.FirstOrDefault(e => e.Name.Equals(name, StringComparison.OrdinalIgnoreCase) && e.Kind == kind);
            if (existing != null)
            {
                existing.Salience = 1.0;
                existing.LastMentionedAtUtc = DateTime.UtcNow;
            }
            else
            {
                Entities.Insert(0, new ConversationEntity(name, kind, 1.0));
                if (Entities.Count > 25) Entities.RemoveAt(Entities.Count - 1);
            }
            UpdatedAtUtc = DateTime.UtcNow;
        }

        public void SetResultList(IEnumerable<(string title, string id, EntityKind kind)> items)
        {
            LastResultList.Clear();
            int idx = 1;
            foreach (var it in items)
            {
                LastResultList.Add(new ResultListItem(idx, it.title, it.id, it.kind));
                MentionEntity(it.title, it.kind);
                idx++;
            }
            UpdatedAtUtc = DateTime.UtcNow;
        }

        public ResultListItem? ItemAtIndex(int index) => LastResultList.FirstOrDefault(i => i.Index == index);

        public ConversationEntity? MostSalientEntity(EntityKind? kind = null)
        {
            var query = kind.HasValue ? Entities.Where(e => e.Kind == kind.Value) : Entities;
            return query.OrderByDescending(e => e.Salience).ThenByDescending(e => e.LastMentionedAtUtc).FirstOrDefault();
        }
    }

    public enum TaskLedgerStatus
    {
        Requested,
        InProgress,
        WaitingForApproval,
        Succeeded,
        Failed,
        Cancelled
    }

    public sealed class TaskLedgerEntry
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string SessionId { get; set; }
        public string RequestText { get; set; }
        public string Plan { get; set; }
        public TaskLedgerStatus Status { get; set; }
        public string? Evidence { get; set; }
        public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
        public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;

        public TaskLedgerEntry(string sessionId, string requestText, string plan, TaskLedgerStatus status = TaskLedgerStatus.Requested)
        {
            SessionId = sessionId;
            RequestText = requestText;
            Plan = plan;
            Status = status;
        }

        public string PromptDescription()
        {
            var outcome = Status switch
            {
                TaskLedgerStatus.Succeeded => $"Verified outcome: SUCCESS. Evidence: {Evidence ?? "Verified"}",
                TaskLedgerStatus.Failed => $"Verified outcome: FAILED. Evidence: {Evidence ?? "Error"}",
                TaskLedgerStatus.WaitingForApproval => "Status: WAITING FOR APPROVAL.",
                TaskLedgerStatus.InProgress => "Status: IN PROGRESS.",
                _ => $"Status: {Status}"
            };
            return $"- Task [{Status}]: User requested: \"{RequestText}\"\n  Plan: {Plan}\n  {outcome}";
        }
    }

    public sealed class TaskLedger
    {
        public static TaskLedger Shared { get; } = new();
        private readonly List<TaskLedgerEntry> _entries = new();
        private readonly object _lock = new();

        public TaskLedgerEntry RecordRequested(string sessionId, string requestText, string plan)
        {
            lock (_lock)
            {
                var entry = new TaskLedgerEntry(sessionId, requestText, plan);
                _entries.Add(entry);
                return entry;
            }
        }

        public bool RecordStatus(string taskId, TaskLedgerStatus status, string? evidence = null)
        {
            lock (_lock)
            {
                var target = _entries.FirstOrDefault(t => t.Id == taskId);
                if (target == null) return false;
                target.Status = status;
                target.Evidence = evidence;
                target.UpdatedAtUtc = DateTime.UtcNow;
                return true;
            }
        }

        public string FormatForPrompt(string sessionId)
        {
            lock (_lock)
            {
                var list = _entries.Where(t => t.SessionId == sessionId).TakeLast(4);
                if (!list.Any()) return string.Empty;
                return "Active Tasks (Truthful Execution Ledger):\n" +
                       string.Join("\n", list.Select(t => t.PromptDescription())) +
                       "\nNote: Model must never claim an action succeeded unless verified.";
            }
        }

        public void Clear()
        {
            lock (_lock) { _entries.Clear(); }
        }
    }

    public sealed record FollowUpResolution(
        string OriginalText,
        string RewrittenText,
        bool WasRewritten,
        string? DisambiguationQuestion = null,
        double Confidence = 1.0);

    public sealed class FollowUpResolver
    {
        public static FollowUpResolver Shared { get; } = new();

        public FollowUpResolution Resolve(string userText, ConversationStateRecord state)
        {
            if (string.IsNullOrWhiteSpace(userText)) return new(userText, userText, false);
            string lower = userText.Trim().ToLowerInvariant();

            // 1. Repetition ("again", "wahi dobara karo", "repeat that")
            if ((lower == "again" || lower == "repeat that" || lower == "wahi dobara karo" || lower == "dobara karo") &&
                !string.IsNullOrEmpty(state.LastActionTool))
            {
                string target = state.LastActionTarget != null ? $" on {state.LastActionTarget}" : "";
                return new(userText, $"{state.LastActionTool}{target}", true, null, 0.95);
            }

            // 2. Analogy ("do the same for <target>")
            if (lower.StartsWith("do the same for ") && !string.IsNullOrEmpty(state.LastActionTool))
            {
                string target = userText.Substring("do the same for ".Length).Trim();
                return new(userText, $"{state.LastActionTool} for {target}", true, null, 0.90);
            }

            // 3. 1-Based Ordinal Indexing (English & Hinglish)
            if (state.LastResultList.Count > 0)
            {
                int? targetIdx = null;
                string matched = "";

                if (lower.Contains("first one") || lower.Contains("1st one") || lower.Contains("the first one") || lower.Contains("pehla wala") || lower.Contains("pehla"))
                { targetIdx = 1; matched = "first"; }
                else if (lower.Contains("second one") || lower.Contains("2nd one") || lower.Contains("the second one") || lower.Contains("dusra wala") || lower.Contains("dusra"))
                { targetIdx = 2; matched = "second"; }
                else if (lower.Contains("third one") || lower.Contains("3rd one") || lower.Contains("the third one") || lower.Contains("teesra wala") || lower.Contains("teesra"))
                { targetIdx = 3; matched = "third"; }
                else if (lower.Contains("last one") || lower.Contains("the last one") || lower.Contains("aakhri wala") || lower.Contains("aakhri"))
                { targetIdx = state.LastResultList.Count; matched = "last"; }

                if (targetIdx.HasValue)
                {
                    var item = state.ItemAtIndex(targetIdx.Value);
                    if (item != null)
                    {
                        string replaced = Regex.Replace(userText, @"\b(?:the\s+)?(?:first|1st|second|2nd|third|3rd|last|pehla|dusra|teesra|aakhri)(?:\s+one|\s+wala)?\b", item.Title, RegexOptions.IgnoreCase);
                        return new(userText, replaced, true, null, 0.98);
                    }
                }
            }

            // 4. Pronoun and Demonstratives ("send that to David", "isko bhej do", "open that pdf")
            if (lower.Contains("that pdf") || lower.Contains("that file") || lower.Contains("us file"))
            {
                var files = state.Entities.Where(e => e.Kind == EntityKind.File || e.Kind == EntityKind.Document).ToList();
                if (files.Count >= 2 && System.Math.Abs(files[0].Salience - files[1].Salience) < 0.15)
                {
                    return new(userText, userText, false, $"Did you mean {files[0].Name} or {files[1].Name}?", 0.5);
                }
                if (files.Count > 0)
                {
                    string replaced = Regex.Replace(userText, @"\b(?:that\s+pdf|that\s+file|us\s+file)\b", files[0].Name, RegexOptions.IgnoreCase);
                    return new(userText, replaced, true, null, 0.92);
                }
            }

            if (Regex.IsMatch(lower, @"\b(?:that|it|isko|use)\b"))
            {
                if (state.LastResultList.Count > 0)
                {
                    var first = state.LastResultList[0];
                    string replaced = Regex.Replace(userText, @"\b(?:that|it|isko|use)\b", first.Title, RegexOptions.IgnoreCase);
                    return new(userText, replaced, true, null, 0.88);
                }
                var salient = state.MostSalientEntity();
                if (salient != null)
                {
                    string replaced = Regex.Replace(userText, @"\b(?:that|it|isko|use)\b", salient.Name, RegexOptions.IgnoreCase);
                    return new(userText, replaced, true, null, 0.85);
                }
            }

            return new(userText, userText, false);
        }
    }

    public sealed class HybridMemorySearcher
    {
        public static HybridMemorySearcher Shared { get; } = new();
        public bool AutoRememberSimplePreferences { get; set; } = false;
        private string? _pendingConsent;

        public (bool savedImmediately, string? prompt) ProposeFact(string content, Action saveAction)
        {
            if (AutoRememberSimplePreferences)
            {
                saveAction();
                return (true, null);
            }
            _pendingConsent = content;
            return (false, $"Do you want me to remember that {content}?");
        }

        public (bool confirmed, string? remembered) ResolveConsent(bool userAffirmed, Action onAffirmed)
        {
            if (_pendingConsent != null && userAffirmed)
            {
                string fact = _pendingConsent;
                _pendingConsent = null;
                onAffirmed();
                return (true, fact);
            }
            _pendingConsent = null;
            return (false, null);
        }

        public double CalculateHybridScore(double keywordScore, double semanticSimilarity, DateTime updatedAtUtc)
        {
            double ageDays = (DateTime.UtcNow - updatedAtUtc).TotalDays;
            double recency = System.Math.Exp(-System.Math.Max(0, ageDays) / 30.0);
            return (0.45 * System.Math.Clamp(semanticSimilarity, 0, 1)) +
                   (0.40 * System.Math.Clamp(keywordScore, 0, 1)) +
                   (0.15 * System.Math.Clamp(recency, 0, 1));
        }
    }
}
