import 'dart:io';
import 'package:social_parser_js/social_parser_js.dart';
import 'package:social_parser/social_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_parser_example/main.dart';

void main() {
  late SocialParser parser;
  setUpAll(() async {
    parser = await createSocialParser(loadAsset: (p) => File(p).readAsString());
  });
  testWidgets('official update page uses the default catalog', (tester) async {
    await tester.pumpWidget(ParserExample(parser: parser));
    await tester.tap(find.byTooltip('平台更新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未配置官方更新地址'), findsNothing);
    expect(
        parser.sources.installed.every(
            (source) => source.indexUrl.toString() == defaultOfficialIndexUrl),
        isTrue);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '检查并更新'))
            .onPressed,
        isNotNull);
    expect(find.text('导入'), findsNothing);
  });
  testWidgets('configured official update page checks the catalog',
      (tester) async {
    final configured = await createSocialParser(
      loadAsset: (path) async => File(path).readAsStringSync(),
      officialIndexUrl: Uri.parse('https://example.com/index.json'),
      updateHttp: EmptyCatalog(),
    );
    await tester.pumpWidget(ParserExample(parser: configured));
    await tester.tap(find.byTooltip('平台更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查并更新'));
    await tester.pumpAndSettle();
    expect(find.text('当前平台已是最新版本。'), findsOneWidget);
  });
  testWidgets(
      'unknown links show a useful error without initializing JavaScript',
      (tester) async {
    await tester.pumpWidget(ParserExample(parser: parser));
    await tester.enterText(
        find.byKey(const Key('share-input')), 'https://example.com/post');
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();
    expect(find.textContaining('unknownPlatform'), findsOneWidget);
  });
}

class EmptyCatalog implements ParserHttpClient {
  @override
  Future<ParserResponse> get(Uri url, ParseOptions options) async =>
      ParserResponse(url, '{"apiVersion":1,"sources":[]}', 200, {});
  @override
  Future<ParserResponse> post(Uri url, Object body, ParseOptions options) =>
      throw UnimplementedError();
}
