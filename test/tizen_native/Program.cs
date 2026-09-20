using System;
using Runner;

var count = 0;
void Check(bool value, string label)
{
    if (!value) throw new Exception(label);
    count++;
}
bool Near(float actual, float expected) => Math.Abs(actual - expected) < 0.0001f;

var letterbox = VideoGeometry.Calculate(100, 200, 600, 300, 1920, 1080, 0);
Check((letterbox.X, letterbox.Y, letterbox.Width, letterbox.Height) == (133, 200, 533, 300),
    "Contain must preserve aspect inside a non-fullscreen physical rectangle");
Check(letterbox.SourceWidth == 1 && letterbox.SourceHeight == 1, "Contain must not crop");
var classic = VideoGeometry.Calculate(0, 0, 1920, 1080, 640, 480, 0);
Check((classic.X, classic.Y, classic.Width, classic.Height) == (240, 0, 1440, 1080), "4:3 pillarbox");
var wide = VideoGeometry.Calculate(0, 0, 1920, 1080, 1920, 800, 0);
Check((wide.X, wide.Y, wide.Width, wide.Height) == (0, 140, 1920, 800), "Wide letterbox");
var cover = VideoGeometry.Calculate(100, 200, 600, 300, 640, 480, 1);
Check((cover.X, cover.Y, cover.Width, cover.Height) == (100, 200, 600, 300), "Cover destination");
Check(Near(cover.SourceY, 1f / 6) && Near(cover.SourceHeight, 2f / 3) && cover.SourceWidth == 1,
    "Cover crops the source, never draws beyond its destination");
var coverWide = VideoGeometry.Calculate(0, 0, 600, 300, 2400, 1000, 1);
Check(Near(coverWide.SourceX, 1f / 12) && Near(coverWide.SourceWidth, 5f / 6), "Wide cover crop");
var fill = VideoGeometry.Calculate(100, 200, 600, 300, 640, 480, 2);
Check((fill.Width, fill.Height, fill.SourceWidth, fill.SourceHeight) == (600, 300, 1f, 1f), "Fill");
var unknown = VideoGeometry.Calculate(0, 0, 1920, 1080, 0, 0, 0);
Check(unknown.Width == 1920 && unknown.Height == 1080, "Before preparation, use the viewport");
var tiny = VideoGeometry.Calculate(0, 0, 1, 1, 3840, 2160, 0);
Check(tiny.Width == 1 && tiny.Height == 1, "Rounding must never create a zero-size ROI");
var invalid = false;
try { VideoGeometry.Calculate(0, 0, 0, 1080, 1920, 1080, 0); }
catch (ArgumentOutOfRangeException) { invalid = true; }
Check(invalid, "Reject an invalid viewport");
Console.WriteLine($"Video geometry: {count} checks passed.");
