// Host structure adapted from George-Fam/plezy-tizen (GPL-3.0).
using Tizen.Flutter.Embedding;

namespace Runner
{
    public class App : FlutterApplication
    {
        private TizenMediaPlayer player;

        public App()
        {
            IsWindowTransparent = true;
            // The video plane lives in a second, normally-stacked window. Lowering that
            // window put it below the TV launcher, so the transparent UI showed the TV
            // instead of the picture. Raise Flutter's window above it instead; the video
            // window then sits between the launcher and the controls.
            IsTopLevel = true;
            // Flutter owns the only remote-input path; no native key grabs.
            IsPointingDeviceSupport = false;
            IsFloatingMenuSupport = false;
        }

        protected override void OnCreate()
        {
            base.OnCreate();
            GeneratedPluginRegistrant.RegisterPlugins(this);
            player = new TizenMediaPlayer();
        }

        protected override void OnPause()
        {
            player?.Suspend();
            base.OnPause();
        }

        protected override void OnResume()
        {
            base.OnResume();
            player?.Resume();
        }

        protected override void OnTerminate()
        {
            player?.Dispose();
            base.OnTerminate();
        }

        static void Main(string[] args) => new App().Run(args);
    }
}
