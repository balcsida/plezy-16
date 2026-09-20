import 'dart:convert';
import 'dart:io';

typedef TizenCue = ({int start, int end, String text});

/// Plain SRT/WebVTT only. ASS styling and bitmap formats belong to server burn-in.
List<TizenCue> parseTizenCaptions(String source) {
  final cues = <TizenCue>[];
  final time = RegExp(r'(?:(\d+):)?(\d{2}):(\d{2})[.,](\d{3})');
  int millis(RegExpMatch m) =>
      ((int.parse(m[1] ?? '0') * 60 + int.parse(m[2]!)) * 60 + int.parse(m[3]!)) * 1000 + int.parse(m[4]!);
  for (final block in source.replaceAll('\r', '').split(RegExp(r'\n\s*\n'))) {
    final lines = block.split('\n');
    final index = lines.indexWhere((line) => line.contains('-->'));
    if (index < 0) continue;
    final times = time.allMatches(lines[index]).toList();
    if (times.length != 2) continue;
    final start = millis(times[0]), end = millis(times[1]);
    if (end <= start) continue;
    final text = lines
        .skip(index + 1)
        .join('\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
    cues.add((start: start, end: end, text: text));
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

/// Bounded, TLS-validating fetch. Redirects stay on the original origin; no
/// Authorization/Cookie header is copied to another server. URLs never log.
Future<List<TizenCue>> loadTizenCaptions(Uri uri, HttpClient client) async {
  final origin = uri.origin;
  for (var redirects = 0; redirects <= 3; redirects++) {
    if (!['http', 'https'].contains(uri.scheme) || uri.userInfo.isNotEmpty || uri.origin != origin) {
      throw const FormatException('Unsafe subtitle URL');
    }
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.isRedirect) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      // Do not consume an unbounded redirect response body.
      await response.listen((_) {}).cancel();
      if (location == null) throw const FormatException('Subtitle redirect missing location');
      uri = uri.resolve(location);
      continue;
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.listen((_) {}).cancel();
      throw const HttpException('Subtitle request failed');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      if (bytes.length + chunk.length > 2 * 1024 * 1024) {
        throw const FormatException('Subtitle exceeds 2 MiB text limit');
      }
      bytes.addAll(chunk);
    }
    return parseTizenCaptions(utf8.decode(bytes));
  }
  throw const HttpException('Too many subtitle redirects');
}
