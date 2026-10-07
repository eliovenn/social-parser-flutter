import 'dart:convert';
import '../errors/parse_exception.dart';

Object? _freeze(Object? value) => value is Map
    ? Map<String, dynamic>.unmodifiable(
        value.map((k, v) => MapEntry(k as String, _freeze(v))))
    : value is List
        ? List<dynamic>.unmodifiable(value.map(_freeze))
        : value;

bool domainMatches(String host, String domain) =>
    host == domain || host.endsWith('.$domain');

class SourceManifest {
  SourceManifest(Map<String, dynamic> json)
      : data = _freeze(json) as Map<String, dynamic> {
    if (['id', 'platformId', 'name', 'version']
        .any((k) => data[k] is! String)) {
      throw const ParseException(
          ParseErrorCode.invalidSource, 'Missing source identity');
    }
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,99}$').hasMatch(id) ||
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,99}$').hasMatch(platformId) ||
        name.isEmpty ||
        !RegExp(r'^\d{1,9}\.\d{1,9}\.\d{1,9}$').hasMatch(version)) {
      throw const ParseException(
          ParseErrorCode.invalidSource, 'Invalid source metadata');
    }
    if (data['apiVersion'] != 1) {
      throw const ParseException(
          ParseErrorCode.incompatibleSource, 'Unsupported source API version');
    }
    for (final key in ['domains', 'requestDomains', 'cookieDomains']) {
      if (key == 'requestDomains' && !data.containsKey(key)) continue;
      final value = data[key];
      if (value is! List ||
          value.any((v) =>
              v is! String ||
              !RegExp(r'^[a-z0-9.-]+$').hasMatch(v) ||
              v.startsWith('.') ||
              v.contains('..'))) {
        throw const ParseException(
            ParseErrorCode.invalidSource, 'Invalid source domains');
      }
    }
    if (domains.isEmpty) {
      throw const ParseException(
          ParseErrorCode.invalidSource, 'Source needs a matching domain');
    }
    try {
      for (final pattern in patterns) {
        if (pattern.length > 512) throw const FormatException();
        RegExp(pattern);
      }
      if (mediaTypes.any((t) =>
          !['image', 'video', 'audio', 'animation', 'livePhoto'].contains(t))) {
        throw const FormatException();
      }
      for (final rule in data['inputRules'] as List? ?? []) {
        final pattern = rule['pattern'] as String, url = rule['url'] as String;
        if (pattern.length > 512 || url.length > 4096) {
          throw const FormatException();
        }
        RegExp(pattern);
      }
    } catch (_) {
      throw const ParseException(
          ParseErrorCode.invalidSource, 'Invalid source matching rule');
    }
  }
  final Map<String, dynamic> data;
  String get id => data['id'] as String? ?? '';
  String get platformId => data['platformId'] as String? ?? '';
  String get name => data['name'] as String? ?? '';
  String get version => data['version'] as String? ?? '';
  List<String> strings(String key) =>
      List<String>.unmodifiable((data[key] as List? ?? []).cast<String>());
  List<String> get domains => strings('domains');
  List<String> get requestDomains =>
      data.containsKey('requestDomains') ? strings('requestDomains') : domains;
  List<String> get cookieDomains => strings('cookieDomains');
  List<String> get patterns => strings('pathPatterns');
  List<String> get mediaTypes => strings('mediaTypes');
  bool matches(Uri url) =>
      domains.any((d) => domainMatches(url.host, d)) &&
      (patterns.isEmpty || patterns.any((p) => RegExp(p).hasMatch(url.path)));
  String normalizeInput(String input) {
    for (final rule in (data['inputRules'] as List? ?? [])) {
      final match = RegExp(rule['pattern'] as String).firstMatch(input.trim());
      if (match != null) {
        return (rule['url'] as String).replaceAllMapped(
            RegExp(r'\$(\d+)'),
            (m) => int.parse(m[1]!) <= match.groupCount
                ? match.group(int.parse(m[1]!)) ?? ''
                : '');
      }
    }
    return input;
  }
}

class SourceFile {
  SourceFile._(this.manifest, this.code);
  final SourceManifest manifest;
  final String code;
  static SourceFile parse(String code) {
    if (utf8.encode(code).length > 8 * 1024 * 1024) {
      throw const ParseException(
          ParseErrorCode.invalidSource, 'Source exceeds 8 MiB');
    }
    final match =
        RegExp(r'^\s*/\*\s*@social-source\s+([\s\S]*?)\*/').firstMatch(code);
    if (match == null || match.end > 65536) {
      throw const ParseException(
          ParseErrorCode.invalidSource, 'Missing source metadata header');
    }
    try {
      return SourceFile._(
          SourceManifest(
              Map<String, dynamic>.from(jsonDecode(match[1]!) as Map)),
          code);
    } on ParseException {
      rethrow;
    } catch (_) {
      throw const ParseException(
          ParseErrorCode.invalidSource, 'Invalid source metadata');
    }
  }
}
