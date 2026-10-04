#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

if [[ ! -x "$NODE_ROOT/bin/node" ]]; then
  case "$NODE_ARCH" in
    arm64) NODE_SHA=c59006db713c770d6ec63ae16cb3edc11f49ee093b5c415d667bb4f436c6526d ;;
    x64) NODE_SHA=3cfed4795cd97277559763c5f56e711852d2cc2420bda1cea30c8aa9ac77ce0c ;;
  esac
  NODE_ARCHIVE="$BUILD_DIR/tools/node-v$NODE_VERSION-darwin-$NODE_ARCH.tar.gz"
  curl --fail --silent --show-error --location --retry 3 \
    "https://nodejs.org/download/release/v$NODE_VERSION/node-v$NODE_VERSION-darwin-$NODE_ARCH.tar.gz" -o "$NODE_ARCHIVE"
  echo "$NODE_SHA  $NODE_ARCHIVE" | shasum -a 256 --check
  tar -xzf "$NODE_ARCHIVE" -C "$BUILD_DIR/tools"
fi

if [[ ! -x "$XCODEGEN" ]]; then
  XCODEGEN_ARCHIVE="$BUILD_DIR/tools/xcodegen.zip"
  curl --fail --silent --show-error --location --retry 3 \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip" -o "$XCODEGEN_ARCHIVE"
  echo "4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806  $XCODEGEN_ARCHIVE" | shasum -a 256 --check
  mkdir -p "$BUILD_DIR/tools/xcodegen"
  unzip -q -o "$XCODEGEN_ARCHIVE" -d "$BUILD_DIR/tools/xcodegen"
fi

cd "$ROOT/agent"
npm ci
npm run build

# A separate production install keeps build/test tools out of the app without
# pruning the developer's installation or losing pi's dynamic assets.
mkdir -p "$BUILD_DIR/runtime"
cp package.json package-lock.json "$BUILD_DIR/runtime/"
npm ci --omit=dev --prefix "$BUILD_DIR/runtime"

"$XCODEGEN" generate --spec "$ROOT/apps/Trigrams/project.yml"
