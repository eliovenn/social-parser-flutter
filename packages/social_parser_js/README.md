# social_parser_js

基于 FJS 3.3.2 / QuickJS 的 Flutter 运行时，随包提供 20 个官方平台 JS 产物。

`await createSocialParser()` 加载本地平台。已配置官方 jsDelivr 索引；传入 sourceDirectory 可持久化更新，officialIndexUrl 可覆盖默认地址。平台使用标准 fetch、FJS crypto、只读 parserContext 和跨任务 parserCache。当前仅支持源 API 1。

本包不需要 Node、Python 或 yt-dlp，不包含 npm 构建工具；平台源码位于独立 social-parser-sources 项目。

- [接入](../../docs/integration.md)
- [官方更新](../../docs/platform-updates.md)
- [运行原理](../../docs/architecture.md)
