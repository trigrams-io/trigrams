# pi 能力兼容契约

状态：待评审的目标清单，**不代表当前已经实现**。

基线：pi 上游快照 `200387122ca450d6387f033949423114a270b96c`。兼容对象是完整 SDK 与公开扩展能力，而不是只保留四个工具的 agent loop。Trigrams 通过原生入口承载 CLI 的能力，终端显示形式可以变化，调用语义不能无声丢失。

## 1. 能力对应表

| pi 能力 | Trigrams 的承载方式 | 验收重点 |
| --- | --- | --- |
| Agent loop、工具批次、生命周期事件 | 原样使用 SDK runtime | 调用、结果、错误、后续生成均进入同一会话 |
| Streaming、取消、自动重试 | Provider bridge + 原生状态投影 | 增量不重复；取消后无迟到提交；重试过程可见 |
| Steering、follow-up 队列 | 输入框队列操作与 SDK 原接口 | 忙碌时可选择立即 steering 或完成后 follow-up |
| read / bash / edit / write、grep / find / ls 等工具 | 保留上游可配置工具集合 | 默认集与可选集按锁定版本校验，行为不重写 |
| Skills 与显式 `/skill:name` | 原 resource loader；输入框补全；Skills 页面 | 发现、按需读取、参数、相对路径、重载 |
| Prompt templates | 原资源与展开逻辑 | 命名、参数、冲突诊断与可发现性 |
| AGENTS.md / SYSTEM.md / APPEND_SYSTEM.md 等上下文资源 | 由上游 loader 处理 | 工作目录、项目 trust、层级规则与 provenance |
| 扩展事件、tools、commands、flags、shortcuts | 同进程扩展 runtime；宿主入口适配 | 不只支持 tool 注册；保留事件顺序和取消 |
| 扩展自定义消息与持久化 entries | pi session tree + 原生通用呈现 | 未知类型仍可展开和导出，数据不丢弃 |
| 扩展工具 / 消息自定义 renderer | pi-tui 兼容视图；原生摘要入口 | renderer 实际执行；fallback 不隐藏原始结果 |
| 结构化扩展 UI | 原生 select / confirm / input / editor | 返回值、dismiss、超时和编辑器文本一致 |
| 任意 TUI component / custom editor / overlay | 同会话终端兼容视图 | 键盘、焦点、主题、dispose、overlay handle |
| status、widgets、header/footer、working indicator | 原生映射或兼容组件 | 每项方法有明确去向，不采用 RPC 空实现 |
| Terminal input hooks / keybindings / autocomplete | 兼容视图与宿主输入适配 | 原始输入、provider wrapper、绑定冲突可诊断 |
| Themes 与 theme API | 扩展兼容视图保留 pi themes | theme 查找、切换和对象可用；应用配色独立 |
| Session tree、fork、clone、resume、import | 原 JSONL；聊天与分支 UI | 上下文来自所选分支；自定义 entries 保留 |
| Auto/manual compaction | 原机制 + AFM 预算配置 | 历史可查看；摘要与保留消息正确 |
| Models、providers、auth、custom models | 原 model runtime + 原生设置 | AFM 默认；其他 provider 显式选择 |
| Scoped models、thinking、virtual models / routing | 保留相应配置入口 | 不支持的后端能力明确显示，不能伪造 |
| 图片与非文本 content、附件 | 原生附件和 artifact 管理 | 原 content 可保留；能否推理取决于 provider |
| MCP stdio / HTTP / OAuth、资源与连接 | 显式加载上游 MCP extension | 生命周期、登录、发现与错误可见 |
| MCP direct / codemode / deferred / hidden exposure | 上游工具目录与发现逻辑 | tool-search、codemode 显式接入，不能漏装 |
| Codemode、输出 schema、结构化 tool results | 原上游扩展与工具管线 | 执行仍经过原工具 hooks；保持结果结构 |
| pi packages：npm / git / local | 原包格式和安装机制 + 管理界面 | 安装、更新、移除、启用与配置 scope |
| Settings / resource reload / diagnostics | 设置与资源页面；保留 slash 入口 | `/reload` 能更新资源，不仅重绘页面 |
| CLI slash commands | 原生命令 dispatcher + SDK 操作 | 不把宿主命令直接当模型提示发送 |
| `!command` / `!!command` shell 入口 | 输入 dispatcher | 保留纳入模型 / 不纳入模型的区别 |
| Export / copy / share / bug report | 原生操作入口 + 上游可用实现 | 本地导出和显式远程上传语义可区分 |
| Print / JSON / RPC 等自动化入口 | 保留打包 pi 入口或协议适配 | headless 可用；说明各模式原有 UI 边界 |
| Managed local models / `/llama` 等版本能力 | 复用可用上游服务与配置 | 不强迫启用；依赖或设备不满足时有原因 |

CLI 的开关通过启动配置或可用的 CLI 入口保留，不要求全部在主聊天窗口放置按钮。上述边缘能力按锁定的上游版本再核对，不能拿旧版 pi 的能力清单代替当前版本。

## 2. Skills 必须保留的行为

标准技能仍是带 frontmatter 的 `SKILL.md`，以及同目录下的 references、scripts、assets。Trigrams 不引入替代格式，也不要求每个 skill 改成 Swift 插件。[pi skills](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/skills.md)

- 启动时加载名称、描述和位置；模型需要使用时才读取完整 skill。
- 保留 agentDir、项目 `.pi/skills`、`.agents/skills`、用户 `.agents/skills` 等上游发现规则及配置路径。
- 显式 `/skill:name` 可带参数；相对资源路径基于 skill 所在目录解析。
- 保留 `disable-model-invocation`、skill command 设置、资源过滤和冲突诊断。
- `/reload` 后资源可更新；无效资源不能阻止全部有效 skills 使用。
- skill 内脚本可以使用 bash / Node / 系统命令或 owner 提供的外部 helper；不依赖 App 的私有工具服务。
- Skills 页显示来源、路径、可用性和加载诊断。它是资源视图，不是另一套内容仓库。

skill 提供工作方法和资源，执行由脚本、程序或配套 extension / MCP 完成。owner 负责依赖和实际执行权限。Trigrams 不新增自己的 skill 格式、工具桥或领域能力接口。

## 3. 内置命令的宿主适配

这些是当前上游命令组。实现时从锁定版本校验；扩展和资源新增的命令同时进入补全与命令列表。[pi commands](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/slash-commands.md)

| 命令组 | 命令 | 原生入口 |
| --- | --- | --- |
| 模型与配置 | `/settings`、`/model`、`/thinking`、`/scoped-models`、`/login`、`/logout`、`/llama` | 设置、模型选择和认证流程 |
| 会话与分支 | `/new`、`/resume`、`/name`、`/session`、`/tree`、`/fork`、`/clone`、`/compact`、`/import` | 聊天列表、分支视图、导入入口 |
| 导出与分享 | `/copy`、`/export`、`/share`、`/bug` | 导出菜单；上传前显示具体内容与目标 |
| 运行与项目 | `/trust`、`/reload`、`/hotkeys`、`/changelog`、`/quit` | 项目资源、快捷键与应用生命周期 |

Trigrams 可用 `⌘` 快捷键承载 macOS 常用动作。pi 的扩展键绑定继续在兼容环境中生效；冲突必须有可见规则。`/quit` 的宿主行为需要正确清理当前 runtime，而不是突然切断工具进程。

## 4. 扩展 UI 验证范围

验证样例至少覆盖：select/confirm/input/editor 的返回；编辑器读写和粘贴；字符串与组件 widget；custom overlay；header/footer；custom editor；autocomplete wrapper；raw terminal hook；tool/message renderer；theme 查找与切换；tools expansion；working 状态定制。

需要验证 `ctx.mode` 判断后的行为：扩展若只在 `tui` mode 创建组件，Trigrams 的兼容宿主必须真正提供该运行环境。不能为了通过类型检查返回假的 TUI 对象。

原生交互与兼容视图共用同一 session 和 command dispatcher。视图关闭要执行 dispose；后端重启不能留下等待中的 UI Promise。第三方组件输出的文本、ANSI 颜色和字符是扩展内容；应用自己的导航、操作图标统一使用 Phosphor。

## 5. 兼容验收与升级

首次发布前形成可运行的 capability fixtures，并记录上游版本、宿主适配版本和结果。优先采用上游 examples 验证真实机制；自己编写的镜像测试不能代替扩展运行验证。

必须验证：一个现有 skill 无修改加载并使用相对脚本；一个标准 package 安装与重载；一个扩展注册工具、命令和事件；一个扩展操作会话树；一个复杂 TUI 扩展完整交互；一个 MCP server 经发现后执行；AFM 完成工具调用与后续回答；中断和恢复不重复执行动作。

升级时按实际变动执行相关检查，保留版本快照与兼容差异。若某个公开机制暂时不支持，发布文档必须明确列出，不能称为“完整兼容”。本提案不预先批准缩减上述兼容目标。
