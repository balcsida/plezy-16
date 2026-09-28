import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/models/transcode_quality_preset.dart';
import 'package:plezy/mpv/player/player_base.dart';
import 'package:plezy/providers/account_preferences_controller.dart';
import 'package:plezy/providers/companion_remote_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/playback_state_provider.dart';
import 'package:plezy/providers/shader_provider.dart';
import 'package:plezy/screens/video_player/playback_reconnect.dart';
import 'package:plezy/screens/video_player/wake_detector.dart';
import 'package:plezy/screens/video_player_screen.dart';
import 'package:plezy/services/download_storage_service.dart';
import 'package:plezy/services/music/music_playback_service.dart';
import 'package:plezy/services/offline_watch_sync_service.dart';
import 'package:plezy/services/playback_coordinator.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/video_player_navigation.dart';
import 'package:plezy/watch_together/providers/watch_together_provider.dart';
import 'package:provider/provider.dart';

import '../test_helpers/io_fakes.dart';
import '../test_helpers/media_items.dart';
import '../test_helpers/mock_player_channels.dart';
import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/pump.dart';
import '../test_helpers/stub_music_playback_service.dart';
import 'tizen_stream_client.dart';

/// Measured on a UE55AU7022KXXH: the TV powers off into standby without a
/// pause or resume ever reaching the app. The process is frozen, and the
/// player it held wakes without a picture. One test per file: a second screen
/// in the same isolate never reaches its first open.
void main() {
  // The screen only builds the Tizen player in a Tizen build.
  if (!const bool.fromEnvironment('TIZEN_BUILD')) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpRoot;
  late PathProviderPlatform previousPathProvider;
  late AppDatabase db;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
    tmpRoot = await Directory.systemTemp.createTemp('tizen_wake_test_');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProvider(tmpRoot);
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    DownloadStorageService.resetForTesting();
    await DownloadStorageService.instance.initialize(SettingsService.instance);
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    DownloadStorageService.resetForTesting();
    SettingsService.resetForTesting();
    PathProviderPlatform.instance = previousPathProvider;
    WakeDetector.debugWallOffset = Duration.zero;
    if (await tmpRoot.exists()) await tmpRoot.delete(recursive: true);
  });

  testWidgets('a standby nobody reported rebuilds the player as it was left', (tester) async {
    final client = TizenStreamClient();
    final multi = testMultiServer(clients: [client]);
    final offlineWatch = OfflineWatchSyncService(database: db, serverManager: multi.manager);
    final accountPreferences = AccountPreferencesController();
    // The test host is a desktop: answer the window plugins it reaches for.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const hostChannels = [MethodChannel('window_manager'), MethodChannel('com.plezy/window_utils')];
    for (final channel in hostChannels) {
      messenger.setMockMethodCallHandler(channel, (call) async => call.method.startsWith('is') ? false : null);
    }
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      for (final channel in hostChannels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
      tester.view.reset();
      offlineWatch.dispose();
      accountPreferences.dispose();
    });

    final navigator = GlobalKey<NavigatorState>();
    final key = GlobalKey<VideoPlayerScreenState>();
    final opens = <Map<Object?, Object?>>[];
    final calls = <String>[];

    PlayerBase player() => key.currentState!.player! as PlayerBase;
    void emit(String event, [Map<String, Object?> data = const {}]) {
      player().handlePlayerEvent('tizen', {
        'instanceId': opens.last['instanceId'],
        'session': opens.last['session'],
        'event': event,
        ...data,
      });
    }

    await withMockPlayerChannels(
      methodChannelName: 'com.plezy/tizen_player',
      eventChannelName: 'com.plezy/tizen_player/events',
      methodHandler: (call) async {
        calls.add(call.method);
        if (call.method != 'open') return null;
        opens.add(Map.of(call.arguments as Map));
        emit('ready', {'durationMs': 3600000, 'width': 1920, 'height': 1080, 'tracks': tizenTracks});
        if (opens.last['play'] == true) emit('playing', {'value': true});
        return null;
      },
      testBody: () async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => PlaybackStateProvider()),
              ChangeNotifierProvider<MultiServerProvider>.value(value: multi.provider),
              ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineWatch),
              ChangeNotifierProvider<AccountPreferencesController>.value(value: accountPreferences),
              ChangeNotifierProvider(create: (_) => CompanionRemoteProvider()),
              ChangeNotifierProvider(create: (_) => WatchTogetherProvider()),
              ChangeNotifierProvider(create: (_) => ShaderProvider()),
              ChangeNotifierProvider<MusicPlaybackService>(create: (_) => StubMusicPlaybackService()),
              Provider<AppDatabase>.value(value: db),
            ],
            child: MaterialApp(
              navigatorKey: navigator,
              home: const Scaffold(body: Text('Browse')),
            ),
          ),
        );
        unawaited(
          VideoPlayerRoute(
            builder: (_) => VideoPlayerScreen(
              key: key,
              metadata: testMediaItem(
                id: 'standby',
                serverId: 'srv-1',
                title: 'Standby',
                backend: MediaBackend.jellyfin,
              ),
              selectedQualityPreset: TranscodeQualityPreset.original,
            ),
          ).push(navigator.currentState!),
        );

        final failureView = find.textContaining('Playback could not be started');
        Future<void> playhead(int ms) async {
          // The player publishes its position at most every 250 ms of wall time.
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
          emit('position', {'positionMs': ms});
          expect(player().state.position, Duration(milliseconds: ms));
        }

        Future<void> ready() => pumpUntil(
          tester,
          () => key.currentState!.debugPlayerUiReadyForTesting,
          describe: () => 'open ${opens.length} never became ready',
        );

        Future<void> opened(int count) =>
            pumpUntil(tester, () => opens.length == count, describe: () => 'opens=${opens.length}, wanted $count');

        Future<void> powerOff() async {
          // The host pauses natively first, then the engine reports the pause.
          emit('playing', {'value': false});
          for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
          await tester.pump();
        }

        Future<void> powerOn() async {
          for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
          await tester.pump();
        }

        /// The TV slept and woke. All the app ever learns is that the wall
        /// clock ran on while its own stood still: 308 s, as measured.
        void sleep() => WakeDetector.debugWallOffset += const Duration(seconds: 308);
        Future<void> standby() async {
          sleep();
          await tester.pump(wakeCheckPeriod);
        }

        /// Rounds of the test clock and of the real loop, for what must not follow.
        Future<void> settle() async {
          for (var round = 0; round < 20; round++) {
            await tester.pump(const Duration(milliseconds: 10));
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
          }
        }

        Future<void> decided(int count) => pumpUntil(
          tester,
          () => client.decisions == count,
          describe: () => 'decisions=${client.decisions}, wanted $count',
        );
        int pauses() => calls.where((call) => call == 'pause').length;
        bool controlsUp() => key.currentState!.chromeController.controlsVisible;

        await opened(1);
        await ready();
        await playhead(1121000);

        // Standby while playing: a new player, playing on from the playhead.
        await standby();
        await opened(2);
        await ready();
        expect(opens[1]['startMs'], 1121000);
        expect(opens[1]['play'], isTrue, reason: 'it was playing when the TV went off');
        expect(failureView, findsNothing);
        await playhead(1200000);

        // The same, but the wake finds the server unreachable: it waits, and
        // still plays on.
        client.reachable = false;
        var decisions = client.decisions;
        await standby();
        await decided(++decisions);
        await settle();
        expect(opens, hasLength(2));
        expect(failureView, findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        client.reachable = true;
        await tester.pump(playbackReconnectDelays[0]);
        await opened(3);
        await ready();
        expect(opens[2]['startMs'], 1200000);
        expect(opens[2]['play'], isTrue);
        expect(failureView, findsNothing);
        await playhead(1300000);

        // Standby while paused: paused again, behind controls that say so. A
        // player that has not started draws nothing of its own.
        final pausedBefore = pauses();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await pumpUntil(tester, () => pauses() == pausedBefore + 1, describe: () => 'calls=$calls');
        emit('playing', {'value': false});
        await tester.pump(const Duration(seconds: 30));
        expect(controlsUp(), isFalse, reason: 'the controls timed out');
        await standby();
        await opened(4);
        await ready();
        expect(opens[3]['startMs'], 1300000);
        expect(opens[3]['play'], isFalse, reason: 'it was paused when the TV went off');
        expect(controlsUp(), isTrue);
        expect(failureView, findsNothing);

        // Paused, and the server unreachable at the wake: the open that lands
        // later is as empty without its controls. The viewer dismissed them.
        key.currentState!.chromeController.hide(ignoreHolds: true);
        await tester.pump(const Duration(seconds: 1));
        expect(controlsUp(), isFalse);
        client.reachable = false;
        decisions = client.decisions;
        await standby();
        await decided(++decisions);
        await settle();
        expect(opens, hasLength(4));
        client.reachable = true;
        await tester.pump(playbackReconnectDelays[0]);
        await opened(5);
        await ready();
        expect(opens[4]['play'], isFalse);
        expect(controlsUp(), isTrue);
        expect(failureView, findsNothing);

        // A TV that does report its standby resumes the app too. That is one
        // wake: the resume answers the gap before the next check sees it.
        await powerOff();
        sleep();
        await powerOn();
        await opened(6);
        await ready();
        await tester.pump(wakeCheckPeriod * 2);
        await settle();
        expect(opens, hasLength(6), reason: 'one wake, one rebuild');

        // Seen first, while the app is still in the background, the gap is
        // left to the resume that follows.
        await powerOff();
        await standby();
        await settle();
        expect(opens, hasLength(6), reason: 'the resume to come rebuilds');
        await powerOn();
        await opened(7);
        await ready();
        await tester.pump(wakeCheckPeriod * 2);
        await settle();
        expect(opens, hasLength(7), reason: 'one wake, one rebuild');

        var shutdownDone = false;
        final shutdown = PlaybackCoordinator.instance.shutdownVideo().whenComplete(() => shutdownDone = true);
        await pumpUntil(tester, () => shutdownDone);
        await shutdown;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}
