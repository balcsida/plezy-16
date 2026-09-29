import 'dart:async';

import 'package:flutter/foundation.dart';

/// How often the clocks are compared: the longest a wake goes unnoticed.
const Duration wakeCheckPeriod = Duration(seconds: 2);

/// How far the wall clock may run ahead of the monotonic one before the gap
/// counts as a suspend rather than a clock correction.
const Duration wakeGapThreshold = Duration(seconds: 5);

/// How long the process has to keep running after a wake for it to count.
///
/// Measured on a UE55AU7022KXXH: for two hours after power-off the TV wakes
/// every five minutes and runs for six to eight seconds with its panel dark.
/// Acting on those reloaded the video fourteen times in one night.
// ponytail: the wait is the price of having no panel signal; drop it for one
// if the TV turns out to report its display state.
const Duration wakeSettle = Duration(seconds: 12);

/// Notices that the process was stopped without anybody telling it.
///
/// A Samsung TV powers off into standby without pausing the app. Measured on
/// a UE55AU7022KXXH: no pause or resume callback reached the host. After five
/// minutes the monotonic clock was 308 s behind the wall clock: the system
/// had suspended. After less than two the clocks agreed, so a short standby
/// can only show as a check that ran late, if the process was stopped at all.
// ponytail: a wall clock stepped forward by the threshold or more reads as a
// wake and costs one needless rebuild; compare against a boot-time clock from
// the host if a trace ever shows it.
class WakeDetector {
  WakeDetector({required this.onWake, DateTime Function()? wallClock, Duration Function()? monotonic})
    : _wallClock = wallClock ?? _systemClock,
      _monotonic = monotonic ?? _processClock;

  /// Moves the default wall clock, as a standby the process never saw does.
  @visibleForTesting
  static Duration debugWallOffset = Duration.zero;

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static Duration _processClock() => _stopwatch.elapsed;
  static DateTime _systemClock() => DateTime.now().add(debugWallOffset);

  /// Called with the time the process did not see.
  final void Function(Duration gap) onWake;
  final DateTime Function() _wallClock;
  final Duration Function() _monotonic;

  Timer? _timer;
  late DateTime _wall;
  late Duration _mono;

  /// What the wake being waited out was missing, and the checks since.
  Duration? _missed;
  int _checksSinceWake = 0;

  void start() {
    stop();
    _missed = null;
    _wall = _wallClock();
    _mono = _monotonic();
    _timer = Timer.periodic(wakeCheckPeriod, (_) => _check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _check() {
    final wall = _wallClock();
    final mono = _monotonic();
    final ran = mono - _mono;
    // A suspended system stops the monotonic clock and leaves the wall clock.
    final suspended = wall.difference(_wall) - ran;
    // A frozen process stops this timer and leaves both clocks.
    // ponytail: a main thread blocked for the threshold reads the same and
    // costs one rebuild; tell them apart if a trace ever shows it.
    final frozen = ran - wakeCheckPeriod;
    _wall = wall;
    _mono = mono;
    final missed = suspended >= wakeGapThreshold
        ? suspended
        : frozen >= wakeGapThreshold
        ? frozen
        : null;
    if (missed != null) {
      // Stopped again before it settled: the wait starts over.
      _missed = missed;
      _checksSinceWake = 0;
      return;
    }
    final waited = _missed;
    // Counted in checks, which stop with the process, not read off a clock.
    if (waited == null || wakeCheckPeriod * ++_checksSinceWake < wakeSettle) return;
    _missed = null;
    onWake(waited);
  }
}
