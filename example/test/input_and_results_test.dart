import 'dart:io';
import 'package:social_parser_js/social_parser_js.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_parser/social_parser.dart';
import 'package:social_parser_example/cookie_input.dart';
import 'package:social_parser_example/main.dart';
import 'package:social_parser_example/result_view.dart';

late SocialParser baseParser;

class StubParser extends SocialParser {
  StubParser()
      : super(
            sourceRuntime: baseParser.sourceRuntime,
            sources: baseParser.sources);
  ParseOptions? options;
  String? input;
  @override
  Future<ParseResult> parse(String input,
      {ParseOptions? options, String? sourceId}) async {
    this.input = input;
    this.options = options;
    return ParseResult(
        platform: SocialPlatform.xhs,
        inputUrl: Uri.parse('https://xiaohongshu.com/explore/123'),
        canonicalUrl: Uri.parse('https://xiaohongshu.com/explore/123'),
        title: '测试结果',
        content: '正文',
        media: [
          MediaItem(type: MediaType.video, sources: [
            MediaSource(
                url: Uri.parse('https://cdn.example/v.mp4'),
                track: MediaTrack.audioVideo)
          ]),
        ]);
  }
}

void main() {
  setUpAll(() async {
    baseParser =
        await createSocialParser(loadAsset: (p) => File(p).readAsString());
  });
  test('Cookie header and JSON retain equals signs and quoted values', () {
    expect(parseCookieInput('Cookie: session=abc==; d_c0="value|123";'),
        {'session': 'abc==', 'd_c0': '"value|123"'});
    expect(parseCookieInput('{"session":"abc=="}'), {'session': 'abc=='});
    expect(parseCookieInput(''), isEmpty);
  });
  test('invalid Cookie input is rejected without reflecting secrets', () {
    for (final input in [
      '{bad',
      '{"a":1}',
      'no-equals',
      'a=secret\r\nX: injected'
    ]) {
      expect(
          () => parseCookieInput(input),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', isNot(contains('secret')))));
    }
  });

  testWidgets('submits share text and Cookie, renders video as link only',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final parser = StubParser();
    await tester.pumpWidget(ParserExample(parser: parser));
    await tester.enterText(find.byKey(const Key('share-input')),
        '分享 https://xiaohongshu.com/explore/123');
    await tester.enterText(find.byKey(const Key('cookie-input')),
        '{"xhs":"session=fixture==","douyin":"session=other"}');
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();
    expect(parser.options!.cookies, {'session': 'fixture=='});
    expect(parser.input, startsWith('分享 '));
    expect(find.text('测试结果'), findsOneWidget);
    expect(find.text('https://cdn.example/v.mp4'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('switching platforms keeps configuration and isolates cookies',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final parser = StubParser();
    await tester.pumpWidget(ParserExample(parser: parser));
    const config = '{"xhs":"session=xhs","douyin":{"session":"douyin"}}';
    await tester.enterText(find.byKey(const Key('cookie-input')), config);
    for (final entry in {
      'https://xiaohongshu.com/explore/123': {'session': 'xhs'},
      'https://www.douyin.com/video/123': {'session': 'douyin'},
      'https://youtu.be/Hp1OsvXdut0': <String, String>{},
    }.entries) {
      await tester.enterText(find.byKey(const Key('share-input')), entry.key);
      await tester.tap(find.text('解析'));
      await tester.pumpAndSettle();
      expect(parser.options!.cookies, entry.value);
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('cookie-input')))
              .controller!
              .text,
          config);
    }
  });

  test('platform configuration rejects invalid shapes and unknown platforms',
      () {
    for (final input in [
      '[]',
      '{"xhs":1}',
      '{"xhs":{"a":1}}',
      '{"xhss":"a=secret"}',
      'session=secret'
    ]) {
      expect(
          () => cookiesForPlatform(input, 'xhs', platformIds: ['xhs']),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', isNot(contains('secret')))));
    }
  });

  testWidgets(
      'Live Photo previews its image with headers and keeps video copyable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MediaCard(
                index: 0,
                item: MediaItem(type: MediaType.livePhoto, sources: [
                  MediaSource(
                      url: Uri.parse('https://cdn.example/photo.jpg'),
                      track: MediaTrack.image,
                      headers: {'Referer': 'https://xiaohongshu.com/'}),
                  MediaSource(
                      url: Uri.parse('https://cdn.example/live.mp4'),
                      track: MediaTrack.audioVideo),
                ])))));
    await tester.pump();
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).headers,
        {'Referer': 'https://xiaohongshu.com/'});
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byTooltip('复制视频地址'));
    await tester.pump();
    expect(copied, 'https://cdn.example/live.mp4');
  });
}
