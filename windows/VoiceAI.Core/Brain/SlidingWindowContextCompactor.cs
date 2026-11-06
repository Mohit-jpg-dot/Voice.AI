using System;
using System.Collections.Generic;

namespace VoiceAI.Core.Brain
{
    public class ExecutionTurnSummary
    {
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
        public string UserIntent { get; set; } = string.Empty;
        public string TargetApplication { get; set; } = string.Empty;
        public List<string> CompletedActions { get; set; } = new List<string>();
    }

    /// <summary>
    /// Dynamic Context Compactor for Windows.
    /// Sliding-window memory manager that consolidates execution history to prevent token bloating.
    /// </summary>
    public class SlidingWindowContextCompactor
    {
        public static readonly SlidingWindowContextCompactor Shared = new SlidingWindowContextCompactor();

        private readonly object _lock = new object();
        private readonly int _windowSize;
        private readonly List<ExecutionTurnSummary> _turns = new List<ExecutionTurnSummary>();
        private string _compactedHistory = string.Empty;

        public SlidingWindowContextCompactor(int windowSize = 4)
        {
            _windowSize = windowSize;
        }

        public void RecordTurn(string userIntent, string targetApplication, List<string> actions)
        {
            lock (_lock)
            {
                var turn = new ExecutionTurnSummary
                {
                    UserIntent = userIntent,
                    TargetApplication = targetApplication,
                    CompletedActions = actions
                };
                _turns.Add(turn);

                if (_turns.Count > _windowSize)
                {
                    var overflow = _turns[0];
                    _turns.RemoveAt(0);
                    var snippet = $"{overflow.TargetApplication} ({overflow.UserIntent})";
                    _compactedHistory = string.IsNullOrEmpty(_compactedHistory) ? snippet : $"{_compactedHistory} | {snippet}";
                }
            }
        }

        public string GetCompactedPromptContext()
        {
            lock (_lock)
            {
                var parts = new List<string>();
                if (!string.IsNullOrEmpty(_compactedHistory))
                {
                    parts.Add($"[Prior Context Summary]: {_compactedHistory}");
                }

                if (_turns.Count > 0)
                {
                    parts.Add("[Recent Actions]:");
                    for (int i = 0; i < _turns.Count; i++)
                    {
                        parts.Add($"  {i + 1}. [{_turns[i].TargetApplication}] \"{_turns[i].UserIntent}\": {string.Join(" -> ", _turns[i].CompletedActions)}");
                    }
                }

                return string.Join("\n", parts);
            }
        }

        public int ActiveTurnsCount
        {
            get { lock (_lock) return _turns.Count; }
        }
    }
}

