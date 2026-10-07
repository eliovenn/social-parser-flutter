import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_parser/social_parser.dart';
import 'helpers.dart';

class Http implements ParserHttpClient {
  Http(this.reply);
  final Object Function(Uri, Object?, ParseOptions) reply;
  @override
  Future<ParserResponse> get(Uri u, ParseOptions o) async =>
      respond(u, null, o);
  @override
  Future<ParserResponse> post(Uri u, Object b, ParseOptions o) async =>
      respond(u, b, o);
  ParserResponse respond(Uri u, Object? b, ParseOptions o) {
    final value = reply(u, b, o);
    return ParserResponse(
      u,
      value is String ? value : jsonEncode(value),
      200,
      {},
    );
  }
}

const id = 'Hp1OsvXdut0';
Map<String, dynamic> player(List<Object> formats, {String videoId = id}) => {
  'videoDetails': {
    'videoId': videoId,
    'title': 'Fixture',
    'lengthSeconds': '12',
  },
  'streamingData': {'formats': formats},
};
void main() {
  setupSources();
  test(
    'anonymous YouTube clients preserve Cookie policy, direct and separated tracks',
    () async {
      final names = <String>[];
      final http = Http((u, b, o) {
        if (u.path == '/watch') {
          return 'ytcfg.set({"PLAYER_JS_URL":"/s/player/test/base.js"});';
        }
        if (b == null) return 'signatureTimestamp:12345;';
        final body = b as Map,
            name = (body['context'] as Map)['client']['clientName'] as String;
        names.add(name);
        if (name == 'VISIONOS') {
          expect(o.cookies, isEmpty);
          expect(
            o.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('authorization')),
          );
        } else {
          expect(o.cookies['PREF'], 'test');
          expect(
            body['playbackContext']['contentPlaybackContext']['signatureTimestamp'],
            12345,
          );
        }
        return player([
          {
            'itag': 18,
            'url': 'https://cdn.example/plain.mp4',
            'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
          },
          {
            'itag': 140,
            'url': 'https://cdn.example/audio.m4a',
            'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
          },
        ]);
      });
      final r = await testParser(http: http).parse(
        'https://youtu.be/$id?si=tracking',
        options: ParseOptions(
          cookies: {'PREF': 'test'},
          headers: {'Authorization': 'test'},
        ),
      );
      expect(names, ['VISIONOS', 'WEB']);
      expect(r.canonicalUrl.toString(), 'https://www.youtube.com/watch?v=$id');
      expect(r.media.single.sources.map((s) => s.track), [
        MediaTrack.audioVideo,
        MediaTrack.audio,
      ]);
    },
  );
  test(
    'logged-in clients sign session headers without exposing Cookie contents',
    () async {
      final names = <String>[];
      final http = Http((u, b, o) {
        if (b == null) {
          return 'ytcfg.set({"USER_SESSION_ID":"user","SESSION_INDEX":1});';
        }
        final name =
            ((b as Map)['context'] as Map)['client']['clientName'] as String;
        names.add(name);
        expect(o.cookies['SAPISID'], 'secret');
        expect(o.headers['authorization'], startsWith('SAPISIDHASH '));
        expect(o.headers['authorization'], endsWith('_u'));
        expect(o.headers['authorization'], isNot(contains('secret')));
        expect(o.headers['x-goog-authuser'], '1');
        return player([
          {'itag': 18, 'url': 'https://cdn.example/a.mp4'},
        ]);
      });
      await testParser(http: http).parse(
        'https://youtube.com/embed/$id',
        options: ParseOptions(
          cookies: {'SAPISID': 'secret', 'LOGIN_INFO': 'yes'},
        ),
      );
      expect(names, ['WEB_EMBEDDED_PLAYER', 'TVHTML5', 'WEB']);
    },
  );
  test(
    'unrelated responses cannot become media and login is classified',
    () async {
      final http = Http(
        (u, b, o) => b == null
            ? ''
            : {
                ...player([
                  {'itag': 18, 'url': 'https://cdn.example/wrong.mp4'},
                ], videoId: 'other'),
                'playabilityStatus': {'status': 'LOGIN_REQUIRED'},
              },
      );
      await expectLater(
        testParser(http: http).parse('https://youtube.com/shorts/$id'),
        throwsA(
          isA<ParseException>().having(
            (e) => e.code,
            'code',
            ParseErrorCode.authenticationRequired,
          ),
        ),
      );
    },
  );
  test(
    'failed challenge drops only unsolved formats and retains HLS/DASH',
    () async {
      final http = Http(
        (u, b, o) => b == null
            ? ''
            : {
                ...player([
                  {'itag': 18, 'url': 'https://cdn.example/ok.mp4'},
                  {
                    'itag': 18,
                    'signatureCipher':
                        'url=https%3A%2F%2Fcdn.example%2Fbad.mp4&s=encrypted',
                  },
                ]),
                'streamingData': {
                  'formats': [
                    {'itag': 18, 'url': 'https://cdn.example/ok.mp4'},
                    {
                      'itag': 18,
                      'url': 'https://cdn.example/needs.mp4?n=throttle',
                    },
                  ],
                  'hlsManifestUrl': 'https://cdn.example/playlist.m3u8',
                  'dashManifestUrl': 'https://cdn.example/playlist.mpd',
                },
              },
      );
      final r = await testParser(http: http).parse('https://youtu.be/$id');
      expect(r.media.single.sources.map((s) => s.kind).toSet(), {
        MediaSourceKind.direct,
        MediaSourceKind.hls,
        MediaSourceKind.dash,
      });
      expect(
        r.media.single.sources.any((s) => s.url.path.contains('needs')),
        isFalse,
      );
    },
  );
  test(
    'cipher and n mapping preserve signed URL values and manifest track type',
    () async {
      final http = Http(
        (u, b, o) => b == null
            ? 'ytcfg.set({"PLAYER_JS_URL":"/s/player/test/base.js"});'
            : {
                'videoDetails': {'videoId': id},
                'streamingData': {
                  'formats': [
                    {
                      'itag': 18,
                      'signatureCipher': Uri(
                        queryParameters: {
                          'url':
                              'https://cdn.example/v.mp4?n=throttle&keep=a%2Bb',
                          's': 'encrypted',
                          'sp': 'sig',
                        },
                      ).query,
                      'mimeType': 'video/mp4; codecs="avc1, mp4a"',
                    },
                  ],
                  'hlsManifestUrl': 'https://cdn.example/n/throttle/index.m3u8',
                },
              },
      );
      final sources = SourceManager(runtime: runtime);
      await sources.initialize([
        SourceFile.parse(
          File(
            'packages/social_parser_js/test/fixtures/youtube.js',
          ).readAsStringSync(),
        ),
      ]);
      final r = await SocialParser(
        sourceRuntime: runtime,
        sources: sources,
        http: http,
      ).parse('https://youtu.be/$id');
      expect(r.media.single.sources.first.url.queryParameters, {
        'n': 'fast',
        'keep': 'a+b',
        'sig': 'clear',
      });
      expect(r.media.single.sources.first.track, MediaTrack.audioVideo);
      final manifest = r.media.single.sources.last;
      expect(manifest.url.path, '/n/fast/index.m3u8');
      expect(manifest.kind, MediaSourceKind.hls);
      expect(manifest.track, MediaTrack.unknown);
    },
  );
  test('PO token requirement is not a JS failure', () async {
    final http = Http((u, b, o) {
      if (b == null) return '';
      final name = ((b as Map)['context'] as Map)['client']['clientName'];
      return player(
        name == 'WEB'
            ? [
                {'itag': 137, 'url': 'https://cdn.example/v.mp4'},
              ]
            : [],
      );
    });
    await expectLater(
      testParser(http: http).parse('https://youtu.be/$id'),
      throwsA(
        isA<ParseException>().having(
          (e) => e.code,
          'code',
          ParseErrorCode.unsupportedContent,
        ),
      ),
    );
  });
  test('valid earlier client survives malformed later response', () async {
    final http = Http((u, b, o) {
      if (b == null) return '';
      final name = ((b as Map)['context'] as Map)['client']['clientName'];
      return name == 'VISIONOS'
          ? player([
              {'itag': 18, 'url': 'https://cdn.example/v.mp4'},
            ])
          : '<broken>';
    });
    expect(
      (await testParser(
        http: http,
      ).parse('https://youtu.be/$id')).media.single.sources,
      hasLength(1),
    );
  });
}
