using System;

namespace Runner
{
    // Pure geometry: no Tizen runtime needed to test physical bounds and crop.
    internal static class VideoGeometry
    {
        public static (int X, int Y, int Width, int Height,
            float SourceX, float SourceY, float SourceWidth, float SourceHeight)
            Calculate(int x, int y, int width, int height, int videoWidth, int videoHeight, int fit)
        {
            if (width <= 0 || height <= 0 || fit < 0 || fit > 2) throw new ArgumentOutOfRangeException();
            if (videoWidth <= 0 || videoHeight <= 0) return (x, y, width, height, 0, 0, 1, 1);
            double aspect = (double)videoWidth / videoHeight;
            double viewport = (double)width / height;
            if (fit == 0)
            {
                int w = Math.Max(1, (int)Math.Round(Math.Min(width, height * aspect)));
                int h = Math.Max(1, (int)Math.Round(Math.Min(height, width / aspect)));
                return (x + (width - w) / 2, y + (height - h) / 2, w, h, 0, 0, 1, 1);
            }
            float sourceWidth = fit == 1 ? (float)Math.Min(1, viewport / aspect) : 1;
            float sourceHeight = fit == 1 ? (float)Math.Min(1, aspect / viewport) : 1;
            return (x, y, width, height, (1 - sourceWidth) / 2, (1 - sourceHeight) / 2, sourceWidth, sourceHeight);
        }
    }
}
