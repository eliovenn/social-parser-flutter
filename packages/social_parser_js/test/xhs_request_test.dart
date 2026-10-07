import 'helpers.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:social_parser/social_parser.dart';
import 'package:test/test.dart';

const xhsUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36';

class XhsAdapter implements HttpClientAdapter {
  XhsAdapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async => handler(options);
  @override
  void close({bool force = false}) {}
}

String page({
  bool firstId = true,
  bool extraScript = false,
  String key = 'note123',
  String? noteId,
}) =>
    '<script>${extraScript ? 'var before=1; ' : ''}window.__INITIAL_STATE__=${jsonEncode({
      'note': {
        if (firstId) 'firstNoteId': 'recommendation',
        'noteDetailMap': {
          key: {
            'note': {
              'type': 'normal',
              'title': '公开笔记',
              'noteId': ?noteId,
              'imageList': [
                {'urlDefault': 'https://cdn.example/photo.webp'},
              ],
            },
          },
        },
      },
    })};${extraScript ? 'window.after=true;' : ''}</script>';

SocialParser client(ResponseBody Function(RequestOptions) handler) =>
    testParser(
      http: DioParserHttpClient(
        createDio: () => Dio()..httpClientAdapter = XhsAdapter(handler),
      ),
    );

void main() {
  setupSources();
  final mobilePage = File(
    'packages/social_parser/test/fixtures/xhs_mobile.html',
  ).readAsStringSync();

  test('desktop login falls back to mobile hydration without Cookie', () async {
    final calls = <RequestOptions>[];
    final parser = client((request) {
      calls.add(request);
      expect(
        request.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('cookie')),
      );
      if (request.headers['User-Agent'] == xhsUserAgent) {
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['/login'],
          },
        );
      }
      expect(request.uri.queryParameters['xsec_token'], 'a+b=');
      if (request.uri.path.startsWith('/explore/')) {
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': [
              '/discovery/item/note123?xsec_token=a%2Bb%3D&xsec_source=app_share',
            ],
          },
        );
      }
      return ResponseBody.fromString(mobilePage, 200);
    });
    final result = await parser.parse(
      'https://www.xiaohongshu.com/explore/note123?xsec_token=a%2Bb%3D&xsec_source=app_share',
    );
    expect(calls, hasLength(3));
    expect(result.title, '移动网页笔记');
    expect(result.media.map((m) => m.type), [
      MediaType.image,
      MediaType.livePhoto,
    ]);
    expect(
      result.media.first.sources.single.url.toString(),
      'https://sns-webpic-qc.xhscdn.com/fixture.jpg?sign=fixture',
    );
    expect(
      result.media.first.thumbnailUrl.toString(),
      'https://cdn.example/thumb.jpg',
    );
    expect(result.media.last.sources.map((s) => s.url.toString()), [
      'https://cdn.example/live.jpg',
      'https://cdn.example/live.mp4',
    ]);
  });

  test('stale Cookie also retries mobile anonymously', () async {
    final calls = <RequestOptions>[];
    final parser = client((request) {
      calls.add(request);
      final hasCookie = request.headers.keys.any(
        (key) => key.toLowerCase() == 'cookie',
      );
      if (request.headers['User-Agent'] == xhsUserAgent || hasCookie) {
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['/login'],
          },
        );
      }
      expect(
        request.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      return ResponseBody.fromString(mobilePage, 200);
    });
    final result = await parser.parse(
      'https://www.xiaohongshu.com/discovery/item/note123',
      options: ParseOptions(
        headers: {'cookie': 'web_session=stale', 'Authorization': 'stale'},
      ),
    );
    expect(result.media, hasLength(2));
    expect(calls, hasLength(4));
  });

  test(
    'public short link uses desktop HTML headers, no Cookie, and preserves all share parameters',
    () async {
      final calls = <RequestOptions>[];
      final parser = client((request) {
        calls.add(request);
        expect(request.headers['User-Agent'], xhsUserAgent);
        expect(request.headers['Accept'], contains('text/html'));
        expect(
          request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('cookie')),
        );
        if (request.uri.host == 'xhslink.cn') {
          return ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': [
                'https://www.xiaohongshu.com/discovery/item/note123?xsec_token=a%2Bb%3D&xsec_source=pc_share&app_platform=android',
              ],
            },
          );
        }
        expect(
          request.uri.query,
          'xsec_token=a%2Bb%3D&xsec_source=pc_share&app_platform=android',
        );
        return ResponseBody.fromString(page(), 200);
      });
      final result = await parser.parse(
        '分享 https://xhslink.cn/o/fixture <br/>复制后打开',
      );
      expect(calls, hasLength(2));
      expect(result.title, '公开笔记');
      expect(result.media, hasLength(1));
      expect(result.canonicalUrl.query, isEmpty);
    },
  );

  test(
    'Cookie is withheld from short host and supplied to a login-required note',
    () async {
      final cookies = <Object?>[];
      final parser = client((request) {
        cookies.add(request.headers['Cookie']);
        if (request.uri.host == 'xhslink.cn') {
          return ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': ['https://www.xiaohongshu.com/explore/note123'],
            },
          );
        }
        if (request.headers['Cookie'] != 'web_session=valid') {
          return ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': ['/login'],
            },
          );
        }
        return ResponseBody.fromString(page(), 200);
      });
      final result = await parser.parse(
        'https://xhslink.cn/o/fixture',
        options: ParseOptions(cookies: {'web_session': 'valid'}),
      );
      expect(result.media, hasLength(1));
      expect(cookies, [null, 'web_session=valid']);
    },
  );

  test(
    'bare host is normalized before sending Cookie and same-platform redirects keep it',
    () async {
      final calls = <RequestOptions>[];
      final parser = client((request) {
        calls.add(request);
        expect(request.uri.host, 'www.xiaohongshu.com');
        expect(request.headers['Cookie'], 'web_session=valid');
        return calls.length == 1
            ? ResponseBody.fromString(
                '',
                302,
                headers: {
                  'location': ['/explore/note123'],
                },
              )
            : ResponseBody.fromString(page(), 200);
      });
      await parser.parse(
        'http://xiaohongshu.com/discovery/item/note123',
        options: ParseOptions(cookies: {'web_session': 'valid'}),
      );
      expect(calls, hasLength(2));
    },
  );

  test(
    'stale Cookie falls back anonymously without carrying Cookie or Authorization',
    () async {
      final calls = <RequestOptions>[];
      final parser = client((request) {
        calls.add(request);
        return calls.length == 1
            ? ResponseBody.fromString(
                '',
                302,
                headers: {
                  'location': ['/login'],
                },
              )
            : ResponseBody.fromString(page(), 200);
      });
      final result = await parser.parse(
        'https://www.xiaohongshu.com/explore/note123',
        options: ParseOptions(
          cookies: {'web_session': 'stale'},
          headers: {'Authorization': 'test'},
        ),
      );
      expect(result.title, '公开笔记');
      expect(calls, hasLength(2));
      expect(
        calls.last.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(
        calls.last.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    },
  );

  test(
    'an empty mobile-style state is parseFailed, not presumed authenticationRequired',
    () async {
      final parser = client(
        (_) => ResponseBody.fromString(
          '<script>window.__INITIAL_STATE__={"note":{}};</script>',
          200,
        ),
      );
      await expectLater(
        parser.parse('https://www.xiaohongshu.com/explore/note123'),
        throwsA(
          isA<ParseException>().having(
            (e) => e.code,
            'code',
            ParseErrorCode.parseFailed,
          ),
        ),
      );
    },
  );

  test('external redirect stops before making another request', () async {
    var count = 0;
    final parser = client((_) {
      count++;
      return ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['https://attacker.example/explore/note123'],
        },
      );
    });
    await expectLater(
      parser.parse(
        'https://www.xiaohongshu.com/explore/note123',
        options: ParseOptions(cookies: {'web_session': 'secret'}),
      ),
      throwsA(
        isA<ParseException>().having(
          (e) => e.code,
          'code',
          ParseErrorCode.unsupportedContent,
        ),
      ),
    );
    expect(count, 1);
  });
}
