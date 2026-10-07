# 运行原理

## 调用流程

```text
分享文本 + Cookie
  → Dart 提取链接并匹配平台
  → 选择本地平台版本（没有更新时使用内置版本）
  → 独立 FJS / QuickJS 引擎执行 resolve 或 parse
  → JS 请求网页、计算签名、提取媒体
  → Dart 校验并转换为 ParseResult
```

`social_parser` 不实现平台解析器。`social_parser_js` 加载 JS、提供执行环境，并把结果交给核心包。每项媒体可以有多个格式；网页地址与媒体直链分开保存，HLS/DASH 清单和独立音视频轨道分别标记。

## JS 能力

普通请求使用 FJS 3.3.2 原生 `fetch`；支持 Headers、Request、Response、AbortController、URL、计时器和流。签名摘要与随机数直接从 FJS 的 `crypto` 模块获取。HTML/XML 由平台产物中的纯 JS 实现解析，不执行网页内的脚本，也没有浏览器 document、Node 文件系统或进程。

宿主额外提供：

| 名称 | 用途 |
| --- | --- |
| `parserContext` | 本次任务的只读 cookies、headers、剩余 timeoutMs；读取不跨 Dart 桥接 |
| `parserCache.get/set` | 跨独立 JS 引擎的短期缓存，由 Dart 持有 |

没有 `@social/host` 模块。显式配置代理或注入自定义 HTTP 客户端时，Dart 提供 GET/POST 传输；普通请求不经过 Dart HTTP。

当前 FJS 的 Request.credentials/redirect getter 返回默认值，运行时用 JS 保留构造参数，使 `fetch(url, init)` 与 `fetch(new Request(...))` 遵守相同规则。这是引擎行为修正，不是旧平台接口兼容。

## 域名与 Cookie

- `domains` 匹配分享链接。
- `requestDomains` 限定请求域名，可省略，默认使用 domains。仅 TikTok 额外声明 tiktokv.com 接口域名。
- `cookieDomains` 限定可发送登录凭据的域名；短链与作品页可能不同，因此单独保留。

每跳重定向都检查域名。跨域跳转移除 Cookie/Authorization；`credentials: 'omit'` 不发送登录凭据。不自动维护浏览器 Cookie 仓库。平台代码仍能读取本次显式传入的 Cookie，因此仅从应用配置的官方索引更新。

## 生命周期

每次任务创建独立 VM，结束后释放；每个 runtime 最多同时执行两个任务，其余排队。排队时间计入总超时。任务取消使用 ParseCancellation，超时/取消会终止执行、取消 Dart 传输并释放引擎。

每个 VM 的堆上限为 256 MiB、栈上限为 2 MiB。fetch 响应限制为 16 MiB。缓存按完整源代码摘要隔离，总量最多 8 MiB、32 项，单项最多 2 MiB，有效期最长一小时。平台不能依赖缓存一定命中。

模块安装校验阶段不提供任务参数、网络或缓存调用。可加载性校验不代表真实网站解析必定成功。
