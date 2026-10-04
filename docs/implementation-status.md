# First implementation

This is the first functional slice of the approved architecture, not a claim that the entire [pi compatibility contract](pi-compatibility.md) is already satisfied. The contract remains the release target.

| Area | Implemented boundary | Remaining validation / work |
| --- | --- | --- |
| Agent runtime | Complete pinned pi SDK 1.0.2, authoritative JSONL session trees, upstream tools and resource loading | Compatibility fixtures for the complete command and extension surface |
| Native app | Custom SwiftUI/AppKit chats, composer, tool records, history branching, settings | Broader attachment, Markdown and keyboard interactions |
| Inference | Native AFM structured action generation and text streaming; pi executes tools after schema validation | Real-device task quality, long-context behavior, more JSON Schema constraints |
| Resources | Standard skills and AGENTS discovery, directories, diagnostics, enable/disable and reload | Native pi package installation/update/removal and complete prompt/extension resource management |
| Extension UI | Structured dialogs, status/widgets and same-session pi-tui terminal input/resize/disposal | Full custom tool/message renderer integration, arbitrary extension shortcuts, flags and native conflict handling |
| Models | AFM default and SDK model selection boundary | Native optional-provider authentication and catalog controls |
| Verification | Real sidecar process E2E, XCTest native app E2E, measured Swift/V8 coverage gate and Codecov workflow | Apple Intelligence and signed distribution checks on supported real hardware |
| Distribution | Self-contained Node/pi bundle; Community build/archive and Developer ID notarization workflow | Apple signing secrets; Store resource policy, sandbox/file grant validation and submission |

Unsupported commands and schemas fail explicitly. Terminal compatibility is experimental; extensions do not receive a fake terminal object. The Store profile deliberately blocks executable runtime initialization until its policy and sandbox are audited. A Store archive is a validation candidate, not a usable App Store release.

The DEBUG-only E2E inference fixture is enabled by an explicit launch argument. It replaces only model inference: tests still use real IPC, pi tools, extensions, resources, settings and session persistence. Release builds ignore the fixture arguments. Actual AFM generation remains visible as uncovered code in CI coverage.

Follow-up work should add one upstream-compatible mechanism and its real E2E fixture at a time. Domain features remain optional owner-maintained skills/extensions/MCP, and no built-in macOS tool service is added to complete this checklist.
