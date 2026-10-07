import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_parser/social_parser.dart';
import 'package:social_parser_js/social_parser_js.dart';
import 'signatures_test.dart' show probe;

class Capture implements ParserHttpClient {
  final delegate = DioParserHttpClient();
  String player = '';
  @override
  Future<ParserResponse> get(Uri u, ParseOptions o) async {
    final r = await delegate.get(u, o);
    if (u.path.endsWith('/base.js')) player = r.body;
    return r;
  }

  @override
  Future<ParserResponse> post(Uri u, Object b, ParseOptions o) =>
      delegate.post(u, b, o);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const link = String.fromEnvironment('YOUTUBE_TEST_LINK');
  const xhs = String.fromEnvironment('XHS_TEST_LINK');
  test(
    'live YouTube sources are accessible and real player solves signature/n',
    () async {
      HttpOverrides.global = null;
      final http = Capture();
      final parser = await createSocialParser(
        http: http,
        loadAsset: (p) => File(p).readAsString(),
      );
      final r = await parser.parse(
        link,
        options: ParseOptions(timeout: const Duration(seconds: 120)),
      );
      final sources = r.media.expand((m) => m.sources).toList();
      expect(sources, isNotEmpty);
      var accessible = false;
      for (final s in sources.take(4)) {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15);
        try {
          final request = await client.getUrl(s.url);
          s.headers.forEach(request.headers.set);
          request.headers.set('Range', 'bytes=0-0');
          final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
          final ok = [200, 206].contains(response.statusCode);
          await response.listen((_) {}).cancel();
          if (ok) {
            accessible = true;
            break;
          }
        } finally {
          client.close(force: true);
        }
      }
      expect(accessible, isTrue);
      expect(http.player, isNotEmpty);
      final solved = await parser.sourceRuntime.execute(
        probe(),
        'parse',
        {
          'operation': 'challenge',
          'player': http.player,
          'signatures': [
            'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz',
          ],
          'nChallenges': ['abcdefghijklmnopqrstuvwxyz'],
        },
        http,
        ParseOptions(timeout: const Duration(seconds: 45)),
      );
      expect((solved['sig'] as Map).values.single, isNotEmpty);
      expect(
        (solved['n'] as Map).values.single,
        isNot('abcdefghijklmnopqrstuvwxyz'),
      );
      print(
        'YouTube JS: ${sources.length} sources; media accessible; real player signature/n solved.',
      );
    },
    skip: link.isEmpty,
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'live public XHS share parses without Cookie',
    () async {
      HttpOverrides.global = null;
      final parser = await createSocialParser(
        loadAsset: (p) => File(p).readAsString(),
      );
      final r = await parser.parse(
        xhs,
        options: ParseOptions(timeout: const Duration(seconds: 90)),
      );
      expect(r.media, isNotEmpty);
      expect(r.sourceId, 'official.xhs');
      print('XHS JS: ${r.media.length} media; no Cookie.');
    },
    skip: xhs.isEmpty,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
