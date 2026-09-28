import 'dart:async';

import 'package:flutter/foundation.dart';

/// How often the clocks are compared: the longest a wake goes unnoticed.
const Duration wakeCheckPeriod = Duration(seconds: 2);

/// How far the wall clock may run ahead of the monotonic one before the gap
/// counts as a suspend rather than a clock correction.
const Duration wakeGapThreshold = Duration(seconds: 5);

/// Notices that the system was suspended under a process nobody told.
///
/// A Samsung TV powers off into standby without pausing the app. Measured on
/// a UE55AU7022KXXH: no pause or resume callback reached the host, and the
/// process stayed frozen for the whole standby. The monotonic clock stops
/// with the process while the wall clock keeps running, so the two drifting
/// apart is the only signal there is.
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

  void start() {
    stop();
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
    final gap = wall.difference(_wall) - (mono - _mono);
    _wall = wall;
    _mono = mono;
    if (gap >= wakeGapThreshold) onWake(gap);
  }
}
