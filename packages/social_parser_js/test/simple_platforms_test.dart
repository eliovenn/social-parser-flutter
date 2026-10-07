import 'helpers.dart';
import 'dart:convert';
import 'package:social_parser/social_parser.dart';
import 'package:test/test.dart';

class FixtureHttp implements ParserHttpClient {
  FixtureHttp(this.data);
  final Map<String, Object?> data;
  @override
  Future<ParserResponse> post(
    Uri url,
    Object body,
    ParseOptions options,
  ) async => ParserResponse(url, jsonEncode(data), 200, {});
  @override
  Future<ParserResponse> get(
    Uri url,
    ParseOptions options,
  ) async => ParserResponse(
    url,
    '<script id="RENDER_DATA">${Uri.encodeComponent(jsonEncode(data))}</script>',
    200,
    {},
  );
}

void main() {
  setupSources();
  test('Zuiyou preserves mixed media ordering and pid', () async {
    final parser = testParser(
      http: FixtureHttp({
        'data': {
          'post': {
            'content': 'mixed',
            'videos': {
              '2': {'url': 'https://cdn.example/v.mp4'},
            },
            'imgs': [
              {
                'id': 1,
                'urls': {
                  'original': {
                    'urls': ['https://cdn.example/a.jpg'],
                  },
                },
              },
              {
                'id': 2,
                'video': true,
                'urls': {
                  'original': {
                    'urls': ['https://cdn.example/b.jpg'],
                  },
                },
              },
            ],
          },
        },
      }),
    );
    final result = await parser.parse(
      'https://share.xiaochuankeji.cn/hybrid/share/post?pid=7&tracking=drop',
    );
    expect(result.media.map((m) => m.type), [MediaType.image, MediaType.video]);
    expect(result.canonicalUrl.queryParameters, {'pid': '7'});
  });
  test('Pipix maps image content', () async {
    final parser = testParser(
      http: FixtureHttp({
        'ppxItemDetail': {
          'item': {
            'item_type': 1,
            'content': 'photo',
            'cover': {
              'download_list': [
                {'url': 'https://cdn.example/a.jpg'},
              ],
            },
          },
        },
      }),
    );
    final result = await parser.parse('https://h5.pipix.com/ppx/item/123');
    expect(result.content, 'photo');
    expect(result.media.single.type, MediaType.image);
  });
}
