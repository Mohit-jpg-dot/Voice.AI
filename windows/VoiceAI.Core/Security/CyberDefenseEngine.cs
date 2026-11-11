using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using VoiceAI.Core.Events;

namespace VoiceAI.Core.Security
{
    public sealed record CyberAnomaly(string Category, string Title, string Detail, VoiceEventSeverity Severity);

    public interface ICyberDefenseEngine
    {
        IReadOnlyList<CyberAnomaly> AnalyzeSnapshot(string netstatOutput, string arpOutput);
    }

    /// <summary>
    /// Process/network anomaly and new LAN MAC detector with security EventBus alerts on Windows.
    /// </summary>
    public sealed class CyberDefenseEngine : ICyberDefenseEngine
    {
        public static CyberDefenseEngine Shared { get; } = new CyberDefenseEngine();

        private static readonly HashSet<int> RiskyPorts = new() { 4444, 5555, 1337, 31337, 6667 };
        private readonly HashSet<string> _baselineMacs = new(StringComparer.OrdinalIgnoreCase);

        public void SeedBaselineMacs(IEnumerable<string> macs)
        {
            foreach (var m in macs) _baselineMacs.Add(m.ToLowerInvariant());
        }

        public IReadOnlyList<CyberAnomaly> AnalyzeSnapshot(string netstatOutput, string arpOutput)
        {
            var list = new List<CyberAnomaly>();
            foreach (var line in (netstatOutput ?? "").Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                string lower = line.ToLowerInvariant();
                if (lower.Contains("ncat") || lower.Contains("netcat") || lower.Contains("xmrig"))
                {
                    list.Add(new CyberAnomaly("process", "Suspicious Network Binary", line.Trim(), VoiceEventSeverity.Critical));
                }
                foreach (var port in RiskyPorts)
                {
                    if (line.Contains($":{port}"))
                    {
                        list.Add(new CyberAnomaly("network", $"High-Risk Listening Port {port}", line.Trim(), VoiceEventSeverity.Warning));
                    }
                }
            }

            if (_baselineMacs.Count > 0 && !string.IsNullOrEmpty(arpOutput))
            {
                foreach (Match m in Regex.Matches(arpOutput, @"\b([0-9a-fA-F]{1,2}[:-]){5}[0-9a-fA-F]{1,2}\b"))
                {
                    string mac = m.Value.ToLowerInvariant();
                    if (mac == "ff:ff:ff:ff:ff:ff" || mac == "ff-ff-ff-ff-ff-ff") continue;
                    if (_baselineMacs.Add(mac))
                    {
                        list.Add(new CyberAnomaly("new_device", $"New LAN Device ({mac})", mac, VoiceEventSeverity.Notice));
                    }
                }
            }

            if (list.Count > 0)
            {
                EventBus.Shared.Publish(VoiceEvent.Create(
                    SystemEventKind.Custom,
                    "CyberDefenseEngine",
                    new Dictionary<string, string> { ["findings"] = list.Count.ToString(), ["top"] = list[0].Title },
                    VoiceEventSeverity.Warning));
            }
            return list;
        }
    }
}

