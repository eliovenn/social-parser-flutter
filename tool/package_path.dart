import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final file = File('.dart_tool/package_config.json').absolute;
  final packages =
      (jsonDecode(file.readAsStringSync()) as Map)['packages'] as List;
  final package = packages.singleWhere((p) => p['name'] == args.single) as Map;
  stdout.write(file.uri.resolve(package['rootUri'] as String).toFilePath());
}
