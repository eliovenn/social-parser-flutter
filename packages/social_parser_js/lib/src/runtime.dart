import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'cache.dart';
import 'standard_runtime.dart';
import 'package:fjs/fjs.dart';
import 'package:social_parser/social_parser.dart';
import 'host_api.dart';

class FjsSourceRuntime implements SourceRuntime {
  static Future<void>? _initializing;
  final _cache = SourceCache();
  int _active = 0;
  final List<Completer<void>> _queue = [];
  Future<void> _acquire(
    Duration timeout,
    ParseCancellation? cancellation,
  ) async {
    if (cancellation?.isCancelled == true) {
      throw const ParseException(
        ParseErrorCode.cancelled,
        'Source task cancelled',
      );
    }
    if (_active < 2) {
      _active++;
      return;
    }
    final wait = Completer<void>();
    _queue.add(wait);
    void cancel() {
      if (_queue.remove(wait)) {
        wait.completeError(
          const ParseException(
            ParseErrorCode.cancelled,
            'Source task cancelled',
          ),
        );
      }
    }

    cancellation?.add(cancel);
    try {
      await wait.future.timeout(timeout);
    } on TimeoutException {
      _queue.remove(wait);
      rethrow;
    } finally {
      cancellation?.remove(cancel);
    }
  }

  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _active--;
    }
  }

  Future<JsEngine> _engine() async {
    try {
      await (_initializing ??= LibFjs.init().catchError((Object e) {
        _initializing = null;
        throw e;
      }));
    } catch (_) {
      throw const ParseException(
        ParseErrorCode.dependencyMissing,
        'Embedded JavaScript engine could not be loaded',
      );
    }
    return JsEngine.create(
      builtins: JsBuiltinOptions.none().copyWith(
        url: true,
        util: true,
        fetch: true,
        abort: true,
        timers: true,
        streamWeb: true,
        crypto: true,
        buffer: true,
      ),
      runtimeOptions: JsEngineRuntimeOptions(
        memoryLimit: BigInt.from(256 * 1024 * 1024),
        maxStackSize: BigInt.from(2 * 1024 * 1024),
      ),
    );
  }

  @override
  Future<void> validate(SourceFile source) async {
    await _run(
      source,
      'validate',
      {},
      null,
      ParseOptions(timeout: const Duration(seconds: 5)),
    );
  }

  @override
  Future<Map<String, dynamic>> execute(
    SourceFile source,
    String operation,
    Map<String, dynamic> input,
    ParserHttpClient http,
    ParseOptions options,
  ) => _run(source, operation, input, http, options);
  Future<Map<String, dynamic>> _run(
    SourceFile source,
    String operation,
    Map<String, dynamic> input,
    ParserHttpClient? http,
    ParseOptions options,
  ) async {
    final clock = Stopwatch()..start();
    Duration remaining() {
      final d = options.timeout - clock.elapsed;
      if (d <= Duration.zero) {
        throw const ParseException(
          ParseErrorCode.timeout,
          'Source parsing timed out',
        );
      }
      return d;
    }

    try {
      await _acquire(remaining(), options.cancellation);
    } on TimeoutException {
      throw const ParseException(
        ParseErrorCode.timeout,
        'Source queue timed out',
      );
    }
    final cancelled = ParseCancellation();
    final stopped = Completer<Map<String, dynamic>>();
    void stop() {
      cancelled.cancel();
      if (!stopped.isCompleted) {
        stopped.completeError(
          const ParseException(
            ParseErrorCode.cancelled,
            'Source task cancelled',
          ),
        );
      }
    }

    options.cancellation?.add(stop);
    JsEngine? engine;
    Future<Map<String, dynamic>> run() async {
      final created = await _engine();
      engine = created;
      if (cancelled.isCancelled) {
        await created.close();
        throw const ParseException(
          ParseErrorCode.timeout,
          'Source task expired',
        );
      }
      final host = http == null
          ? null
          : SourceHost(
              source.manifest,
              http,
              options,
              cancelled,
              remaining,
              _cache,
              sha256.convert(utf8.encode(source.code)).toString(),
            );
      await created.init(
        bridge: (value) async {
          try {
            if (host == null) {
              throw const ParseException(
                ParseErrorCode.permissionDenied,
                'Host calls are disabled during source validation',
              );
            }
            final request = Map<String, dynamic>.from(value.value as Map);
            final result = await host.invoke(
              request['method'] as String,
              Map<String, dynamic>.from(request['args'] as Map),
            );
            return JsResult.ok(JsValue.from({'ok': true, 'value': result}));
          } on ParseException catch (e) {
            return JsResult.ok(
              JsValue.from({
                'ok': false,
                'code': e.code.name,
                'message': e.message,
              }),
            );
          } catch (_) {
            return JsResult.ok(
              JsValue.from({
                'ok': false,
                'code': 'scriptError',
                'message': 'Invalid host request',
              }),
            );
          }
        },
      );
      await created.declareNewModules(
        modules: [
          JsModule.code(module: '@social/runtime', code: standardRuntimeModule),
          JsModule.code(module: 'source', code: source.code),
          JsModule.code(
            module: 'entry',
            code: r'''
import {configure} from '@social/runtime';
import * as source from 'source';
export async function run(encoded) {
  try {
    const {operation,input,config}=JSON.parse(encoded);
    if(operation!=='validate')configure(config);
    if(typeof source.parse!=='function'||typeof source.resolve!=='function') throw Object.assign(new Error('Source must export parse and resolve'),{code:'invalidSource'});
    if(operation==='validate') return JSON.stringify({ok:true,value:{}});
    return JSON.stringify({ok:true,value:await source[operation](input)});
  } catch(e) {return JSON.stringify({ok:false,code:e.code||'scriptError',reason:['YouTube requires a PO token','YouTube unavailable or region restricted','Missing player','YouTube challenge failed'].includes(e.message)?e.message:null});}
}
''',
          ),
        ],
      );
      final result = await created.call(
        module: 'entry',
        method: 'run',
        params: [
          JsValue.string(
            jsonEncode({
              'operation': operation,
              'input': input,
              'config': {
                'headers': options.headers,
                'cookies': options.cookies,
                'requestDomains': source.manifest.requestDomains,
                'cookieDomains': source.manifest.cookieDomains,
                'deadline':
                    DateTime.now().millisecondsSinceEpoch +
                    remaining().inMilliseconds,
                'userAgent': parserUserAgent,
                'nativeTransport':
                    http is DioParserHttpClient &&
                    http.supportsNativeFetch &&
                    options.proxy == null,
              },
            }),
          ),
        ],
      );
      final data = jsonDecode((result as JsValue_String).field0) as Map;
      if (data['ok'] != true) {
        final code =
            ParseErrorCode.values
                .where((c) => c.name == data['code'])
                .firstOrNull ??
            ParseErrorCode.scriptError;
        final reason = switch (data['reason']) {
          'YouTube requires a PO token' => '该 YouTube 格式需要额外的 PO Token',
          'YouTube unavailable or region restricted' => 'YouTube 表示视频不可用或有地区限制',
          'Missing player' => '未获取到 YouTube 播放器脚本',
          'YouTube challenge failed' => 'YouTube 播放器校验失败，可能需要更新源',
          _ => null,
        };
        throw ParseException(
          code,
          reason ??
              switch (code) {
                ParseErrorCode.authenticationRequired => '网站需要有效 Cookie 或验证',
                ParseErrorCode.unsupportedContent => '该内容不可用或需要额外访问能力',
                ParseErrorCode.permissionDenied => '源请求了未允许的宿主能力或域名',
                ParseErrorCode.cancelled => '解析已取消',
                ParseErrorCode.timeout => '解析超时',
                _ => 'JS 源未能返回有效结果',
              },
        );
      }
      return Map<String, dynamic>.from(data['value'] as Map);
    }

    try {
      return await Future.any([run(), stopped.future]).timeout(remaining());
    } on TimeoutException {
      throw const ParseException(
        ParseErrorCode.timeout,
        'Source parsing timed out',
      );
    } on ParseException {
      rethrow;
    } catch (_) {
      throw const ParseException(
        ParseErrorCode.scriptError,
        'JavaScript source execution failed',
      );
    } finally {
      options.cancellation?.remove(stop);
      cancelled.cancel();
      try {
        await engine?.close();
      } finally {
        _release();
      }
    }
  }
}
