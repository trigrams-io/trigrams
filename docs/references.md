# 参考资料与版本快照

查询日期：2026-10-04。架构提案与设计选择是 Trigrams 自己的方案；以下资料用于核对上游事实，不代表上游已经替 Trigrams 完成适配。

## pi

原 `badlogic/pi-mono` 地址目前跳转到 [earendil-works/pi](https://github.com/earendil-works/pi)。本轮读取的 `main` 快照是 `200387122ca450d6387f033949423114a270b96c`；其中 coding-agent manifest 版本为 `1.0.2`，Node engine 为 `>=22.19.0`。它只是设计基线，实际实现应锁定可用发布版本。

- [SDK](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/sdk.md)：宿主接口、事件、MCP/codemode 的显式加载。
- [Skills](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/skills.md)：发现、显式调用、按需读取。
- [Extensions](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/extensions.md)：事件、工具、命令与 UI。
- [Extension types](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/src/core/extensions/types.ts)：完整 UI 接口与 mode。
- [RPC extension UI](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/rpc-extension-ui.md)：原 RPC 的 UI 范围。
- [Session format](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/session-format.md)、[sessions](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/sessions.md)：JSONL、会话树与分支。
- [Commands](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/slash-commands.md)、[templates](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/prompt-templates.md)、[packages](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/packages.md)。
- [MCP](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/mcp.md)、[codemode](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/codemode.md)、[security](https://github.com/earendil-works/pi/blob/200387122ca450d6387f033949423114a270b96c/packages/coding-agent/docs/security.md)。

## Apple Foundation Models

- [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession)：文本、schema、流式接口和 session 状态。
- [Generating content and performing tasks](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models)：可选工具、availability 与上下文预算。
- [Guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)：类型与动态结构化输出。
- [Multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)：更新系统版本的能力需单独验证，不当作 macOS 26 基线承诺。

Apple 在线文档随 SDK 更新。实现需核对具体部署版本的 API availability、设备能力和语言支持。

## 可插拔 macOS 能力的宿主边界

- [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)：签名应用请求 Apple Events 权限的配置。
- [NSAppleEventsUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)：使用 Apple Events 的应用所需说明。

具体工具实现可由能力包交付；签名应用元数据仍需按真实运行路径验证。此边界不等于需要内置一套 macOS 工具服务。

## 界面与品牌

- [Phosphor Icons](https://phosphoricons.com)：所有应用操作图标的来源。
- [Phosphor core](https://github.com/phosphor-icons/core/tree/2b75f3ad12b420c9504ef05df8d2564a28f8500e)：图标名称、资源和 MIT license 的快照。
- [Phosphor Swift](https://github.com/phosphor-icons/swift)：官方 SwiftUI 接入方式；实现时锁定版本或仅内置所选资源。
- [Nano Emacs](https://github.com/rougier/nano-emacs/tree/12fbfebec39f72a133c8751cadf3d311b93f5e7f)：设计参考。
- [Nano light palette](https://github.com/rougier/nano-emacs/blob/12fbfebec39f72a133c8751cadf3d311b93f5e7f/nano-theme-light.el)、[dark palette](https://github.com/rougier/nano-emacs/blob/12fbfebec39f72a133c8751cadf3d311b93f5e7f/nano-theme-dark.el)：配色值来源。Trigrams 自行实现视觉 tokens 和控件，不复制 Emacs 主题代码。
- [Inter v4.1](https://github.com/rsms/inter/tree/v4.1)：品牌字标与预览的字体来源。字体、OFL license 与来源记录位于品牌目录；交付 SVG 已转为轮廓。
