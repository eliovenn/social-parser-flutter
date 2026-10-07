import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'platform_updates_page.dart';
import 'package:flutter/material.dart';
import 'package:social_parser/social_parser.dart';
import 'package:social_parser_js/social_parser_js.dart';
import 'cookie_input.dart';
import 'result_view.dart';

void main() => runApp(const ParserExample());

class ParserExample extends StatefulWidget {
  const ParserExample({super.key, this.parser});
  final SocialParser? parser;
  @override
  State<ParserExample> createState() => _ParserExampleState();
}

class _ParserExampleState extends State<ParserExample> {
  late final Future<SocialParser> _loading = _load();
  Future<SocialParser> _load() async {
    if (widget.parser != null) return widget.parser!;
    final directory = await getApplicationSupportDirectory();
    const index = String.fromEnvironment(
      'SOCIAL_PARSER_INDEX_URL',
      defaultValue: defaultOfficialIndexUrl,
    );
    return createSocialParser(
      sourceDirectory: Directory('${directory.path}/official_platforms'),
      officialIndexUrl: index.isEmpty ? null : Uri.parse(index),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '社交媒体解析测试',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: widget.parser != null
            ? ParserPage(parser: widget.parser!)
            : FutureBuilder<SocialParser>(
                future: _loading,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return ParserPage(parser: snapshot.data!);
                  }
                  return Scaffold(
                      appBar: AppBar(title: const Text('社交媒体解析测试')),
                      body: Center(
                          child: snapshot.hasError
                              ? const Text('内置平台加载失败，请重启应用后重试。')
                              : const CircularProgressIndicator()));
                }),
      );
}

class ParserPage extends StatefulWidget {
  const ParserPage({super.key, required this.parser});
  final SocialParser parser;
  @override
  State<ParserPage> createState() => _ParserPageState();
}

class _ParserPageState extends State<ParserPage> {
  final _input = TextEditingController();
  final _cookie = TextEditingController();
  late final _parser = widget.parser;
  ParseCancellation? _cancellation;
  bool _busy = false, _showCookie = false;
  SocialPlatform? _detected;
  ParseResult? _result;
  String? _error;
  Duration? _elapsed;

  void _inputChanged(String value) {
    setState(() => _detected = _parser.detectPlatform(value));
  }

  Future<void> _parse() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
      _elapsed = null;
    });
    final watch = Stopwatch()..start();
    _cancellation = ParseCancellation();
    try {
      final result = await _parser.parse(_input.text,
          options: ParseOptions(
              cookies: cookiesForPlatform(
                _cookie.text,
                _parser.detectPlatform(_input.text)?.name,
                platformIds: _parser.platforms.map((p) => p.platform.name),
              ),
              cancellation: _cancellation,
              timeout: const Duration(seconds: 90)));
      if (mounted) setState(() => _result = result);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on ParseException catch (e) {
      if (mounted) setState(() => _error = parseErrorText(e));
    } catch (_) {
      if (mounted) setState(() => _error = '解析未完成，请检查链接后重试。');
    } finally {
      watch.stop();
      if (mounted) {
        setState(() {
          _busy = false;
          _elapsed = watch.elapsed;
        });
      }
    }
  }

  String _platformName(SocialPlatform platform) =>
      _parser.platforms.firstWhere((p) => p.platform == platform).name;

  @override
  void dispose() {
    _cancellation?.cancel();
    _input.dispose();
    _cookie.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('社交媒体解析测试'), actions: [
          IconButton(
              tooltip: '平台更新',
              icon: const Icon(Icons.system_update),
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) =>
                          PlatformUpdatesPage(manager: _parser.sources)))),
        ]),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  const Text('粘贴分享链接，按需添加 Cookie。解析后预览图片，复制视频地址。'),
                  ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('已接入 ${_parser.platforms.length} 个社交平台'),
                      subtitle: const Text('自动识别链接所属平台'),
                      children: [
                        Wrap(spacing: 6, children: [
                          for (final p in _parser.platforms)
                            Chip(
                                label: Text('${p.name} (${p.platform.name})'),
                                avatar: Icon(
                                    p.available ? Icons.check : Icons.extension,
                                    size: 16))
                        ])
                      ]),
                  const SizedBox(height: 12),
                  TextField(
                      key: const Key('share-input'),
                      controller: _input,
                      enabled: !_busy,
                      onChanged: _inputChanged,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: '分享链接或文案',
                          hintText: '粘贴完整分享内容，保留链接中的参数')),
                  if (_detected case final platform?)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('识别为：${_platformName(platform)}',
                            key: const Key('detected-platform'))),
                  const SizedBox(height: 16),
                  TextField(
                      key: const Key('cookie-input'),
                      controller: _cookie,
                      enabled: !_busy,
                      obscureText: !_showCookie,
                      minLines: _showCookie ? 4 : 1,
                      maxLines: _showCookie ? 8 : 1,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: '各平台 Cookie（JSON 对象，可选）',
                          hintText:
                              '{"xhs":"a=1; b=2","douyin":{"sessionid":"值"}}',
                          suffixIcon: IconButton(
                              tooltip: _showCookie ? '隐藏 Cookie' : '显示 Cookie',
                              onPressed: () =>
                                  setState(() => _showCookie = !_showCookie),
                              icon: Icon(_showCookie
                                  ? Icons.visibility_off
                                  : Icons.visibility)))),
                  const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                          '按平台标识填写，仅使用当前平台的 Cookie；切换链接会保留配置，仅保存在页面内存中。',
                          style: TextStyle(fontSize: 12))),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                      onPressed: _busy ? null : _parse,
                      icon: const Icon(Icons.search),
                      label: Text(_busy ? '解析中…' : '解析')),
                  if (_busy)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Column(children: [
                          LinearProgressIndicator(),
                          SizedBox(height: 8),
                          Text('正在调用平台 JS 源获取作品数据。')
                        ])),
                  if (_busy)
                    TextButton(
                        onPressed: () => _cancellation?.cancel(),
                        child: const Text('取消解析')),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: SelectableText(_error!,
                            key: const Key('parse-error'),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (_result case final result?) ...[
                    const SizedBox(height: 20),
                    Text(
                        '解析完成 · ${result.media.length} 项媒体 · ${((_elapsed?.inMilliseconds ?? 0) / 1000).toStringAsFixed(1)} 秒'),
                    ResultView(result: result),
                  ],
                ]))),
      );
}

String parseErrorText(ParseException error) {
  final message = switch (error.code) {
    ParseErrorCode.invalidInput => '请输入有效的分享链接或文案。',
    ParseErrorCode.unknownPlatform => '无法识别这个链接，请使用上方列表中平台的作品链接。',
    ParseErrorCode.authenticationRequired =>
      '网站要求登录或验证，请更新该平台 Cookie，必要时先在网站完成验证。',
    ParseErrorCode.notFound => '作品不存在、已删除或当前账户不可见。',
    ParseErrorCode.cancelled => '解析已取消。',
    ParseErrorCode.timeout => '请求超时，请检查网络后重试。',
    ParseErrorCode.network => '网络请求失败，请检查网络连接。',
    ParseErrorCode.dependencyMissing => '缺少视频解析依赖，或该内容需要额外运行能力，请查看下方原因。',
    ParseErrorCode.unsupportedContent => '该内容暂时无法解析，请查看下方具体原因。',
    _ => '解析未完成，网站接口可能发生变化，请检查链接与 Cookie。',
  };
  return '$message\n${error.message}\n错误代码：${error.code.name}';
}
