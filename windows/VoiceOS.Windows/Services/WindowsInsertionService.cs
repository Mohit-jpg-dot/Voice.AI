using System;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Windows.ApplicationModel.DataTransfer;

namespace VoiceOS.Windows.Services
{
    public interface IWindowsInsertionService
    {
        Task<bool> InsertTextAsync(string text);
        bool IsTargetWindowElevated(IntPtr hWnd);
    }

    public class WindowsInsertionService : IWindowsInsertionService
    {
        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool GetTokenInformation(IntPtr TokenHandle, int TokenInformationClass, IntPtr TokenInformation, uint TokenInformationLength, out uint ReturnLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint processAccess, bool bInheritHandle, uint processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr hObject);

        [DllImport("user32.dll")]
        private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        private const byte VK_CONTROL = 0x11;
        private const byte VK_V = 0x56;
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        private const uint TOKEN_QUERY = 0x0008;

        public bool IsTargetWindowElevated(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero) return false;
            GetWindowThreadProcessId(hWnd, out uint processId);
            IntPtr hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, processId);
            if (hProcess == IntPtr.Zero) return true; // Access denied usually implies elevated target

            try
            {
                if (OpenProcessToken(hProcess, TOKEN_QUERY, out IntPtr hToken))
                {
                    try
                    {
                        // TokenElevation = 20
                        int elevationType = 0;
                        int size = sizeof(int);
                        IntPtr pElevation = Marshal.AllocHGlobal(size);
                        try
                        {
                            if (GetTokenInformation(hToken, 20, pElevation, (uint)size, out _))
                            {
                                elevationType = Marshal.ReadInt32(pElevation);
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

        public async Task<bool> InsertTextAsync(string text)
        {
            IntPtr fgWindow = GetForegroundWindow();
            if (IsTargetWindowElevated(fgWindow))
            {
                // Target is running as Administrator; cannot inject keystrokes via non-elevated VoiceOS
                // Fallback to clipboard without synthetic paste, notify user
                var dp = new DataPackage();
                dp.SetText(text);
                Clipboard.SetContent(dp);
                return false;
            }

            // 1. Save existing clipboard content
            string originalText = string.Empty;
            try
            {
                var content = Clipboard.GetContent();
                if (content.Contains(StandardDataFormats.Text))
                {
                    originalText = await content.GetTextAsync();
                }
            }
            catch { }

            // 2. Set new text to clipboard
            var package = new DataPackage();
            package.SetText(text);
            Clipboard.SetContent(package);

            // 3. Simulate Ctrl + V
            keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
            keybd_event(VK_V, 0, 0, UIntPtr.Zero);
            keybd_event(VK_V, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);

            // 4. Restore original clipboard after brief delay
            _ = Task.Delay(250).ContinueWith(_ =>
            {
                if (!string.IsNullOrEmpty(originalText))
                {
                    var restorePackage = new DataPackage();
                    restorePackage.SetText(originalText);
                    Clipboard.SetContent(restorePackage);
                }
            });

            return true;
        }
    }
}

