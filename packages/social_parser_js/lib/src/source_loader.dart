import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:social_parser/social_parser.dart';
import 'runtime.dart';

/// Official catalog used when no override is supplied.
const defaultOfficialIndexUrl =
    'https://cdn.jsdelivr.net/gh/eliovenn/social-parser-sources@main/index.json';

Future<SocialParser> createSocialParser({
  Directory? sourceDirectory,
  Uri? officialIndexUrl,
  ParserHttpClient? updateHttp,
  ParserHttpClient? http,
  Future<String> Function(String)? loadAsset,
}) async {
  final load = loadAsset ?? rootBundle.loadString;
  const prefix = 'packages/social_parser_js/assets/sources/';
  final index = jsonDecode(await load('${prefix}index.json')) as Map;
  if (index['apiVersion'] != 1) {
    throw const ParseException(
      ParseErrorCode.incompatibleSource,
      'Unsupported bundled index',
    );
  }
  final builtins = <SourceFile>[];
  for (final item in index['sources'] as List) {
    final code = await load('$prefix${item['url']}');
    if (sha256.convert(utf8.encode(code)).toString() != item['sha256']) {
      throw const ParseException(
        ParseErrorCode.integrityFailure,
        'Bundled source checksum mismatch',
      );
    }
    final source = SourceFile.parse(code);
    if (source.manifest.id != item['id'] ||
        source.manifest.version != item['version']) {
      throw const ParseException(
        ParseErrorCode.invalidSource,
        'Bundled source index mismatch',
      );
    }
    builtins.add(source);
  }
  final runtime = FjsSourceRuntime();
  final manager = SourceManager(
    runtime: runtime,
    directory: sourceDirectory,
    http: updateHttp,
    builtinsOnly: true,
  );
  await manager.initialize(builtins);
  await manager.setBuiltinUpdateIndex(
    officialIndexUrl ?? Uri.parse(defaultOfficialIndexUrl),
  );
  return SocialParser(sourceRuntime: runtime, sources: manager, http: http);
}
