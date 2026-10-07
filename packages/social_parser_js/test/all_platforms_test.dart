import 'helpers.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'package:social_parser/social_parser.dart';
import 'package:test/test.dart';

class ScriptHttp implements ParserHttpClient {
  ScriptHttp(this.responses);
  final List<dynamic> responses;
  final calls = <(Uri, ParseOptions, Object?)>[];
  int step = 0;
  Future<ParserResponse> call(
    String method,
    Uri url,
    ParseOptions options,
    Object? body,
  ) async {
    calls.add((url, options, body));
    expect(
      step,
      lessThan(responses.length),
      reason: 'Unexpected request: $method ${url.path}',
    );
    final fixture = responses[step++] as Map;
    expect(method, fixture['method']);
    expect(url.path, fixture['path']);
    if (fixture['error'] == true) {
      throw const ParseException(ParseErrorCode.network, 'Fixture unavailable');
    }
    final data = fixture['data'];
    return ParserResponse(
      fixture['redirect'] == null
          ? url
          : Uri.parse(fixture['redirect'] as String),
      data is String ? data : jsonEncode(data),
      200,
      Map<String, List<String>>.from(fixture['headers'] as Map? ?? {}),
    );
  }

  @override
  Future<ParserResponse> get(Uri url, ParseOptions options) =>
      call('GET', url, options, null);
  @override
  Future<ParserResponse> post(Uri url, Object body, ParseOptions options) =>
      call('POST', url, options, body);
}

void main() {
  setupSources();
  final cases =
      jsonDecode(
            File(
              'packages/social_parser/test/fixtures/platform_cases.json',
            ).readAsStringSync(),
          )
          as List;
  for (final fixture in cases.cast<Map>()) {
    test(
      '${fixture['name']}: request, cookies, content and media mapping',
      () async {
        final http = ScriptHttp(fixture['responses'] as List);
        final parser = testParser(http: http);
        final result = await parser.parse(
          fixture['url'] as String,
          options: ParseOptions(
            cookies: {
              'csrftoken': 'fixture-csrf',
              'ct0': 'fixture-ct0',
              'auth_token': 'fixture-auth',
              'd_c0': 'fixture-dc0',
              'x_xhh_tokenid': 'fixture-device',
            },
          ),
        );
        expect(result.platform.name, fixture['name']);
        expect(result.media.map((m) => m.type.name), fixture['types']);
        expect(result.content, fixture['content']);
        expect(http.step, http.responses.length);
        for (final call in http.calls) {
          expect(
            call.$2.cookies['csrftoken'],
            call.$1.host.endsWith('tiktokv.com') ? isNull : 'fixture-csrf',
          );
        }
        for (final item in result.media) {
          expect(item.sources, isNotEmpty);
          for (final source in item.sources) {
            expect(source.url.host, 'cdn.example');
            for (final entry in (fixture['headers'] as Map).entries) {
              expect(source.headers[entry.key], entry.value);
            }
          }
        }
        expect(ParseResult.fromJson(result.toJson()).toJson(), result.toJson());
        if (result.platform == SocialPlatform.coolapk) {
          expect(http.calls.first.$1.queryParameters, {
            'shareKey': 'keep',
            's': 'keep',
          });
          expect(result.canonicalUrl.query, '');
        }
        if (result.platform == SocialPlatform.weixin) {
          expect(result.canonicalUrl.queryParameters, {
            '__biz': 'test',
            'mid': '1',
            'idx': '1',
            'sn': 'keep',
          });
        }
        if (result.platform == SocialPlatform.douyin) {
          expect(http.calls.first.$1.queryParameters['a_bogus'], isNotEmpty);
        }
        if (result.platform == SocialPlatform.tieba) {
          final fields = Uri.splitQueryString(http.calls.last.$3 as String);
          final actual = fields.remove('sign');
          final canonical = (fields.keys.toList()..sort())
              .map((k) => '$k=${fields[k]}')
              .join();
          expect(
            actual,
            md5
                .convert(
                  utf8.encode('${canonical}36770b1f34c9bbf2e7d1a99d2b82fa9e'),
                )
                .toString(),
          );
          expect(fields['tbs'], 'fixture-token');
        }
        if (result.platform == SocialPlatform.douban) {
          expect(result.media.last.duration, const Duration(seconds: 72));
        }
        if (result.platform == SocialPlatform.tiktok) {
          expect(result.media.single.sources, hasLength(2));
          expect(
            result.media.single.duration,
            const Duration(milliseconds: 1234),
          );
        }
      },
    );
  }

  test('registers all 20 platforms with unique identities', () {
    final parser = testParser();
    expect(
      parser.platforms.map((p) => p.platform).toSet(),
      SocialPlatform.values.toSet(),
    );
    expect(parser.platforms, hasLength(20));
    for (final fixture in cases.cast<Map>()) {
      final uri = Uri.parse(fixture['url'] as String);
      expect(
        parser.detectPlatform(
          uri.replace(host: '${uri.host}.evil.example').toString(),
        ),
        isNull,
      );
    }
  });

  test('Threads refuses a response for a different post', () async {
    final http = ScriptHttp([
      {
        'method': 'POST',
        'path': '/graphql/query',
        'data': {
          'data': {
            'data': {
              'edges': [
                {
                  'node': {
                    'thread_items': [
                      {
                        'post': {'code': 'wrong', 'caption': 'unrelated'},
                      },
                    ],
                  },
                },
              ],
            },
          },
        },
      },
    ]);
    await expectLater(
      testParser(http: http).parse(
        'https://www.threads.com/@user/post/right',
        options: ParseOptions(cookies: {'csrftoken': 'fixture'}),
      ),
      throwsA(isA<ParseException>()),
    );
  });

  test(
    'Instagram obtains CSRF cookie and sends it with the GraphQL form',
    () async {
      final http = ScriptHttp([
        {
          'method': 'GET',
          'path': '/',
          'data': '',
          'headers': {
            'set-cookie': ['csrftoken=server-csrf; Path=/; Secure'],
          },
        },
        {
          'method': 'POST',
          'path': '/graphql/query',
          'data': {
            'data': {
              'xdt_api__v1__media__shortcode__web_info': {
                'items': [
                  {
                    'code': 'test',
                    'media_type': 1,
                    'image_versions2': {
                      'candidates': [
                        {'url': 'https://cdn.example/a.jpg'},
                      ],
                    },
                  },
                ],
              },
            },
          },
        },
      ]);
      await testParser(http: http).parse('https://instagram.com/p/test/');
      expect(http.calls.last.$2.cookies['csrftoken'], 'server-csrf');
      expect(http.calls.last.$2.headers['x-csrftoken'], 'server-csrf');
    },
  );

  test(
    'TikTok ignores other feed IDs and falls back to the matching web photo',
    () async {
      final http = ScriptHttp([
        {
          'method': 'GET',
          'path': '/aweme/v1/feed/',
          'data': {
            'aweme_list': [
              {'aweme_id': 'other', 'desc': 'wrong'},
            ],
          },
        },
        {
          'method': 'GET',
          'path': '/@user/photo/123',
          'data':
              '<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__">${jsonEncode({
                '__DEFAULT_SCOPE__': {
                  'webapp.video-detail': {
                    'itemInfo': {
                      'itemStruct': {
                        'id': '123',
                        'desc': 'photo',
                        'imagePost': {
                          'images': [
                            {
                              'imageURL': {
                                'urlList': ['https://cdn.example/photo.jpg'],
                              },
                            },
                          ],
                        },
                      },
                    },
                  },
                },
              })}</script>',
        },
      ]);
      final result = await testParser(
        http: http,
      ).parse('https://tiktok.com/@user/photo/123');
      expect(result.media.single.type, MediaType.image);
      expect(result.content, 'photo');
    },
  );

  test('Douyin short link resolves a share page without a Cookie', () async {
    final http = ScriptHttp([
      {
        'method': 'GET',
        'path': '/code/',
        'redirect': 'https://www.iesdouyin.com/share/video/123/',
        'data': '',
      },
      {
        'method': 'GET',
        'path': '/share/video/123/',
        'data':
            '<script>window._ROUTER_DATA = ${jsonEncode({
              'loaderData': {
                'video': {
                  'videoInfoRes': {
                    'item_list': [
                      {
                        'aweme_id': '123',
                        'desc': 'share',
                        'video': {
                          'play_addr': {
                            'url_list': ['https://cdn.example/v.mp4'],
                          },
                        },
                      },
                    ],
                  },
                },
              },
            })};</script>',
      },
    ]);
    final result = await testParser(
      http: http,
    ).parse('分享 https://v.douyin.com/code/');
    expect(result.media.single.type, MediaType.video);
    expect(result.content, 'share');
  });

  test(
    'Kuaishou atlas joins CDN and paths without treating cover as video',
    () async {
      final http = ScriptHttp([
        {
          'method': 'GET',
          'path': '/fw/photo/123',
          'data':
              '<script>window.INIT_STATE = ${jsonEncode({
                'detail': {
                  'photo': {'id': '123', 'caption': 'atlas'},
                  'atlas': {
                    'cdn': ['cdn.example'],
                    'list': ['a.webp', 'b.jpg'],
                    'size': [
                      {'w': 100, 'h': 200},
                      {'w': 300, 'h': 400},
                    ],
                  },
                },
              })};</script>',
        },
      ]);
      final result = await testParser(
        http: http,
      ).parse('https://v.m.chenzhongtech.com/fw/photo/123');
      expect(result.media.map((m) => m.type), [
        MediaType.image,
        MediaType.image,
      ]);
      expect(
        result.media.last.sources.single.url.toString(),
        'https://cdn.example/b.jpg',
      );
      expect(result.media.last.width, 300);
    },
  );

  test(
    'Xiaoheihe reports token errors without leaking cookie values',
    () async {
      final http = ScriptHttp([
        {
          'method': 'GET',
          'path': '/bbs/app/link/tree',
          'data': {'status': 'lack_token'},
        },
      ]);
      await expectLater(
        testParser(http: http).parse(
          'https://xiaoheihe.cn/app/bbs/link/123',
          options: ParseOptions(cookies: {'secret': 'must-not-leak'}),
        ),
        throwsA(
          isA<ParseException>()
              .having(
                (e) => e.code,
                'code',
                ParseErrorCode.authenticationRequired,
              )
              .having(
                (e) => e.message,
                'message',
                isNot(contains('must-not-leak')),
              ),
        ),
      );
    },
  );

  test('Weibo MP4 animation is not mislabeled as a Live Photo', () async {
    final http = ScriptHttp([
      {
        'method': 'GET',
        'path': '/ajax/statuses/show',
        'data': {
          'id': 'abc',
          'text_raw': 'gif',
          'pic_infos': {
            'a': {
              'type': 'gif',
              'largest': {'url': 'https://cdn.example/preview.jpg'},
              'video': 'https://cdn.example/animation.mp4',
            },
          },
        },
      },
    ]);
    final result = await testParser(
      http: http,
    ).parse('https://weibo.com/111/abc');
    expect(result.media.single.type, MediaType.animation);
    expect(result.media.single.sources.single.track, MediaTrack.audioVideo);
  });

  test('Douyin accepts an image slides share URL', () async {
    final http = ScriptHttp([
      {
        'method': 'GET',
        'path': '/share/video/123/',
        'data':
            '<script>window._ROUTER_DATA = ${jsonEncode({
              'post': {
                'aweme_id': '123',
                'images': [
                  {
                    'url_list': ['https://cdn.example/photo.jpg'],
                  },
                ],
              },
            })};</script>',
      },
    ]);
    final result = await testParser(
      http: http,
    ).parse('https://www.iesdouyin.com/share/slides/123/');
    expect(result.media.single.type, MediaType.image);
  });
}
