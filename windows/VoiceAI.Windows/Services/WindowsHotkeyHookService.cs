using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace VoiceAI.Windows.Services
{
    public enum HotkeyTriggerType
    {
        Tap,
        HoldStart,
        HoldEnd
    }

    /// <summary>
    /// Global low-level keyboard hook (WH_KEYBOARD_LL) for hold-to-talk interaction
    /// with a configurable 250ms hold threshold without stealing foreground window focus.
    /// </summary>
    public class WindowsHotkeyHookService : IDisposable
    {
        private const int WH_KEYBOARD_LL = 13;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_KEYUP = 0x0101;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int WM_SYSKEYUP = 0x0105;

        // Default hotkey: Right Control (0xA3) or Right Alt / Menu (0xA5)
        public int TargetVirtualKey { get; set; } = 0xA3; // VK_RCONTROL
        public int HoldThresholdMs { get; set; } = 250;

        public event Action? OnHoldStart;
        public event Action? OnHoldEnd;
        public event Action? OnTap;

        private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
        private LowLevelKeyboardProc? _proc;
        private IntPtr _hookId = IntPtr.Zero;

        private long _keyDownTimestamp;
        private bool _isHolding;

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr GetModuleHandle(string lpModuleName);

        public void Start()
        {
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return;

            _proc = HookCallback;
            using var curProcess = Process.GetCurrentProcess();
            using var curModule = curProcess.MainModule;
            var modHandle = curModule != null ? GetModuleHandle(curModule.ModuleName) : IntPtr.Zero;
            _hookId = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, modHandle, 0);
        }

        public void Stop()
        {
            if (_hookId != IntPtr.Zero)
            {
                UnhookWindowsHookEx(_hookId);
                _hookId = IntPtr.Zero;
            }
        }

        private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0)
            {
                int vkCode = Marshal.ReadInt32(lParam);
                if (vkCode == TargetVirtualKey)
                {
                    int msg = wParam.ToInt32();
                    if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
                    {
                        if (_keyDownTimestamp == 0)
                        {
                            _keyDownTimestamp = Stopwatch.GetTimestamp();
                            _isHolding = false;
                        }
                        else
                        {
                            double elapsedMs = (Stopwatch.GetTimestamp() - _keyDownTimestamp) * 1000.0 / Stopwatch.Frequency;
                            if (elapsedMs >= HoldThresholdMs && !_isHolding)
                            {
                                _isHolding = true;
                                OnHoldStart?.Invoke();
                            }
                        }
                    }
                    else if (msg == WM_KEYUP || msg == WM_SYSKEYUP)
                    {
                        if (_keyDownTimestamp != 0)
                        {
                            double elapsedMs = (Stopwatch.GetTimestamp() - _keyDownTimestamp) * 1000.0 / Stopwatch.Frequency;
                            _keyDownTimestamp = 0;

                            if (_isHolding)
                            {
                                _isHolding = false;
                                OnHoldEnd?.Invoke();
                                return (IntPtr)1; // Consume key release after hold
                            }
                            else if (elapsedMs < HoldThresholdMs)
                            {
                                OnTap?.Invoke();
                            }
                        }
                    }
                }
            }
            return CallNextHookEx(_hookId, nCode, wParam, lParam);
        }

        public void Dispose()
        {
            Stop();
            GC.SuppressFinalize(this);
        }
    }
}

