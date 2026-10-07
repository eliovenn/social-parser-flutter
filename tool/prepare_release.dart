import 'dart:io';

/// Configure the one internal Git dependency before tagging a release.
/// Run with the repository URL and an optional version tag.
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2 || args.first.contains('\n')) {
    stderr.writeln(
        'Usage: dart run tool/prepare_release.dart <repository-url> [v0.2.0]');
    exitCode = 64;
    return;
  }
  final repository = args.first;
  final tag = args.length == 2 ? args[1] : 'v0.2.0';
  if (!RegExp(r'^v\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$').hasMatch(tag)) {
    throw ArgumentError('Use a semantic version tag such as v0.2.0');
  }
  String quote(String value) => "'${value.replaceAll("'", "''")}'";
  final file = File('packages/social_parser_js/pubspec.yaml');
  final original = await file.readAsString();
  final pattern = RegExp(r'^  social_parser:.*(?:\n    .*)*', multiLine: true);
  if (!pattern.hasMatch(original)) {
    throw StateError('Internal dependency not found');
  }
  final replacement = '  social_parser:\n    git:\n'
      '      url: ${quote(repository)}\n'
      '      ref: ${quote(tag)}\n'
      '      path: packages/social_parser';
  await file.writeAsString(original.replaceFirst(pattern, replacement));
  for (final name in ['social_parser', 'social_parser_js']) {
    final manifest = File('packages/$name/pubspec.yaml');
    await manifest.writeAsString((await manifest.readAsString()).replaceFirst(
        RegExp(r'^version:.*$', multiLine: true),
        'version: ${tag.substring(1)}'));
  }
  stdout.writeln(
      'Configured internal Git dependency at $tag. Commit and create that tag before consumers resolve it.');
}
