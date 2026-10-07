import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_parser/social_parser.dart';
import 'package:social_parser_js/social_parser_js.dart';

class Fake implements ParserHttpClient {
  @override
  Future<ParserResponse> get(Uri url, ParseOptions options) async =>
      ParserResponse(
        url,
        File(
          'packages/social_parser/test/fixtures/xhs_mixed.html',
        ).readAsStringSync(),
        200,
        {},
      );
  @override
  Future<ParserResponse> post(Uri url, Object body, ParseOptions options) =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('XHS source executes in native FJS', () async {
    final p = await createSocialParser(
      http: Fake(),
      loadAsset: (p) => File(p).readAsString(),
    );
    final r = await p.parse('https://www.xiaohongshu.com/explore/fixture');
    expect(r.media.map((m) => m.type), [MediaType.image, MediaType.livePhoto]);
  });
}
