import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/services/playback_initialization_types.dart';

import '../test_helpers/playback_report_fakes.dart';

/// What the host lists for a prepared stream: the TV always has the audio
/// track, and an empty list would leave track selection waiting for one.
const List<Map<String, Object?>> tizenTracks = [
  {'id': 'audio:0', 'type': 'audio', 'lang': 'eng', 'selected': true},
  {'id': 'video:0', 'type': 'video', 'selected': true},
];

/// Resolves every item to a stream URL; [reachable] false fails the playback
/// decision the way an unreachable server does.
class TizenStreamClient with PlaybackReportRecorder implements MediaServerClient {
  bool reachable = true;

  /// Playback decisions asked for, answered or not.
  int decisions = 0;

  @override
  ServerId get serverId => ServerId('srv-1');
  @override
  String get serverName => 'Server';
  @override
  MediaBackend get backend => MediaBackend.jellyfin;
  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;
  @override
  double get watchedThreshold => 0.9;
  @override
  bool get marksWatchedOnPlaybackStopped => true;
  @override
  Map<String, String> get streamHeaders => const {};

  @override
  Future<PlaybackInitializationResult> getPlaybackInitialization(PlaybackInitializationOptions options) async {
    decisions++;
    if (!reachable) throw StateError('server unreachable');
    return PlaybackInitializationResult(
      availableVersions: const [],
      videoUrl: 'https://example.invalid/${options.metadata.id}',
    );
  }

  @override
  Future<PlaybackExtras> fetchPlaybackExtras(
    String itemId, {
    String? introPattern,
    String? creditsPattern,
    bool forceChapterFallback = false,
    bool forceRefresh = false,
  }) async => PlaybackExtras(chapters: const [], markers: const []);

  @override
  Future<PlaybackExtras?> fetchPlaybackExtrasFromCacheOnly(
    String itemId, {
    String? introPattern,
    String? creditsPattern,
    bool forceChapterFallback = false,
  }) async => null;

  @override
  Future<void> onPlaybackReport(PlaybackReportCall call) async {}

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
