# Native protocol v1

The Swift application launches its bundled Node executable and `runtime/dist/main.js`. The sidecar owns the complete pi SDK session. Communication uses newline-delimited UTF-8 JSON over a private Unix domain socket. stdout and stderr are local diagnostics, never protocol streams.

The parent runtime directory is mode `0700`; the socket is `0600`. The first request must authenticate with `{version: 1, token}`. The launch token is ephemeral and is never persisted or included in logs. One authenticated client is allowed. Both endpoints enforce a 4 MiB frame limit; the sidecar bounds its pending output. Request IDs identify replies, generation IDs identify inference tasks, and pi session IDs identify session events.

```json
{"id":"request-id","method":"session.prompt","params":{"text":"Read this file"}}
{"id":"request-id","result":{"accepted":true}}
{"id":"request-id","error":{"code":"session.busy","message":"Choose steer or followUp while the agent is working."}}
{"event":"session.event","params":{"sessionID":"pi-session-id","sequence":1,"event":{"type":"agent_start"}}}
```

Only one of `result` / `error` occurs in a reply. Unknown methods produce an explicit error. Accepted prompts finish asynchronously through pi events; a request acknowledgment is not a completed task. `message_end` carries a completed message and `agent_settled` establishes the end of automatic work. Final snapshots rebuild the native projection from pi's authoritative messages.

## Methods

| Group | Methods | Contract |
| --- | --- | --- |
| Initialization | `hello` | version/token and optional `capabilities: ["terminal-v1"]`; reply includes pi version, profile, supported mechanisms |
| Sessions | `session.list`, `.create`, `.open` | list summaries `{id,path,title,cwd,updatedAt}`; create/open return `{session,messages}` |
| Running | `session.prompt`, `.abort` | prompt accepts `text`, optional `mode: "steer" \| "followUp"`; abort retains completed actions |
| History | `session.rename`, `.tree`, `.fork`, `.navigate`, `.compact`, `.export` | use pi's session tree, entries, branch context and export |
| Resources | `resources.list`, `.reload` | skills/provenance/enabled state, context file paths and diagnostics from the SDK |
| Settings | `settings.get`, `.update` | editable preamble, shipped default, theme, skill directories and disabled skill names |
| Models | `models.list`, `.select`, `.thinking` | pi model catalog; unsupported AFM features return errors |
| Native inference | `model.delta`, `.complete`, `.fail` | reply to a model generation notification by its generation ID |
| Extension UI | `ui.reply`, `ui.editor.set` | resolve structured interaction / update the extension composer |
| Terminal UI | `ui.tui.input`, `.resize`, `.close` | raw terminal input, columns/rows and component disposal |

Extensions and domain tools do not depend on this private protocol. They use normal pi and skill interfaces.

## Inference boundary

`model.generate` supplies `{id,instructions,prompt,tools,maxTokens}`. `prompt` is a JSON rendering of pi's non-system messages, preserving roles and tool results; `instructions` is the current assembled pi system prompt. Tools retain original parameter schemas. Swift builds a fresh `LanguageModelSession` with **no executable tools** and a dynamic action schema.

`model.delta` carries `{id,text}` containing new text only. `model.complete` carries `{id,response:{text,toolCalls:[{name,arguments}]}}`; its complete text must begin with the previously streamed text. Tool arguments are only executed after pi's provider validates the entire batch against the original declared tool schemas. Unknown tools, malformed responses, unsupported schema constraints and stale generations fail explicitly.

`model.cancel` cancels the Swift task. A canceled task never submits its final action. Model errors preserve their reason; there is no automatic cloud fallback. AFM token usage is currently unavailable, and the native UI must not present SDK-required zero usage fields as measured usage.

## UI boundary and lifecycle

Structured UI requests have IDs and resolve through `ui.reply`; dismiss/timeout/disconnect must resolve or cancel the waiting interaction. Terminal output is ordered ANSI data delivered through `ui.tui.frame`; input and resizing return to the same pi session's `TuiAltScreen`. No second CLI agent or local shell is launched for this view.

Only hosts with a real terminal view advertise `terminal-v1`. Without it, the extension context uses RPC mode and reports the appropriate UI capability. Terminal support remains experimental until the compatibility fixtures in [pi compatibility](../docs/pi-compatibility.md) pass.

On exit the host cancels inference and terminates the sidecar; the sidecar handles termination by aborting pi and disposing extensions and connections. Recovery reads existing pi JSONL files and never automatically replays interrupted tools.
