import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/models/trackers/device_code.dart';
import 'package:plezy/services/plezy_server.dart';
import 'package:plezy/services/trackers/mal/mal_constants.dart';
import 'package:plezy/services/trackers/mdblist/mdblist_constants.dart';
import 'package:plezy/services/trackers/simkl/simkl_constants.dart';
import 'package:plezy/services/trackers/trakt/trakt_auth_service.dart';
import 'package:plezy/services/trackers/trakt/trakt_constants.dart';

void main() {
  // A misspelled key builds without an error and leaves upstream's value in the TV build.
  test('every value in defines.env reaches the constant it is meant for', () {
    const constants = {
      'PLEZY_SERVER_URL': plezyServerBaseUrl,
      'TRAKT_CLIENT_ID': TraktConstants.clientId,
      'TRAKT_CLIENT_SECRET': TraktConstants.clientSecret,
      'SIMKL_CLIENT_ID': SimklConstants.v2ClientId,
      'SIMKL_LEGACY_CLIENT_ID': SimklConstants.legacyClientId,
      'TRACKER_APP_NAME': SimklConstants.appName,
      'MDBLIST_CLIENT_ID': MdblistConstants.clientId,
      'MAL_CLIENT_ID': MalConstants.clientId,
    };
    final lines = File('scripts/tizen/defines.env').readAsLinesSync().map((line) => line.trim());
    final set = <String>{};
    for (final line in lines.where((line) => line.isNotEmpty && !line.startsWith('#'))) {
      final split = line.indexOf('=');
      final key = line.substring(0, split);
      expect(constants[key], line.substring(split + 1), reason: key);
      set.add(key);
    }
    // A key left out would leave upstream's server or registration in the TV build.
    expect(set, constants.keys.toSet());
    expect(MdblistConstants.appName, SimklConstants.appName);
  }, skip: !const bool.fromEnvironment('TIZEN_BUILD'));

  // Trakt gives an app registered for PKCE no secret and asks that none be sent.
  test('a Trakt registration without a secret sends no secret', () async {
    final sent = <Map<String, dynamic>>[];
    final trakt = TraktAuthService(
      httpClient: MockClient((request) async {
        sent.add(json.decode(request.body) as Map<String, dynamic>);
        return http.Response('', 400);
      }),
    );
    addTearDown(trakt.dispose);
    await trakt.probe(
      const DeviceCode(deviceCode: 'code', userCode: 'CODE', verificationUrl: '', expiresIn: 600, interval: 5),
    );
    expect(sent.single['client_id'], TraktConstants.clientId);
    expect(sent.single.containsKey('client_secret'), TraktConstants.clientSecret.isNotEmpty);
  });
}
