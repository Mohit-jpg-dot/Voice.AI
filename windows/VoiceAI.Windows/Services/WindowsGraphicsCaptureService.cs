using System;
using System.Drawing;
using System.Threading.Tasks;

namespace VoiceOS.Windows.Services
{
    public interface IWindowsCaptureService
    {
        Task<Bitmap?> CaptureRegionAsync(Rectangle bounds);
        bool IsScreenCaptureSupported();
    }

    public class WindowsGraphicsCaptureService : IWindowsCaptureService
    {
        public bool IsScreenCaptureSupported()
        {
            // Windows.Graphics.Capture is supported on Windows 10 build 1803+ and Windows 11
            return Environment.OSVersion.Version.Major >= 10;
        }

        public async Task<Bitmap?> CaptureRegionAsync(Rectangle bounds)
        {
            if (bounds.Width <= 0 || bounds.Height <= 0) return null;

            await Task.Yield();
            var bitmap = new Bitmap(bounds.Width, bounds.Height);
            using (var g = Graphics.FromImage(bitmap))
            {
                g.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size);
            }
            return bitmap;
        }
    }
}

