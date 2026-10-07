import 'package:flutter/material.dart';
import 'package:social_parser/social_parser.dart';

class PlatformUpdatesPage extends StatefulWidget {
  const PlatformUpdatesPage({super.key, required this.manager});
  final SourceManager manager;
  @override
  State<PlatformUpdatesPage> createState() => _PlatformUpdatesPageState();
}

class _PlatformUpdatesPageState extends State<PlatformUpdatesPage> {
  bool _busy = false;
  String _status = '检查后会自动下载并使用兼容的新版解析代码。';
  bool get _configured => widget.manager.installed
      .any((source) => source.builtin != null && source.indexUrl != null);

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _status = '正在检查并更新平台…';
    });
    try {
      final results = await widget.manager.updateBuiltins();
      final failed = results.values.where((value) => value != null).length;
      if (mounted) {
        setState(() {
          _status = results.isEmpty
              ? '当前平台已是最新版本。'
              : '已更新 ${results.length - failed} 个平台'
                  '${failed == 0 ? '。' : '，$failed 个更新失败，继续使用原版本。'}';
        });
      }
    } on ParseException catch (error) {
      if (mounted) {
        setState(() => _status = switch (error.code) {
              ParseErrorCode.incompatibleSource => '此更新需要新版应用，继续使用当前平台版本。',
              ParseErrorCode.integrityFailure => '更新文件校验失败，继续使用当前版本。',
              _ => '暂时无法检查更新，当前版本仍可使用。',
            });
      }
    } catch (_) {
      if (mounted) setState(() => _status = '暂时无法检查更新，当前版本仍可使用。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rollback(String id) async {
    setState(() => _busy = true);
    try {
      await widget.manager.rollback(id);
      if (mounted) setState(() => _status = '已恢复上一版本。');
    } catch (_) {
      if (mounted) setState(() => _status = '恢复失败，当前版本保持不变。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('平台更新')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(_configured ? _status : '尚未配置官方更新地址，当前使用本地平台版本。'),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: _busy || !_configured ? null : _update,
              child: Text(_busy ? '正在处理…' : '检查并更新')),
          if (_busy) const LinearProgressIndicator(),
          for (final source
              in widget.manager.installed.where((s) => s.builtin != null))
            ListTile(
                title: Text(source.current.manifest.name),
                subtitle: Text('版本 ${source.current.manifest.version}'),
                trailing: source.previous == null
                    ? null
                    : TextButton(
                        onPressed: _busy
                            ? null
                            : () => _rollback(source.current.manifest.id),
                        child: const Text('恢复上一版'))),
        ]),
      );
}
