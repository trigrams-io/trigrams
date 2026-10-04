# Build and distribution

Trigrams requires macOS 26. Inference requires an Apple Intelligence-capable
Mac with Apple Intelligence enabled and the local model ready. A build is
architecture-specific: the app, Node, and native pi dependencies match the
build machine. GitHub Actions builds Apple Silicon artifacts on `macos-26`.

```sh
scripts/bootstrap.sh
scripts/build.sh community Debug
scripts/archive.sh community
```

The generated Xcode project has `Trigrams` (community) and `TrigramsStore`
(sandbox candidate) schemes. Community uses `io.trigrams.app`; the Store
candidate uses `io.trigrams.store` and the `APP_STORE` compile condition.

## Self-contained runtime

Every build embeds the verified Node executable at
`Trigrams.app/Contents/MacOS/node`. The app's resources contain
`runtime/dist/main.js`, pi's production `node_modules`, package metadata,
runtime prompt resources, and Node's license. A separate locked production
install omits development tools from the bundle while preserving pi's dynamic
workers, native libraries, extension loader, and asset paths. There is no
dependency on Homebrew Node or a global pi install when launching the app.

Build scripts sign nested Mach-O code before Xcode signs the containing app.
Development and CI archives use ad-hoc signatures. The archive script verifies
the full bundle and creates both the application ZIP and an `.xcarchive.zip`
with preserved executable permissions, plus a SHA-256 checksum for the app ZIP.
These are reproducible build inputs and verified artifacts; ZIP contents can
include build/signing timestamps, so byte-identical archives are not promised.

## GitHub distribution workflow

Tag pushes matching `v*` and manual dispatch run the same E2E coverage gate
before archiving. Artifacts are retained by GitHub Actions; this workflow does
not create a public GitHub release or submit to the App Store.

Manual dispatch can request Developer ID signing and notarization for the
community profile. Configure the GitHub `developer-id` environment and its
secrets first:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | Password for that certificate export |
| `DEVELOPER_ID_APPLICATION_IDENTITY` | Exact Developer ID Application signing identity |
| `APPLE_TEAM_ID` | Apple Developer team ID |
| `APPLE_ID` | Apple account used for notarization |
| `APPLE_APP_PASSWORD` | App-specific password for that account |

Signing uses a disposable keychain, signs the bundled Node executable with its
JIT entitlement, signs native dependency libraries, then signs the app with
the hardened runtime. It waits for notarization acceptance, staples and
validates the ticket, and runs Gatekeeper assessment before uploading the
notarized ZIP. Missing credentials and rejected submissions fail explicitly.
Secrets are never printed by the scripts. Configure environment reviewers if
the repository needs an approval gate for credential-bearing release jobs.

## Store candidate

`scripts/archive.sh store` prepares an ad-hoc signed sandbox archive for
validation. The app has user-selected file access and app-scoped bookmarks;
its bundled Node process inherits the sandbox. That archive is **not a
release-ready App Store submission**. Subprocess inheritance, security-scoped
workspace access, native dependency loading, pi tools and extensions, and
Apple's review requirements must be validated on a real signed Store build.
Store distribution certificates, provisioning, installer export, App Store
Connect metadata, and submission are not configured by this workflow. The
Developer ID notarization job explicitly rejects the Store profile.

Sources: [XcodeGen release](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0),
[Node release checksums](https://nodejs.org/download/release/v22.19.0/SHASUMS256.txt),
[GitHub macOS runners](https://github.com/actions/runner-images).
