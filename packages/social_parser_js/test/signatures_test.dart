import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_parser/social_parser.dart';
import 'helpers.dart';

SourceFile probe() => SourceFile.parse(
  '/* @social-source\n${jsonEncode({
    'id': 'test.probe',
    'platformId': 'test',
    'name': 'Probe',
    'version': '1.0.0',
    'apiVersion': 1,
    'domains': ['example.com'],
    'requestDomains': [],
    'cookieDomains': [],
  })}\n*/\n${File('packages/social_parser_js/test/fixtures/probe.js').readAsStringSync()}',
);
void main() {
  setupSources();
  Future<Map<String, dynamic>> run(Map<String, dynamic> input) => runtime
      .execute(probe(), 'parse', input, DioParserHttpClient(), ParseOptions());
  test(
    'native JS signatures match all original Python vectors and WBI reference',
    () async {
      final r = await run({});
      final vectors =
          jsonDecode(
                File(
                  'packages/social_parser/test/fixtures/signature_vectors.json',
                ).readAsStringSync(),
              )
              as Map;
      for (final e in vectors.entries) {
        expect(r[e.key], e.value, reason: e.key as String);
      }
      expect(r['wbi'], '8f6f2b5b3d485fe1886cec6a0be8c5d4');
      expect(r['threads'], '73786976294838206463');
    },
  );
  test('EJS transforms both signature and n in isolated QuickJS', () async {
    final r = await run({
      'operation': 'challenge',
      'prepared':
          '_result.n = s => s.split("").reverse().join(""); _result.sig = s => s.slice(1) + s[0];',
      'signatures': ['xyz'],
      'nChallenges': ['abc'],
    });
    expect(r['sig'], {'xyz': 'yzx'});
    expect(r['n'], {'abc': 'cba'});
  });
  test(
    'data reader preserves large IDs and never evaluates expressions',
    () async {
      expect(
        (await run({
          'operation': 'data',
          'text':
              r'''{bare:'a } \' b',number:'8' * 1,missing:undefined,id:73786976294838206463,values:[true,null,],}''',
        }))['data'],
        {
          'bare': "a } ' b",
          'number': 8,
          'missing': null,
          'id': '73786976294838206463',
          'values': [true, null],
        },
      );
      await expectLater(
        run({'operation': 'data', 'text': '{value:process.exit()}'}),
        throwsA(isA<ParseException>()),
      );
    },
  );
}
