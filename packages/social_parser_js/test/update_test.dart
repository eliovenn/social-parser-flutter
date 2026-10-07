import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_parser/social_parser.dart';
import 'package:social_parser_js/social_parser_js.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'remote catalog installs and updates real JS, survives restart, and rolls back',
    () async {
      HttpOverrides.global = null;
      var version = '1.0.0';
      String source() =>
          '/* @social-source ${jsonEncode({
            'id': 'remote.source',
            'platformId': 'new_platform',
            'name': 'Remote',
            'version': version,
            'apiVersion': 1,
            'domains': ['example.com'],
            'requestDomains': [],
            'cookieDomains': [],
          })} */\nexport function resolve(i){return {url:i.url,canonicalUrl:i.url};}export function parse(i){return {canonicalUrl:i.url,title:"$version",media:[]};}';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
          dir = await Directory.systemTemp.createTemp('remote-js-');
      final sub = server.listen((request) async {
        if (request.uri.path == '/index.json') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'apiVersion': 1,
              'sources': [
                {
                  'id': 'remote.source',
                  'version': version,
                  'url': 'source.js',
                  'sha256': sha256.convert(utf8.encode(source())).toString(),
                },
              ],
            }),
          );
        } else {
          request.response.write(source());
        }
        await request.response.close();
      });
      try {
        final runtime = FjsSourceRuntime(),
            manager = SourceManager(
              runtime: FjsSourceRuntime(),
              directory: dir,
              allowLocalhostHttp: true,
            );
        await manager.initialize([]);
        await manager.install(
          Uri.parse('http://127.0.0.1:${server.port}/index.json'),
          sourceId: 'remote.source',
        );
        final parser = SocialParser(sourceRuntime: runtime, sources: manager);
        expect((await parser.parse('https://example.com/post')).title, '1.0.0');
        version = '1.1.0';
        expect((await manager.checkUpdates()).single.version, '1.1.0');
        expect((await parser.parse('https://example.com/post')).title, '1.0.0');
        await manager.update('remote.source');
        expect((await parser.parse('https://example.com/post')).title, '1.1.0');
        final restored = SourceManager(
          runtime: runtime,
          directory: dir,
          allowLocalhostHttp: true,
        );
        await restored.initialize([]);
        await restored.rollback('remote.source');
        expect(
          (await SocialParser(
            sourceRuntime: runtime,
            sources: restored,
          ).parse('https://example.com/post')).title,
          '1.0.0',
        );
      } finally {
        await sub.cancel();
        await server.close(force: true);
        await dir.delete(recursive: true);
      }
    },
  );
  test('in-memory cache is isolated by complete source revision', () async {
    final runtime = FjsSourceRuntime();
    SourceFile source(String version) => SourceFile.parse(
      '/* @social-source ${jsonEncode({
        'id': 'cached',
        'platformId': 'test',
        'name': 'Cache',
        'version': version,
        'apiVersion': 1,
        'domains': ['example.com'],
        'requestDomains': [],
        'cookieDomains': [],
      })} */\nexport function resolve(i){return i;}export async function parse(i){if(i.value)await parserCache.set("key",i.value);return {value:await parserCache.get("key")};}',
    );
    Future<Map<String, dynamic>> run(
      String version,
      Map<String, dynamic> input,
    ) => runtime.execute(
      source(version),
      'parse',
      input,
      DioParserHttpClient(),
      ParseOptions(),
    );
    expect(await run('1.0.0', {'value': 'prepared'}), {'value': 'prepared'});
    expect(await run('1.0.0', {}), {'value': 'prepared'});
    expect(await run('1.1.0', {}), {'value': null});
  });
}
