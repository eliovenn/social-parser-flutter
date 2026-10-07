import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:social_parser_example/main.dart';
import 'package:social_parser_example/result_view.dart';

/// Explicit opt-in live check: `--dart-define=XHS_TEST_LINK=<share URL>`.
/// No Cookie is supplied, persisted, or printed by this test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const link = String.fromEnvironment('XHS_TEST_LINK');
  testWidgets('public Xiaohongshu share works without Cookie on device',
      (tester) async {
    await tester.pumpWidget(const ParserExample());
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('share-input')), link);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('cookie-input')))
            .controller!
            .text,
        isEmpty);
    await tester.ensureVisible(find.text('解析'));
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 100));
    expect(find.byKey(const Key('parse-error')), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle(const Duration(milliseconds: 200),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 100));
    final result = tester.widget<ResultView>(find.byType(ResultView)).result;
    expect(result.title, isNotEmpty);
    expect(result.media, isNotEmpty);
    expect(find.byType(Image), findsWidgets);
    bool imageDecoded() => tester
        .widgetList<RawImage>(find.byType(RawImage))
        .any((widget) => widget.image != null);
    // Creating Image.network does not prove its asynchronous load completed.
    for (var attempt = 0; attempt < 150 && !imageDecoded(); attempt++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(imageDecoded(), isTrue, reason: 'Expected a decoded network image');
    expect(find.text('图片预览失败，仍可复制下方地址'), findsNothing);
    // Report only harmless summary fields, not signed media URLs.
    debugPrint(
        'XHS live: ${result.title}; ${result.media.length} media; Cookie empty; image rendered');
  }, skip: link.isEmpty, timeout: const Timeout(Duration(minutes: 4)));
}
