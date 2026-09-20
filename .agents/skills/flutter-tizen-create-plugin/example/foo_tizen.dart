// foo_tizen.dart
// Dart-facing API. The MethodChannel name must match the C++ side.

import 'package:flutter/services.dart';

class FooTizen {
  static const _channel = MethodChannel('foo_tizen');

  Future<String?> getDataPath() {
    return _channel.invokeMethod<String>('getDataPath');
  }
}
