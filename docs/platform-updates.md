# 官方平台更新

应用初始使用内置 JS。示例点击“平台更新 → 检查并更新”后获取官方索引，下载较新的平台代码；不在启动时自动联网检查，也不提供自定义源导入。

## 应用配置

```dart
import 'dart:io';
import 'package:social_parser_js/social_parser_js.dart';

final parser = await createSocialParser(
  sourceDirectory: Directory('/your/app/support/official_platforms'),
  officialIndexUrl: Uri.parse(
    'https://cdn.jsdelivr.net/gh/eliovenn/social-parser-sources@main/index.json',
  ),
);
final results = await parser.sources.updateBuiltins();
```

results 按平台 ID 返回结果：null 表示成功，其他值为该平台错误。索引获取或协议错误会抛出异常，单个平台更新失败不阻断其他平台。

示例已使用应用支持目录，可在 example 目录运行：

```sh
flutter run
```

默认地址为 `https://cdn.jsdelivr.net/gh/eliovenn/social-parser-sources@main/index.json`，无需额外配置。更新请求不携带解析任务中的 Cookie。

## 索引与安装

```json
{
  "apiVersion": 1,
  "sources": [{
    "id": "official.xhs",
    "version": "1.0.0",
    "url": "https://cdn.jsdelivr.net/gh/eliovenn/social-parser-sources@v1.0.0/dist/xhs.js",
    "sha256": "由发布工具计算的64位十六进制摘要"
  }]
}
```

仅接受当前 API 1。索引和 JS 中的 ID、版本必须一致，SHA-256 校验及模块加载校验通过后才原子保存。失败保留旧版；更新成功后可恢复上一版。重新启动会加载本地版本，应用新内置版本不会被更旧的本地版本覆盖。

未上线阶段统一使用平台版本 1.0.0。正式发布后需递增要更新的平台版本，客户端才会识别新版；普通平台修复不改变 apiVersion。

## JS 项目发布

在独立 social-parser-sources 项目中：

1. 修改平台并构建、测试，将 dist/ 一并提交到 GitHub。
2. 为该提交创建固定 tag 或使用完整提交号。
3. 运行 `npm run publish:index -- --repo eliovenn/social-parser-sources --ref v1.0.0`。
4. 将生成的根目录 index.json 提交到 main。

JS 地址固定到已发布 ref，索引地址跟随 main；不要修改已发布的 tag。dist/index.json 保持相对路径，供构建检查和内置同步使用。jsDelivr 缓存可能延迟新版可见时间。摘要校验用于完整性，不是发布者签名。

## 更新 Flutter 内置基线

在 Flutter 仓库运行：

```sh
dart run tool/sync_sources.dart /absolute/path/to/social-parser-sources
```

工具先读取并检查全部源的 API、ID、版本、文件名和摘要，再同步 assets 及两份 FJS 测试脚本。随后执行 [回归测试](testing.md)。仅发布远程平台修复时不必同步或重新发布 Flutter 应用。
