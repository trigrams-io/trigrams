# End-to-end testing

Trigrams uses process tests and native UI tests as its main verification tools.
There is no mocked replacement for pi, session persistence, settings, resource
loading, or the Swift-to-Node transport in the UI suite.

## Run locally

Use a worktree on `/Volumes/SSD/Developer` with Xcode 26 or newer and macOS 26.
The scripts refuse to place local build dependencies on the internal drive.
They set `TMPDIR`, `TMP`, and `TEMP` to `/Volumes/SSD/Developer/Codex/tmp`.

```sh
scripts/bootstrap.sh
scripts/test.sh
```

Bootstrap downloads Node 22.19.0 and XcodeGen 2.46.0, verifies their pinned
SHA-256 checksums, installs the locked runtime dependencies, and generates the
Xcode project. Build output, npm's package cache, Swift package checkouts and
cache, production dependencies, and test fixtures stay in the worktree's
ignored `build/` directory. Open
`apps/Trigrams/Trigrams.xcodeproj` after bootstrap to run the same UI target
from Xcode. XCTest UI automation needs a logged-in graphical macOS session.
The XCTest runner has its own test-only entitlement disabling its default
sandbox so it can create, change, and inspect those SSD fixtures. This does not
change either app target's entitlements or the Store sandbox boundary.

The compatibility terminal pins SwiftTerm 1.11.0, using its AppKit/Core Graphics
renderer. This version supplies the required VT terminal behavior without an
additional Metal toolchain or a package build plugin. Its exact revision and
transitive dependencies are recorded in `Package.resolved`.

The runtime tests launch a real Node subprocess and speak the JSON-RPC protocol.
They exercise pi behavior with repeatable inference supplied at the protocol
boundary. The native suite launches the app and its bundled sidecar. Only the
on-device model response changes when the Debug app receives `--ui-testing`.
Hosted runners cannot be assumed to have Apple Intelligence enabled and its
model downloaded. Release builds ignore this launch argument.

The UI scenarios cover creating and reopening chats after relaunch, persisted
assistant responses, stopping generation, follow-up queues, steering,
Nano Light/Nano Dark/System settings, persistent system prompt edits and reset,
standard `SKILL.md` discovery, persistent enable/disable, resource reload, and
an unavailable model's reason and disabled Send button. Further scenarios
exercise a workspace read tool and its raw result, branch forks, native
extension dialogs with persisted answers, extension status/widgets, real TUI
keyboard input, and Markdown code/table rendering with code copying.

## Coverage

Coverage comes from execution, not estimated source length:

- Node's `NODE_V8_COVERAGE` captures the process tests; c8 remaps the transpiled
  JavaScript to TypeScript through compiler source maps and emits LCOV.
- Xcode instruments the production app during XCTest UI runs. The Swift
  converter reads `xccov`'s JSON report and per-line archive counts, verifies
  that their executable/covered line counts agree, and emits LCOV.
- `scripts/coverage-gate.mjs` combines the reports, rejects missing production
  source files, and requires **more than 80% line coverage** independently for
  the native app, the pi runtime, and the combined app.

Every production folder under `apps/Trigrams/Sources/` and `agent/src/` belongs
in the coverage gate. Tests and third-party dependencies are not production
code authored by this project. No app module is excluded to raise a percentage.
The deterministic inference fixture does not execute Apple's generation path;
those lines remain uncovered. Real-device model validation remains a separate
test on an Apple Intelligence-capable Mac.

Reports are saved to `build/coverage/production.lcov`, `summary.json`, and
`xccov.json`; XCTest results are in `build/UITests.xcresult`. The GitHub CI job
retains these artifacts on failure for diagnosis. A failed coverage gate must
be repaired by exercising uncovered behavior or deleting unused code.

## GitHub Actions and Codecov

The CI workflow runs on the official `macos-26` Apple Silicon runner and uses
commit-pinned actions. It typechecks the sidecar, runs both E2E suites and the
coverage gate, then builds a self-contained community archive. The native and
runtime thresholds are also configured in `codecov.yml` so the service can
show the same component breakdown on pull requests.

Connect `trigrams-io/trigrams` in Codecov before expecting a green upload.
Uploads use GitHub OIDC (`id-token: write`), with no repository upload token.
`fail_ci_if_error: true` deliberately makes authentication, onboarding, or
service upload failures visible instead of treating missing reports as success.
The local coverage gate remains the authoritative check even if the service
changes its presentation.

Sources: [GitHub runner images](https://github.com/actions/runner-images),
[Codecov OIDC configuration](https://github.com/codecov/codecov-action#using-oidc).
