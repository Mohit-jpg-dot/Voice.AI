using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using H.NotifyIcon;

namespace VoiceOS.Windows
{
    public partial class App : Application
    {
        private Window? _mainWindow;
        private TaskbarIcon? _trayIcon;

        public App()
        {
            this.InitializeComponent();
        }

        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            _mainWindow = new MainWindow();
            _mainWindow.Activate();

            SetupSystemTray();
        }

        private void SetupSystemTray()
        {
            _trayIcon = new TaskbarIcon
            {
                ToolTipText = "VoiceOS — Voice Assistant for Windows 11",
                IconSource = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri("ms-appx:///Assets/Square44x44Logo.png"))
            };

            _trayIcon.TrayLeftMouseDown += (s, e) =>
            {
                if (_mainWindow != null)
                {
                    if (_mainWindow.Visible)
                        _mainWindow.Hide();
                    else
                        _mainWindow.Show();
                }
            };
        }
    }
}

