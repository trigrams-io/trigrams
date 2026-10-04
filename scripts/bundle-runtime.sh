#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

: "${TARGET_BUILD_DIR:?Xcode target build directory is required}"
: "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?Xcode resources directory is required}"
: "${EXECUTABLE_FOLDER_PATH:?Xcode executable directory is required}"

if [[ ! -f "$ROOT/agent/dist/main.js" || ! -d "$BUILD_DIR/runtime/node_modules" || ! -x "$NODE_ROOT/bin/node" ]]; then
  echo "Runtime dependencies are missing. Run scripts/bootstrap.sh before building in Xcode." >&2
  exit 1
fi

RUNTIME_DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/runtime"
NODE_DEST="$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/node"
mkdir -p "$RUNTIME_DEST" "$(dirname "$NODE_DEST")"
rsync -a --delete "$BUILD_DIR/runtime/" "$RUNTIME_DEST/"
rsync -a --delete "$ROOT/agent/dist/" "$RUNTIME_DEST/dist/"
rsync -a --delete "$ROOT/agent/resources/" "$RUNTIME_DEST/resources/"
NODE_STAGING="$(mktemp "$NODE_DEST.XXXXXX")"
trap 'rm -f "$NODE_STAGING"' EXIT
cp "$NODE_ROOT/bin/node" "$NODE_STAGING"
chmod 755 "$NODE_STAGING"
cp "$NODE_ROOT/LICENSE" "$RUNTIME_DEST/NODE-LICENSE"

# Sign nested executable code explicitly before Xcode signs the containing app.
# Ad-hoc signatures support local/CI builds. The archive signing step replaces
# them with the selected distribution identity and hardened-runtime options.
SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
[[ -n "$SIGN_IDENTITY" ]] || SIGN_IDENTITY=-
node "$ROOT/scripts/sign-runtime-code.mjs" "$RUNTIME_DEST" --force --sign "$SIGN_IDENTITY"
if [[ "${TARGET_NAME:-Trigrams}" == TrigramsStore ]]; then
  NODE_ENTITLEMENTS="$ROOT/apps/Trigrams/Configs/NodeStore.entitlements"
else
  NODE_ENTITLEMENTS="$ROOT/apps/Trigrams/Configs/NodeCommunity.entitlements"
fi
codesign --force --identifier node --options runtime --entitlements "$NODE_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$NODE_STAGING"
# Rebuilding a preview must not modify the executable pages of its live sidecar.
mv -f "$NODE_STAGING" "$NODE_DEST"
