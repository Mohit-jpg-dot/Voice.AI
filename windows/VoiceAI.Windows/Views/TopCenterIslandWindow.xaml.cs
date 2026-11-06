using System;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using VoiceAI.Core.Brain;

namespace VoiceAI.Windows.Views
{
    public sealed partial class TopCenterIslandWindow : Window
    {
        private const int GWL_EXSTYLE = -20;
        private const int WS_EX_NOACTIVATE = 0x08000000;
        private const int WS_EX_TOPMOST = 0x00000008;

        [DllImport("user32.dll")]
        private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll")]
        private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        private Action<bool>? _pendingApprovalCallback;

        public TopCenterIslandWindow()
        {
            this.InitializeComponent();
            ConfigureWindowStyle();
        }

        private void ConfigureWindowStyle()
        {
            var hWnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            if (hWnd != IntPtr.Zero)
            {
                int exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
                SetWindowLong(hWnd, GWL_EXSTYLE, exStyle | WS_EX_NOACTIVATE | WS_EX_TOPMOST);
            }
        }

        public void SetState(string state, string message, string? transcript = null)
        {
            DispatcherQueue.TryEnqueue(() =>
            {
                StatusLabel.Text = state;
                ResponseText.Text = message;

                if (!string.IsNullOrEmpty(transcript))
                {
                    TranscriptText.Text = $"\"{transcript}\"";
                    TranscriptText.Visibility = Visibility.Visible;
                }
                else
                {
                    TranscriptText.Visibility = Visibility.Collapsed;
                }

                StatusDot.Fill = state switch
                {
                    "Listening" => new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.DeepSkyBlue),
                    "Thinking" => new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Orange),
                    "Speaking" => new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.LimeGreen),
                    "Error" => new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Crimson),
                    _ => new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Gray)
                };
            });
        }

        public void RequestApproval(string actionDetails, Action<bool> callback)
        {
            _pendingApprovalCallback = callback;
            DispatcherQueue.TryEnqueue(() =>
            {
                ApprovalDetails.Text = actionDetails;
                ApprovalCard.Visibility = Visibility.Visible;
            });
        }

        private void BtnApprove_Click(object sender, RoutedEventArgs e)
        {
            ApprovalCard.Visibility = Visibility.Collapsed;
            _pendingApprovalCallback?.Invoke(true);
            _pendingApprovalCallback = null;
        }

        private void BtnReject_Click(object sender, RoutedEventArgs e)
        {
            ApprovalCard.Visibility = Visibility.Collapsed;
            _pendingApprovalCallback?.Invoke(false);
            _pendingApprovalCallback = null;
        }
    }
}
