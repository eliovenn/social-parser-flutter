import 'dart:convert';
import 'cache.dart';
import 'package:social_parser/social_parser.dart';

class SourceHost {
  SourceHost(
    this.manifest,
    this.http,
    this.options,
    this.cancellation,
    this.remaining,
    this.cache,
    this.cacheNamespace,
  );
  final SourceCache cache;
  final String cacheNamespace;
  final SourceManifest manifest;
  final ParserHttpClient http;
  final ParseOptions options;
  final ParseCancellation cancellation;
  final Duration Function() remaining;
  bool _allowed(Uri u, List<String> domains) =>
      ['http', 'https'].contains(u.scheme) &&
      u.userInfo.isEmpty &&
      domains.any((d) => domainMatches(u.host, d));
  Future<Object?> invoke(String method, Map<String, dynamic> args) async {
    if (cancellation.isCancelled) {
      throw const ParseException(
        ParseErrorCode.timeout,
        'Source task has ended',
      );
    }
    remaining();
    if (method == 'cache.get') {
      return cache.get(cacheNamespace, args['key'] as String);
    }
    if (method == 'cache.set') {
      cache.set(
        cacheNamespace,
        args['key'] as String,
        args['value'],
        args['ttlMs'] as int? ?? 3600000,
      );
      return null;
    }
    if (method == 'fetch') {
      final uri = Uri.parse(args['url'] as String);
      if (!_allowed(uri, manifest.requestDomains)) {
        throw const ParseException(
          ParseErrorCode.permissionDenied,
          'Request domain is not allowed',
        );
      }
      final headers = Map<String, String>.from(args['headers'] as Map);
      final cookies = <String, String>{};
      final cookie = headers.remove('cookie');
      if (cookie != null) {
        for (final part in cookie.split(';')) {
          final split = part.indexOf('=');
          if (split > 0) {
            cookies[part.substring(0, split).trim()] = part
                .substring(split + 1)
                .trim();
          }
        }
      }
      Object? body = args['body'];
      if (body is String &&
          (headers['content-type'] ?? '').contains('application/json')) {
        try {
          body = jsonDecode(body);
        } catch (_) {
          /* Preserve non-JSON payload. */
        }
      }
      final request = ParseOptions(
        cookies: cookies,
        headers: headers,
        timeout: remaining(),
        proxy: options.proxy,
        followRedirects: false,
        cancellation: cancellation,
      );
      final response = args['method'] == 'POST'
          ? await http.post(uri, body ?? '', request)
          : args['method'] == 'GET'
          ? await http.get(uri, request)
          : throw const ParseException(
              ParseErrorCode.unsupportedContent,
              'Injected transport supports GET and POST',
            );
      return {
        'url': response.uri.toString(),
        'body': response.body,
        'status': response.statusCode,
        'headers': response.headers,
      };
    }
    throw const ParseException(
      ParseErrorCode.permissionDenied,
      'Unknown host operation',
    );
  }
}
