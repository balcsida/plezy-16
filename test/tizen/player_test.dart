import 'dart:async';
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
}
