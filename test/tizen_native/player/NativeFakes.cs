// Host-only boundary doubles: never linked into the TPK. The real bridge is
// compiled unchanged. These model the API-6 cancellation contract and the TV's
// observed metadata failure; they do not prove decoder/device compatibility.
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace ElmSharp
{
    public class Window
    {
        public Window(string name) { }
        public (int Width, int Height) ScreenSize => (1920, 1080);
        public void Resize(int width, int height) { }
        public void FocusSkip(bool value) { }
        public void Show() { }
        public void Hide() { }
        public void Lower() { }
        public void Unrealize() { }
    }
    public static class EcoreMainloop
    {
        public static IntPtr AddTimer(double seconds, Func<bool> callback) => new IntPtr(1);
        public static void RemoveTimer(IntPtr timer) { }
    }
}

namespace Tizen.Flutter.Embedding
{
    public class MethodCall
    {
        public string Method { get; set; }
        public object Arguments { get; set; }
    }
    public class MethodChannel
    {
        public static Func<MethodCall, Task<object>> Handler;
        public MethodChannel(string name) { }
        public void SetMethodCallHandler(Func<MethodCall, Task<object>> handler) => Handler = handler;
    }
    public class EventChannel
    {
        public EventChannel(string name) { }
        public void SetStreamHandler(IEventStreamHandler handler) { }
    }
    public interface IEventStreamHandler
    {
        void OnListen(object arguments, IEventSink events);
        void OnCancel(object arguments);
    }
    public interface IEventSink { void Success(object value); }
    public class MissingPluginException : Exception { }
}

namespace Tizen.Multimedia
{
    public enum PlayerState { Idle, Preparing, Ready, Playing, Paused }
    public enum PlayerDisplayMode { LetterBox, CroppedFull, FullScreen, Roi }
    public struct Rectangle
    {
        public int X, Y, Width, Height;
        public Rectangle(int x, int y, int width, int height)
            { X = x; Y = y; Width = width; Height = height; }
    }
    public struct ScaleRectangle
    {
        public ScaleRectangle(float x, float y, float width, float height) { }
    }
    public class Display { public Display(ElmSharp.Window window) { } }
    public class DisplaySettings
    {
        public PlayerDisplayMode Mode { get; set; }
        // Native default is not visible; the bridge must opt in.
        public bool IsVisible { get; set; }
        public void SetRoi(Rectangle rectangle) { }
    }
    public class MediaUriSource { public MediaUriSource(string uri) { } }
    public class VideoProperties { public (int Width, int Height) Size => (1920, 1080); }
    public class StreamInfo
    {
        public int GetDuration() => 60000;
        public VideoProperties GetVideoProperties() => new VideoProperties();
    }
    public class BufferingArgs : EventArgs { public int Percent { get; set; } }
    public class SubtitleArgs : EventArgs
    {
        public string Text { get; set; }
        public int Duration { get; set; }
    }
    public class ErrorArgs : EventArgs { public object Error { get; set; } }
    public class PlayerTrackInfo
    {
        private readonly Player owner;
        private readonly bool subtitle;
        private int selected;
        public PlayerTrackInfo(Player player, bool isSubtitle)
            { owner = player; subtitle = isSubtitle; }
        public int GetCount()
        {
            owner.Require(PlayerState.Ready, PlayerState.Playing, PlayerState.Paused);
            if (subtitle && Player.SubtitleFailure == "count") throw new InvalidOperationException();
            return subtitle ? 2 : 1;
        }
        public string GetLanguageCode(int index)
        {
            if (index < 0 || index >= GetCount()) throw new ArgumentOutOfRangeException();
            if (subtitle && index == 1 && Player.SubtitleFailure == "language")
                throw new InvalidOperationException();
            return "en";
        }
        public int Selected
        {
            get { owner.Require(PlayerState.Ready, PlayerState.Playing, PlayerState.Paused); return selected; }
            set { if (value < 0 || value >= GetCount()) throw new ArgumentOutOfRangeException(); selected = value; }
        }
    }
    public class Player : IDisposable
    {
        public static Player Last;
        public static string SubtitleFailure;
        public static bool HoldPreparation;
        public PlayerState State { get; set; } = PlayerState.Idle;
        public bool Disposed, PreparationCancelled;
        public string UserAgent { get; set; }
        public float Volume { get; set; }
        public Display Display { get; set; }
        public DisplaySettings DisplaySettings { get; } = new DisplaySettings();
        public StreamInfo StreamInfo { get; } = new StreamInfo();
        public PlayerTrackInfo AudioTrackInfo { get; }
        public PlayerTrackInfo SubtitleTrackInfo { get; }
        public EventHandler PlaybackCompleted { get; set; }
        public EventHandler<BufferingArgs> BufferingProgressChanged { get; set; }
        public EventHandler<SubtitleArgs> SubtitleUpdated { get; set; }
        public EventHandler<ErrorArgs> ErrorOccurred { get; set; }
        private readonly TaskCompletionSource<bool> prepared = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        public Player()
        {
            Last = this;
            AudioTrackInfo = new PlayerTrackInfo(this, false);
            SubtitleTrackInfo = new PlayerTrackInfo(this, true);
        }
        public void Require(params PlayerState[] states)
        {
            if (Disposed) throw new ObjectDisposedException(nameof(Player));
            if (Array.IndexOf(states, State) < 0) throw new InvalidOperationException();
        }
        public void SetSource(MediaUriSource source) => Require(PlayerState.Idle);
        public Task PrepareAsync(CancellationToken token)
        {
            Require(PlayerState.Idle);
            State = PlayerState.Preparing;
            // API-6 Player.cs registers this callback without disposing its
            // registration on completion. Cancelling after Ready is invalid.
            token.Register(() =>
            {
                Require(PlayerState.Preparing);
                PreparationCancelled = true;
                State = PlayerState.Idle;
                prepared.TrySetCanceled();
            });
            if (!HoldPreparation) CompletePreparation();
            return prepared.Task;
        }
        public void CompletePreparation()
        {
            if (!Disposed) State = PlayerState.Ready;
            prepared.TrySetResult(true);
        }
        public Task SetPlayPositionAsync(int position, bool accurate)
        {
            Require(PlayerState.Ready, PlayerState.Playing, PlayerState.Paused);
            return Task.CompletedTask;
        }
        public int GetPlayPosition() { Require(PlayerState.Ready, PlayerState.Playing, PlayerState.Paused); return 0; }
        public void Start() { Require(PlayerState.Ready, PlayerState.Paused); State = PlayerState.Playing; }
        public void Pause() { Require(PlayerState.Playing); State = PlayerState.Paused; }
        public void SetPlaybackRate(float rate) => Require(PlayerState.Playing, PlayerState.Paused);
        public void SetVideoRoi(ScaleRectangle rectangle) { }
        public void Dispose() { Disposed = true; State = PlayerState.Idle; }
    }
}
