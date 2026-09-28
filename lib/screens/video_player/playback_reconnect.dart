import 'dart:async';

/// Waits between automatic reopens of an item that had already played.
///
/// mpv rides out a dropped network through ffmpeg's reconnect loop; a backend
/// without one (Tizen) reports the first failed connection as terminal, and
/// after standby the TV's network can lag the wake by several seconds.
// ponytail: guessed from a network that returns within ~30 s of wake plus a
// 45 s hung-open lease; resize from a device trace.
const List<Duration> playbackReconnectDelays = [
  Duration(seconds: 2),
  Duration(seconds: 3),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 10),
  Duration(seconds: 10),
  Duration(seconds: 10),
  Duration(seconds: 10),
];

/// How long after its first attempt was armed a schedule may arm another.
///
/// An attempt that fails at once spends little of it; one that waits out the
/// backend's own timeout (thirty seconds on Tizen) spends it in three.
// ponytail: sized from one evening's trace of a server slow to start sending
// (two timeouts, then eighteen seconds); resize from more of them.
const Duration playbackReconnectWindow = Duration(seconds: 90);

/// Bounds the automatic reopens of one failed item, by count and by time.
///
/// The caller decides which failures are eligible and runs the reopen. Only
/// the budget and the timer live here so they are testable with `fakeAsync`.
class PlaybackReconnect {
  PlaybackReconnect({
    required this.onAttempt,
    this.delays = playbackReconnectDelays,
    this.window = playbackReconnectWindow,
    Duration Function()? clock,
  }) : _clock = clock ?? _processClock;

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static Duration _processClock() => _stopwatch.elapsed;

  final List<Duration> delays;
  final Duration window;
  final void Function() onAttempt;
  final Duration Function() _clock;

  int _spent = 0;
  Duration? _firstArmed;
  Timer? _timer;

  bool get hasBudget {
    final firstArmed = _firstArmed;
    return _spent < delays.length && (firstArmed == null || _clock() - firstArmed < window);
  }

  /// Whether an attempt is armed and has not fired.
  bool get pending => _timer != null;

  /// Arms the next attempt, replacing a pending one. Returns false, arming
  /// nothing, once the budget is spent.
  bool schedule() {
    if (!hasBudget) return false;
    _firstArmed ??= _clock();
    _timer?.cancel();
    _timer = Timer(delays[_spent++], () {
      _timer = null;
      onAttempt();
    });
    return true;
  }

  /// A newer open owns the player. The spent attempt is not refunded: that is
  /// the loop guard.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// The user retried, the item changed, or the app resumed: a fresh budget.
  void reset() {
    cancel();
    _spent = 0;
    _firstArmed = null;
  }
}
