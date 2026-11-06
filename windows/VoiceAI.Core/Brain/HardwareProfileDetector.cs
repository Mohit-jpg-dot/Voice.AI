using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

namespace VoiceAI.Core.Brain
{
    public struct MemoryStatusEx
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    public class ModelCatalogItem
    {
        public string Id { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string RoleTitle { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public string PurposeDescription { get; set; } = string.Empty;
        public int DownloadSizeMB { get; set; }
        public double RamRequiredGB { get; set; }
        public string Command { get; set; } = string.Empty;
        public string DownloadUrl { get; set; } = string.Empty;
        public bool IsCore { get; set; }
    }

    public class HardwareSpecification
    {
        public double TotalRamGB { get; set; }
        public double FreeDiskGB { get; set; }
        public bool HasLowMemoryGuardrail { get; set; }
        public string? GuardrailWarning { get; set; }
        public string RecommendedMode { get; set; } = "Hybrid (Local Brain + Cloud Vision)";
    }

    /// <summary>
    /// Detects Windows system hardware (RAM via GlobalMemoryStatusEx, free disk)
    /// and enforces safety guardrails to prevent OOM lockups when running 7B Vision models.
    /// </summary>
    public static class HardwareProfileDetector
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GlobalMemoryStatusEx(ref MemoryStatusEx lpBuffer);

        public static HardwareSpecification DetectHardware()
        {
            double ramGB = 16.0; // Default fallback
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                var memStatus = new MemoryStatusEx();
                memStatus.dwLength = (uint)Marshal.SizeOf(typeof(MemoryStatusEx));
                if (GlobalMemoryStatusEx(ref memStatus))
                {
                    ramGB = memStatus.ullTotalPhys / (1024.0 * 1024.0 * 1024.0);
                }
            }

            double freeDiskGB = 50.0;
            try
            {
                var systemDrive = Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\";
                var driveInfo = new DriveInfo(systemDrive);
                freeDiskGB = driveInfo.AvailableFreeSpace / (1024.0 * 1024.0 * 1024.0);
            }
            catch {}

            bool lowMem = ramGB <= 8.5;
            string? warning = lowMem
                ? "⚠️ 8 GB RAM Guardrail: Running 7B Vision models locally on 8GB systems may cause memory pressure. We recommend Hybrid Mode (Local Brain 3B + Cloud Vision API) for lockup-free performance."
                : null;

            return new HardwareSpecification
            {
                TotalRamGB = System.Math.Round(ramGB, 1),
                FreeDiskGB = System.Math.Round(freeDiskGB, 1),
                HasLowMemoryGuardrail = lowMem,
                GuardrailWarning = warning,
                RecommendedMode = lowMem ? "Hybrid (Local Brain + Cloud Vision)" : "100% Local Offline"
            };
        }

        public static List<ModelCatalogItem> GetCoreThreeModels()
        {
            return new List<ModelCatalogItem>
            {
                new ModelCatalogItem
                {
                    Id = "brain.llama3.2.3b",
                    Name = "Llama-3.2-3B",
                    RoleTitle = "The Brain",
                    Category = "brain",
                    PurposeDescription = "Understands colloquial Hinglish/Hindi text commands & breaks down multi-step goals into structured JSON plans.",
                    DownloadSizeMB = 2500,
                    RamRequiredGB = 3.5,
                    Command = "ollama pull llama3.2:3b",
                    DownloadUrl = "http://localhost:11434/api/pull?name=llama3.2:3b",
                    IsCore = true
                },
                new ModelCatalogItem
                {
                    Id = "vision.qwen2vl.7b",
                    Name = "Qwen2-VL-7B",
                    RoleTitle = "The Eyes",
                    Category = "vision",
                    PurposeDescription = "Inspects display screenshots, tracks clickable boundaries, and identifies target UI buttons via Set-of-Mark visual grounding.",
                    DownloadSizeMB = 5200,
                    RamRequiredGB = 6.0,
                    Command = "ollama pull qwen2-vl:7b",
                    DownloadUrl = "http://localhost:11434/api/pull?name=qwen2-vl:7b",
                    IsCore = true
                },
                new ModelCatalogItem
                {
                    Id = "voice.kokoro.82m",
                    Name = "Kokoro-82M",
                    RoleTitle = "The Voice",
                    Category = "voice",
                    PurposeDescription = "Ultra-fast, natural multilingual text-to-speech synthesis with zero internet lag.",
                    DownloadSizeMB = 300,
                    RamRequiredGB = 0.5,
                    Command = "kokoro-tts serve --port 8880",
                    DownloadUrl = "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/kokoro-v0_19.onnx",
                    IsCore = true
                }
            };
        }
    }
}
