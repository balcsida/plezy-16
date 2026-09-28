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

/// Powering the TV off pauses the app and may freeze it before anything else
/// runs; powering it on resumes it, often before the network is back. One test
/// per file: a second screen in the same isolate never reaches its first open.
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
    tmpRoot = await Directory.systemTemp.createTemp('tizen_resume_test_');
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
    if (await tmpRoot.exists()) await tmpRoot.delete(recursive: true);
  });

  testWidgets('a wake rebuilds the player paused at the playhead, waiting out an unreachable server', (tester) async {
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
    var stops = 0;

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
        if (call.method == 'stop') stops++;
        if (call.method != 'open') return null;
        opens.add(Map.of(call.arguments as Map));
        emit('ready', {'durationMs': 3600000, 'width': 1920, 'height': 1080, 'tracks': const <Object?>[]});
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
        await pumpUntil(tester, () => opens.length == 1, describe: () => 'opens=$opens');
        await pumpUntil(tester, () => key.currentState!.debugPlayerUiReadyForTesting);
        // The player publishes its position at most every 250 ms of wall time.
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        emit('position', {'positionMs': 120000});
        expect(player().state.position, const Duration(minutes: 2));

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

        // Standby froze the process before the grace timer ran, and the wake
        // finds the server unreachable.
        await powerOff();
        expect(stops, 0, reason: 'the suspend never ran');
        client.reachable = false;
        await powerOn();
        await pumpUntil(tester, () => !key.currentState!.debugPlayerUiReadyForTesting);
        expect(opens, hasLength(1), reason: 'no stream to hand to the player yet');
        expect(find.byType(SnackBar), findsNothing, reason: 'a restore that will be retried is not announced');
        expect(failureView, findsNothing);

        await tester.pump(playbackReconnectDelays[0]);
        await pumpUntil(tester, () => client.decisions == 3, describe: () => 'decisions=${client.decisions}');
        expect(opens, hasLength(1));
        expect(failureView, findsNothing);

        client.reachable = true;
        await tester.pump(playbackReconnectDelays[1]);
        await pumpUntil(tester, () => opens.length == 2, describe: () => 'opens=$opens');
        await pumpUntil(tester, () => key.currentState!.debugPlayerUiReadyForTesting);
        expect(opens[1]['startMs'], 120000, reason: 'the rebuild starts at the playhead');
        expect(opens[1]['play'], isFalse, reason: 'a wake comes back paused');
        expect(failureView, findsNothing);

        // A standby that lets the grace timer run releases the player first.
        final stopsBefore = stops;
        await powerOff();
        await tester.pump(const Duration(seconds: 2));
        await pumpUntil(tester, () => stops == stopsBefore + 1, describe: () => 'stops=$stops');
        await powerOn();
        await pumpUntil(tester, () => opens.length == 3, describe: () => 'opens=$opens');
        await pumpUntil(tester, () => key.currentState!.debugPlayerUiReadyForTesting);
        expect(opens[2]['startMs'], 120000);
        expect(opens[2]['play'], isFalse);
        expect(failureView, findsNothing);

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
