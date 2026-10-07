# social_parser

纯 Dart 核心包，提供结果模型、分享链接提取、平台元数据、HTTP 抽象及源版本管理。它不包含平台实现或 JS 引擎。

直接构造 SocialParser 时必须提供 SourceRuntime 和 SourceManager。Flutter 使用方通常通过 social_parser_js 的 `createSocialParser()` 初始化，再用本包的 ParseOptions、ParseResult 等类型。

源码通过 Git 分发，不发布到 pub.dev。使用方法见 [接入说明](../../docs/integration.md)，模块职责见 [运行原理](../../docs/architecture.md)。
