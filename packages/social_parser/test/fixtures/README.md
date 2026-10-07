# 离线测试样本

| 文件 | 用途 |
| --- | --- |
| platform_cases.json | 13 个平台的构造请求/响应及预期媒体，用于 FJS 平台回归 |
| signature_vectors.json | 固定时间、随机值和 IV 的参考签名输出 |
| xhs_mixed.html | 小红书图文、Live Photo 和 undefined 数据处理 |
| xhs_mobile.html | 小红书移动页面数据解析 |

样本不含真实登录凭据。部分预期值源于 ParseHub 原算法对照，不需要运行 Python。测试通过只说明样本行为正确，不证明网站当前线上可用。
