# Trigrams pi sidecar

This is a thin host for `@earendil-works/pi-coding-agent` 1.0.2. Pi owns the
agent loop, executable tools, resource discovery, lifecycle events, compaction,
and authoritative JSONL session trees. Swift provides inference and native UI.
The AFM provider never executes a tool.

Requires Node >=22.19.0. Run `npm ci && npm run build` in this directory. The
application packages `dist/`, **all production `node_modules/` files**, and
`resources/` together; preserve upstream workers, WASM, dynamic extension loader,
native binaries, themes, and export assets. `dist/main.js` is the entry point:

```sh
node agent/dist/main.js --socket PATH --token TOKEN --agent-dir DIR --cwd DIR
```

The socket is private (0600 in an owner-only directory), has authenticated NDJSON
protocol v1, a 4 MiB frame limit, and bounded write buffering. Stdout/stderr belong
to diagnostics and extensions. A fresh socket path and at least 32-byte token are
required. `hello` may advertise `capabilities: ["terminal-v1"]`; this binds the
extension context in `tui` mode using a real pi `TuiAltScreen`. Other clients get
`rpc` mode with native dialogs. A disconnected native connection aborts inference
and disposes pending UI. Session JSONL paths are preserved across restart; empty
sessions remain in memory until the first user/assistant message, as upstream pi
does.

The current routes cover session list/create/open/prompt/abort/rename/tree/fork/
navigate/compact/export/tools, steer/follow-up aliases, resource list/reload,
settings get/update, and model catalog/selection/thinking. Model generation is
sent as `model.generate`; clients reply with `model.complete` or `model.fail`.
`model.delta` carries actual text deltas. Final text must match the accumulated
prefix; all tool calls validate against their original schemas before any call
is exposed to pi. Tool-call IDs are assigned here. AFM token usage is unavailable;
the provider records an explicit diagnostic rather than presenting zero counts
as measured usage.

The default prompt is the shipped `resources/system-prompt.md` preamble. Pi adds
project instructions, skill metadata, and cwd sections. A project `SYSTEM.md`
retains its upstream precedence. A nonempty user `systemPrompt` overrides the
preamble; an empty value resets it. Host settings are written atomically as 0600
`trigrams-host.json`. Prompt/skill changes require idle state. App theme changes
persist live and do not alter pi terminal themes. Disabled skills accept either
canonical `SKILL.md` paths or names. Pi's own settings/provider/auth files stay in
the selected agent directory, including MCP's config, credentials, and logs.

Codemode, tool search, and MCP are explicitly loaded and bound. Project trust uses
upstream `resolveProjectTrusted` and `ProjectTrustStore`, including global
extension trust hooks, before executing project resources. Native dialog
requests carry `id`, `type`/`method`, title and options; reply with `ui.reply` and
`value` or `cancelled`. Timeout/abort emits `ui.dismiss`. TUI frames are ANSI writes
with dimensions and monotonically increasing sequence numbers; clients send
`ui.tui.input`, `ui.tui.resize`, or `ui.tui.close`. Component/header/footer/widget/
custom editor factories run in the same session and have real disposal, focus,
overlay and raw-input semantics.

This is an initial implementation, **not a claim of complete pi compatibility**.
Tool/message/entry custom renderers are not yet projected into the compatibility
terminal; extension shortcut conflict resolution, arbitrary CLI flag controls,
full provider authentication UI, package installation/update/removal UI, and
several CLI host commands still require integration. Unsupported host commands
return explicit errors, and unknown slash commands cannot become model prompts.
The `store` profile supports handshake and listing only; creation/prompting returns
`profile.unsupported` before executable resources load, pending its sandbox audit.

`npm test` runs black-box process integration with a deterministic inference peer,
while the real SDK loads standard skills/extensions/MCP and executes file/shell
tools. Tests cover tool results and final answers, streaming, cancellation,
steering/follow-up, JSONL restart/fork, native dialogs, genuine TUI components and
input, reload, settings persistence, trust, schema failure before execution,
Store exclusion and transport authentication. They use SSD scratch files on the
local Mac and the configured runner directory in GitHub CI. No database or AFM
model is mocked inside the SDK.
