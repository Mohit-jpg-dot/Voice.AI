using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using VoiceAI.Core.Security;
using VoiceAI.Core.Tools;

namespace VoiceAI.Core.Marketplace
{
    public sealed record DeclarativePluginToolSpec(
        string Name,
        string Description,
        string PermissionTier,
        string ResponseTemplate);

    public sealed record ExternalPluginManifest(
        string Id,
        string Name,
        string Version,
        IReadOnlyList<DeclarativePluginToolSpec> Tools);

    /// <summary>
    /// Dynamically loads user-supplied JSON plugin manifests into ToolRegistry without modifying core code.
    /// </summary>
    public sealed class UserPluginLoader
    {
        public static UserPluginLoader Shared { get; } = new UserPluginLoader();

        private readonly Dictionary<string, List<string>> _installedToolNames = new();

        public IReadOnlyList<string> InstallFromJson(string json)
        {
            var manifest = JsonSerializer.Deserialize<ExternalPluginManifest>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
            if (manifest == null || string.IsNullOrWhiteSpace(manifest.Id)) return Array.Empty<string>();
            return Install(manifest);
        }

        public IReadOnlyList<string> Install(ExternalPluginManifest manifest)
        {
            Uninstall(manifest.Id);
            var added = new List<string>();
            foreach (var spec in manifest.Tools)
            {
                string fullName = $"plugin.{manifest.Id}.{spec.Name}";
                var tier = spec.PermissionTier?.ToUpperInvariant() switch
                {
                    "READ_ONLY" or "READONLY" => PermissionTier.ReadOnly,
                    "CONSEQUENTIAL" => PermissionTier.Consequential,
                    _ => PermissionTier.Reversible
                };

                var def = new ToolDefinition(
                    fullName,
                    manifest.Name,
                    spec.Description,
                    tier,
                    new ToolInputSchema(
                        new Dictionary<string, ToolSchemaProperty>
                        {
                            ["input"] = new("string", "Optional input")
                        },
                        Array.Empty<string>()),
                    $"plugin:{manifest.Id}");

                ToolRegistry.Shared.Register(def, args =>
                {
                    args.TryGetValue("input", out var input);
                    string rendered = (spec.ResponseTemplate ?? "").Replace("{{input}}", input ?? "");
                    return Task.FromResult(new ToolInvocationResult(true, SecretRedactor.Redact(rendered), tier == PermissionTier.Consequential, true));
                });
                added.Add(fullName);
            }
            _installedToolNames[manifest.Id] = added;
            return added;
        }

        public void Uninstall(string pluginId)
        {
            if (_installedToolNames.Remove(pluginId, out var names))
            {
                foreach (var n in names) ToolRegistry.Shared.Unregister(n);
            }
        }
    }
}

