import 'helpers.dart';
import 'dart:convert';
import 'package:social_parser/social_parser.dart';
import 'package:test/test.dart';

class Http implements ParserHttpClient {
  Http(this.reply);
  final Object Function(Uri, Object?, ParseOptions) reply;
  @override
  Future<ParserResponse> get(Uri u, ParseOptions o) async =>
      response(u, null, o);
  @override
  Future<ParserResponse> post(Uri u, Object b, ParseOptions o) async =>
      response(u, b, o);
  ParserResponse response(Uri u, Object? b, ParseOptions o) {
    final value = reply(u, b, o);
    return ParserResponse(
      u,
      value is String ? value : jsonEncode(value),
      200,
      {},
    );
  }
}

void main() {
  setupSources();
  test(
    'Snapchat selects the requested Spotlight, never a neighbouring story',
    () async {
      final http = Http(
        (u, b, o) =>
            '<script id="__NEXT_DATA__">${jsonEncode({
              'props': {
                'pageProps': {
                  'spotlightFeed': {
                    'spotlightStories': [
                      for (final key in ['wrong', 'wanted']) {
                          'story': {
                            'storyId': {'value': key},
                          },
                          'metadata': {
                            'videoMetadata': {'name': key, 'contentUrl': 'https://cdn.example/$key.mp4', 'durationMs': 1200},
                          },
                        },
                    ],
                  },
                },
              },
            })}</script>',
      );
      final parser = testParser(http: http);
      expect(parser.detectPlatform('https://snapchat.com/@someone'), isNull);
      final result = await parser.parse(
        'https://snapchat.com/spotlight/wanted',
      );
      expect(result.title, 'wanted');
      expect(result.media.single.duration, const Duration(milliseconds: 1200));
    },
  );
  test(
    'Facebook Relay returns direct, HLS and DASH sources of the requested video only',
    () async {
      final http = Http(
        (u, b, o) =>
            '<script data-sjs>${jsonEncode({
              'data': [
                {'__typename': 'Video', 'id': '999', 'playable_url': 'https://cdn.example/wrong.mp4'},
                {
                  '__typename': 'Video',
                  'id': '123',
                  'name': 'Target',
                  'videoDeliveryResponseFragment': {
                    'videoDeliveryResponseResult': {
                      'progressive_urls': [
                        {'progressive_url': 'https://cdn.example/a.mp4'},
                      ],
                      'dash_manifest_urls': [
                        {'manifest_url': 'https://cdn.example/a.mpd'},
                      ],
                      'hls_playlist_urls': [
                        {'hls_playlist_url': 'https://cdn.example/a.m3u8'},
                      ],
                    },
                  },
                },
              ],
            })}</script>',
      );
      final result = await testParser(
        http: http,
      ).parse('https://facebook.com/reel/123');
      expect(result.media.single.sources.map((s) => s.kind).toSet(), {
        MediaSourceKind.direct,
        MediaSourceKind.hls,
        MediaSourceKind.dash,
      });
      expect(
        result.media.single.sources.every((s) => !s.url.path.contains('wrong')),
        isTrue,
      );
      expect(
        result.media.single.sources.first.headers['User-Agent'],
        'facebookexternalhit/1.1',
      );
    },
  );
  test('Facebook legacy and inline DASH reject fragment directories', () async {
    final payload = {
      'instances': [
        [
          null,
          ['VideoConfig'],
          [
            {
              'video_id': '123',
              'videoData': [
                {
                  'hd_src': 'https://cdn.example/hd.mp4',
                  'dash_manifest':
                      '<MPD><Period><AdaptationSet mimeType="video/mp4"><Representation id="good"><BaseURL>https://cdn.example/full.mp4</BaseURL><SegmentBase/></Representation><Representation id="bad"><BaseURL>https://cdn.example/fragments/</BaseURL><SegmentTemplate media="x"/></Representation></AdaptationSet></Period></MPD>',
                },
              ],
            },
          ],
        ],
      ],
    };
    final http = Http(
      (u, b, o) => '<script>handleServerJS(${jsonEncode(payload)});</script>',
    );
    final result = await testParser(
      http: http,
    ).parse('https://facebook.com/watch?v=123');
    expect(result.media.single.sources.map((s) => s.url.path).toSet(), {
      '/hd.mp4',
      '/full.mp4',
    });
  });
  test(
    'Bilibili WBI official signing vector and signed fallback with split tracks',
    () async {
      const img = 'https://i.example/7cd084941338484aae1ad9425b84077c.png';
      const sub = 'https://i.example/4932caff0ff746eab6f01bf08b70ac45.png';
      final paths = <String>[];
      final http = Http((u, b, o) {
        paths.add(u.path);
        if (u.path == '/x/web-interface/view/detail') {
          throw const ParseException(
            ParseErrorCode.parseFailed,
            'old endpoint failed',
          );
        }
        if (u.path.endsWith('/nav')) {
          return {
            'code': -101,
            'data': {
              'wbi_img': {'img_url': img, 'sub_url': sub},
            },
          };
        }
        expect(u.queryParameters['w_rid'], isNotEmpty);
        if (u.path.endsWith('/detail')) {
          return {
            'code': 0,
            'data': {
              'View': {
                'title': 'Part',
                'pages': [
                  {'cid': 1},
                  {'cid': 2},
                ],
              },
            },
          };
        }
        expect(u.queryParameters['cid'], '2');
        return {
          'code': 0,
          'data': {
            'dash': {
              'video': [
                {
                  'id': 80,
                  'baseUrl': 'https://cdn.example/v.m4s',
                  'codecs': 'avc1',
                },
              ],
              'audio': [
                {
                  'id': 30280,
                  'base_url': 'https://cdn.example/a.m4s',
                  'codecs': 'mp4a',
                },
              ],
            },
          },
        };
      });
      final result = await testParser(
        http: http,
      ).parse('https://www.bilibili.com/video/BV1xx411c7mD?p=2');
      expect(paths, contains('/x/player/wbi/playurl'));
      expect(result.media.single.sources.map((s) => s.track), [
        MediaTrack.video,
        MediaTrack.audio,
      ]);
    },
  );
}
