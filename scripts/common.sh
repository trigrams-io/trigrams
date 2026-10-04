#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD_DIR="$ROOT/build"

# Local development scratch files and dependencies stay on the external SSD.
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  TRIGRAMS_TMP="$RUNNER_TEMP/trigrams"
else
  if [[ ! -d /Volumes/SSD || "$ROOT" != /Volumes/SSD/* ]]; then
    echo "Trigrams development requires a mounted /Volumes/SSD checkout." >&2
    exit 1
  fi
  TRIGRAMS_TMP=/Volumes/SSD/Developer/Codex/tmp
fi
mkdir -p "$TRIGRAMS_TMP" "$BUILD_DIR/tools"
export TMPDIR="$TRIGRAMS_TMP" TMP="$TRIGRAMS_TMP" TEMP="$TRIGRAMS_TMP"
export npm_config_cache="$BUILD_DIR/npm-cache"

NODE_VERSION=22.19.0
XCODEGEN_VERSION=2.46.0
XCODEGEN="$BUILD_DIR/tools/xcodegen/xcodegen/bin/xcodegen"

case "$(uname -m)" in
  arm64) NODE_ARCH=arm64 ;;
  x86_64) NODE_ARCH=x64 ;;
  *) echo "Unsupported macOS architecture: $(uname -m)" >&2; exit 1 ;;
esac
NODE_ROOT="$BUILD_DIR/tools/node-v$NODE_VERSION-darwin-$NODE_ARCH"
export PATH="$NODE_ROOT/bin:$PATH"

# A stable developer signature lets macOS reuse local Files and Folders grants
# across rebuilds. CI has no developer key and deliberately remains ad-hoc.
TRIGRAMS_SIGN_IDENTITY="${TRIGRAMS_CODE_SIGN_IDENTITY:--}"
if [[ "${GITHUB_ACTIONS:-}" != "true" && -z "${TRIGRAMS_CODE_SIGN_IDENTITY:-}" ]]; then
  TRIGRAMS_SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2; exit }')"
  [[ -n "$TRIGRAMS_SIGN_IDENTITY" ]] || TRIGRAMS_SIGN_IDENTITY=-
fi
