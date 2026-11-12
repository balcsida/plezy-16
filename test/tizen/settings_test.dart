import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/playback_settings_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';

import '../test_helpers/prefs.dart';

void main() {
  testWidgets('the TV offers the Playback Buffer tiers, without Android\'s description', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(theme: monoTheme(MonoPalette.dark), home: const PlaybackSettingsScreen()));
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(ListTile, 'Playback Buffer');
    // The whole subtitle: the description speaks of a Buffer Size setting the TV has not.
    expect(find.descendant(of: tile, matching: find.text('Auto (Recommended)')), findsOneWidget);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extra Large'));
    await tester.pumpAndSettle();

    expect(SettingsService.instance.read(SettingsService.playbackBufferTier), PlaybackBufferTier.extraLarge);
    expect(find.descendant(of: tile, matching: find.text('Extra Large')), findsOneWidget);
  }, skip: !const bool.fromEnvironment('TIZEN_BUILD'));
}
