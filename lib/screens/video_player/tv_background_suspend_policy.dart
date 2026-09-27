import '../../media/live_tv_support.dart';

/// Whether backgrounding may release the native video pipeline after its
/// grace period.
///
/// Retained live sessions stay paused with their player open because stopping
/// one would discard its capture buffer and time-shift position. On Tizen a
/// paused player held across standby wakes with a dead connection and fails
/// with `ConnectionFailed`, so it releases and reloads like Android TV.
bool shouldSuspendPlayerForTvBackground({
  required bool isAndroid,
  bool isTizen = false,
  required bool isTv,
  required bool isLive,
  required bool alreadySuspended,
}) {
  return (isAndroid || isTizen) && isTv && !isLive && !alreadySuspended;
}

/// Whether the current TV live session must be closed before suspension.
bool shouldStopLiveSessionForTvBackground({required bool isTv, required LiveTvBackgroundPolicy? policy}) {
  return isTv && policy == LiveTvBackgroundPolicy.stopAndExit;
}
