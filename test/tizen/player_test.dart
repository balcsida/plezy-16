import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/mpv/models.dart';
import 'package:plezy/mpv/player/platform/player_tizen.dart';
import 'package:plezy/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('com.plezy/tizen_player');
  const events = MethodChannel('com.plezy/tizen_player/events');
  final calls = <MethodCall>[];
  Completer<void>? seekGate;
  setUp(() {
    calls.clear();
    seekGate = null;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'seek' && seekGate != null) await seekGate!.future;
      return null;
    });
  });

  void event(PlayerTizen player, Map args, String name, [Map<String, Object?> data = const {}]) {
    player.handlePlayerEvent('tizen', {...args, 'event': name, ...data});
  }

  test('late callbacks cannot mutate a replacement or stopped session', () async {
    final player = PlayerTizen();
    addTearDown(player.dispose);
    await player.open(Media('https://example.test/one.mp4'), play: false);
    final old = Map.of(calls.last.arguments as Map);
    await player.open(Media('https://example.test/two.mp4'), play: false);
    final current = Map.of(calls.last.arguments as Map);
    event(player, current, 'ready', {'durationMs': 20000, 'tracks': []});
    event(player, old, 'ready', {'durationMs': 9000, 'tracks': []});
    event(player, old, 'playing', {'value': true});
    expect(player.state.duration, const Duration(seconds: 20));
    expect(player.state.playing, isFalse);
    await player.stop();
    event(player, current, 'playing', {'value': true});
    expect(player.state.playing, isFalse);
  });

  test('a paused open reports its loaded frame without playing', () async {
    final player = PlayerTizen();
    addTearDown(player.dispose);
    await player.open(Media('https://example.test/video.mp4'), play: false);
    event(player, Map.of(calls.last.arguments as Map), 'ready', {'durationMs': 20000, 'tracks': []});
    expect(player.state.hasRenderedFrame, isTrue);
    expect(player.state.playing, isFalse);
  });

  test('a stall is a position standing still while it plays, not a buffer under 100 %', () async {
    final player = PlayerTizen();
    addTearDown(player.dispose);
    await player.open(Media('https://example.test/video.mp4'));
    final args = Map.of(calls.last.arguments as Map);
    event(player, args, 'ready', {'durationMs': 20000, 'tracks': []});
    event(player, args, 'playing', {'value': true});
    // What the host used to forward: the TV says how full its buffer is, and plays on.
    event(player, args, 'buffering', {'value': true});
    for (var ms = 0; ms <= 1000; ms += 250) {
      event(player, args, 'position', {'positionMs': ms});
    }
    expect(player.state.buffering, isFalse);
    // The host reads the position every 250 ms: five reads without a move are not yet 1.5 s.
    for (var read = 0; read < 5; read++) {
      event(player, args, 'position', {'positionMs': 1000});
    }
    expect(player.state.buffering, isFalse);
    event(player, args, 'position', {'positionMs': 1000});
    expect(player.state.buffering, isTrue);
    event(player, args, 'position', {'positionMs': 1250});
    expect(player.state.buffering, isFalse);
  });

  test('a pause and the end are not stalls', () async {
    final player = PlayerTizen();
    addTearDown(player.dispose);
    await player.open(Media('https://example.test/video.mp4'));
    final args = Map.of(calls.last.arguments as Map);
    event(player, args, 'ready', {'durationMs': 20000, 'tracks': []});
    void standStill() {
      event(player, args, 'playing', {'value': true});
      for (var read = 0; read < 7; read++) {
        event(player, args, 'position', {'positionMs': 1000});
      }
    }

    standStill();
    expect(player.state.buffering, isTrue);
    event(player, args, 'playing', {'value': true});
    expect(player.state.buffering, isTrue, reason: 'a play that changes nothing leaves the stall standing');
    // As the host pauses: its last position, then the pause.
    event(player, args, 'position', {'positionMs': 1000});
    event(player, args, 'playing', {'value': false});
    expect(player.state.buffering, isFalse);
    // Paused, the host reads the position only once more, after a seek.
    event(player, args, 'position', {'positionMs': 1000});
    expect(player.state.buffering, isFalse);

    standStill();
    expect(player.state.buffering, isTrue);
    event(player, args, 'completed');
    expect(player.state.buffering, isFalse);
  });

  test('a reopen counts afresh, and a channel is not watched', () async {
    final player = PlayerTizen();
    addTearDown(player.dispose);
    Future<Map> open({bool isLive = false}) async {
      await player.open(Media('https://example.test/video.mp4'), isLive: isLive);
      final args = Map.of(calls.last.arguments as Map);
      // As the host opens: ready, where it stands, then playing.
      event(player, args, 'ready', {'durationMs': 20000, 'tracks': []});
      event(player, args, 'position', {'positionMs': 1000});
      event(player, args, 'playing', {'value': true});
      return args;
    }

    void stand(Map args, int reads) {
      for (var read = 0; read < reads; read++) {
        event(player, args, 'position', {'positionMs': 1000});
      }
    }

    var args = await open();
    stand(args, 6);
    expect(player.state.buffering, isTrue);
    // A reconnect reopens where the stream dropped: standing there is no stall yet.
    args = await open();
    stand(args, 5);
    expect(player.state.buffering, isFalse);
    stand(args, 1);
    expect(player.state.buffering, isTrue);

    // Unverified on the TV: a channel's position may never move.
    args = await open(isLive: true);
    stand(args, 12);
    expect(player.state.buffering, isFalse);
  });

  test('the Playback Buffer tier goes to the host with every open, except a live one', () async {
    final player = PlayerTizen();
    addTearDown(player.dispose);
    Object? tier() => (calls.lastWhere((c) => c.method == 'open').arguments as Map)['bufferTier'];
    await player.open(Media('https://example.test/video.mp4'), play: false);
    expect(tier(), 'auto');
    await player.setProperty('exo-buffer-tier', PlaybackBufferTier.extraLarge.nativeValue);
    await player.open(Media('https://example.test/video.mp4'), play: false);
    expect(tier(), 'extra_large');
    await player.open(Media('https://example.test/video.mp4'), play: false);
    expect(tier(), 'extra_large', reason: 'a reconnect reopens on the same player');
    // A channel has no media ahead to wait for.
    await player.open(Media('https://example.test/live.m3u8'), play: false, isLive: true);
    expect(tier(), 'auto');
  });

  test('only a connection failure is tagged as one', () async {
    final player = PlayerTizen();
    addTearDown(player.dispose);
    final errors = <PlayerError>[];
    final subscription = player.streams.error.listen(errors.add);
    addTearDown(subscription.cancel);
    for (final code in ['ConnectionFailed', 'NotSupportedFile']) {
      await player.open(Media('https://example.test/video.mp4'), play: false);
      event(player, Map.of(calls.last.arguments as Map), 'error', {'code': code});
      await Future<void>.delayed(Duration.zero);
    }
    expect(errors.map((e) => e.cause), [PlayerError.connectionFailed, null]);
    expect(errors.map((e) => e.message), ['Tizen player: ConnectionFailed', 'Tizen player: NotSupportedFile']);
  });

  test('seeks are serialized and coalesce to the most recent target', () async {
    final player = PlayerTizen();
    addTearDown(player.dispose);
    await player.open(Media('https://example.test/video.mp4'), play: false);
    seekGate = Completer<void>();
    final first = player.seek(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    final middle = player.seek(const Duration(seconds: 2));
    final last = player.seek(const Duration(seconds: 3));
    expect(calls.where((c) => c.method == 'seek').length, 1);
    seekGate!.complete();
    await Future.wait([first, middle, last]);
    expect(calls.where((c) => c.method == 'seek').map((c) => (c.arguments as Map)['positionMs']), [1000, 3000]);
    expect(player.currentPosition, const Duration(seconds: 3));
  });

  test('a stacked part plays in its own time and reports on the item timeline', () async {
    final player = PlayerTizen();
    addTearDown(player.dispose);
    // The second file of an item whose first runs ten minutes, resumed two minutes into it.
    await player.open(
      Media('https://example.test/part2.mp4', start: const Duration(minutes: 12)),
      play: false,
      timelineOffset: const Duration(minutes: 10),
    );
    final args = Map.of(calls.last.arguments as Map);
    expect(args['startMs'], 120000);
    event(player, args, 'ready', {'durationMs': 600000, 'tracks': []});
    event(player, args, 'position', {'positionMs': 180000});
    expect(player.currentPosition, const Duration(minutes: 13));
    await player.seek(const Duration(minutes: 15));
    expect((calls.last.arguments as Map)['positionMs'], 300000);
    expect(player.currentPosition, const Duration(minutes: 15));
  });

  test('native track IDs are not Jellyfin indexes and switching never plays', () async {
    final player = PlayerTizen();
    addTearDown(player.dispose);
    await player.open(Media('https://example.test/video.mp4'), play: false);
    await player.selectAudioTrack(const AudioTrack(id: 'audio:2'));
    expect((calls.last.arguments as Map)['index'], 2);
    expect(calls.where((c) => c.method == 'play'), isEmpty);
    await expectLater(player.selectAudioTrack(const AudioTrack(id: '7')), throwsArgumentError);
    await player.selectSubtitleTrack(SubtitleTrack.off);
    expect((calls.last.arguments as Map)['index'], -1);
    expect(player.state.playing, isFalse);
  });

  test('unsupported authentication is rejected rather than silently dropped', () async {
    final player = PlayerTizen();
    addTearDown(player.dispose);
    await expectLater(
      player.open(Media('https://example.test/video', headers: {'Authorization': 'Bearer fixture'})),
      throwsUnsupportedError,
    );
    expect(calls.where((c) => c.method == 'open'), isEmpty);
    await player.open(
      Media('https://example.test/jellyfin/video?api_key=fixture', headers: {'X-Emby-Token': 'fixture'}),
    );
    expect(calls.where((c) => c.method == 'open').length, 1);
  });

  test('a mapped video window raises the controls over it, never from the background', () async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // As the embedder reports it, on the platform channel.
    Future<void> lifecycle(AppLifecycleState state) => messenger.handlePlatformMessage(
      SystemChannels.lifecycle.name,
      SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
      (_) {},
    );
    const window = MethodChannel('tizen/internal/window');
    final raised = <String>[];
    messenger.setMockMethodCallHandler(window, (call) async {
      raised.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(window, null));
    addTearDown(() => lifecycle(AppLifecycleState.resumed));
    final player = PlayerTizen();
    addTearDown(player.dispose);
    await player.open(Media('https://example.test/video.mp4'), play: false);
    final args = Map.of(calls.last.arguments as Map);
    await lifecycle(AppLifecycleState.resumed);
    event(player, args, 'shown');
    await Future<void>.delayed(Duration.zero);
    expect(raised, ['raiseWindow']);
    // Home: the launcher is now on top, and raising would cover it again.
    await lifecycle(AppLifecycleState.paused);
    event(player, args, 'shown');
    await Future<void>.delayed(Duration.zero);
    expect(raised, ['raiseWindow']);
  });

  test('after a standby nobody reported, the controls wait for a key before rising', () async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const window = MethodChannel('tizen/internal/window');
    final raised = <String>[];
    messenger.setMockMethodCallHandler(window, (call) async {
      raised.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(window, null));
    addTearDown(PlayerTizen.releaseRaiseHold);
    await messenger.handlePlatformMessage(
      SystemChannels.lifecycle.name,
      SystemChannels.lifecycle.codec.encodeMessage(AppLifecycleState.resumed.toString()),
      (_) {},
    );
    final player = PlayerTizen();
    addTearDown(player.dispose);
    await player.open(Media('https://example.test/video.mp4'), play: false);
    final args = Map.of(calls.last.arguments as Map);

    // The lifecycle still says resumed, but the TV may have woken behind its launcher.
    PlayerTizen.holdRaiseUntilInput();
    event(player, args, 'shown');
    await Future<void>.delayed(Duration.zero);
    expect(raised, isEmpty, reason: 'raising now would cover the launcher');

    // Only a focused window gets the remote's keys.
    const key = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.arrowDown,
      logicalKey: LogicalKeyboardKey.arrowDown,
      timeStamp: Duration.zero,
    );
    expect(HardwareKeyboard.instance.handleKeyEvent(key), isFalse, reason: 'the key still reaches the app');
    await Future<void>.delayed(Duration.zero);
    expect(raised, ['raiseWindow']);
    HardwareKeyboard.instance.handleKeyEvent(
      const KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.arrowDown,
        logicalKey: LogicalKeyboardKey.arrowDown,
        timeStamp: Duration.zero,
      ),
    );

    // Nothing owed: a later hold released by a resume raises nothing.
    PlayerTizen.holdRaiseUntilInput();
    PlayerTizen.releaseRaiseHold();
    await Future<void>.delayed(Duration.zero);
    expect(raised, ['raiseWindow']);
    event(player, args, 'shown');
    await Future<void>.delayed(Duration.zero);
    expect(raised, ['raiseWindow', 'raiseWindow'], reason: 'released, a map raises at once again');
  });
}
