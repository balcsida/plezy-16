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

/// A TV that wakes from standby, or loses its network, reports the dropped
/// stream as `ConnectionFailed`. That used to end playback on the failure view
/// until someone pressed Retry. One test per file: a second screen in the same
/// isolate never reaches its first open.
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
    tmpRoot = await Directory.systemTemp.createTemp('tizen_reconnect_test_');
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

  testWidgets('a dropped stream reopens at the playhead; the failure view waits for the budget', (tester) async {
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
    // What the host answers an open with: an error code, 'silent' for a
    // stream that never arrives, or null to prepare it.
    String? failure = 'silent';
    Completer<void>? silentOpen;
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
        // Releasing the player cancels a prepare that is still waiting.
        if (call.method == 'stop' || call.method == 'open') silentOpen?.complete();
        silentOpen = null;
        if (call.method != 'open') return null;
        opens.add(Map.of(call.arguments as Map));
        if (failure == 'silent') {
          final pending = silentOpen = Completer<void>();
          await pending.future;
          return null;
        }
        if (failure case final code?) {
          // Measured on the TV: the host reports the failed prepare, releases
          // the player, and completes the call about a second later.
          emit('error', {'code': code});
          await Future<void>.delayed(const Duration(seconds: 1));
          return null;
        }
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
                durationMs: 3600000,
                viewOffsetMs: 600000,
              ),
              selectedQualityPreset: TranscodeQualityPreset.original,
            ),
          ).push(navigator.currentState!),
        );

        final failureView = find.text(t.messages.playbackFailedDetail(error: 'Tizen player: ConnectionFailed'));
        final retry = find.widgetWithText(FilledButton, t.common.retry);
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

        final unsupported = find.text(t.messages.playbackFailedDetail(error: 'Tizen player: NotSupportedFile'));

        Future<void> powerOff() async {
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

        void expectStillLoading(String reason) {
          expect(find.textContaining('Playback could not be started'), findsNothing, reason: reason);
          expect(find.byType(SnackBar), findsNothing, reason: reason);
          expect(key.currentState!.debugPlayerUiReadyForTesting, isFalse, reason: reason);
        }

        // The first open of an item never arrives. The screen's own deadline
        // can beat the backend's timeout to it; either way it is retried.
        await opened(1);
        await tester.pump(const Duration(seconds: 30));
        await tester.pump();
        expectStillLoading('an open that timed out is retried');
        expect(opens, hasLength(1));

        failure = 'ConnectionFailed';
        var spent = 0;
        await tester.pump(playbackReconnectDelays[spent++]);
        await opened(2);
        expect(opens[1]['startMs'], 600000, reason: 'an unplayed item reopens where it would have started');
        expect(opens[1]['play'], isTrue);
        await tester.pump(const Duration(seconds: 1));
        expectStillLoading('a stream that could not be reached is retried');

        // The TV goes off before the next attempt. None runs in the
        // background, and the wake reopens what the failure left standing.
        await powerOff();
        await tester.pump(playbackReconnectDelays[spent] * 2);
        expect(opens, hasLength(2), reason: 'no attempt in the background');
        failure = 'NotSupportedFile';
        await powerOn();
        await opened(3);
        expect(opens[2]['startMs'], 600000);
        expect(opens[2]['play'], isTrue, reason: 'it was to play when the TV went off');

        // An item that never played fails at once on what a reopen cannot change.
        await pumpUntil(tester, () => unsupported.evaluate().isNotEmpty, describe: () => 'no failure view');
        await tester.pump(playbackReconnectDelays[0] * 2);
        expect(opens, hasLength(3), reason: 'an unplayed item is not retried for that');

        failure = null;
        await tester.tap(retry);
        await opened(4);
        await ready();
        expect(opens[3]['startMs'], 600000);
        expect(unsupported, findsNothing);
        expect(failureView, findsNothing);
        emit('playing', {'value': true});
        await playhead(1200000);
        spent = 0;
        var count = opens.length;

        // The network goes away: the held stream dies and reopening fails too.
        failure = 'ConnectionFailed';
        emit('error', {'code': 'ConnectionFailed'});
        await tester.pump();
        expectStillLoading('a played item is retried before it is given up');
        expect(opens, hasLength(count), reason: 'the attempt waits for its delay');

        await tester.pump(playbackReconnectDelays[spent++]);
        await opened(++count);
        expect(opens.last['startMs'], 1200000, reason: 'the reopen starts at the playhead');
        expect(opens.last['play'], isTrue, reason: 'playback was running when the stream dropped');
        await tester.pump(const Duration(seconds: 1));
        expectStillLoading('the reopen failed too');

        // The network returns before the next attempt.
        failure = null;
        await tester.pump(playbackReconnectDelays[spent++]);
        await opened(++count);
        await ready();
        expect(opens.last['startMs'], 1200000);
        expect(failureView, findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        await playhead(1800000);

        // A network that stays away spends what is left of the budget, and
        // only then raises the failure view. Recovering did not refill it.
        failure = 'ConnectionFailed';
        emit('error', {'code': 'ConnectionFailed'});
        while (spent < playbackReconnectDelays.length) {
          await tester.pump();
          expect(failureView, findsNothing, reason: 'attempt ${spent + 1} is still to come');
          await tester.pump(playbackReconnectDelays[spent++]);
          await opened(++count);
          expect(opens.last['startMs'], 1800000);
          await tester.pump(const Duration(seconds: 1));
        }
        await pumpUntil(tester, () => failureView.evaluate().isNotEmpty, describe: () => 'opens=${opens.length}');
        await tester.pump(const Duration(minutes: 2));
        expect(opens, hasLength(count), reason: 'a spent budget arms nothing');

        // Retry is the viewer's: it reopens and refills the budget.
        failure = null;
        await tester.tap(retry);
        await opened(++count);
        await pumpUntil(tester, () => failureView.evaluate().isEmpty, describe: () => 'failure view still up');
        await ready();
        expect(opens.last['startMs'], 1800000);
        await playhead(2400000);

        failure = 'ConnectionFailed';
        emit('error', {'code': 'ConnectionFailed'});
        await tester.pump();
        expect(failureView, findsNothing, reason: 'Retry refilled the budget');
        await tester.pump(playbackReconnectDelays[0]);
        await opened(++count);
        expect(opens.last['startMs'], 2400000);
        await tester.pump(const Duration(seconds: 1));
        failure = null;
        await tester.pump(playbackReconnectDelays[1]);
        await opened(++count);
        await ready();
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
