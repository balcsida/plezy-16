import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/mpv/player/platform/tizen_captions.dart';
import 'package:plezy/services/download_storage_service.dart';

void main() {
  test('only the mounts under /opt/media are offered as USB drives', () {
    expect(
      tizenUsbMountPoints(
        'rootfs / ext4 ro 0 0\n'
        'tmpfs /opt/media tmpfs rw 0 0\n'
        '/dev/sda1 /opt/media/USBDriveA1 vfat rw 0 0\n'
        // A space and a backslash in a name are written as octal escapes.
        '/dev/sdb1 /opt/media/My\\040Drive\\134x exfat rw 0 0\n',
      ),
      ['/opt/media/USBDriveA1', r'/opt/media/My Drive\x'],
    );
  });

  test('a download folder counts only while its drive is mounted', () {
    const mounted = '/dev/sda1 /opt/media/USBDriveA1 vfat rw 0 0\n';
    expect(isOnTizenUsbDrive(mounted, '/opt/media/USBDriveA1/Plezy/downloads'), isTrue);
    // Unplugged, the same path is a plain directory; the TV's own storage never counts.
    expect(isOnTizenUsbDrive('', '/opt/media/USBDriveA1/Plezy/downloads'), isFalse);
    expect(isOnTizenUsbDrive(mounted, '/opt/usr/home/owner/apps_rw/app/data/downloads'), isFalse);
    expect(isOnTizenUsbDrive(mounted, '/opt/media/USBDriveA10/Plezy/downloads'), isFalse);
  });

  test('a downloaded sidecar subtitle is read from its file', () async {
    final dir = await Directory.systemTemp.createTemp('tizen_captions_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/1 [a].srt')..writeAsStringSync('1\n00:00:01,000 --> 00:00:02,000\nLocal');
    final cues = await loadTizenCaptions(Uri.file(file.path), HttpClient());
    expect(cues.single.text, 'Local');
  });
}
