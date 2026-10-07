# Social Parser Flutter

从分享文本或链接解析社交媒体内容，返回图片、视频、音频及其地址。示例展示图片，视频仅提供格式、轨道、请求头和可复制链接；库不下载或转码媒体。

## 项目组成

```text
packages/social_parser/     Dart 模型、链接识别、网络与平台版本管理
packages/social_parser_js/  FJS 运行时及 20 个内置平台 JS 产物
example/                    Android/iOS 示例
tool/                       同步、检查与 Git 发布工具
docs/                       接入和维护说明
```

平台源码、npm 打包和 jsDelivr 索引发布位于独立的 `social-parser-sources` 项目。本项目使用其构建产物，运行和构建不依赖上一级目录，也不需要 Node、Python 或 yt-dlp。

当前源协议为 `apiVersion: 1`，20 个平台初始版本均为 `1.0.0`。尚未上线，不维护旧接口兼容。

## 快速使用

```dart
import 'package:social_parser/social_parser.dart';
import 'package:social_parser_js/social_parser_js.dart';

final parser = await createSocialParser();
final result = await parser.parse(
  '分享链接或文案',
  options: ParseOptions(cookies: {'cookie_name': 'cookie_value'}),
);
for (final media in result.media) {
  for (final source in media.sources) {
    print(source.url);
  }
}
```

运行示例：

```sh
flutter pub get
cd example
flutter run
```

通过示例右上角“平台更新”检查官方新版。已配置官方 jsDelivr 索引，点击后检查更新。示例不提供自定义源导入，不持久化 Cookie。

## 文档

- [接入与构建](docs/integration.md)：Git 依赖、初始化和移动端要求。
- [运行原理](docs/architecture.md)：JS 执行、网络、Cookie、缓存和取消。
- [平台范围](docs/platforms.md)：20 个平台的支持内容与边界。
- [官方更新](docs/platform-updates.md)：jsDelivr 配置、版本与内置同步。
- [测试与维护](docs/testing.md)：验证命令、工具用途和已验证范围。

当前目录不包含项目 LICENSE 或 third_party 声明文件。删除目录不改变所使用第三方代码的许可要求；公开分发前需核对授权和应保留的版权声明。
