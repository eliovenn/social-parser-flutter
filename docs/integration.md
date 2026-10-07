# 接入与构建

## 仓库内开发

仓库使用 Dart workspace，两个包和示例共用依赖解析：

```sh
flutter pub get
cd example
flutter run
```

Node/npm 只用于独立的 JS 项目，本仓库不需要。FJS 原生构建需要相应的 Rust、libclang 和移动端工具链；首次构建会下载依赖。

## Git 引用

两个 Dart 包设置 publish_to: none，不发布到 pub.dev。当前包版本为 0.2.0；这是 Dart 包版本，与 JS 协议 1、平台版本 1.0.0 分别管理。

维护者发布前，在仓库根目录执行以下命令，将包间依赖固定到真实仓库与同一 tag：

```sh
dart run tool/prepare_release.dart https://github.com/OWNER/FLUTTER_REPO.git v0.2.0
```

检查改动、验证并提交后再创建和推送 tag。以下地址为占位符，不代表已发布：

```yaml
dependencies:
  social_parser:
    git:
      url: https://github.com/OWNER/FLUTTER_REPO.git
      ref: v0.2.0
      path: packages/social_parser
  social_parser_js:
    git:
      url: https://github.com/OWNER/FLUTTER_REPO.git
      ref: v0.2.0
      path: packages/social_parser_js
```

## 初始化

`await createSocialParser()` 加载内置平台。默认使用官方 jsDelivr 索引；需要持久化更新时传入 sourceDirectory，可用 officialIndexUrl 覆盖索引地址，详见 [官方更新](platform-updates.md)。不传目录时更新仅在本次进程中有效。

只使用纯 Dart 核心包时，需要自行提供 SourceRuntime 和 SourceManager；它自身不能执行 JS。可通过 ParseOptions 传入 Cookie、请求头、代理、超时及取消令牌。

## 移动端

Android 需要 Internet 权限，示例已配置。测试 ARM64 包：

```sh
cd example
flutter build apk --release --target-platform android-arm64
```

示例 release 使用开发签名。iOS 需要 macOS/Xcode 及 FJS 所需工具链，HTTP 媒体还可能受应用 ATS 设置限制。桌面测试不代表移动端验证；当前验证范围见 [测试说明](testing.md)。
