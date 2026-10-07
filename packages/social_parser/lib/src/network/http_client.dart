import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../errors/parse_exception.dart';
import '../options/parse_options.dart';

const parserUserAgent = 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

class ParserResponse {
  const ParserResponse(this.uri, this.body, this.statusCode, this.headers);
  final Uri uri;
  final String body;
  final int statusCode;
  final Map<String, List<String>> headers;
}

abstract interface class ParserHttpClient {
  Future<ParserResponse> get(Uri url, ParseOptions options);
  Future<ParserResponse> post(Uri url, Object body, ParseOptions options);
}

/// A request-scoped Dio keeps proxy, cookies and headers isolated across calls.
class DioParserHttpClient implements ParserHttpClient {
  DioParserHttpClient({Dio Function()? createDio})
      : _createDio = createDio ?? Dio.new,
        supportsNativeFetch = createDio == null;
  final bool supportsNativeFetch;
  final Dio Function() _createDio;

  @override
  Future<ParserResponse> get(Uri url, ParseOptions options) =>
      _request(url, options, 'GET');
  @override
  Future<ParserResponse> post(Uri url, Object body, ParseOptions options) =>
      _request(url, options, 'POST', body);

  Future<ParserResponse> _request(Uri url, ParseOptions options, String method,
      [Object? body]) async {
    final dio = _createDio();
    final cancel = CancelToken();
    void abort() => cancel.cancel();
    options.cancellation?.add(abort);
    if (options.proxy case final proxy?) {
      dio.httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () => HttpClient()
            ..findProxy = (_) =>
                'PROXY ${proxy.host}:${proxy.hasPort ? proxy.port : 8080}');
    }
    Future<ParserResponse> run() async {
      var current = url;
      var requestMethod = method;
      var requestBody = body;
      var headers = <String, dynamic>{
        'User-Agent': parserUserAgent,
        ...options.headers,
        if (options.cookies.isNotEmpty)
          'Cookie': options.cookies.entries
              .map((e) => '${e.key}=${e.value}')
              .join('; '),
      };
      for (var redirects = 0; redirects <= 8; redirects++) {
        if (!['http', 'https'].contains(current.scheme)) {
          throw const ParseException(
              ParseErrorCode.invalidInput, 'Unsupported URL scheme');
        }
        final response = await dio.requestUri<String>(current,
            data: requestBody,
            cancelToken: cancel,
            options: Options(
                method: requestMethod,
                headers: headers,
                responseType: ResponseType.plain,
                followRedirects: false,
                receiveTimeout: options.timeout,
                sendTimeout: options.timeout,
                validateStatus: (_) => true));
        final status = response.statusCode ?? 0;
        final location = response.headers.value('location');
        if (status >= 300 && status < 400 && !options.followRedirects) {
          return ParserResponse(
              current, response.data ?? '', status, response.headers.map);
        }
        if ([301, 302, 303, 307, 308].contains(status) && location != null) {
          final next = current.resolve(location);
          if (next.origin != current.origin) {
            headers = {'User-Agent': headers['User-Agent'] ?? parserUserAgent};
          }
          if (status == 303 ||
              ((status == 301 || status == 302) && requestMethod == 'POST')) {
            requestMethod = 'GET';
            requestBody = null;
          }
          current = next;
          continue;
        }
        if (status == 401 || status == 403) {
          throw const ParseException(ParseErrorCode.authenticationRequired,
              'Access requires authentication or is restricted');
        }
        if (status == 404) {
          throw const ParseException(ParseErrorCode.notFound, 'Post not found');
        }
        if (status < 200 || status >= 300) {
          throw ParseException(
              ParseErrorCode.network, 'HTTP request failed ($status)');
        }
        return ParserResponse(
            current, response.data ?? '', status, response.headers.map);
      }
      throw const ParseException(ParseErrorCode.network, 'Too many redirects');
    }

    try {
      return await run().timeout(options.timeout, onTimeout: () {
        cancel.cancel();
        throw const ParseException(
            ParseErrorCode.timeout, 'Network request timed out');
      });
    } on DioException catch (e) {
      if ([
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout
      ].contains(e.type)) {
        throw const ParseException(
            ParseErrorCode.timeout, 'Network request timed out');
      }
      throw const ParseException(
          ParseErrorCode.network, 'Network request failed');
    } finally {
      options.cancellation?.remove(abort);
      dio.close(force: true);
    }
  }
}
