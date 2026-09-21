import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/platform_detector.dart';

void main() {
  test('Tizen selects TV navigation, not the host desktop services', () {
    if (!const bool.fromEnvironment('TIZEN_BUILD')) return;
    expect(PlatformDetector.isTV(), isTrue);
    expect(PlatformDetector.isDesktopOS(), isFalse);
    expect(PlatformDetector.supportsExternalPlayers(), isFalse);
    expect(PlatformDetector.supportsAudioPassthrough(), isFalse);
  });

  test('Tizen offers no mpv tuning settings', () {
    // PlayerTizen.setProperty rejects every mpv option, so the mpv.conf
    // editor, hwdec, deinterlace, the downmix filters and volume-max all
    // point at something that cannot accept them.
    if (!const bool.fromEnvironment('TIZEN_BUILD')) return;
    expect(PlatformDetector.supportsMpvTuning(), isFalse);
  });

  test('a non-Tizen build keeps its mpv tuning settings', () {
    if (const bool.fromEnvironment('TIZEN_BUILD')) return;
    expect(PlatformDetector.supportsMpvTuning(), isTrue);
  });
}
