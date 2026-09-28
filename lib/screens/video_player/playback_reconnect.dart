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

/// Bounds the automatic reopens of one failed item.
///
/// The caller decides which failures are eligible and runs the reopen. Only
/// the budget and the timer live here so they are testable with `fakeAsync`.
class PlaybackReconnect {
  PlaybackReconnect({required this.onAttempt, this.delays = playbackReconnectDelays});

  final List<Duration> delays;
  final void Function() onAttempt;

  int _spent = 0;
  Timer? _timer;

  bool get hasBudget => _spent < delays.length;

  /// Whether an attempt is armed and has not fired.
  bool get pending => _timer != null;

  /// Arms the next attempt, replacing a pending one. Returns false, arming
  /// nothing, once the budget is spent.
  bool schedule() {
    if (!hasBudget) return false;
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
  }
}
