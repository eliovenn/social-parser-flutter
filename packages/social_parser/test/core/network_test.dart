import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:social_parser/social_parser.dart';
import 'package:test/test.dart';

class Adapter implements HttpClientAdapter {
  Adapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      handler(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  test('cross-origin redirect does not forward cookies or credentials',
      () async {
    final seen = <RequestOptions>[];
    final client = DioParserHttpClient(
        createDio: () => Dio()
          ..httpClientAdapter = Adapter((request) {
            seen.add(request);
            return seen.length == 1
                ? ResponseBody.fromString('', 302, headers: {
                    'location': ['https://other.example/post']
                  })
                : ResponseBody.fromString('ok', 200);
          }));
    await client.get(
        Uri.parse('https://source.example/post'),
        ParseOptions(
            cookies: {'secret': 'value'},
            headers: {'Authorization': 'Bearer value'}));
    expect(seen.first.headers['Cookie'], contains('secret'));
    expect(seen.last.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('cookie')));
    expect(seen.last.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')));
  });

  test('concurrent requests have independent headers', () async {
    final seen = <String>[];
    final client = DioParserHttpClient(
        createDio: () => Dio()
          ..httpClientAdapter = Adapter((request) {
            seen.add(request.headers['Cookie'] as String);
            return ResponseBody.fromString('ok', 200);
          }));
    await Future.wait(['a', 'b'].map((s) => client.get(
        Uri.parse('https://example.com'),
        ParseOptions(cookies: {'session': s}))));
    expect(seen, containsAll(['session=a', 'session=b']));
  });
}
