import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_parser/social_parser.dart';
import 'package:social_parser_js/social_parser_js.dart';

SourceFile script(
  String code, {
  List<String> domains = const ['example.com'],
}) => SourceFile.parse(
  '/* @social-source ${jsonEncode({
    'id': 'test.runtime',
    'platformId': 'test',
    'name': 'Runtime',
    'version': '1.0.0',
    'apiVersion': 1,
    'domains': ['example.com'],
    'requestDomains': domains,
    'cookieDomains': ['example.com'],
  })} */\nexport async function resolve(i){return i;}\n$code',
);

class Http implements ParserHttpClient {
  Http(this.reply);
  final Future<ParserResponse> Function(Uri, ParseOptions) reply;
  @override
  Future<ParserResponse> get(Uri u, ParseOptions o) => reply(u, o);
  @override
  Future<ParserResponse> post(Uri u, Object b, ParseOptions o) => reply(u, o);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final runtime = FjsSourceRuntime();
  final http = Http((u, o) async => ParserResponse(u, 'ok', 200, {}));
  Future<Map<String, dynamic>> run(
    String code, {
    ParseOptions? options,
    ParserHttpClient? client,
  }) => runtime.execute(
    script(code),
    'parse',
    {},
    client ?? http,
    options ?? ParseOptions(timeout: const Duration(seconds: 5)),
  );
  test(
    'concurrent tasks isolate globals and retain request correspondence',
    () async {
      final results = await Future.wait([
        for (var i = 0; i < 6; i++)
          run(
            'export async function parse(){globalThis.value=$i;return {value:globalThis.value};}',
          ),
      ]);
      expect(results.map((r) => r['value']), [0, 1, 2, 3, 4, 5]);
    },
  );
  test('timeout interrupts infinite JS and subsequent calls recover', () async {
    await expectLater(
      run(
        'export function parse(){while(true){}}',
        options: ParseOptions(timeout: const Duration(milliseconds: 200)),
      ),
      throwsA(
        isA<ParseException>().having(
          (e) => e.code,
          'code',
          ParseErrorCode.timeout,
        ),
      ),
    );
    expect(await run('export function parse(){return {ready:true};}'), {
      'ready': true,
    });
  });
  test('cancelling running and queued requests releases the pool', () async {
    final tokens = List.generate(3, (_) => ParseCancellation());
    final calls = [
      for (final token in tokens)
        run(
          'export function parse(){while(true){}}',
          options: ParseOptions(cancellation: token),
        ).then<Object>((v) => v, onError: (Object e) => e),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 100));
    for (final token in tokens) {
      token.cancel();
    }
    final results = await Future.wait(calls);
    expect(
      results,
      everyElement(
        isA<ParseException>().having(
          (e) => e.code,
          'code',
          ParseErrorCode.cancelled,
        ),
      ),
    );
    expect(await run('export function parse(){return {ready:true};}'), {
      'ready': true,
    });
  });
  test('late HTTP result after timeout cannot affect next request', () async {
    final late = Completer<ParserResponse>();
    ParseCancellation? token;
    final client = Http((u, o) {
      token = o.cancellation;
      return late.future;
    });
    await expectLater(
      run(
        "export async function parse(){return {value:await (await fetch('https://example.com/')).text()};}",
        client: client,
        options: ParseOptions(timeout: const Duration(milliseconds: 200)),
      ),
      throwsA(isA<ParseException>()),
    );
    expect(token?.isCancelled, isTrue);
    late.complete(
      ParserResponse(Uri.parse('https://example.com/'), 'late', 200, {}),
    );
    expect(await run('export function parse(){return {value:"new"};}'), {
      'value': 'new',
    });
  });
  test(
    'unsupported imports, syntax and export failures are contained',
    () async {
      for (final code in [
        'export const parse = ;',
        "import fs from 'node:fs';export function parse(){return {};}",
        'export const parse=1;',
      ]) {
        await expectLater(
          runtime.validate(script(code)),
          throwsA(isA<ParseException>()),
        );
      }
      await runtime.validate(script('export function parse(){return {};}'));
    },
  );
  test('standard fetch is exposed without DOM, filesystem or process', () async {
    expect(
      await run(
        'export function parse(){return {document:typeof document,process:typeof process,fetch:typeof fetch,require:typeof require};}',
      ),
      {
        'document': 'undefined',
        'process': 'undefined',
        'fetch': 'function',
        'require': 'undefined',
      },
    );
  });
  test('HTTP domain boundaries and every redirect are checked', () async {
    var calls = 0;
    final client = Http((u, o) async {
      calls++;
      return ParserResponse(u, '', 302, {
        'location': ['https://example.com.evil.test/'],
      });
    });
    await expectLater(
      run(
        "export async function parse(){return await fetch('https://example.com/');}",
        client: client,
      ),
      throwsA(
        isA<ParseException>().having(
          (e) => e.code,
          'code',
          ParseErrorCode.permissionDenied,
        ),
      ),
    );
    expect(calls, 1);
  });
  test(
    'validation cannot call host or leak script-provided error text',
    () async {
      await expectLater(
        runtime.validate(
          script(
            "const context = parserContext;export function parse(){return {}; }",
          ),
        ),
        throwsA(isA<ParseException>()),
      );
      await expectLater(
        run('export function parse(){throw new Error("secret-cookie");}'),
        throwsA(
          isA<ParseException>().having(
            (e) => e.message,
            'message',
            isNot(contains('secret-cookie')),
          ),
        ),
      );
    },
  );
}
