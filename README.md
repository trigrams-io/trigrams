# Trigrams

A native macOS agent, built around pi's extensible harness and Apple's on-device Foundation Models.

**当前状态：架构与设计提案，等待确认。应用尚未开始实现。**

Trigrams 是通用的本地 agent。核心只保留原生界面、AFM 模型桥接和完整 pi 宿主；具体功能通过可读取、可安装、可组合的 skills、extensions 和 MCP 接入。App 不内置 macOS 自动化工具服务。

| 文档 | 内容 |
| --- | --- |
| [架构](docs/architecture.md) | pi SDK、Swift 服务、模型适配、工具边界、会话与数据 |
| [pi 能力兼容](docs/pi-compatibility.md) | 上游能力对应表、skills 规则、扩展 UI 兼容与验收 |
| [界面设计](docs/design.md) | 聊天列表、聊天框、自定义控件、Phosphor 图标、Nano 深浅配色 |
| [品牌与数学标志](docs/brand/README.md) | Sine 标志、Nano 两套配色、字标、app icon、favicon 与完整物料包 |
| [评审与实施顺序](docs/review.md) | 本轮需要确认的决策、验证项与阶段验收 |
| [参考资料](docs/references.md) | 上游版本快照与官方资料 |

![Trigrams mark studies](docs/brand/trigrams-preview.png)

这一轮只添加设计文档和标志设计资产。文档中的目录、接口、命令和组件均是拟议方案，除标志生成器外尚未实现。
