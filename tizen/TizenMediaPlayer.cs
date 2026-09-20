// Adapted from George-Fam/plezy-tizen, native host commit 5235059d (GPL-3.0).
// Public Tizen 6.0 .NET APIs only. No DRM, P/Invoke, key grabs or window-manager stubs.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using ElmSharp;
using Tizen.Flutter.Embedding;
using Tizen.Multimedia;
using MediaPlayer = Tizen.Multimedia.Player;
using Rectangle = Tizen.Multimedia.Rectangle;

namespace Runner
{
    internal sealed class TizenMediaPlayer : IEventStreamHandler, IDisposable
    {
        private readonly SynchronizationContext main;
        private readonly MethodChannel methods = new MethodChannel("com.plezy/tizen_player");
        private readonly EventChannel events = new EventChannel("com.plezy/tizen_player/events");
        private readonly Window window = new Window("plezy-video");
        private IEventSink sink;
        private MediaPlayer player;
        private CancellationTokenSource preparing;
        private IntPtr timer;
        private int owner, session, generation, videoWidth, videoHeight;
        private bool disposed, subtitles, suspended, cropped;
        private float rate = 1;
        private Rectangle bounds;
        private PlayerDisplayMode displayMode = PlayerDisplayMode.LetterBox;

        public TizenMediaPlayer()
        {
            main = SynchronizationContext.Current ?? throw new InvalidOperationException("Tizen UI context missing");
            var size = window.ScreenSize;
            window.Resize(size.Width, size.Height);
            window.FocusSkip(true);
            bounds = new Rectangle(0, 0, size.Width, size.Height);
            methods.SetMethodCallHandler(Handle);
            events.SetStreamHandler(this);
        }

        private Task<object> Handle(MethodCall call)
        {
            var completion = new TaskCompletionSource<object>();
            main.Post(async _ =>
            {
                SynchronizationContext.SetSynchronizationContext(main);
                try { completion.SetResult(await Dispatch(call)); }
                // Never serialize native exception text: a decoder may include the authenticated URI.
                catch (Exception e) { completion.SetException(new InvalidOperationException("Tizen " + call.Method + " failed: " + e.GetType().Name)); }
            }, null);
            return completion.Task;
        }

        private async Task<object> Dispatch(MethodCall call)
        {
            if (disposed) throw new ObjectDisposedException(nameof(TizenMediaPlayer));
            var args = call.Arguments as IDictionary ?? new Hashtable();
            var requestedOwner = Convert.ToInt32(args["instanceId"]);
            if (call.Method == "open")
            {
                if (requestedOwner < owner) throw new OperationCanceledException();
                await Open(args); return null;
            }
            if (call.Method == "dispose")
            {
                if (owner == requestedOwner) Release();
                return null; // Explicit stale-owner disposal contract.
            }
            if (call.Method == "setVideoRect" && player == null)
            {
                SetRect(args); return null;
            }
            if (requestedOwner != owner || Convert.ToInt32(args["session"]) != session)
                throw new OperationCanceledException();
            switch (call.Method)
            {
                case "play": Play(); break;
                case "pause": Pause(); break;
                case "stop": Release(); break;
                case "seek":
                    var seekingPlayer = player;
                    var gen = generation;
                    await seekingPlayer.SetPlayPositionAsync(Convert.ToInt32(args["positionMs"]), false);
                    if (IsCurrent(gen, seekingPlayer)) Position();
                    break;
                case "selectAudioTrack":
                    var audio = Convert.ToInt32(args["index"]);
                    if (audio < 0) throw new NotSupportedException("Audio off is not supported");
                    player.AudioTrackInfo.Selected = audio;
                    Emit("audio", new Dictionary<string, object> { ["id"] = "audio:" + audio });
                    break;
                case "selectSubtitleTrack":
                    var subtitle = Convert.ToInt32(args["index"]);
                    subtitles = false;
                    if (subtitle >= 0) { player.SubtitleTrackInfo.Selected = subtitle; subtitles = true; }
                    // -1 means stop forwarding SubtitleUpdated, NOT an invalid native track index.
                    break;
                case "setVolume": player.Volume = (float)Math.Max(0, Math.Min(1, Convert.ToDouble(args["volume"]) / 100)); break;
                case "setRate":
                    rate = (float)Convert.ToDouble(args["rate"]);
                    if (player.State == PlayerState.Playing || player.State == PlayerState.Paused) player.SetPlaybackRate(rate);
                    break;
                case "setVideoRect": SetRect(args); ApplyRect(); break;
                case "setVisible":
                    if (Convert.ToBoolean(args["visible"])) { window.Show(); }
                    else window.Hide();
                    break;
                case "setDisplayMode":
                    var mode = Convert.ToInt32(args["mode"]);
                    if (mode < 0 || mode > 2) throw new ArgumentOutOfRangeException("mode");
                    displayMode = new[] { PlayerDisplayMode.LetterBox, PlayerDisplayMode.CroppedFull, PlayerDisplayMode.FullScreen }[mode];
                    ApplyRect();
                    break;
                default: throw new MissingPluginException();
            }
            return null;
        }

        private async Task Open(IDictionary args)
        {
            Release();
            owner = Convert.ToInt32(args["instanceId"]);
            session = Convert.ToInt32(args["session"]);
            var gen = generation;
            var uri = new Uri((string)args["url"], UriKind.Absolute);
            if (uri.Scheme != "https" && uri.Scheme != "http" && uri.Scheme != "file") throw new NotSupportedException();
            var opened = new MediaPlayer();
            player = opened;
            preparing = new CancellationTokenSource();
            var cancellation = preparing.Token;
            try
            {
                if (args["userAgent"] is string agent) opened.UserAgent = agent;
                opened.Volume = (float)Math.Max(0, Math.Min(1, Convert.ToDouble(args["volume"] ?? 100) / 100));
                rate = (float)Convert.ToDouble(args["rate"] ?? 1);
                displayMode = new[] { PlayerDisplayMode.LetterBox, PlayerDisplayMode.CroppedFull, PlayerDisplayMode.FullScreen }[Convert.ToInt32(args["displayMode"] ?? 0)];
                if (!(args["audioOnly"] is bool audioOnly && audioOnly))
                {
                    opened.Display = new Display(window);
                    // Every flutter-tizen video plugin sets this explicitly after the display:
                    // without it the overlay plane stays hidden and only audio reaches the TV.
                    opened.DisplaySettings.IsVisible = true;
                    ApplyRect();
                    if (!suspended) window.Show();
                }
                opened.PlaybackCompleted += (s, e) => Post(gen, opened, () =>
                {
                    StopTimer();
                    Emit("completed");
                });
                opened.BufferingProgressChanged += (s, e) => Post(gen, opened, () =>
                    Emit("buffering", new Dictionary<string, object> { ["value"] = e.Percent < 100 }));
                opened.SubtitleUpdated += (s, e) => Post(gen, opened, () =>
                {
                    if (subtitles) Emit("subtitle", new Dictionary<string, object> { ["text"] = e.Text ?? "", ["durationMs"] = (int)e.Duration });
                });
                opened.ErrorOccurred += (s, e) => Post(gen, opened, () =>
                {
                    StopTimer();
                    Emit("error", new Dictionary<string, object> { ["code"] = e.Error.ToString() });
                    Release();
                });
                opened.SetSource(new MediaUriSource(uri.ToString()));
                await opened.PrepareAsync(cancellation);
                if (!IsCurrent(gen, opened)) return;
                // API 6 retains its cancellation callback after preparation.
                preparing.Dispose(); preparing = null;
                var start = Convert.ToInt32(args["startMs"] ?? 0);
                if (start > 0) await opened.SetPlayPositionAsync(start, false);
                if (!IsCurrent(gen, opened)) return;
                var tracks = new List<Dictionary<string, object>>();
                AddTracks(tracks, opened.AudioTrackInfo, "audio");
                var subtitleStart = tracks.Count;
                try { AddTracks(tracks, opened.SubtitleTrackInfo, "sub"); }
                catch (InvalidOperationException) when (opened.State == PlayerState.Ready)
                {
                    // Some TV streams prepare successfully but have unavailable subtitle metadata.
                    // Keep A/V playback; do not advertise a partial native subtitle list.
                    tracks.RemoveRange(subtitleStart, tracks.Count - subtitleStart);
                }
                int width = 0, height = 0;
                // Audio-only media legitimately has no video properties.
                try { var video = opened.StreamInfo.GetVideoProperties(); width = video.Size.Width; height = video.Size.Height; }
                catch (InvalidOperationException) { }
                videoWidth = width; videoHeight = height;
                ApplyRect();
                if (width > 0) tracks.Add(new Dictionary<string, object> { ["id"] = "video:0", ["type"] = "video", ["selected"] = true });
                Emit("ready", new Dictionary<string, object>
                {
                    ["durationMs"] = opened.StreamInfo.GetDuration(), ["width"] = width,
                    ["height"] = height, ["tracks"] = tracks
                });
                Position();
                if (args["play"] is bool play && play && !suspended) Play();
            }
            catch (OperationCanceledException) when (!IsCurrent(gen, opened)) { }
            catch
            {
                if (IsCurrent(gen, opened)) Release();
                throw;
            }
        }

        private static void AddTracks(List<Dictionary<string, object>> tracks, PlayerTrackInfo info, string type)
        {
            // GetCount is a public API since Tizen 3; don't probe until an exception.
            for (int i = 0, count = info.GetCount(); i < count; i++)
                tracks.Add(new Dictionary<string, object>
                {
                    ["id"] = (type == "audio" ? "audio:" : "sub:") + i,
                    ["type"] = type, ["lang"] = info.GetLanguageCode(i) ?? "und",
                    ["selected"] = type == "audio" && i == info.Selected
                });
        }

        private bool IsCurrent(int gen, MediaPlayer current) => !disposed && gen == generation && ReferenceEquals(player, current);
        private void Post(int gen, MediaPlayer current, Action action) => main.Post(_ => { if (IsCurrent(gen, current)) action(); }, null);
        private void Emit(string name, Dictionary<string, object> data = null)
        {
            data = data ?? new Dictionary<string, object>();
            data["event"] = name; data["instanceId"] = owner; data["session"] = session;
            sink?.Success(new Dictionary<string, object> { ["type"] = "event", ["name"] = "tizen", ["data"] = data });
        }
        private void Position() => Emit("position", new Dictionary<string, object> { ["positionMs"] = player.GetPlayPosition() });
        private void Play()
        {
            if (suspended) throw new InvalidOperationException("Application suspended");
            if (player.Display != null) { window.Show(); }
            if (player.State != PlayerState.Playing) player.Start();
            if (rate != 1) player.SetPlaybackRate(rate);
            Emit("playing", new Dictionary<string, object> { ["value"] = true });
            StopTimer();
            var current = player; var gen = generation;
            timer = EcoreMainloop.AddTimer(0.25, () =>
            {
                if (!IsCurrent(gen, current)) { timer = IntPtr.Zero; return false; }
                try { Position(); return true; }
                catch (Exception e)
                {
                    Emit("error", new Dictionary<string, object> { ["code"] = e.GetType().Name });
                    timer = IntPtr.Zero; return false;
                }
            });
        }
        private void Pause()
        {
            if (player?.State == PlayerState.Playing) player.Pause();
            StopTimer();
            if (player != null)
            {
                if (player.State == PlayerState.Ready || player.State == PlayerState.Paused) Position();
                Emit("playing", new Dictionary<string, object> { ["value"] = false });
            }
        }
        public void Suspend() { if (!disposed) { suspended = true; Pause(); window.Hide(); } }
        public void Resume()
        {
            suspended = false; // Restore the paused picture, never autoplay.
            if (player?.Display != null) { window.Show(); }
        }
        private void SetRect(IDictionary args)
        {
            var left = Convert.ToInt32(args["left"]); var top = Convert.ToInt32(args["top"]);
            var width = Convert.ToInt32(args["right"]) - left; var height = Convert.ToInt32(args["bottom"]) - top;
            if (width <= 0 || height <= 0) throw new ArgumentOutOfRangeException("video bounds");
            bounds = new Rectangle(left, top, width, height);
        }
        private void ApplyRect()
        {
            if (player?.Display == null) return;
            int fit = displayMode == PlayerDisplayMode.LetterBox ? 0 : displayMode == PlayerDisplayMode.CroppedFull ? 1 : 2;
            var layout = VideoGeometry.Calculate(bounds.X, bounds.Y, bounds.Width, bounds.Height, videoWidth, videoHeight, fit);
            bool needsCrop = layout.SourceWidth < 1 || layout.SourceHeight < 1;
            if (cropped || needsCrop)
            {
                // Public overlay-source ROI (since API 5), not a private decoder option.
                player.SetVideoRoi(new ScaleRectangle(layout.SourceX, layout.SourceY, layout.SourceWidth, layout.SourceHeight));
                cropped = needsCrop;
            }
            player.DisplaySettings.SetRoi(new Rectangle(layout.X, layout.Y, layout.Width, layout.Height));
            // SetRoi only controls destination geometry in Roi mode.
            player.DisplaySettings.Mode = PlayerDisplayMode.Roi;
        }
        private void StopTimer() { if (timer != IntPtr.Zero) EcoreMainloop.RemoveTimer(timer); timer = IntPtr.Zero; }
        private void Release()
        {
            generation++;
            StopTimer();
            var pending = preparing; preparing = null;
            var old = player; player = null;
            try
            {
                // Native completion can precede Open's awaiting UI continuation.
                if (old != null && old.State == PlayerState.Preparing) pending?.Cancel();
            }
            finally
            {
                pending?.Dispose();
                // Dispose owns native unprepare and all player event registrations.
                try { old?.Dispose(); }
                finally
                {
                    subtitles = false; cropped = false;
                    videoWidth = 0; videoHeight = 0;
                    window.Hide();
                }
            }
        }
        public void OnListen(object arguments, IEventSink events) => sink = events;
        public void OnCancel(object arguments) => sink = null;
        public void Dispose()
        {
            if (disposed) return;
            Release(); disposed = true; sink = null;
            methods.SetMethodCallHandler(null); events.SetStreamHandler(null);
            window.Unrealize();
        }
    }
}
