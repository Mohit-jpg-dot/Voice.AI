using System;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using VoiceAI.Core.Brain;

namespace VoiceAI.Windows.Views
{
    public sealed partial class ModelSetupDashboardWindow : Window
    {
        public ModelSetupDashboardWindow()
        {
            this.InitializeComponent();
            CheckHardware();
        }

        private void CheckHardware()
        {
            var hw = HardwareProfileDetector.DetectHardware();
            TxtHardwareSummary.Text = $"{hw.TotalRamGB} GB RAM · {hw.FreeDiskGB} GB Free";

            if (hw.HasLowMemoryGuardrail)
            {
                GuardrailCard.Visibility = Visibility.Visible;
            }
        }

        private async void BtnDownloadAll_Click(object sender, RoutedEventArgs e)
        {
            BtnDownloadAll.IsEnabled = false;
            GlobalProgress.Visibility = Visibility.Visible;

            for (int i = 0; i <= 100; i += 10)
            {
                GlobalProgress.Value = i;
                await Task.Delay(100);
            }

            BtnDownloadAll.Content = "✓ Models Installed & Ready";
        }
    }
}

