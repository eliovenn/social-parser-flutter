import 'helpers.dart';
import 'dart:io';
import 'package:social_parser/social_parser.dart';
import 'package:test/test.dart';

class FakeHttp implements ParserHttpClient {
  final requests = <Uri>[];
  bool login = false;
  @override
  Future<ParserResponse> get(Uri url, ParseOptions options) async {
    requests.add(url);
    if (url.host == 'xhslink.com') {
      return ParserResponse(
        Uri.parse(
          'https://www.xiaohongshu.com/explore/fixture?xsec_token=needed&tracking=drop',
        ),
        '',
        200,
        {},
      );
    }
    return ParserResponse(
      login ? Uri.parse('https://www.xiaohongshu.com/login') : url,
      File(
        'packages/social_parser/test/fixtures/xhs_mixed.html',
      ).readAsStringSync(),
      200,
      {},
    );
  }

  @override
  Future<ParserResponse> post(Uri url, Object body, ParseOptions options) =>
      throw UnimplementedError();
}

void main() {
  setupSources();
  test(
    'share text and short link preserve parse token, final URL removes it',
    () async {
      final http = FakeHttp();
      final result = await testParser(
        http: http,
      ).parse('来看这篇 https://xhslink.com/a/xyz。');
      expect(http.requests.last.queryParameters, {
        'xsec_token': 'needed',
        'tracking': 'drop',
      });
      expect(result.canonicalUrl.query, '');
      expect(result.inputUrl.host, 'xhslink.com');
      expect(result.media.map((m) => m.type), [
        MediaType.image,
        MediaType.livePhoto,
      ]);
      expect(result.media.last.sources.map((s) => s.track), [
        MediaTrack.image,
        MediaTrack.audioVideo,
      ]);
      expect(
        result.media.first.sources.first.headers['Referer'],
        'https://www.xiaohongshu.com/',
      );
      expect(result.content, contains('literal undefined'));
      expect(result.content, isNot(contains('[话题]')));
      expect(ParseResult.fromJson(result.toJson()).toJson(), result.toJson());
    },
  );

  test('resolveUrl offers clean and parsing forms', () async {
    final parser = testParser(http: FakeHttp());
    expect((await parser.resolveUrl('https://xhslink.com/a/xyz')).query, '');
    expect(
      (await parser.resolveUrl(
        'https://xhslink.com/a/xyz',
        forParsing: true,
      )).queryParameters['xsec_token'],
      'needed',
    );
  });

  test(
    'recognition checks host boundaries and reports optional JS capability',
    () async {
      final parser = testParser();
      expect(
        parser.detectPlatform('https://youtube.com.evil.example/watch?v=1'),
        isNull,
      );
      expect(
        parser.detectPlatform('https://youtu.be/Hp1OsvXdut0'),
        SocialPlatform.youtube,
      );
      expect(
        parser.platforms
            .singleWhere((p) => p.platform == SocialPlatform.youtube)
            .available,
        isTrue,
      );
      expect(
        () => parser.parse('https://youtube.com/watch?v=1'),
        throwsA(
          isA<ParseException>().having(
            (e) => e.code,
            'code',
            ParseErrorCode.invalidInput,
          ),
        ),
      );
      expect(
        () => parser.parse('https://example.invalid/not-supported'),
        throwsA(
          isA<ParseException>().having(
            (e) => e.code,
            'code',
            ParseErrorCode.unknownPlatform,
          ),
        ),
      );
    },
  );

  test('authentication error is preserved', () {
    final http = FakeHttp()..login = true;
    expect(
      () => testParser(
        http: http,
      ).parse('https://www.xiaohongshu.com/explore/fixture'),
      throwsA(
        isA<ParseException>().having(
          (e) => e.code,
          'code',
          ParseErrorCode.authenticationRequired,
        ),
      ),
    );
  });

  test('options copy cookie and header maps', () {
    final cookies = {'session': 'a'};
    final options = ParseOptions(cookies: cookies);
    cookies['session'] = 'b';
    expect(options.cookies['session'], 'a');
    expect(() => options.cookies['session'] = 'c', throwsUnsupportedError);
  });
}
