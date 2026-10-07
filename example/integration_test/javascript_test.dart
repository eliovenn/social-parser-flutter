import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:social_parser/social_parser.dart';
import 'package:social_parser_js/social_parser_js.dart';

SourceFile source(String body) =>
    SourceFile.parse('/* @social-source ${jsonEncode({
          'id': 'device.test',
          'platformId': 'test',
          'name': 'Device',
          'version': '1.0.0',
          'apiVersion': 1,
          'domains': ['example.com'],
          'requestDomains': [],
          'cookieDomains': []
        })} */\nexport async function resolve(i){return i;} export function parse(){ $body }');
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'device source runtime supports concurrency and interrupt recovery',
      (tester) async {
    final runtime = FjsSourceRuntime(), http = DioParserHttpClient();
    Future<Map<String, dynamic>> run(String body,
            {Duration timeout = const Duration(seconds: 15)}) =>
        runtime.execute(
            source(body), 'parse', {}, http, ParseOptions(timeout: timeout));
    final values = await Future.wait(
        [for (var i = 0; i < 3; i++) run('return {value:$i};')]);
    expect(values.map((v) => v['value']), [0, 1, 2]);
    await expectLater(
        run('while(true){}', timeout: const Duration(milliseconds: 300)),
        throwsA(isA<ParseException>()
            .having((e) => e.code, 'code', ParseErrorCode.timeout)));
    expect(await run('return {recovered:true};'), {'recovered': true});
  });
}
