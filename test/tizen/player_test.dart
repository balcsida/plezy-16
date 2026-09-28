import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/mpv/models.dart';
import 'package:plezy/mpv/player/platform/player_tizen.dart';

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
}
