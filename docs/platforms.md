# 平台范围

当前内置 20 个官方平台，仅解析单条内容，不扩展频道、播放列表、下载或转码。平台实现位于独立 JS 项目。

| 平台 | 当前路径 | 验证 |
| --- | --- | --- |
| YouTube | JS 网页/Innertube；随源内置 EJS signature/n | 离线签名、轨道、身份、错误测试；登录、地区限制或 PO Token 可能阻止解析 |
| Facebook | JS legacy/Relay、直链与清单 | 构造样本；本次未验证真实登录视频 |
| Snapchat | JS Spotlight Next.js | 构造样本；不支持 /@ 个人主页故事 |
| Bilibili | JS API + WBI 备用接口、DASH 分轨 | 固定签名向量、分 P 与备用接口样本 |

## 其他平台

| 平台 | 当前实现 | 验证/后续 |
| --- | --- | --- |
| 小红书 | JS 桌面/移动网页数据、视频多编码、图片、Live Photo；保留分享参数、Cookie/匿名回退 | 离线样本与 Cookie/匿名请求测试；视频/Live Photo 真实网站待验证 |
| 皮皮虾 | JS 网页数据、图片/视频 | 离线样本 |
| 最右 | JS 接口、图文混排 | 离线样本 |
| 抖音 | JS A-Bogus/SM3 网页接口、分享页、视频/图集/Live Photo | 离线样本、参考签名向量 |
| TikTok | JS app feed 与网页 hydration，视频/图文、多格式 | 离线样本；严格匹配作品 ID |
| 微博 | JS 普通微博、混排、转发、TV，图片/视频/动图/Live Photo | 离线混排样本 |
| 微信公众号 | JS 数据对象与正文 DOM，文章/图文/纯文本、Markdown | 离线脚本样本、保留文章定位参数 |
| 贴吧 | JS TBS、表单签名、帖子图文和视频 | 离线样本 |
| Instagram | JS GraphQL、CSRF、旧/新媒体结构、轮播 | 离线样本、CSRF Cookie 传递 |
| Threads | JS GraphQL、CSRF、图文/视频/轮播 | 离线样本、大整数 ID、拒绝错误作品 |
| Twitter / X | JS GraphQL，推文/长文/文章媒体、多视频格式 | 离线样本；文章正文为纯文本 |
| 快手 | JS Apollo/INIT_STATE、图集 CDN、多格式、GraphQL 回退 | 离线视频/图集样本 |
| 酷安 | JS feed/picture 网页、富文本、图片/动图 | 离线样本、保留 shareKey/s |
| 小黑盒 | JS hkey 签名、帖子接口、图文/视频，使用用户 Cookie | 离线样本、参考签名向量、缺 token 错误 |
| 知乎 | JS x-zse-96，问答/专栏/想法/日报、富文本/图片/视频 | 离线回答样本、参考签名向量 |
| 豆瓣 | JS 小组话题接口、富文本、图片/视频/动图 | 离线混合样本 |


接口、登录、风控和地区限制会影响实际可用性。YouTube 的播放器校验由内置 EJS 完成，不会提供登录身份或 PO Token。小红书保留分享参数并尝试 Cookie/匿名路径，不能因一次请求失败就判定必须登录。当前验证范围见 [测试说明](testing.md)。
