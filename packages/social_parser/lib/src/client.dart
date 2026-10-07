import 'dart:async';
import 'dart:convert';
import 'models/media.dart';
import 'sources/runtime.dart';
import 'sources/manager.dart';
import 'sources/source.dart';
import 'errors/parse_exception.dart';
import 'models/platform.dart';
import 'models/parse_result.dart';
import 'network/http_client.dart';
import 'options/parse_options.dart';
import 'url/links.dart';

class SocialParser {
  SocialParser(
      {required this.sourceRuntime,
      required this.sources,
      ParserHttpClient? http})
      : _http = http ?? DioParserHttpClient();
  final SourceRuntime sourceRuntime;
  final SourceManager sources;
  final ParserHttpClient _http;
  Uri _url(String input) => extractUrl(sources.normalizeInput(input));
  SocialPlatform? detectPlatform(String input) {
    try {
      final s = sources.find(_url(input));
      return s == null ? null : SocialPlatform.fromId(s.manifest.platformId);
    } on ParseException {
      return null;
    }
  }

  List<PlatformCapability> get platforms {
    final groups = <String, List<InstalledSource>>{};
    for (final source in sources.installed) {
      groups
          .putIfAbsent(source.current.manifest.platformId, () => [])
          .add(source);
    }
    return [
      for (final entry in groups.entries) _capability(entry.key, entry.value)
    ];
  }

  PlatformCapability _capability(String id, List<InstalledSource> installed) {
    final enabled = installed.where((s) => s.enabled).toList();
    final candidates = enabled.isEmpty ? installed : enabled;
    final selected = candidates
            .where((s) => s.current.manifest.id == sources.defaultFor(id))
            .firstOrNull ??
        candidates.where((s) => s.builtin != null).firstOrNull ??
        candidates.first;
    return PlatformCapability(
        platform: SocialPlatform.fromId(id),
        name: selected.current.manifest.name,
        mediaTypes: candidates
            .expand((s) => s.current.manifest.mediaTypes)
            .toSet()
            .toList(),
        available: enabled.isNotEmpty,
        supportsJavaScript: true,
        javaScriptAvailable: true);
  }

  SourceFile _require(Uri url, String? id) =>
      sources.find(url, sourceId: id) ??
      (throw const ParseException(ParseErrorCode.unknownPlatform,
          'No enabled source matches this link'));
  Future<Uri> resolveUrl(String input,
          {ParseOptions? options, bool forParsing = false, String? sourceId}) =>
      _guard(() async {
        final url = _url(input), source = _require(_url(input), sourceId);
        final result = await sourceRuntime.execute(source, 'resolve',
            {'url': url.toString()}, _http, options ?? ParseOptions());
        final resolved = _address(
            result[forParsing ? 'url' : 'canonicalUrl'] ?? result['url']);
        if (!source.manifest.domains
            .any((d) => domainMatches(resolved.host, d))) {
          throw const ParseException(
              ParseErrorCode.scriptError, 'Source returned an unrelated URL');
        }
        return resolved;
      });
  Future<ParseResult> parse(String input,
          {ParseOptions? options, String? sourceId}) =>
      _guard(() async {
        final url = _url(input), source = _require(_url(input), sourceId);
        final data = await sourceRuntime.execute(source, 'parse',
            {'url': url.toString()}, _http, options ?? ParseOptions());
        final canonical = _address(data['canonicalUrl'] ?? url.toString());
        if (!source.manifest.domains
            .any((d) => domainMatches(canonical.host, d))) {
          throw const ParseException(ParseErrorCode.scriptError,
              'Source returned an unrelated post URL');
        }
        if (utf8.encode(jsonEncode(data)).length > 16 * 1024 * 1024) {
          throw const ParseException(
              ParseErrorCode.scriptError, 'Source result exceeds 16 MiB');
        }
        for (final key in ['title', 'content', 'markdown']) {
          if (data[key] != null && data[key] is! String) {
            throw const ParseException(
                ParseErrorCode.scriptError, 'Source returned invalid text');
          }
        }
        final media = data['media'];
        if (media is! List || media.length > 10000) {
          throw const ParseException(
              ParseErrorCode.scriptError, 'Source returned invalid media');
        }
        for (final item in media) {
          if (item is! Map ||
              !MediaType.values.any((e) => e.name == item['type']) ||
              item['sources'] is! List ||
              (item['sources'] as List).isEmpty ||
              (item['sources'] as List).length > 10000) {
            throw const ParseException(
                ParseErrorCode.scriptError, 'Source returned invalid media');
          }
          if (item['thumbnailUrl'] != null) _address(item['thumbnailUrl']);
          _numbers(item, ['width', 'height', 'durationMs']);
          for (final source in item['sources'] as List) {
            if (source is! Map ||
                !MediaSourceKind.values.any((e) => e.name == source['kind']) ||
                !MediaTrack.values.any((e) => e.name == source['track']) ||
                _address(source['url']) == canonical) {
              throw const ParseException(ParseErrorCode.scriptError,
                  'Source returned invalid media source');
            }
            _numbers(source, ['width', 'height', 'bitrate']);
            final headers = source['headers'];
            if (headers != null &&
                (headers is! Map ||
                    headers.entries.any((e) =>
                        e.key is! String ||
                        e.value is! String ||
                        RegExp(r'[\r\n]').hasMatch('${e.key}${e.value}')))) {
              throw const ParseException(ParseErrorCode.scriptError,
                  'Source returned invalid media headers');
            }
          }
        }
        return ParseResult.fromJson({
          ...data,
          'platform': source.manifest.platformId,
          'sourceId': source.manifest.id,
          'sourceVersion': source.manifest.version,
          'inputUrl': url.toString(),
          'canonicalUrl': canonical.toString()
        });
      });
  void _numbers(Map data, List<String> keys) {
    for (final key in keys) {
      final v = data[key];
      if (v != null && (v is! num || !v.isFinite || v < 0)) {
        throw const ParseException(ParseErrorCode.scriptError,
            'Source returned invalid dimensions or duration');
      }
    }
  }

  Uri _address(Object? value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const ParseException(
          ParseErrorCode.scriptError, 'Source returned an invalid URL');
    }
    return uri;
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on ParseException {
      rethrow;
    } on TimeoutException {
      throw const ParseException(ParseErrorCode.timeout, 'Parsing timed out');
    } catch (_) {
      throw const ParseException(
          ParseErrorCode.scriptError, 'Source returned unexpected data');
    }
  }
}
