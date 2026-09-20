using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Runner;
using Tizen.Flutter.Embedding;
using Tizen.Multimedia;

class Program
{
    sealed class Context : SynchronizationContext
    {
        public override void Post(SendOrPostCallback callback, object state)
        {
            var previous = Current;
            SetSynchronizationContext(this);
            try { callback(state); }
            finally { SetSynchronizationContext(previous); }
        }
    }
    sealed class Sink : IEventSink
    {
        public readonly List<Dictionary<string, object>> Events = new List<Dictionary<string, object>>();
        public void Success(object value) => Events.Add((Dictionary<string, object>)((Dictionary<string, object>)value)["data"]);
    }
    static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
    static Task<object> Call(string method, int session = 1) => MethodChannel.Handler(new MethodCall
    {
        Method = method,
        Arguments = new Dictionary<string, object>
        {
            ["instanceId"] = 1, ["session"] = session,
            ["url"] = "https://example.invalid/test.mp4", ["play"] = true
        }
    });
    static async Task MainTest(string subtitleFailure)
    {
        Player.SubtitleFailure = subtitleFailure;
        Player.HoldPreparation = false;
        using var host = new TizenMediaPlayer();
        var sink = new Sink();
        host.OnListen(null, sink);
        await Call("open");
        var native = Player.Last;
        Check(native.State == PlayerState.Playing, "Optional subtitle metadata must not prevent playback");
        Check(native.DisplaySettings.IsVisible, "The video overlay must be made visible, or only audio reaches the TV");
        var ready = sink.Events.Single(item => (string)item["event"] == "ready");
        var tracks = (List<Dictionary<string, object>>)ready["tracks"];
        Check(tracks.Count(item => (string)item["type"] == "audio") == 1, "Preserve audio tracks");
        Check(tracks.Count(item => (string)item["type"] == "sub") == (subtitleFailure == null ? 2 : 0),
            "Unavailable subtitle metadata must not publish partial/fabricated tracks");
        await Call("stop");
        Check(native.Disposed && !native.PreparationCancelled, "Do not cancel an already prepared player");
    }
    static async Task StopPending(bool nativeAlreadyReady)
    {
        Player.SubtitleFailure = null;
        Player.HoldPreparation = true;
        using var host = new TizenMediaPlayer();
        var sink = new Sink();
        host.OnListen(null, sink);
        var open = Call("open");
        var native = Player.Last;
        Check(native.State == PlayerState.Preparing, "Fixture must hold native preparation");
        // Model native completion before the awaiting UI continuation runs.
        if (nativeAlreadyReady) native.State = PlayerState.Ready;
        await Call("stop");
        native.CompletePreparation();
        await open;
        Check(native.Disposed, "Stop must dispose the native resource");
        Check(native.PreparationCancelled == !nativeAlreadyReady, "Cancel only while native state is Preparing");
        Check(sink.Events.All(item => (string)item["event"] != "ready"), "A stopped open must not emit ready");
    }
    static async Task<int> Main()
    {
        SynchronizationContext.SetSynchronizationContext(new Context());
        var tests = new (string Name, Func<Task> Run)[]
        {
            ("stop after successful preparation", () => MainTest(null)),
            ("unavailable subtitle count", () => MainTest("count")),
            ("unavailable subtitle language", () => MainTest("language")),
            ("cancel pending preparation", () => StopPending(false)),
            ("stop after native completion before continuation", () => StopPending(true)),
        };
        var failed = 0;
        foreach (var test in tests)
        {
            try { await test.Run(); Console.WriteLine("PASS " + test.Name); }
            catch (Exception error) { failed++; Console.WriteLine("FAIL " + test.Name + ": " + error.GetType().Name + " — " + error.Message); }
        }
        Console.WriteLine($"Native bridge host checks: {tests.Length - failed} passed, {failed} failed.");
        return failed == 0 ? 0 : 1;
    }
}
