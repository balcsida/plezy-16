import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plezy/mpv/player/platform/tizen_captions.dart';
import 'package:plezy/services/download_storage_service.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/io_fakes.dart';
import '../test_helpers/prefs.dart';

void main() {
  test('only the mounts under /opt/media are offered as USB drives', () {
    expect(
      tizenUsbMountPoints(
        'rootfs / ext4 ro 0 0\n'
        'tmpfs /opt/media tmpfs rw 0 0\n'
        '/dev/sda1 /opt/media/USBDriveA1 vfat rw 0 0\n'
        '/dev/sdb1 /opt/media/My\\040Drive exfat rw 0 0\n',
      ),
      ['/opt/media/USBDriveA1', '/opt/media/My Drive'],
    );
  });

  test('a downloaded sidecar subtitle is read from its file', () async {
    final dir = await Directory.systemTemp.createTemp('tizen_captions_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/1 [a].srt')..writeAsStringSync('1\n00:00:01,000 --> 00:00:02,000\nLocal');
    final cues = await loadTizenCaptions(Uri.file(file.path), HttpClient());
    expect(cues.single.text, 'Local');
  });

  test('Tizen downloads to a chosen USB folder or not at all', () async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    DownloadStorageService.resetForTesting();
    final root = await Directory.systemTemp.createTemp('tizen_downloads_');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProvider(root);
    addTearDown(() async {
      DownloadStorageService.resetForTesting();
      SettingsService.resetForTesting();
      PathProviderPlatform.instance = previous;
      await root.delete(recursive: true);
    });

    final settings = await SettingsService.getInstance();
    final storage = DownloadStorageService.instance;
    await storage.initialize(settings);
    // The TV's own storage is never the fallback: no folder, no download.
    await expectLater(storage.getDownloadsDirectory(), throwsA(isA<DownloadStorageException>()));

    final usb = '${root.path}/USBDriveA1/Plezy/downloads';
    await settings.write(SettingsService.customDownloadPathType, 'file');
    await settings.write(SettingsService.customDownloadPath, usb);
    await storage.refreshCustomPath();
    expect((await storage.getDownloadsDirectory()).path, usb);
    expect(storage.artworkDirectoryPath, '${root.path}/USBDriveA1/Plezy/artwork');
  }, skip: !const bool.fromEnvironment('TIZEN_BUILD'));
}
