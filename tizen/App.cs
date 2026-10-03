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
            // Not IsTopLevel: a notification-level window also stays above the TV launcher,
            // so Home played its sound but showed nothing. The player raises this window
            // over its separate video window instead, in the normal stack.
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
