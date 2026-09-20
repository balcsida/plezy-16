import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/mpv/player/platform/tizen_captions.dart';
import 'package:plezy/services/tizen_device_profile.dart';
import '../test_helpers/backend_client_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('profile makes no unverified decoder or subtitle-renderer claim', () {
    final profile = tizenDeviceProfile();
    final encoded = jsonEncode(profile);
    for (final unsupported in ['hevc', 'av1', 'vp9', 'dts', 'truehd', 'Embed']) {
      expect(encoded, isNot(contains(unsupported)));
    }
    expect(encoded, contains('h264'));
    expect(encoded, contains('1920'));
    expect(encoded, contains('1080'));
    expect(jsonEncode(tizenDeviceProfile(burnSubtitles: true)['SubtitleProfiles']), isNot(contains('External')));
  });

  test('SRT and WebVTT preserve timing and overlapping plain text', () {
    final srt = parseTizenCaptions(
      '1\n00:00:01,001 --> 00:00:03,500\n<i>One</i> &amp; two\n\n2\n00:00:02,000 --> 00:00:04,000\nThree',
    );
    expect(srt, [(start: 1001, end: 3500, text: 'One & two'), (start: 2000, end: 4000, text: 'Three')]);
    expect(parseTizenCaptions('WEBVTT\n\n00:01.000 --> 00:02.000 align:center\nTest').single, (
      start: 1000,
      end: 2000,
      text: 'Test',
    ));
    expect(parseTizenCaptions('[Script Info]\nTitle: unsupported ASS'), isEmpty);
    expect(parseTizenCaptions('00:02.000 --> 00:01.000\nBackwards'), isEmpty);
  });

  test('Tizen negotiation keeps sparse server stream indexes and base path', () async {
    final client = testJellyfinClient(
      connection: testJellyfinConnection(baseUrl: 'https://example.test/jellyfin', accessToken: 'fixture-token'),
      handler: (request) async {
        expect(request.url.path, '/jellyfin/Items/fixture/PlaybackInfo');
        final body = jsonDecode(request.body) as Map;
        expect(body['AudioStreamIndex'], 7);
        expect(body['SubtitleStreamIndex'], 12);
        expect((body['DeviceProfile'] as Map)['Name'], 'Plezy Tizen 6');
        return http.Response('{"MediaSources":[]}', 200, headers: {'content-type': 'application/json'});
      },
    );
    await client.getPlaybackInfo('fixture', audioStreamIndex: 7, subtitleStreamIndex: 12);
  }, skip: !const bool.fromEnvironment('TIZEN_BUILD'));
}
