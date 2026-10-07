# 测试与维护

## 日常验证

先执行 `flutter pub get`，然后：

```sh
dart analyze --fatal-infos
cd packages/social_parser
dart test
```

Flutter/FJS 测试需要主机原生库。从仓库根目录使用已有动态库运行：

```sh
LD_LIBRARY_PATH=/absolute/path/to/native flutter test --no-pub packages/social_parser_js/test example/test
```

Linux 上也可以执行 `bash tool/verify_embedded_js.sh`，脚本会构建原生库、运行平台测试，并验证仓库外 Git 接入。需要 Flutter/Dart 在 PATH，及 Rust/libclang。

## 工具职责

| 工具 | 用途 |
| --- | --- |
| sync_sources.dart | 从独立 JS 项目同步校验过的内置产物和测试脚本 |
| prepare_release.dart | 配置两个 Dart 包的发布版本与内部 Git 依赖 |
| git_dependency_smoke.dart | 创建临时 Git 消费项目，验证仓库外接入 |
| verify_embedded_js.sh | 构建 Linux FJS 原生库并运行验证 |
| package_path.dart | 为验证脚本定位已解析的 FJS 依赖 |

这些工具有实际用途，不是历史迁移脚本。

## 真实网站与设备

普通回归使用脱敏样本，原生 fetch 测试使用本地 HTTP 服务。真实网站测试需显式传入链接：

```sh
LD_LIBRARY_PATH=/absolute/path/to/native flutter test --no-pub \
  --dart-define=YOUTUBE_TEST_LINK=https://youtu.be/Hp1OsvXdut0 \
  --dart-define=XHS_TEST_LINK=https://xhslink.cn/o/3qIptYqjdjh \
  packages/social_parser_js/test/youtube_live_test.dart
```

在 example 目录运行移动端集成测试：

```sh
flutter test integration_test/ui_test.dart -d DEVICE_ID
flutter test integration_test/javascript_test.dart -d DEVICE_ID
```

另有 youtube_live_test.dart 和 xhs_live_test.dart，分别传入上述对应链接参数。

## 已验证范围

2026-10-07 当前实现：74 项 Flutter/FJS/示例测试、11 项核心测试通过，2 项真实网站测试默认跳过，静态检查通过。覆盖 20 个平台样本、签名、Cookie、分轨、原生 fetch、取消/超时、域名匹配以及官方更新持久化与回退。

2026-10-05 的较早实现曾验证用户提供的 YouTube 媒体地址、小红书无 Cookie 图片，并在 MI 8 上构建安装运行。随后网络与宿主接口已有调整，因此这些结果不作为当前移动端或网站验证结论。当前实现尚未重新验证 Android/iOS 设备或全部真实网站。
