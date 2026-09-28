import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/live_tv_support.dart';
import 'package:plezy/screens/video_player/tv_background_suspend_policy.dart';

void main() {
  test('Android TV VOD releases the player after the background grace period', () {
    expect(
      shouldSuspendPlayerForTvBackground(isAndroid: true, isTv: true, isLive: false, alreadySuspended: false),
      isTrue,
    );
  });

  test('Tizen VOD releases the player so standby cannot strand its stream', () {
    expect(
      shouldSuspendPlayerForTvBackground(
        isAndroid: false,
        isTizen: true,
        isTv: true,
        isLive: false,
        alreadySuspended: false,
      ),
      isTrue,
    );
  });

  test('live TV retains its tuned session and time-shift state', () {
    expect(
      shouldSuspendPlayerForTvBackground(isAndroid: true, isTv: true, isLive: true, alreadySuspended: false),
      isFalse,
    );
  });

  test('non-Android and non-TV players do not use the TV suspend flow', () {
    expect(
      shouldSuspendPlayerForTvBackground(isAndroid: false, isTv: true, isLive: false, alreadySuspended: false),
      isFalse,
    );
    expect(
      shouldSuspendPlayerForTvBackground(isAndroid: true, isTv: false, isLive: false, alreadySuspended: false),
      isFalse,
    );
  });

  test('an already suspended player is not scheduled again', () {
    expect(
      shouldSuspendPlayerForTvBackground(isAndroid: true, isTv: true, isLive: false, alreadySuspended: true),
      isFalse,
    );
  });

  bool rebuild({bool suspended = false, bool isTizen = true, bool isLive = false, bool openSettled = true}) =>
      shouldRebuildPlayerOnResume(
        suspended: suspended,
        isTizen: isTizen,
        isTv: true,
        isLive: isLive,
        openSettled: openSettled,
      );

  test('Tizen rebuilds on every resume, whether or not the suspend ran first', () {
    expect(rebuild(), isTrue);
    expect(rebuild(suspended: true), isTrue);
  });

  test('Android TV rebuilds only what its suspend released', () {
    expect(rebuild(isTizen: false), isFalse);
    expect(rebuild(isTizen: false, suspended: true), isTrue);
  });

  test('a resume never rebuilds live TV or an open that is still in flight', () {
    expect(rebuild(isLive: true), isFalse);
    expect(rebuild(openSettled: false), isFalse);
  });

  test('TV backgrounding stops non-resumable live sessions', () {
    expect(shouldStopLiveSessionForTvBackground(isTv: true, policy: LiveTvBackgroundPolicy.stopAndExit), isTrue);
  });

  test('TV backgrounding retains capture-buffer sessions', () {
    expect(shouldStopLiveSessionForTvBackground(isTv: true, policy: LiveTvBackgroundPolicy.retainSession), isFalse);
  });

  test('non-TV backgrounding does not use the TV live-session policy', () {
    expect(shouldStopLiveSessionForTvBackground(isTv: false, policy: LiveTvBackgroundPolicy.stopAndExit), isFalse);
  });
}
