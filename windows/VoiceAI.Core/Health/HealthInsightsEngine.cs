using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace VoiceAI.Core.Health
{
    public enum HealthMetricKind
    {
        Steps,
        HeartRate,
        RestingHeartRate,
        SleepHours,
        ActiveCalories
    }

    public sealed record HealthSample(HealthMetricKind Metric, double Value, DateTimeOffset RecordedAt);

    public sealed record HealthTrendWarning(string Title, string Detail);

    public interface IHealthInsightsEngine
    {
        bool IsOptedIn { get; }
        void SetOptedIn(bool enabled);
        int ImportAppleHealthXml(string xml);
        (int TotalSteps, double? AvgRestingHr, double? AvgSleepHours, IReadOnlyList<HealthTrendWarning> Warnings) ComputeDigest();
    }

    /// <summary>
    /// Strictly opt-in, on-device health export analyzer with trend warnings for Windows VoiceAI.Core.
    /// </summary>
    public sealed class HealthInsightsEngine : IHealthInsightsEngine
    {
        public static HealthInsightsEngine Shared { get; } = new HealthInsightsEngine();

        private readonly object _lock = new();
        private bool _optedIn = false;
        private readonly List<HealthSample> _samples = new();

        public bool IsOptedIn { get { lock (_lock) return _optedIn; } }

        public void SetOptedIn(bool enabled)
        {
            lock (_lock) _optedIn = enabled;
        }

        public int ImportAppleHealthXml(string xml)
        {
            if (!IsOptedIn || string.IsNullOrWhiteSpace(xml)) return 0;
            var matches = Regex.Matches(xml, @"<Record[^>]*type=""([^""]+)""[^>]*value=""([0-9]+(?:\.[0-9]+)?)""[^>]*/?>");
            var added = new List<HealthSample>();
            foreach (Match m in matches)
            {
                string type = m.Groups[1].Value;
                if (!double.TryParse(m.Groups[2].Value, out double val)) continue;
                HealthMetricKind? kind = type switch
                {
                    "HKQuantityTypeIdentifierStepCount" => HealthMetricKind.Steps,
                    "HKQuantityTypeIdentifierHeartRate" => HealthMetricKind.HeartRate,
                    "HKQuantityTypeIdentifierRestingHeartRate" => HealthMetricKind.RestingHeartRate,
                    "HKQuantityTypeIdentifierActiveEnergyBurned" => HealthMetricKind.ActiveCalories,
                    "HKQuantityTypeIdentifierAppleSleepingHours" => HealthMetricKind.SleepHours,
                    _ => null
                };
                if (kind.HasValue) added.Add(new HealthSample(kind.Value, val, DateTimeOffset.UtcNow));
            }
            lock (_lock) _samples.AddRange(added);
            return added.Count;
        }

        public void ClearData()
        {
            lock (_lock) _samples.Clear();
        }

        public (int TotalSteps, double? AvgRestingHr, double? AvgSleepHours, IReadOnlyList<HealthTrendWarning> Warnings) ComputeDigest()
        {
            lock (_lock)
            {
                if (!_optedIn) return (0, null, null, Array.Empty<HealthTrendWarning>());

                int steps = (int)_samples.Where(s => s.Metric == HealthMetricKind.Steps).Sum(s => s.Value);
                var rhrList = _samples.Where(s => s.Metric == HealthMetricKind.RestingHeartRate).Select(s => s.Value).ToList();
                var sleepList = _samples.Where(s => s.Metric == HealthMetricKind.SleepHours).Select(s => s.Value).ToList();
                double? avgRhr = rhrList.Count > 0 ? rhrList.Average() : null;
                double? avgSleep = sleepList.Count > 0 ? sleepList.Average() : null;

                var warnings = new List<HealthTrendWarning>();
                if (avgRhr >= 85)
                    warnings.Add(new("Elevated Resting Heart Rate", $"Resting HR averages {(int)avgRhr.Value} bpm."));
                if (avgSleep < 6.0)
                    warnings.Add(new("Sleep Deficit Trend", $"Average sleep is {avgSleep.Value:F1} hrs (< 6.0 hrs)."));

                return (steps, avgRhr, avgSleep, warnings);
            }
        }
    }
}

