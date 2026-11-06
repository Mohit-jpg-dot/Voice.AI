using System;
using Microsoft.UI.Xaml;
using VoiceAI.Windows.Services;

namespace VoiceAI.Windows.Views
{
    public sealed partial class SetupWizardWindow : Window
    {
        private readonly WindowsAudioCaptureService _audioService = new();
        private readonly WindowsCredentialManagerService _credentialManager = new();

        public event Action? OnSetupCompleted;

        public SetupWizardWindow()
        {
            this.InitializeComponent();
            RbPaidCloud.Checked += (s, e) => CloudKeyPanel.Visibility = Visibility.Visible;
            RbFreeOffline.Checked += (s, e) => CloudKeyPanel.Visibility = Visibility.Collapsed;
            RbGoogleSearch.Checked += (s, e) => CloudKeyPanel.Visibility = Visibility.Collapsed;
        }

        private void BtnTestMic_Click(object sender, RoutedEventArgs e)
        {
            if (_audioService.CheckMicrophonePermission())
            {
                MicStatusLabel.Text = "✓ Microphone is enabled and ready!";
                MicStatusLabel.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.LimeGreen);
            }
            else
            {
                MicStatusLabel.Text = "⚠️ Access denied. Opening Windows Microphone Settings...";
                MicStatusLabel.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Orange);
                _audioService.OpenMicrophonePrivacySettings();
            }
        }

        private void BtnComplete_Click(object sender, RoutedEventArgs e)
        {
            var accountId = string.IsNullOrWhiteSpace(TxtAccountId.Text) ? "default" : TxtAccountId.Text.Trim();

            if (RbPaidCloud.IsChecked == true && !string.IsNullOrWhiteSpace(TxtApiKey.Password))
            {
                _credentialManager.SaveCredential(accountId, "OpenAI_ApiKey", TxtApiKey.Password);
            }

            OnSetupCompleted?.Invoke();
            this.Close();
        }
    }
}
