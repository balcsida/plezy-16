// request_location.dart
// Runtime location permission with three explicit outcomes.

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Returns the user's position or `null` if permission is denied.
Future<Position?> readPosition() async {
  var status = await Permission.location.status;

  if (status.isPermanentlyDenied) {
    // User checked "don't ask again" — popping the OS prompt again is a
    // no-op. Send them to settings instead.
    await openAppSettings();
    return null;
  }

  if (!status.isGranted) {
    status = await Permission.location.request();
    if (!status.isGranted) return null;
  }

  return Geolocator.getCurrentPosition();
}
