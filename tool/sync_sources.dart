import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:social_parser/social_parser.dart';

/// Synchronize a reviewed JS project release into Flutter's bundled baseline.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
        'Usage: dart run tool/sync_sources.dart /path/to/social-parser-sources');
    exitCode = 64;
    return;
  }
  final project = Directory(args.single).absolute.path;
  final indexText = await File('$project/dist/index.json').readAsString();
  final index = jsonDecode(indexText) as Map;
  if (index['apiVersion'] != 1) {
    throw StateError('Unsupported source API');
  }
  final files = <String, String>{}, ids = <String>{};
  for (final item in index['sources'] as List) {
    final name = item['url'] as String;
    if (!RegExp(r'^[a-z0-9_-]+\.js$').hasMatch(name) ||
        files.containsKey(name)) {
      throw StateError('Invalid or duplicate filename');
    }
    final code = await File('$project/dist/$name').readAsString();
    if (sha256.convert(utf8.encode(code)).toString() != item['sha256']) {
      throw StateError('Digest mismatch: $name');
    }
    final source = SourceFile.parse(code);
    if (!ids.add(source.manifest.id) ||
        source.manifest.id != item['id'] ||
        source.manifest.version != item['version']) {
      throw StateError('Invalid source identity: $name');
    }
    files[name] = code;
  }
  if (files.isEmpty) throw StateError('Empty source catalog');
  final fixtures = <String, String>{};
  for (final name in ['probe.js', 'youtube.js']) {
    fixtures[name] = await File('$project/test/fixtures/$name').readAsString();
  }
  // Validate/read every input before modifying the bundled files.
  final output = Directory('packages/social_parser_js/assets/sources');
  await output.create(recursive: true);
  for (final entry in files.entries) {
    await File('${output.path}/${entry.key}').writeAsString(entry.value);
  }
  await File('${output.path}/index.json').writeAsString(indexText);
  for (final file in output.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (name.endsWith('.js') && !files.containsKey(name)) await file.delete();
  }
  for (final entry in fixtures.entries) {
    await File('packages/social_parser_js/test/fixtures/${entry.key}')
        .writeAsString(entry.value);
  }
  stdout.writeln(
      'Synchronized ${files.length} bundled platforms and FJS fixtures. Run Flutter tests before release.');
}
