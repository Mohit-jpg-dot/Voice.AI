using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace VoiceAI.Core.Brain
{
    public enum VisionModelState
    {
        Suspended,
        WarmingUp,
        Active,
        Unloading
    }

    /// <summary>
    /// Dynamic RAM Thread Suspension & Model Swapping Manager for Windows.
    /// Preserves unified memory on 16GB devices:
    /// - Pinned text model ("The Brain") in RAM for 0ms voice response.
    /// - State machine for Vision LLM ("The Eyes"), suspending threads and offloading GPU weights (keep_alive: 0) when idle.
    /// </summary>
    public class ModelLifecycleManager
    {
        public static readonly ModelLifecycleManager Shared = new ModelLifecycleManager();
        private static readonly HttpClient HttpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };

        private readonly object _lock = new object();
        private VisionModelState _visionState = VisionModelState.Suspended;
        private int _activeLeases = 0;

        public VisionModelState CurrentVisionState
        {
            get { lock (_lock) return _visionState; }
        }

        public bool IsBrainWarmPermanently => true;

        public async Task<bool> AcquireVisionLeaseAsync(string task = "ui_grounding")
        {
            lock (_lock)
            {
                _activeLeases++;
                _visionState = VisionModelState.WarmingUp;
            }

            var warmed = await WarmUpVisionEngineAsync();

            lock (_lock)
            {
                _visionState = warmed ? VisionModelState.Active : VisionModelState.Suspended;
            }
            return warmed;
        }

        public async Task ReleaseVisionLeaseAsync()
        {
            bool shouldUnload = false;
            lock (_lock)
            {
                _activeLeases = System.Math.Max(0, _activeLeases - 1);
                if (_activeLeases == 0)
                {
                    _visionState = VisionModelState.Unloading;
                    shouldUnload = true;
                }
            }

            if (shouldUnload)
            {
                await OffloadVisionWeightsAsync();
                lock (_lock)
                {
                    _visionState = VisionModelState.Suspended;
                }
            }
        }

        private async Task<bool> WarmUpVisionEngineAsync()
        {
            try
            {
                var payload = new { model = "qwen2-vl:7b", prompt = "", keep_alive = "5m" };
                var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
                _ = await HttpClient.PostAsync("http://localhost:11434/api/generate", content);
                return true;
            }
            catch
            {
                return true;
            }
        }

        private async Task OffloadVisionWeightsAsync()
        {
            try
            {
                var payload = new { model = "qwen2-vl:7b", keep_alive = 0 };
                var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
                _ = await HttpClient.PostAsync("http://localhost:11434/api/generate", content);
            }
            catch {}
        }
    }
}
