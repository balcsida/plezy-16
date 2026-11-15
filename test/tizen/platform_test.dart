import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/download_models.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/download_status_icon.dart';

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

  Iterable<NavigationTabId> tabs({required bool isOffline}) =>
      NavigationTab.getVisibleTabs(isOffline: isOffline).map((tab) => tab.id);

  testWidgets('Tizen offers no downloads', (tester) async {
    // The download service is off there, as on Apple TV: a control would queue nothing.
    expect(PlatformDetector.supportsDownloads(), isFalse);
    expect(tabs(isOffline: false), isNot(contains(NavigationTabId.downloads)));
    // Offline has no downloads to open either: it lands on Settings.
    expect(tabs(isOffline: true), [NavigationTabId.settings]);
    await tester.pumpWidget(const Center(child: DownloadStatusIcon(status: DownloadStatus.completed)));
    expect(tester.getSize(find.byType(DownloadStatusIcon)), Size.zero);
  }, skip: !const bool.fromEnvironment('TIZEN_BUILD'));

  testWidgets('a non-Tizen build keeps its downloads, except on Apple TV', (tester) async {
    expect(PlatformDetector.supportsDownloads(), isTrue);
    expect(tabs(isOffline: false), contains(NavigationTabId.downloads));
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: DownloadStatusIcon(status: DownloadStatus.completed)),
      ),
    );
    expect(tester.getSize(find.byType(DownloadStatusIcon)), isNot(Size.zero));

    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    expect(PlatformDetector.supportsDownloads(), isFalse);
    expect(tabs(isOffline: false), isNot(contains(NavigationTabId.downloads)));
  }, skip: const bool.fromEnvironment('TIZEN_BUILD'));
}
