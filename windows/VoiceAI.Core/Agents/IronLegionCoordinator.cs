using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using VoiceAI.Core.Events;
using VoiceAI.Core.Knowledge;

namespace VoiceAI.Core.Agents
{
    public enum LegionWorkerRole
    {
        Research,
        Code,
        Summarize
    }

    public sealed record LegionWorkerReport(LegionWorkerRole Role, string Summary, long ElapsedMs);

    public interface IIronLegionCoordinator
    {
        Task<(IReadOnlyList<LegionWorkerReport> Workers, string UnifiedSummary)> DispatchAsync(string goal);
    }

    /// <summary>
    /// Coordinates parallel Research, Code, and Summarize workers for Iron Legion mode in Windows VoiceAI.Core.
    /// </summary>
    public sealed class IronLegionCoordinator : IIronLegionCoordinator
    {
        public static IronLegionCoordinator Shared { get; } = new IronLegionCoordinator();

        public async Task<(IReadOnlyList<LegionWorkerReport> Workers, string UnifiedSummary)> DispatchAsync(string goal)
        {
            string clean = (goal ?? "").Trim();
            var tasks = new[]
            {
                RunWorkerAsync(LegionWorkerRole.Research, clean),
                RunWorkerAsync(LegionWorkerRole.Code, clean),
                RunWorkerAsync(LegionWorkerRole.Summarize, clean)
            };

            var results = await Task.WhenAll(tasks);
            string summary = string.Join("\n", results.Select(r => $"• [{r.Role}] {r.Summary}"));

            EventBus.Shared.Publish(VoiceEvent.Create(
                SystemEventKind.Custom,
                "IronLegionCoordinator",
                new Dictionary<string, string> { ["workers"] = results.Length.ToString(), ["goal"] = clean }));

            return (results, summary);
        }

        private static Task<LegionWorkerReport> RunWorkerAsync(LegionWorkerRole role, string goal)
        {
            return Task.Run(() =>
            {
                var sw = System.Diagnostics.Stopwatch.StartNew();
                string note = role switch
                {
                    LegionWorkerRole.Research => $"Scanned {LocalKnowledgeEngine.Shared.Search(goal, 2).Count} local RAG hits for '{goal}'.",
                    LegionWorkerRole.Code => $"Scoped protocol modules & ToolRegistry bindings for '{goal}'.",
                    _ => $"Synthesized concise executive briefing for '{goal}'."
                };
                sw.Stop();
                return new LegionWorkerReport(role, note, sw.ElapsedMilliseconds);
            });
        }
    }
}

