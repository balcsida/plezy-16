import '../../media/live_tv_support.dart';

/// Whether backgrounding may release the native video pipeline after its
/// grace period.
///
/// Retained live sessions stay paused with their player open because stopping
/// one would discard its capture buffer and time-shift position. On Tizen the
/// release is best effort: it frees the decoder before standby when the
/// process runs long enough, and [shouldRebuildPlayerOnResume] covers the rest.
bool shouldSuspendPlayerForTvBackground({
  required bool isAndroid,
  bool isTizen = false,
  required bool isTv,
  required bool isLive,
  required bool alreadySuspended,
}) {
  return (isAndroid || isTizen) && isTv && !isLive && !alreadySuspended;
}

/// Whether a resume rebuilds the playback session in place.
///
/// Android TV rebuilds only what its suspend released. Tizen rebuilds on every
/// resume: standby can freeze the process before the grace timer runs, and a
/// player held across it wakes with a dead connection. [openSettled] keeps the
/// rebuild off an open that is still in flight.
bool shouldRebuildPlayerOnResume({
  required bool suspended,
  required bool isTizen,
  required bool isLive,
  required bool openSettled,
}) {
  return suspended || (isTizen && !isLive && openSettled);
}

/// Whether the current TV live session must be closed before suspension.
bool shouldStopLiveSessionForTvBackground({required bool isTv, required LiveTvBackgroundPolicy? policy}) {
  return isTv && policy == LiveTvBackgroundPolicy.stopAndExit;
}
