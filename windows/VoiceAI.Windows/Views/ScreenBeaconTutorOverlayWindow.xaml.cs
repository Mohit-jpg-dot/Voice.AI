using System;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace VoiceAI.Windows.Views
{
    public sealed partial class ScreenBeaconTutorOverlayWindow : Window
    {
        private const int GWL_EXSTYLE = -20;
        private const int WS_EX_TRANSPARENT = 0x00000020;
        private const int WS_EX_LAYERED = 0x00080000;
        private const int WS_EX_NOACTIVATE = 0x08000000;
        private const int WS_EX_TOPMOST = 0x00000008;

        [DllImport("user32.dll")]
        private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll")]
        private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        public ScreenBeaconTutorOverlayWindow()
        {
            this.InitializeComponent();
            ConfigureTransparentPassThrough();
        }

        private void ConfigureTransparentPassThrough()
        {
            var hWnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            if (hWnd != IntPtr.Zero)
            {
                int exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
                SetWindowLong(hWnd, GWL_EXSTYLE, exStyle | WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TOPMOST);
            }
        }

        public void GuideUser(int x, int y, string label)
        {
            DispatcherQueue.TryEnqueue(() =>
            {
                TxtInstruction.Text = label;

                Canvas.SetLeft(OuterRipple, x - 40);
                Canvas.SetTop(OuterRipple, y - 40);

                Canvas.SetLeft(InnerRing, x - 18);
                Canvas.SetTop(InnerRing, y - 18);

                Canvas.SetLeft(CenterDot, x - 3);
                Canvas.SetTop(CenterDot, y - 3);

                Canvas.SetLeft(InstructionBadge, x - 50);
                Canvas.SetTop(InstructionBadge, y - 80);

                this.Activate();
            });
        }
    }
}

