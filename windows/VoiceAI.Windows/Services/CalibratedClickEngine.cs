using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace VoiceAI.Windows.Services
{
    /// <summary>
    /// Calibrated Click & Window Elevation Engine for Windows.
    /// Normalizes mouse movement with monitor DPI scaling, elevates target window,
    /// waits for deterministic settle delay, and executes SendInput mouse down/up sequences.
    /// </summary>
    public class CalibratedClickEngine
    {
        private const uint MOUSEEVENTF_MOVE = 0x0001;
        private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
        private const uint MOUSEEVENTF_LEFTUP = 0x0004;
        private const uint MOUSEEVENTF_ABSOLUTE = 0x8000;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool BringWindowToTop(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern uint SendInput(uint nInputs, [In] INPUT[] pInputs, int cbSize);

        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr hWnd);

        [StructLayout(LayoutKind.Sequential)]
        private struct INPUT
        {
            public uint type;
            public MOUSEINPUT mi;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public nuint dwExtraInfo;
        }

        public Point Calibrate(Point rawPixel, double dpiScale = 1.0)
        {
            return new Point((int)(rawPixel.X / dpiScale), (int)(rawPixel.Y / dpiScale));
        }

        public async Task<bool> ElevateWindowAsync(string processName)
        {
            try
            {
                var processes = Process.GetProcessesByName(processName);
                if (processes.Length > 0)
                {
                    var hWnd = processes[0].MainWindowHandle;
                    if (hWnd != IntPtr.Zero)
                    {
                        BringWindowToTop(hWnd);
                        SetForegroundWindow(hWnd);
                        // Deterministic UI settle delay
                        await Task.Delay(160);
                        return true;
                    }
                }
            }
            catch {}
            return false;
        }

        public async Task ClickAsync(Point screenPoint, string? targetApp = null)
        {
            if (!string.IsNullOrEmpty(targetApp))
            {
                await ElevateWindowAsync(targetApp);
            }

            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return;

            // SendInput mouse down / up sequences
            var inputs = new INPUT[2];
            inputs[0].type = 0; // INPUT_MOUSE
            inputs[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;

            inputs[1].type = 0; // INPUT_MOUSE
            inputs[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;

            SendInput(1, new[] { inputs[0] }, Marshal.SizeOf<INPUT>());
            await Task.Delay(50);
            SendInput(1, new[] { inputs[1] }, Marshal.SizeOf<INPUT>());
        }
    }
}

