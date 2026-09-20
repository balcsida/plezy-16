import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../player_base.dart';
import '../video_rect_support.dart';
import 'tizen_captions.dart';

/// Public Tizen.Multimedia.Player in the C# TV host. No mpv library is loaded.
class PlayerTizen extends PlayerBase with VideoRectSupport {
  PlayerTizen({this.audioOnly = false});
  final bool audioOnly;
  static const _methods = MethodChannel('com.plezy/tizen_player');
  static const _events = EventChannel('com.plezy/tizen_player/events');
  @override
  MethodChannel get methodChannel => _methods;
  @override
  EventChannel get eventChannel => _events;
  @override
  String get logPrefix => 'Tizen';
  @override
  String get playerType => 'tizen';
  @override
  bool get nativeDisposeIsStaleGuarded => true;
  @override
  bool get supportsSecondarySubtitles => false;
  @override
  bool get attachesExternalSubtitlesAtOpen => true;
  @override
  bool get providesNativeStats => true;

  int _session = 0;
  int _subtitleGeneration = 0;
  bool _opened = false;
  double _volume = 100, _rate = 1;
  int _displayMode = 0;
  int? _width, _height;
  Duration? _pendingSeek;
  Future<void>? _seekWork;
  final caption = ValueNotifier<String>('');
  Timer? _captionTimer;
  HttpClient? _captionClient;
  List<TizenCue> _cues = const [];
  final List<Map<String, Object?>> _nativeTracks = [];
  final List<SubtitleTrack> _external = [];

  Future<T?> _call<T>(String method, [Map<String, Object?> args = const {}, int? session]) =>
      invoke<T>(method, {'instanceId': nativeInstanceId, 'session': session ?? _session, ...args});

  @override
  void handlePlayerEvent(String name, Map? data) {
    if (disposed || name != 'tizen' || data?['instanceId'] != nativeInstanceId || data?['session'] != _session) return;
    switch (data?['event']) {
      case 'ready':
        _width = data?['width'] as int?;
        _height = data?['height'] as int?;
        _nativeTracks
          ..clear()
          ..addAll((data?['tracks'] as List? ?? []).whereType<Map>().map((t) => Map<String, Object?>.from(t)));
        _publishTracks();
        handlePropertyChange('duration', (data?['durationMs'] as num? ?? 0) / 1000);
        handlePropertyChange('paused-for-cache', false);
        setSeekable(true);
        super.handlePlayerEvent('file-loaded', null);
      case 'position':
        final ms = data?['positionMs'] as int? ?? 0;
        handlePropertyChange('time-pos', ms / 1000);
        if (_cues.isNotEmpty) {
          // ponytail: bounded 2 MiB text file; a cue interval index if measured scans become costly.
          caption.value = _cues.where((c) => c.start <= ms && ms < c.end).map((c) => c.text).join('\n');
        }
      case 'playing':
        final playing = data?['value'] == true;
        handlePropertyChange('pause', !playing);
        if (playing) super.handlePlayerEvent('playback-restart', null);
      case 'buffering':
        // Buffering percent is NOT a fraction of the whole file cached.
        handlePropertyChange('paused-for-cache', data?['value'] == true);
      case 'audio':
        updateSelectedAudioTrack(data?['id']);
      case 'subtitle':
        if (state.track.subtitle?.id.startsWith('sub:') != true) return;
        _captionTimer?.cancel();
        caption.value = (data?['text'] as String? ?? '').replaceAll(RegExp(r'<[^>]*>'), '');
        final generation = _subtitleGeneration;
        _captionTimer = Timer(Duration(milliseconds: (data?['durationMs'] as int? ?? 3000).clamp(0, 60000)), () {
          if (!disposed && generation == _subtitleGeneration) caption.value = '';
        });
      case 'completed':
        handlePropertyChange('pause', true);
        super.handlePlayerEvent('end-file', {'reason': 'eof'});
        _clearCaption();
      case 'error':
        handlePropertyChange('paused-for-cache', false);
        handlePropertyChange('pause', true);
        // Only enum-like error codes from the bridge, never native exception text.
        final code = data?['code'];
        final safeCode = code is String && RegExp(r'^[A-Za-z0-9_]{1,80}$').hasMatch(code) ? code : 'playback';
        super.handlePlayerEvent('end-file', {'reason': 'error', 'message': 'Tizen player: $safeCode'});
    }
  }

  void _publishTracks() {
    handlePropertyChange('track-list', [
      ..._nativeTracks,
      for (final track in _external)
        {
          'id': track.id,
          'type': 'sub',
          'external': true,
          'external-filename': track.uri,
          'title': track.title,
          'lang': track.language,
        },
    ]);
  }

  /// Native APIs support only Cookie/User-Agent. Use Jellyfin's existing query
  /// token URLs, and only elide a *redundant matching* token header. Cookies and
  /// all other headers fail closed rather than creating a partially-authenticated
  /// session. No token is moved to a different URI/origin.
  static String? userAgentFor(Media media) {
    final uri = Uri.parse(media.uri);
    if (!['http', 'https', 'file'].contains(uri.scheme) || uri.userInfo.isNotEmpty) {
      throw const FormatException('Unsupported Tizen media URL');
    }
    String? agent;
    for (final entry in (media.headers ?? const <String, String>{}).entries) {
      final name = entry.key.toLowerCase();
      if (name == 'user-agent') {
        agent = entry.value;
        continue;
      }
      final token =
          uri.queryParameters['api_key'] ?? uri.queryParameters['X-Emby-Token'] ?? uri.queryParameters['X-Plex-Token'];
      if (['x-emby-token', 'x-plex-token'].contains(name) && token != null && token == entry.value) continue;
      throw UnsupportedError('Tizen playback requires URL-based authentication; unsupported header: $name');
    }
    return agent;
  }

  @override
  Future<void> open(
    Media media, {
    bool play = true,
    bool isLive = false,
    List<SubtitleTrack>? externalSubtitles,
    Duration? timelineDuration,
  }) async {
    if (disposed) throw StateError('Player disposed');
    final agent = userAgentFor(media);
    final session = ++_session;
    _pendingSeek = null;
    _clearCaption();
    _external
      ..clear()
      ..addAll(externalSubtitles ?? []);
    _nativeTracks.clear();
    clearTracks();
    setExternalSubtitleMetadata(externalSubtitles);
    configureTimeline(duration: timelineDuration);
    takeSourceOwnership();
    resetPlaybackProgress(media.start ?? Duration.zero);
    handlePropertyChange('pause', true);
    handlePropertyChange('paused-for-cache', true);
    super.handlePlayerEvent('start-file', null);
    _opened = true;
    try {
      await _call<void>('open', {
        'url': media.uri,
        'userAgent': agent,
        'startMs': media.start?.inMilliseconds ?? 0,
        'play': play,
        'audioOnly': audioOnly,
        'volume': _volume,
        'rate': _rate,
        'displayMode': _displayMode,
      }, session).timeout(const Duration(seconds: 45));
    } catch (_) {
      if (!disposed && session == _session) {
        handlePropertyChange('paused-for-cache', false);
        super.handlePlayerEvent('end-file', {'reason': 'error', 'message': 'Tizen could not open this stream'});
        await stop();
      }
      throw const PlayerInitializationException();
    }
  }

  @override
  Future<void> play() => _call<void>('play');
  @override
  Future<void> pause() => _call<void>('pause');
  @override
  Future<void> stop() async {
    final oldSession = _session++;
    _pendingSeek = null;
    _clearCaption();
    handlePropertyChange('pause', true);
    handlePropertyChange('paused-for-cache', false);
    setSeekable(false);
    if (_opened) {
      _opened = false;
      await _call<void>('stop', const {}, oldSession);
    }
  }

  @override
  Future<void> seek(Duration position) => runSeek(position, () {
    _clearCaption(clearCues: false);
    _pendingSeek = position;
    return _seekWork ??= _drainSeeks().whenComplete(() => _seekWork = null);
  });
  Future<void> _drainSeeks() async {
    while (!disposed && _pendingSeek != null) {
      final target = _pendingSeek!;
      final session = _session;
      _pendingSeek = null;
      await _call<void>('seek', {'positionMs': target.inMilliseconds.clamp(0, 2147483647)}, session);
      if (session == _session && !disposed) publishPlayheadRelocation(target);
    }
  }

  static int _nativeIndex(String id, String type) {
    if (!id.startsWith('$type:')) throw ArgumentError('Expected native $type track ID');
    final index = int.tryParse(id.substring(type.length + 1));
    if (index == null || index < 0) throw ArgumentError('Invalid native track ID');
    return index;
  }

  @override
  Future<void> selectAudioTrack(AudioTrack track) async {
    if (track == AudioTrack.auto) return; // Native default selection, not index zero.
    await _call<void>('selectAudioTrack', {'index': _nativeIndex(track.id, 'audio')});
    if (!disposed) updateSelectedAudioTrack(track.id);
  }

  @override
  Future<void> selectSubtitleTrack(SubtitleTrack track) async {
    _clearCaption();
    final generation = _subtitleGeneration;
    final session = _session;
    final external = track.uri != null && track.isExternal;
    final index = track == SubtitleTrack.off || external ? -1 : _nativeIndex(track.id, 'sub');
    await _call<void>('selectSubtitleTrack', {'index': index});
    if (disposed || session != _session || generation != _subtitleGeneration) return;
    updateSelectedSubtitleTrack(track.id);
    if (external) {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      _captionClient = client;
      try {
        final cues = await loadTizenCaptions(Uri.parse(track.uri!), client);
        if (cues.isEmpty) throw const FormatException('No supported text cues');
        if (!disposed && session == _session && generation == _subtitleGeneration) _cues = cues;
      } catch (_) {
        if (!disposed && session == _session && generation == _subtitleGeneration) {
          updateSelectedSubtitleTrack(SubtitleTrack.off.id);
          throw const FormatException('Tizen text subtitles unavailable; select server burn-in');
        }
      } finally {
        client.close(force: true);
        if (identical(_captionClient, client)) _captionClient = null;
      }
    }
  }

  @override
  Future<void> addSubtitleTrack({required String uri, String? title, String? language, bool select = false}) async {
    final track = SubtitleTrack.uri(uri, title: title, language: language);
    if (!_external.any((t) => t.uri == uri)) _external.add(track);
    _publishTracks();
    if (select) await selectSubtitleTrack(track);
  }

  void _clearCaption({bool clearCues = true}) {
    _subtitleGeneration++;
    _captionTimer?.cancel();
    _captionClient?.close(force: true);
    _captionClient = null;
    if (clearCues) _cues = const [];
    if (!disposed) caption.value = '';
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0, 100);
    if (_opened) await _call<void>('setVolume', {'volume': _volume});
    setVolumeState(_volume);
  }

  @override
  Future<void> setRate(double rate) async {
    if (!rate.isFinite || rate < 0.5 || rate > 2) throw ArgumentError('Tizen playback rate must be 0.5–2');
    _rate = rate;
    if (_opened) await _call<void>('setRate', {'rate': rate});
    setRateState(rate);
  }

  @override
  Future<bool> setVisible(bool visible, {bool restoreOnWindowVisible = false}) async {
    if (!_opened || audioOnly) return false;
    await _call<void>('setVisible', {'visible': visible});
    return true;
  }

  @override
  Future<void> setVideoRect({
    required int left,
    required int top,
    required int right,
    required int bottom,
    required double devicePixelRatio,
  }) => _call<void>('setVideoRect', {'left': left, 'top': top, 'right': right, 'bottom': bottom});
  @override
  Future<void> setBoxFitMode(int mode) async {
    if (mode < 0 || mode > 2) throw ArgumentError('Invalid display mode');
    _displayMode = mode;
    if (_opened) await _call<void>('setDisplayMode', {'mode': mode});
  }

  @override
  Future<Map<String, dynamic>> getStats() async => {
    'videoWidth': _width,
    'videoHeight': _height,
    'playerType': 'tizen',
    'videoDecoder': 'unknown',
  };
  @override
  Future<String?> getProperty(String name) async => switch (name) {
    'pause' => state.playing ? 'no' : 'yes',
    'time-pos' => '${currentPosition.inMilliseconds / 1000}',
    'duration' => '${state.duration.inMilliseconds / 1000}',
    'width' || 'dwidth' => _width?.toString(),
    'height' || 'dheight' => _height?.toString(),
    _ => null,
  };
  @override
  Future<void> setProperty(String name, String value) async {
    switch (name) {
      case 'pause':
        await (value == 'yes' ? pause() : play());
      case 'sub-visibility':
        if (value == 'no') await selectSubtitleTrack(SubtitleTrack.off);
      default:
        throw UnsupportedError('mpv option $name is unavailable on Tizen');
    }
  }

  @override
  Future<void> command(List<String> args) async => throw UnsupportedError('mpv commands are unavailable on Tizen');
  @override
  Future<void> dispose({bool preserveDisplayMode = false}) async {
    if (disposed) return;
    _session++;
    _pendingSeek = null;
    _clearCaption();
    await super.dispose(preserveDisplayMode: preserveDisplayMode);
    caption.dispose();
  }
}
