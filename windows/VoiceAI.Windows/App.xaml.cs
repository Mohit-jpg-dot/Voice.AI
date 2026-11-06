using System;
using Microsoft.UI.Xaml;
using H.NotifyIcon;
using VoiceAI.Windows.Views;

namespace VoiceAI.Windows
{
    public partial class App : Application
    {
        private TopCenterIslandWindow? _islandWindow;
        private TaskbarIcon? _trayIcon;

        public App()
        {
            this.InitializeComponent();
        }

        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            _islandWindow = new TopCenterIslandWindow();
            _islandWindow.Activate();

            SetupSystemTray();
        }

        private void SetupSystemTray()
        {
            _trayIcon = new TaskbarIcon
            {
                ToolTipText = "Voice.AI — Top-Center Floating Voice Island",
                IconSource = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri("ms-appx:///Assets/Square44x44Logo.png"))
            };

            _trayIcon.TrayLeftMouseDown += (s, e) =>
            {
                if (_islandWindow != null)
                {
                    _islandWindow.Activate();
                }
            };
        }
    }
}
