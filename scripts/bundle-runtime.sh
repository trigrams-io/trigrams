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
cp "$NODE_ROOT/bin/node" "$NODE_DEST"
chmod 755 "$NODE_DEST"
cp "$NODE_ROOT/LICENSE" "$RUNTIME_DEST/NODE-LICENSE"

# Sign nested executable code explicitly before Xcode signs the containing app.
# Ad-hoc signatures support local/CI builds. The archive signing step replaces
# them with the selected distribution identity and hardened-runtime options.
SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
[[ -n "$SIGN_IDENTITY" ]] || SIGN_IDENTITY=-
while IFS= read -r -d '' NESTED_FILE; do
  if file -b "$NESTED_FILE" | /usr/bin/grep -q 'Mach-O'; then
    codesign --force --sign "$SIGN_IDENTITY" "$NESTED_FILE"
  fi
done < <(find "$RUNTIME_DEST" -type f -print0)
if [[ "${TARGET_NAME:-Trigrams}" == TrigramsStore ]]; then
  NODE_ENTITLEMENTS="$ROOT/apps/Trigrams/Configs/NodeStore.entitlements"
else
  NODE_ENTITLEMENTS="$ROOT/apps/Trigrams/Configs/NodeCommunity.entitlements"
fi
codesign --force --options runtime --entitlements "$NODE_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$NODE_DEST"
