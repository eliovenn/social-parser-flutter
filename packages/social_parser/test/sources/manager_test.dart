import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:social_parser/social_parser.dart';
import 'package:test/test.dart';

String code(
        {String id = 'test.source',
        String platform = 'custom',
        String version = '1.0.0'}) =>
    '/* @social-source ${jsonEncode({
          'id': id,
          'platformId': platform,
          'name': 'Custom',
          'version': version,
          'apiVersion': 1,
          'domains': ['example.com'],
          'requestDomains': ['example.com'],
          'cookieDomains': [],
          'mediaTypes': ['image']
        })} */\nexport function resolve(i){return i;}export function parse(i){return {};}';

class Runtime implements SourceRuntime {
  bool reject = false;
  Map<String, dynamic> output = {};
  @override
  Future<void> validate(SourceFile s) async {
    if (reject) {
      throw const ParseException(ParseErrorCode.invalidSource, 'Invalid JS');
    }
  }

  @override
  Future<Map<String, dynamic>> execute(
          SourceFile s,
          String op,
          Map<String, dynamic> input,
          ParserHttpClient http,
          ParseOptions options) async =>
      output;
}

class Http implements ParserHttpClient {
  final values = <String, String>{};
  @override
  Future<ParserResponse> get(Uri u, ParseOptions o) async =>
      ParserResponse(u, values[u.path]!, 200, {});
  @override
  Future<ParserResponse> post(Uri u, Object b, ParseOptions o) =>
      throw UnimplementedError();
}

void main() {
  late Directory dir;
  late Runtime runtime;
  late Http http;
  late SourceManager manager;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('source-test-');
    runtime = Runtime();
    http = Http();
    manager = SourceManager(runtime: runtime, http: http, directory: dir);
    await manager.initialize([SourceFile.parse(code())]);
  });
  tearDown(() async => dir.delete(recursive: true));
  test(
      'request domains default to share domains, extra API hosts do not match links',
      () {
    final data =
        Map<String, dynamic>.from(SourceFile.parse(code()).manifest.data)
          ..remove('requestDomains');
    final defaults = SourceManifest(data);
    expect(defaults.requestDomains, ['example.com']);
    expect(() => defaults.requestDomains.add('extra.test'),
        throwsUnsupportedError);
    final extra = SourceManifest({
      ...data,
      'requestDomains': ['example.com', 'api.test']
    });
    expect(extra.requestDomains, contains('api.test'));
    expect(extra.matches(Uri.parse('https://api.test/item')), isFalse);
    expect(() => SourceManifest({...data, 'requestDomains': null}),
        throwsA(isA<ParseException>()));
  });
  test(
      'official updates persist, isolate failures and ignore unknown platforms',
      () async {
    manager = SourceManager(
        runtime: runtime, http: http, directory: dir, builtinsOnly: true);
    await manager.initialize(
        [SourceFile.parse(code()), SourceFile.parse(code(id: 'second'))]);
    await manager
        .setBuiltinUpdateIndex(Uri.parse('https://example.com/index.json'));
    final first = code(version: '2.0.0');
    final second = code(id: 'second', version: '2.0.0');
    http.values['/first.js'] = first;
    http.values['/second.js'] = second;
    http.values['/index.json'] = jsonEncode({
      'apiVersion': 1,
      'sources': [
        {
          'id': 'test.source',
          'version': '2.0.0',
          'url': 'first.js',
          'sha256': sha256.convert(utf8.encode(first)).toString()
        },
        {
          'id': 'second',
          'version': '2.0.0',
          'url': 'second.js',
          'sha256': '0' * 64
        },
        {
          'id': 'unknown',
          'version': '2.0.0',
          'url': 'unknown.js',
          'sha256': '0' * 64
        },
      ]
    });
    final results = await manager.updateBuiltins();
    expect(results.keys, ['test.source', 'second']);
    expect(results['test.source'], isNull);
    expect(results['second'], isA<ParseException>());
    final restarted =
        SourceManager(runtime: runtime, directory: dir, builtinsOnly: true);
    await restarted.initialize(
        [SourceFile.parse(code()), SourceFile.parse(code(id: 'second'))]);
    expect(restarted.installed.first.current.manifest.version, '2.0.0');
    expect(restarted.installed.last.current.manifest.version, '1.0.0');
    await restarted.rollback('test.source');
    expect(restarted.installed.first.current.manifest.version, '1.0.0');
    http.values['/index.json'] = jsonEncode({'apiVersion': 3, 'sources': []});
    await expectLater(
        manager.updateBuiltins(),
        throwsA(isA<ParseException>().having(
            (error) => error.code, 'code', ParseErrorCode.incompatibleSource)));
    expect(manager.installed.first.current.manifest.version, '2.0.0');
  });
  test(
      'bundled-only restart ignores custom sources and obsolete saved versions',
      () async {
    await manager.importCode(code(id: 'other'));
    final restricted =
        SourceManager(runtime: runtime, directory: dir, builtinsOnly: true);
    await restricted.initialize([SourceFile.parse(code(version: '3.0.0'))]);
    expect(restricted.installed, hasLength(1));
    expect(restricted.installed.single.current.manifest.version, '3.0.0');
    await expectLater(restricted.importCode(code(id: 'other')),
        throwsA(isA<ParseException>()));
  });
  test('unknown platform can be imported, selected and restored after restart',
      () async {
    await manager.importCode(code(id: 'alternate', platform: 'custom'));
    await manager.setDefault('alternate');
    expect(SocialParser(sourceRuntime: runtime, sources: manager).platforms,
        hasLength(1));
    expect(manager.find(Uri.parse('https://example.com/a'))!.manifest.id,
        'alternate');
    await manager.setEnabled('alternate', false);
    expect(manager.find(Uri.parse('https://example.com/a'))!.manifest.id,
        'test.source');
    final reloaded = SourceManager(runtime: runtime, directory: dir);
    await reloaded.initialize([SourceFile.parse(code())]);
    expect(
        reloaded.installed
            .singleWhere((s) => s.current.manifest.id == 'alternate')
            .enabled,
        isFalse);
    expect(reloaded.defaultFor('custom'), 'alternate');
    await reloaded.remove('alternate');
    expect(reloaded.installed, hasLength(1));
  });
  test('imports are serialized, rollback keeps last working version', () async {
    await Future.wait([
      manager.importCode(code(version: '1.1.0')),
      manager.importCode(code(version: '1.2.0'))
    ]);
    expect(manager.installed.single.current.manifest.version, '1.2.0');
    await manager.rollback('test.source');
    expect(manager.installed.single.current.manifest.version, '1.1.0');
    await manager.remove('test.source');
    expect(manager.installed.single.current.manifest.version, '1.0.0');
    expect(manager.installed.single.enabled, isFalse);
  });
  test(
      'syntax validation failure and storage failure preserve current and disk',
      () async {
    await manager.importCode(code(version: '1.1.0'));
    final persisted = await File('${dir.path}/sources.json').readAsString();
    runtime.reject = true;
    await expectLater(manager.importCode(code(version: '1.2.0')),
        throwsA(isA<ParseException>()));
    runtime.reject = false;
    await Directory('${dir.path}/sources.tmp').create();
    await expectLater(manager.importCode(code(version: '1.2.0')),
        throwsA(isA<FileSystemException>()));
    expect(manager.installed.single.current.manifest.version, '1.1.0');
    expect(await File('${dir.path}/sources.json').readAsString(), persisted);
  });
  test(
      'manual remote update checks hash, identity and version before replacement',
      () async {
    final index = Uri.parse('https://example.com/index.json');
    void publish(String source, {String? hash}) {
      http.values['/source.js'] = source;
      http.values['/index.json'] = jsonEncode({
        'apiVersion': 1,
        'sources': [
          {
            'id': 'test.source',
            'version': '2.0.0',
            'url': 'source.js',
            'sha256': hash ?? sha256.convert(utf8.encode(source)).toString()
          }
        ]
      });
    }

    publish(code(version: '2.0.0'));
    await manager.setUpdateIndex('test.source', index);
    expect((await manager.checkUpdates()).single.version, '2.0.0');
    expect(manager.installed.single.current.manifest.version, '1.0.0');
    publish(code(version: '2.0.0'), hash: '0' * 64);
    await expectLater(
        manager.update('test.source'),
        throwsA(isA<ParseException>()
            .having((e) => e.code, 'code', ParseErrorCode.integrityFailure)));
    expect(manager.installed.single.current.manifest.version, '1.0.0');
    publish(code(version: '2.0.0'));
    await manager.update('test.source');
    expect(manager.installed.single.current.manifest.version, '2.0.0');
    await manager.rollback('test.source');
    expect(manager.installed.single.current.manifest.version, '1.0.0');
  });
  test('source cannot change platform identity and insecure index is refused',
      () async {
    await expectLater(manager.importCode(code(platform: 'different')),
        throwsA(isA<ParseException>()));
    await expectLater(
        manager.setUpdateIndex(
            'test.source', Uri.parse('http://example.com/index.json')),
        throwsA(isA<ParseException>()));
  });
  test(
      'metadata is immutable, API checked, malformed and unrelated URLs rejected',
      () async {
    final source = SourceFile.parse(code());
    expect(() => source.manifest.data['domains'].add('evil.test'),
        throwsUnsupportedError);
    expect(
        () => SourceFile.parse(
            code().replaceFirst('"apiVersion":1', '"apiVersion":3')),
        throwsA(isA<ParseException>()
            .having((e) => e.code, 'code', ParseErrorCode.incompatibleSource)));
    expect(() => SourceFile.parse('export function parse(){}'),
        throwsA(isA<ParseException>()));
    final parser =
        SocialParser(sourceRuntime: runtime, sources: manager, http: http);
    expect(parser.detectPlatform('https://example.com/post'),
        const SocialPlatform('custom'));
    expect(parser.detectPlatform('https://example.com.evil.test/post'), isNull);
    runtime.output = {'canonicalUrl': 'https://evil.test/post'};
    await expectLater(parser.resolveUrl('https://example.com/post'),
        throwsA(isA<ParseException>()));
    runtime.output = {
      'canonicalUrl': 'https://example.com/post',
      'media': [
        {
          'type': 'video',
          'sources': [
            {
              'url': 'https://example.com/post',
              'kind': 'direct',
              'track': 'audioVideo'
            }
          ]
        }
      ]
    };
    await expectLater(parser.parse('https://example.com/post'),
        throwsA(isA<ParseException>()));
    runtime.output = {
      'canonicalUrl': 'https://example.com/post',
      'media': [
        {
          'type': 'video',
          'sources': [
            {'url': 'file:///secret', 'kind': 'direct', 'track': 'audioVideo'}
          ]
        }
      ]
    };
    await expectLater(parser.parse('https://example.com/post'),
        throwsA(isA<ParseException>()));
    runtime.output = {'canonicalUrl': 'https://example.com/post', 'media': []};
    final result = await parser.parse('https://example.com/post');
    expect(result.sourceId, 'test.source');
    expect(result.sourceVersion, '1.0.0');
    expect(ParseResult.fromJson(result.toJson()).toJson(), result.toJson());
  });
}
