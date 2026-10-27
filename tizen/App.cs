// Host structure adapted from George-Fam/plezy-tizen (GPL-3.0).
using Tizen.Flutter.Embedding;

namespace Runner
{
    public class App : FlutterApplication
    {
        private TizenMediaPlayer player;
        // The channel the embedder's own lifecycle messages travel on.
        private BasicMessageChannel<string> lifecycle;

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
            lifecycle = new BasicMessageChannel<string>("flutter/lifecycle", new StringCodec());
        }

        protected override void OnPause()
        {
            player?.Suspend();
            // Not base.OnPause(): the embedder would also mark the view unfocused, and the next
            // focus change in Plezy, such as a refresh landing, would then have the embedder
            // activate this window over the TV launcher. Dart still sees the same pause.
            lifecycle.Send("AppLifecycleState.paused");
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
