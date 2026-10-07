import 'dart:convert';
import 'dart:io';

/// Creates disposable, local Git consumers. Never commits the working repository.
Future<void> main(List<String> args) async {
  final source = Directory.current;
  final temporary = await Directory.systemTemp.createTemp('social-parser-git-');
  final dart = Platform.resolvedExecutable;
  final flutter = Platform.environment['FLUTTER_BIN'] ?? 'flutter';
  Future<void> run(
      String executable, List<String> arguments, String cwd) async {
    final process = await Process.start(executable, arguments,
        workingDirectory: cwd, mode: ProcessStartMode.inheritStdio);
    if (await process.exitCode != 0) throw StateError('$executable failed');
  }

  Future<void> copy(Directory from, Directory to) async {
    await to.create(recursive: true);
    for (final entry in from.listSync(followLinks: false)) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if ([
            '.git',
            '.agents',
            '.codex',
            '.dart_tool',
            'build',
            '.gradle',
            'Pods',
            '.symlinks',
            'ephemeral'
          ].contains(name) ||
          name.startsWith('.flutter-plugins') ||
          name == 'local.properties') {
        continue;
      }
      if (entry is Directory) {
        await copy(entry, Directory('${to.path}/$name'));
      }
      if (entry is File) {
        await entry.copy('${to.path}/$name');
      }
    }
  }

  try {
    final repo = Directory('${temporary.path}/repository');
    // Only distribution sources are needed in the fixture repository.
    await copy(Directory('${source.path}/packages'),
        Directory('${repo.path}/packages'));
    await Directory('${repo.path}/tool').create();
    await File('${source.path}/tool/prepare_release.dart')
        .copy('${repo.path}/tool/prepare_release.dart');
    await run(dart, ['tool/prepare_release.dart', repo.path], repo.path);
    for (final command in [
      ['init', '-q'],
      ['add', '.'],
      [
        '-c',
        'user.name=Dependency Test',
        '-c',
        'user.email=test@example.invalid',
        'commit',
        '-qm',
        'fixture'
      ],
      ['tag', 'v0.2.0'],
    ]) {
      await run('git', command, repo.path);
    }
    for (final isFlutter in [false, true]) {
      final consumer = Directory(
          '${temporary.path}/${isFlutter ? 'flutter' : 'core'}_consumer')
        ..createSync();
      final name = isFlutter ? 'social_parser_js' : 'social_parser';
      await File('${consumer.path}/pubspec.yaml').writeAsString('''
name: external_consumer
publish_to: none
environment:
  sdk: '>=3.9.2 <4.0.0'
dependencies:
${isFlutter ? '  flutter:\n    sdk: flutter\n' : ''}  $name:
    git:
      url: ${jsonEncode(repo.path)}
      ref: v0.2.0
      path: packages/$name
''');
      await run(
          isFlutter ? flutter : dart,
          ['pub', 'get', if (args.contains('--offline')) '--offline'],
          consumer.path);
      final config = jsonDecode(
          await File('${consumer.path}/.dart_tool/package_config.json')
              .readAsString()) as Map;
      final names = (config['packages'] as List).map((p) => p['name']).toSet();
      if (names.any((n) => '$n'.contains('serious_python')) ||
          (!isFlutter && names.contains('flutter'))) {
        throw StateError('Unexpected dependency');
      }
      if (isFlutter) {
        final item = (config['packages'] as List)
            .singleWhere((p) => p['name'] == 'social_parser_js') as Map;
        final base = File('${consumer.path}/.dart_tool/package_config.json')
            .uri
            .resolve(
                '${(item['rootUri'] as String).replaceFirst(RegExp(r'/+$'), '')}/');
        for (final asset in ['index.json', 'youtube.js', 'xhs.js']) {
          if (!await File.fromUri(base.resolve('assets/sources/$asset'))
              .exists()) {
            throw StateError('Missing JS resource');
          }
        }
        await Directory('${consumer.path}/test').create();
        await File('${consumer.path}/test/asset_test.dart')
            .writeAsString(r'''import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:social_parser/social_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_parser_js/social_parser_js.dart';
void main(){TestWidgetsFlutterBinding.ensureInitialized();test('packaged sources and official catalog',()async{
 final parser=await createSocialParser();expect(parser.platforms,hasLength(20));
 final index=jsonDecode(await rootBundle.loadString('packages/social_parser_js/assets/sources/index.json')) as Map;
 expect(index['sources'],hasLength(20));
 expect(parser.sources.installed.every((source) => source.indexUrl.toString() == defaultOfficialIndexUrl), isTrue);
 expect(parser.detectPlatform('https://www.xiaohongshu.com/explore/fixture')?.name, 'xhs');
 final runtime = FjsSourceRuntime();
 await runtime.validate(SourceFile.parse(await rootBundle.loadString('packages/social_parser_js/assets/sources/xhs.js')));

 });}
''');
        // flutter_test is intentionally a consumer dev dependency.
        await File('${consumer.path}/pubspec.yaml').writeAsString(
            'dev_dependencies:\n  flutter_test:\n    sdk: flutter\n',
            mode: FileMode.append);
        await run(
            flutter,
            ['pub', 'get', if (args.contains('--offline')) '--offline'],
            consumer.path);
        await run(flutter, ['test', '--no-pub'], consumer.path);
      } else {
        await File('${consumer.path}/main.dart').writeAsString(
            "import 'package:social_parser/social_parser.dart';\nvoid main() { if (SocialPlatform.fromId('custom').name != 'custom') throw StateError('custom platforms failed'); final options=ParseOptions(); if(options.cookies.isNotEmpty) throw StateError('defaults failed'); }\n");
        await run(dart, ['run', 'main.dart'], consumer.path);
      }
    }
    stdout.writeln('External Git core and Flutter consumers passed.');
  } finally {
    await temporary.delete(recursive: true);
  }
}
