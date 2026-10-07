# 示例应用

在仓库根目录执行 `flutter pub get`，进入本目录后运行 `flutter run`。

粘贴分享文本或链接，按需填写 Cookie。解析结果直接预览图片，视频/音频显示格式、轨道、请求头及可复制地址。Cookie 按平台填写 JSON 对象，例如 `{"xhs":"a=1; b=2","douyin":{"sessionid":"值"}}`。解析时仅取当前平台的配置，切换链接不会清空；配置仅保存在当前页面内存中。

右上角“平台更新”可检查并下载官方新版、查看版本和恢复上一版。默认使用官方 jsDelivr 索引，可用 `--dart-define=SOCIAL_PARSER_INDEX_URL=其他JSON地址` 覆盖。

- [接入与移动端构建](../docs/integration.md)
- [官方更新与 jsDelivr](../docs/platform-updates.md)
- [测试命令与验证范围](../docs/testing.md)
