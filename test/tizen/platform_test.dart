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
}
