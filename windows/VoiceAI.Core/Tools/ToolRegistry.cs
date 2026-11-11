using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using VoiceAI.Core.Events;
using VoiceAI.Core.Security;

namespace VoiceAI.Core.Tools
{
    public enum PermissionTier
    {
        ReadOnly,
        Reversible,
        Consequential
    }

    public sealed record ToolSchemaProperty(string Type, string Description);

    public sealed record ToolInputSchema(
        IReadOnlyDictionary<string, ToolSchemaProperty> Properties,
        IReadOnlyList<string> Required);

    public sealed record ToolDefinition(
        string Name,
        string AppName,
        string Description,
        PermissionTier PermissionTier,
        ToolInputSchema InputSchema,
        string Source = "built_in");

    public sealed record ToolInvocationResult(
        bool Success,
        string Summary,
        bool RequiresApproval,
        bool WasApproved);

    public interface IToolRegistry
    {
        void Register(ToolDefinition definition, Func<IReadOnlyDictionary<string, string>, Task<ToolInvocationResult>> handler);
        bool Unregister(string name);
        IReadOnlyList<ToolDefinition> AllTools();
        ToolDefinition? GetTool(string name);
        Task<ToolInvocationResult> InvokeAsync(
            string name,
            IReadOnlyDictionary<string, string>? arguments = null,
            Func<ToolDefinition, IReadOnlyDictionary<string, string>, Task<bool>>? approvalHandler = null);
    }

    /// <summary>
    /// Cross-platform MCP-compatible, permission-tiered tool registry for Windows VoiceAI.Core.
    /// </summary>
    public sealed class ToolRegistry : IToolRegistry
    {
        public static ToolRegistry Shared { get; } = new ToolRegistry();

        private sealed record RegisteredEntry(
            ToolDefinition Definition,
            Func<IReadOnlyDictionary<string, string>, Task<ToolInvocationResult>> Handler);

        private readonly object _lock = new();
        private readonly Dictionary<string, RegisteredEntry> _entries = new(StringComparer.OrdinalIgnoreCase);

        public ToolRegistry()
        {
            RegisterDefaultTools();
        }

        public void Register(
            ToolDefinition definition,
            Func<IReadOnlyDictionary<string, string>, Task<ToolInvocationResult>> handler)
        {
            lock (_lock)
            {
                _entries[definition.Name] = new RegisteredEntry(definition, handler);
            }
        }

        public bool Unregister(string name)
        {
            lock (_lock)
            {
                return _entries.Remove(name);
            }
        }

        public IReadOnlyList<ToolDefinition> AllTools()
        {
            lock (_lock)
            {
                return _entries.Values.Select(e => e.Definition).OrderBy(d => d.Name).ToList();
            }
        }

        public ToolDefinition? GetTool(string name)
        {
            lock (_lock)
            {
                return _entries.TryGetValue(name, out var entry) ? entry.Definition : null;
            }
        }

        public async Task<ToolInvocationResult> InvokeAsync(
            string name,
            IReadOnlyDictionary<string, string>? arguments = null,
            Func<ToolDefinition, IReadOnlyDictionary<string, string>, Task<bool>>? approvalHandler = null)
        {
            RegisteredEntry? entry;
            lock (_lock)
            {
                _entries.TryGetValue(name, out entry);
            }
            if (entry == null)
            {
                return new ToolInvocationResult(false, $"Tool '{name}' is not registered.", false, false);
            }

            var args = arguments ?? new Dictionary<string, string>();
            if (entry.Definition.PermissionTier == PermissionTier.Consequential)
            {
                var safeArgs = SecretRedactor.RedactDictionary(args);
                EventBus.Shared.Publish(VoiceEvent.Create(
                    SystemEventKind.ApprovalRequested,
                    "ToolRegistry",
                    new Dictionary<string, string>
                    {
                        ["tool"] = entry.Definition.Name,
                        ["tier"] = entry.Definition.PermissionTier.ToString()
                    },
                    VoiceEventSeverity.Warning));

                bool approved = approvalHandler != null && await approvalHandler(entry.Definition, safeArgs);
                EventBus.Shared.Publish(VoiceEvent.Create(
                    SystemEventKind.ApprovalResolved,
                    "ToolRegistry",
                    new Dictionary<string, string>
                    {
                        ["tool"] = entry.Definition.Name,
                        ["approved"] = approved ? "true" : "false"
                    },
                    approved ? VoiceEventSeverity.Notice : VoiceEventSeverity.Warning));

                if (!approved)
                {
                    return new ToolInvocationResult(
                        false,
                        $"Cancelled: approval required before running '{entry.Definition.Name}'.",
                        true,
                        false);
                }
            }

            var result = await entry.Handler(args);
            EventBus.Shared.Publish(VoiceEvent.Create(
                SystemEventKind.ToolInvoked,
                "ToolRegistry",
                new Dictionary<string, string>
                {
                    ["tool"] = entry.Definition.Name,
                    ["tier"] = entry.Definition.PermissionTier.ToString(),
                    ["success"] = result.Success ? "true" : "false"
                },
                result.Success ? VoiceEventSeverity.Info : VoiceEventSeverity.Warning));

            return result;
        }

        private void RegisterDefaultTools()
        {
            Register(
                new ToolDefinition(
                    "math_evaluate",
                    "Calculator",
                    "Evaluate arithmetic and percentages locally.",
                    PermissionTier.ReadOnly,
                    new ToolInputSchema(
                        new Dictionary<string, ToolSchemaProperty>
                        {
                            ["expression"] = new("string", "Arithmetic expression")
                        },
                        new[] { "expression" })),
                args =>
                {
                    args.TryGetValue("expression", out var expr);
                    var res = Math.MathEngine.Shared.Evaluate(expr ?? "");
                    return Task.FromResult(res != null
                        ? new ToolInvocationResult(true, res.DisplaySummary, false, true)
                        : new ToolInvocationResult(false, "Invalid math expression.", false, true));
                });

            Register(
                new ToolDefinition(
                    "send_message",
                    "WhatsApp",
                    "Send an external message (requires explicit Approval Card confirmation).",
                    PermissionTier.Consequential,
                    new ToolInputSchema(
                        new Dictionary<string, ToolSchemaProperty>
                        {
                            ["recipient"] = new("string", "Target contact"),
                            ["body"] = new("string", "Message body")
                        },
                        new[] { "recipient", "body" })),
                args =>
                {
                    args.TryGetValue("recipient", out var r);
                    args.TryGetValue("body", out var b);
                    return Task.FromResult(new ToolInvocationResult(true, $"Sent message to {r}: {b}", true, true));
                });

            Register(
                new ToolDefinition(
                    "rag_search_files",
                    "Local Knowledge",
                    "Search user-chosen local folders on-device using semantic RAG.",
                    PermissionTier.ReadOnly,
                    new ToolInputSchema(
                        new Dictionary<string, ToolSchemaProperty>
                        {
                            ["query"] = new("string", "Semantic search query")
                        },
                        new[] { "query" })),
                args =>
                {
                    args.TryGetValue("query", out var q);
                    var hits = Knowledge.LocalKnowledgeEngine.Shared.Search(q ?? "", 3);
                    string msg = hits.Count == 0
                        ? "No matching local files found."
                        : string.Join(" | ", hits.Select(h => $"{h.Chunk.FileName}: {h.Chunk.Snippet}"));
                    return Task.FromResult(new ToolInvocationResult(true, msg, false, true));
                });

            Register(
                new ToolDefinition(
                    "smarthome_control_security",
                    "Smart Home Security",
                    "Unlock/disarm smart locks or alarms (CONSEQUENTIAL Approval Card required).",
                    PermissionTier.Consequential,
                    new ToolInputSchema(
                        new Dictionary<string, ToolSchemaProperty>
                        {
                            ["device"] = new("string", "Lock or alarm device"),
                            ["action"] = new("string", "lock, unlock, arm, disarm")
                        },
                        new[] { "device", "action" })),
                async args =>
                {
                    args.TryGetValue("device", out var d);
                    args.TryGetValue("action", out var a);
                    var res = await SmartHome.SmartHomeCoordinator.Shared.ExecuteAsync(
                        d ?? "", a ?? "lock", null, (_, _) => Task.FromResult(true));
                    return new ToolInvocationResult(res.Success, res.Summary, true, true);
                });
        }
    }
}

