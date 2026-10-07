import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_parser/social_parser.dart';
import 'package:social_parser_js/social_parser_js.dart';

class NativeOnly extends DioParserHttpClient {
  @override
  Future<ParserResponse> get(Uri url, ParseOptions options) =>
      throw StateError('Native fetch must not use Dart HTTP');
  @override
  Future<ParserResponse> post(Uri url, Object body, ParseOptions options) =>
      throw StateError('Native fetch must not use Dart HTTP');
}

SourceFile script(String body) =>
    SourceFile.parse('''/* @social-source ${jsonEncode({
      'id': 'native.test',
      'name': 'Native test',
      'platformId': 'native',
      'version': '1.0.0',
      'apiVersion': 1,
      'domains': ['127.0.0.1', 'localhost'],
      'requestDomains': ['127.0.0.1', 'localhost'],
      'cookieDomains': ['127.0.0.1', 'localhost'],
      'mediaTypes': ['image'],
    })} */
export function resolve(input){return input;}
export async function parse(input){$body}
''');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native fetch uses real network, redirects and withholds cross-origin cookies',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <HttpRequest>[];
      server.listen((request) async {
        requests.add(request);
        if (request.uri.path == '/redirect') {
          request.response.statusCode = 302;
          request.response.headers.set(
            'location',
            'http://localhost:${server.port}/end',
          );
        } else {
          request.response.headers.add('set-cookie', 'one=1; Path=/');
          request.response.headers.add('set-cookie', 'two=2; Path=/');
          request.response.write('{"ok":true}');
        }
        await request.response.close();
      });
      final result = await FjsSourceRuntime().execute(
        script('''
      const direct=await fetch(input.url+'/direct');
      const cookies=direct.headers.getSetCookie();
      const json=await direct.json();
      const anonymous=await fetch(new Request(input.url+'/anonymous',{credentials:'omit'}));
      await anonymous.text();
      const manual=await fetch(new Request(input.url+'/redirect',{redirect:'manual'}));
      if(manual.status!==302)throw new Error('Manual redirect was followed');
      const redirected=await fetch(input.url+'/redirect');
      return {json,cookies,url:redirected.url,status:redirected.status};
    '''),
        'parse',
        {'url': 'http://127.0.0.1:${server.port}'},
        NativeOnly(),
        ParseOptions(
          cookies: {'session': 'secret'},
          headers: {'Authorization': 'fixture'},
        ),
      );
      expect(result['json'], {'ok': true});
      expect(result['cookies'], hasLength(2));
      expect(result['status'], 200);
      expect(requests.first.headers.value('cookie'), 'session=secret');
      expect(
        requests
            .firstWhere((r) => r.uri.path == '/anonymous')
            .headers
            .value('cookie'),
        isNull,
      );
      expect(requests.last.headers.value('cookie'), isNull);
      expect(requests.last.headers.value('authorization'), isNull);
    },
  );
  test(
    'native pending fetch respects task timeout and releases the runtime',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {});
      final runtime = FjsSourceRuntime();
      await expectLater(
        runtime.execute(
          script('await fetch(input.url); return {};'),
          'parse',
          {'url': 'http://127.0.0.1:${server.port}'},
          NativeOnly(),
          ParseOptions(timeout: const Duration(milliseconds: 250)),
        ),
        throwsA(
          isA<ParseException>().having(
            (e) => e.code,
            'code',
            ParseErrorCode.timeout,
          ),
        ),
      );
      final result = await runtime.execute(
        script('return {recovered:true};'),
        'parse',
        {},
        NativeOnly(),
        ParseOptions(),
      );
      expect(result['recovered'], true);
    },
  );
  test('standard abort signal cancels native fetch', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {});
    final result = await FjsSourceRuntime().execute(
      script('''
      const controller=new AbortController();
      setTimeout(()=>controller.abort(),50);
      try {await fetch(input.url,{signal:controller.signal});return {cancelled:false};}
      catch(error){return {cancelled:error.code==='cancelled',code:String(error.code),message:error.message};}
    '''),
      'parse',
      {'url': 'http://127.0.0.1:${server.port}'},
      NativeOnly(),
      ParseOptions(timeout: const Duration(seconds: 4)),
    );
    expect(result, containsPair('cancelled', true));
  });
}
