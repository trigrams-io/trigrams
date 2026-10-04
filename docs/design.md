# Trigrams 界面设计提案

状态：待评审。首版产品界面只有英文；本文的中文用于设计评审。

## 1. 视觉方向

采用类似 Codex 的两列结构：左侧聊天列表，右侧消息和固定输入框。视觉参考 Nano Emacs 的克制配色、清楚的文字层级和少量强调色。界面不使用玻璃材质、渐变装饰和大面积彩色聊天气泡。

应用内所有可见控件由 Trigrams 自定义绘制和组合，包括标题区、按钮、选择器、菜单、列表行、滚动区域装饰、输入框、开关、对话框和状态提示。可以使用 SwiftUI / AppKit 的布局、文本输入和 accessibility 能力，但不直接采用默认系统外观。

所有应用操作图标来自 [Phosphor Icons](https://phosphoricons.com)，不使用 SF Symbols、系统应用图标或 emoji 充当 UI 图标。唯一独立品牌图形是按数学规则生成的 Trigrams 标志。工具截图和用户附件属于内容，不属于操作图标。

macOS 自身的权限弹窗、授权界面和系统外部界面由操作系统控制。Trigrams 不能重绘这些窗口。可选能力包提供的说明由通用工具记录或扩展 UI 展示，不建设首版 App 的领域权限中心。

## 2. 主窗口与信息结构

初始窗口建议 1120 × 760 pt，最小 800 × 560 pt。侧栏初始宽度 256 pt，可调整为 220–320 pt，也可折叠。消息阅读宽度约 760 pt；工具结果可以在右侧详情面板中扩展。窗口空间不足时详情显示为覆盖面板，不挤压聊天内容。

```text
┌──────────────────────┬───────────────────────────────────────────────────┐
│ Trigrams     New chat │ Chat title              Branch      More          │
│ Search chats         │ Working directory · Model                         │
├──────────────────────┼───────────────────────────────────────────────────┤
│ CHATS                │                                                   │
│ Today                │ User message                                      │
│   Prepare workspace  │                                                   │
│   Organize documents │ Assistant response                                │
│ Yesterday            │                                                   │
│   Review notes       │ ▸ Tool call  · Completed                          │
│                      │                                                   │
│                      │                                                   │
├──────────────────────┤                                                   │
│ Skills               ├───────────────────────────────────────────────────┤
│ Extensions           │ Attachment chips / queue                          │
│ Settings             │ Ask Trigrams…                                     │
│                      │ Attach   Skills   Model       Stop / Send         │
└──────────────────────┴───────────────────────────────────────────────────┘
```

顶层页面为 Chats、Skills、Extensions、Settings。Packages、MCP、Templates、资源诊断等在 Extensions / Settings 中有明确入口，避免首页堆满技术配置。通用资源搜索和 slash 补全可以到达全部能力。

聊天行显示名称、最近时间和运行状态。有活动的聊天保持可见，切换聊天不会停止其他任务。执行包若报告排队或等待状态，按 pi 事件显示；App 不自行提供跨包桌面排队机制。归档只改变列表可见性；删除必须明确涉及的本地数据。

## 3. 消息与工具呈现

用户消息使用浅底或窄左边线区分；assistant 消息直接在阅读区域呈现 Markdown。正文可以选择和复制，代码使用独立等宽样式。保留链接、列表、表格和附件的正常阅读能力。

工具调用以紧凑记录显示名称、目标、耗时和状态，默认折叠。展开后显示参数、进度、输出和错误；长结果进入详情面板。状态同时有文字和图标，不仅依靠颜色。截图显示来源应用和观察时间；可打开 artifact，不能让预览代替原始输出。

会话树通过 `Branch` 入口显示，可导航历史、fork 或查看 compaction。压缩前内容仍然可查看。自定义扩展消息保留类型、来源和原始内容；存在 renderer 时能够打开其兼容视图。

## 4. 输入框与运行交互

- 输入框从一行增长到约 200 pt，超出后内部滚动；保留 IME、选区、粘贴和撤销能力。
- Enter 发送；Shift+Enter 换行；⌘+Enter 也发送。运行中提交时明确选择 `Steer now` 或 `Queue after completion`。
- `/` 打开包含内置命令、扩展命令、templates 和 skills 的补全列表。列表显示来源，不另做一套 skill 语法。
- 支持文件拖入和 `Attach`。附件 chip 可移除，显示模型是否能直接读取；纯文本内容与文件引用可以分别处理。
- `Stop` 取消当前生成与可取消工具。不能把“已发送取消”显示成“外部应用动作已撤销”。
- 队列在输入框上方显示，可编辑、重新排序或移除；steering 与 follow-up 使用不同的明确标签。
- 工具或扩展要求交互时，在输入区域附近显示自定义卡片。复杂 pi-tui UI 在可聚焦的兼容面板中打开。

默认模型标签为 `Apple On-Device`，实际 provider、能力和 availability 在详情中可见。模型切换采用自定义选择器；不支持的 thinking 等选项显示具体原因。

## 5. 深浅主题与颜色 tokens

主题名为 `Nano Light`、`Nano Dark`。用户可选 `System` 自动跟随 macOS 外观。下表直接引用 Nano 的角色配色，Trigrams 的语义 tokens 在此基础上建立。[Nano light](https://github.com/rougier/nano-emacs/blob/12fbfebec39f72a133c8751cadf3d311b93f5e7f/nano-theme-light.el)，[Nano dark](https://github.com/rougier/nano-emacs/blob/12fbfebec39f72a133c8751cadf3d311b93f5e7f/nano-theme-dark.el)

| Nano 角色 | Light | Dark | 在 Trigrams 中的基础用途 |
| --- | --- | --- | --- |
| background | `#FFFFFF` | `#2E3440` | 主背景 |
| foreground | `#37474F` | `#ECEFF4` | 正文 |
| highlight | `#FAFAFA` | `#3B4252` | 侧栏、工具卡片、hover |
| subtle | `#ECEFF1` | `#434C5E` | 选中项和区域分隔 |
| salient | `#673AB7` | `#81A1C1` | 操作强调色 |
| strong | `#000000` | `#ECEFF4` | 强调标题 |
| critical | `#FF6F00` | `#EBCB8B` | 警示色来源 |
| popout | `#FFAB91` | `#D08770` | 少量辅助强调 |
| faded | `#B0BEC5` | `#677691` | 非文本装饰、弱分隔 |

Nano 的 faded 在基础背景上的对比度约为 1.91:1 / 2.72:1，不适合正文。因此不把它直接当作辅助文字颜色。拟议可读语义 tokens：

| Token | Light | Dark | 规则 |
| --- | --- | --- | --- |
| text.primary | `#37474F` | `#ECEFF4` | 消息与普通标签 |
| text.secondary | `#586C76` | `#B9C3D3` | 时间、来源和说明；覆盖三种基础表面 |
| text.accent | `#673AB7` | `#AFC3DC` | 链接和强调文字；区别于装饰 accent |
| text.warning | `#9A4600` | `#EBCB8B` | 在主背景上的警告说明 |
| text.error | `#B23A32` | `#E28A8F` | 在主背景上的错误说明 |
| text.success | `#28704B` | `#A3BE8C` | 在主背景上的完成说明 |
| action.fill | `#673AB7` | `#81A1C1` | 主要操作背景 |
| action.foreground | `#FFFFFF` | `#2E3440` | 主要操作文字 / 图标 |

状态文字如出现在其他表面，需使用验证过的色对或独立状态底色。正常文本目标对比度至少 4.5:1，可交互图标和边界至少 3:1。faded 只用于非必要装饰，不能承担唯一的输入边界或状态信息。聚焦边框采用 accent；正文选区在两种主题下单独验证。

消息代码块使用同一主题背景体系，语法着色只添加必要层级。终端扩展可以使用其 pi theme；宿主窗口不会因此切换成第三方配色。

## 6. 字体、尺度与组件

建议内置 Inter 作为 UI 字体，JetBrains Mono 用于代码与终端；具体版本与字体许可在实现阶段锁定。标志本身不依赖字体。全英文 UI 使用 sentence case，保留未来其他文字的 fallback 和排版空间。

| 用途 | 初始值 |
| --- | --- |
| 消息正文 | 15 pt，行高约 1.55 |
| 导航、按钮和输入 | 13–14 pt |
| 标题 | 16 pt，中等字重 |
| 时间与元信息 | 12 pt，不低对比 |
| 代码与终端 | 13 pt，行高约 1.5 |
| 间距 | 4 / 8 / 12 / 16 / 24 / 32 pt |
| 按钮 / 输入 / 卡片圆角 | 6 / 10 / 8 pt |
| 普通操作命中区域 | 至少 28 × 28 pt，常用操作 32 × 32 pt |

基础组件包括 `TrigramsButton`、`IconButton`、`ChatRow`、`Composer`、`SelectPopover`、`CommandList`、`ToolRecord`、`StatusBadge`、`ResourceRow`、`DialogCard` 和 `CompatibilityPanel`。这些是拟议设计名称，尚未创建实现。

组件必须拥有 hover、pressed、selected、disabled、focus、loading 和 error 中适用的状态。不能用默认系统样式填补遗漏。动效以短时 opacity / position 变化为主，遵循 Reduce Motion；不持续展示无信息的闪烁动画。

自定义标题区保留窗口拖动、双击行为与可访问性。关闭、最小化、缩放使用自定义控件，操作调用真实窗口 API；不用系统交通灯外观代替设计。

## 7. Phosphor 图标选择

统一使用 `regular`，常规尺寸 18 pt；小型元信息 16 pt，主要操作 20 pt。选中态优先使用颜色与背景，不随意切换字重。以下名称已在本轮 Phosphor core 快照中核对：[资源目录](https://github.com/phosphor-icons/core/tree/2b75f3ad12b420c9504ef05df8d2564a28f8500e/assets/regular)。

| 用途 | Phosphor 名称 |
| --- | --- |
| Chats | `chats` |
| New chat | `plus` |
| Search | `magnifying-glass` |
| Sidebar | `sidebar-simple` |
| Send | `arrow-up` |
| Stop | `stop` |
| Attach | `paperclip` |
| Working directory | `folder-open` |
| Skills | `book-open` |
| Extensions | `puzzle-piece` |
| Tool / terminal view | `terminal-window` |
| Branch | `git-branch` |
| Reload | `arrows-clockwise` |
| Settings | `gear-six` |
| Appearance | `sun` / `moon` |
| More | `dots-three` |
| Completed | `check-circle` |
| Warning / error | `warning-circle`，另配状态文字 |
| Close / remove | `x` |
| Minimize | `minus` |
| Zoom / expand | `arrows-out` |

可使用官方 [Phosphor Swift](https://github.com/phosphor-icons/swift)，或只内置选定的 SVG/PDF 资源。所有图标离线可用；不在运行时从 CDN 下载。保留 MIT notices。新增图标必须加入集中目录，禁止在组件里混入 `Image(systemName:)` 或系统文件类型图标。

## 8. 产品状态与英文文案

| 状态 | 主要呈现与文案 |
| --- | --- |
| 新聊天 | `What would you like to do?`；输入提示 `Ask Trigrams…` |
| 生成中 | `Working`；工具进度；`Stop` |
| 扩展报告等待 | 显示扩展提供的状态与原因；宿主不推断桌面队列 |
| 等待用户交互 | `Your input is needed`；具体问题和操作 |
| 模型不可用 | `Apple On-Device is unavailable`；具体 availability 原因 |
| 扩展报告缺少权限 | `Permission required`；展示执行方给出的说明或交互 |
| 工具操作失败 | `Action failed`；展示工具结果中的原因和恢复方法 |
| 用户取消 | `Stopped`；保留已经产生的工具结果 |
| backend 中断 | `Interrupted`；可继续，但不自动重放副作用 |
| 资源加载失败 | `Couldn’t load this resource`；来源、路径和诊断 |
| 成功结束 | `Completed`；以 pi settled 事件为准 |

失败不能只弹出一条短暂 toast。相关聊天或资源中保留可查看的记录。

## 9. 键盘、可访问性与未来语言

默认快捷键建议：⌘N 新聊天，⌘K 搜索 / 命令，⌘B 切换侧栏，⌘, 设置，⌘. 停止，Esc 关闭当前弹层。Stop 与输入法 / 终端的 Escape 语义分开处理。完整 bindings 可查看和调整，与 pi 扩展绑定冲突时明确提示。

所有自定义控件保留 VoiceOver role、label、value、焦点次序和键盘操作。消息、代码与工具输出支持选择；不能为获得自定义外观而用不可编辑的绘制层替代真实文本引擎。深浅模式、对比度、放大文字和 Reduce Motion 都有独立检查。

首版界面文案集中在 string catalog，只创建英文 locale。业务逻辑不用翻译后的字符串作状态判断。布局不依赖英文字符宽度；日期、数字与路径保持正确格式。用户消息和模型输出可以是其他语言，界面语言与模型语言能力分开处理。
