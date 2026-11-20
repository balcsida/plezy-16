import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/plezy_server.dart';
import 'package:plezy/services/trackers/mal/mal_constants.dart';
import 'package:plezy/services/trackers/mdblist/mdblist_constants.dart';
import 'package:plezy/services/trackers/simkl/simkl_constants.dart';
import 'package:plezy/services/trackers/trakt/trakt_constants.dart';

void main() {
  // A misspelled key builds without an error and leaves upstream's value in the TV build.
  test('every value in defines.env reaches the constant it is meant for', () {
    const constants = {
      'PLEZY_SERVER_URL': plezyServerBaseUrl,
      'TRAKT_CLIENT_ID': TraktConstants.clientId,
      'TRAKT_CLIENT_SECRET': TraktConstants.clientSecret,
      'SIMKL_CLIENT_ID': SimklConstants.v2ClientId,
      'MDBLIST_CLIENT_ID': MdblistConstants.clientId,
      'MAL_CLIENT_ID': MalConstants.clientId,
    };
    final lines = File('scripts/tizen/defines.env').readAsLinesSync().map((line) => line.trim());
    for (final line in lines.where((line) => line.isNotEmpty && !line.startsWith('#'))) {
      final split = line.indexOf('=');
      final key = line.substring(0, split);
      expect(constants[key], line.substring(split + 1), reason: key);
    }
  }, skip: !const bool.fromEnvironment('TIZEN_BUILD'));
}
