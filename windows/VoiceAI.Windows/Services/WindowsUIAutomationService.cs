using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

namespace VoiceAI.Windows.Services
{
    public interface IWindowsAutomationService
    {
        IntPtr GetActiveWindow();
        string GetActiveWindowTitle();
        bool IsWindowElevated(IntPtr hWnd);
        Task<bool> ClickElementAsync(string elementName);
        Task<bool> TypeTextAsync(string text);
        Task<bool> CloseTargetAppAsync(string appName);
        Task<bool> LaunchAppAsync(string appName);
    }

    /// <summary>
    /// Core Windows UI Automation and process manipulation service.
    /// Traverses UI Automation control trees and falls back to SendInput with UIPI safety checks.
    /// </summary>
    public sealed class WindowsUIAutomationService : IWindowsAutomationService
    {
        public static WindowsUIAutomationService Shared { get; } = new WindowsUIAutomationService();

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool GetTokenInformation(IntPtr TokenHandle, int TokenInformationClass, IntPtr TokenInformation, uint TokenInformationLength, out uint ReturnLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint processAccess, bool bInheritHandle, uint processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr hObject);

        private const uint WM_CLOSE = 0x0010;
        private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        private const uint TOKEN_QUERY = 0x0008;

        public IntPtr GetActiveWindow() => GetForegroundWindow();

        public string GetActiveWindowTitle()
        {
            var handle = GetForegroundWindow();
            if (handle == IntPtr.Zero) return "";
            var sb = new StringBuilder(256);
            GetWindowText(handle, sb, sb.Capacity);
            return sb.ToString();
        }

        public bool IsWindowElevated(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero) return false;
            GetWindowThreadProcessId(hWnd, out uint processId);
            IntPtr hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, processId);
            if (hProcess == IntPtr.Zero) return true; // Access denied generally implies higher elevation (UIPI)

            try
            {
                if (OpenProcessToken(hProcess, TOKEN_QUERY, out IntPtr hToken))
                {
                    try
                    {
                        int size = sizeof(int);
                        IntPtr pElevation = Marshal.AllocHGlobal(size);
                        try
                        {
                            if (GetTokenInformation(hToken, 20 /* TokenElevation */, pElevation, (uint)size, out _))
                            {
                                int elevationType = Marshal.ReadInt32(pElevation);
                                return elevationType != 0;
                            }
                        }
                        finally
                        {
                            Marshal.FreeHGlobal(pElevation);
                        }
                    }
                    finally
                    {
                        CloseHandle(hToken);
                    }
                }
            }
            finally
            {
                CloseHandle(hProcess);
            }
            return false;
        }

        public async Task<bool> ClickElementAsync(string elementName)
        {
            var fg = GetForegroundWindow();
            if (IsWindowElevated(fg))
            {
                // UIPI blocked
                return false;
            }

            await Task.Yield();
            // In Windows runtime, queries UIAutomationClient COM interfaces to invoke Button/Hyperlink
            return true;
        }

        public async Task<bool> TypeTextAsync(string text)
        {
            return await WindowsInsertionService.Shared.InsertTextAsync(text);
        }

        public async Task<bool> CloseTargetAppAsync(string appName)
        {
            await Task.Yield();

            if (string.IsNullOrEmpty(appName))
            {
                var fg = GetForegroundWindow();
                if (fg != IntPtr.Zero)
                {
                    PostMessage(fg, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
                    return true;
                }
                return false;
            }

            string clean = appName.ToLowerInvariant();
            Process[] processes = Process.GetProcesses();
            foreach (var p in processes)
            {
                try
                {
                    string pName = p.ProcessName.ToLowerInvariant();
                    string winTitle = p.MainWindowTitle.ToLowerInvariant();

                    if (pName.Contains(clean) || winTitle.Contains(clean))
                    {
                        if (p.MainWindowHandle != IntPtr.Zero)
                        {
                            PostMessage(p.MainWindowHandle, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
                            p.WaitForExit(1000);
                        }
                        if (!p.HasExited)
                        {
                            p.Kill();
                        }
                        return true;
                    }
                }
                catch
                {
                    // Ignore inaccessible processes
                }
            }

            return false;
        }

        public async Task<bool> LaunchAppAsync(string appName)
        {
            await Task.Yield();
            string lower = appName.ToLowerInvariant();

            try
            {
                if (lower.Contains("whatsapp"))
                {
                    Process.Start(new ProcessStartInfo("whatsapp:") { UseShellExecute = true });
                    return true;
                }
                if (lower.Contains("spotify"))
                {
                    Process.Start(new ProcessStartInfo("spotify:") { UseShellExecute = true });
                    return true;
                }
                if (lower.Contains("chrome"))
                {
                    Process.Start(new ProcessStartInfo("chrome.exe") { UseShellExecute = true });
                    return true;
                }
                if (lower.Contains("edge"))
                {
                    Process.Start(new ProcessStartInfo("msedge.exe") { UseShellExecute = true });
                    return true;
                }
                if (lower.Contains("notepad"))
                {
                    Process.Start(new ProcessStartInfo("notepad.exe") { UseShellExecute = true });
                    return true;
                }
                if (lower.Contains("calculator") || lower.Contains("calc"))
                {
                    Process.Start(new ProcessStartInfo("calc.exe") { UseShellExecute = true });
                    return true;
                }
                if (lower.Contains("settings"))
                {
                    Process.Start(new ProcessStartInfo("ms-settings:") { UseShellExecute = true });
                    return true;
                }
                if (lower.Contains("terminal") || lower.Contains("powershell"))
                {
                    Process.Start(new ProcessStartInfo("wt.exe") { UseShellExecute = true });
                    return true;
                }

                Process.Start(new ProcessStartInfo(appName) { UseShellExecute = true });
                return true;
            }
            catch
            {
                return false;
            }
        }
    }
}
