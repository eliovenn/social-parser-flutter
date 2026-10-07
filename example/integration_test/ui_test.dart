import 'package:social_parser_js/social_parser_js.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:social_parser/social_parser.dart';
import 'package:social_parser_example/main.dart';

class LocalFixtureParser extends SocialParser {
  LocalFixtureParser(this.base, SocialParser parser)
      : super(sourceRuntime: parser.sourceRuntime, sources: parser.sources);
  final Uri base;
  ParseOptions? options;
  @override
  Future<ParseResult> parse(String input,
      {ParseOptions? options, String? sourceId}) async {
    this.options = options;
    return ParseResult(
        platform: SocialPlatform.xhs,
        inputUrl: Uri.parse('https://xiaohongshu.com/explore/test'),
        canonicalUrl: Uri.parse('https://xiaohongshu.com/explore/test'),
        content: '设备显示测试',
        media: [
          MediaItem(type: MediaType.livePhoto, sources: [
            MediaSource(
                url: base.resolve('/image.png'),
                track: MediaTrack.image,
                headers: {'Referer': 'https://xiaohongshu.com/'}),
            MediaSource(
                url: base.resolve('/video.mp4'), track: MediaTrack.audioVideo),
          ]),
        ]);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'entered Cookie, real image preview with headers, no video request',
      (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var imageRequests = 0, videoRequests = 0;
    String? referer;
    final subscription = server.listen((request) async {
      if (request.uri.path == '/image.png') {
        imageRequests++;
        referer = request.headers.value('referer');
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAGElEQVR4nGNgaGj4TxEeNWDUgFEDhosBALpE/xCdMimXAAAAAElFTkSuQmCC'));
      } else {
        videoRequests++;
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final parser = LocalFixtureParser(
        Uri.parse('http://127.0.0.1:${server.port}/'),
        await createSocialParser());
    try {
      await tester.pumpWidget(ParserExample(parser: parser));
      await tester.enterText(find.byKey(const Key('share-input')),
          'https://xiaohongshu.com/explore/test');
      await tester.enterText(
          find.byKey(const Key('cookie-input')), 'session=device-fixture');
      await tester.ensureVisible(find.text('解析'));
      await tester.tap(find.text('解析'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -550));
      await tester.pumpAndSettle();
      expect(parser.options!.cookies['session'], 'device-fixture');
      expect(imageRequests, 1);
      expect(referer, 'https://xiaohongshu.com/');
      expect(videoRequests, 0);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('图片预览失败，仍可复制下方地址'), findsNothing);
      expect(find.byTooltip('复制视频地址'), findsOneWidget);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
