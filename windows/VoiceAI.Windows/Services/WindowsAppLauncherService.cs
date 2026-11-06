using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

namespace VoiceAI.Windows.Services
{
    /// <summary>
    /// Service for discovering and launching applications and URI schemes on Windows.
    /// </summary>
    public class WindowsAppLauncherService
    {
        private static readonly Dictionary<string, string> StandardAppMap = new(StringComparer.OrdinalIgnoreCase)
        {
            { "spotify", "spotify:" },
            { "whatsapp", "whatsapp:" },
            { "chrome", "chrome" },
            { "google chrome", "chrome" },
            { "edge", "msedge" },
            { "microsoft edge", "msedge" },
            { "notepad", "notepad" },
            { "calculator", "calc" },
            { "calc", "calc" },
            { "terminal", "wt" },
            { "powershell", "powershell" },
            { "settings", "ms-settings:" },
            { "vs code", "code" },
            { "code", "code" }
        };

        public bool LaunchApp(string appName)
        {
            var cleanName = appName.Trim().ToLowerInvariant();

            if (StandardAppMap.TryGetValue(cleanName, out var target))
            {
                return StartProcessOrUri(target);
            }

            return StartProcessOrUri(cleanName);
        }

        private static bool StartProcessOrUri(string target)
        {
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = target,
                    UseShellExecute = true
                });
                return true;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[WindowsAppLauncherService] Failed to launch {target}: {ex.Message}");
                return false;
            }
        }
    }
}

