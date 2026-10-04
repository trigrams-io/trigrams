#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

for REQUIRED_NAME in APPLE_CERTIFICATE_BASE64 APPLE_CERTIFICATE_PASSWORD DEVELOPER_ID_APPLICATION_IDENTITY APPLE_TEAM_ID APPLE_ID APPLE_APP_PASSWORD; do
  if [[ -z "${!REQUIRED_NAME:-}" ]]; then
    echo "Signing requires the GitHub developer-id environment secret $REQUIRED_NAME." >&2
    exit 1
  fi
done
mkdir -p "$BUILD_DIR/notarization"
ditto -x -k "$BUILD_DIR/Trigrams-community.zip" "$BUILD_DIR/notarization"
APP="$BUILD_DIR/notarization/Trigrams.app"
test -d "$APP"
SIGNING_DIR="$(mktemp -d "$TRIGRAMS_TMP/trigrams-signing.XXXXXX")"
KEYCHAIN="$SIGNING_DIR/signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$SIGNING_DIR"
}
trap cleanup EXIT
printf '%s' "$APPLE_CERTIFICATE_BASE64" | base64 --decode > "$SIGNING_DIR/certificate.p12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$SIGNING_DIR/certificate.p12" -k "$KEYCHAIN" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
while IFS= read -r -d '' NESTED_FILE; do
  if file -b "$NESTED_FILE" | /usr/bin/grep -q 'Mach-O'; then
    codesign --force --timestamp --options runtime --keychain "$KEYCHAIN" --sign "$DEVELOPER_ID_APPLICATION_IDENTITY" "$NESTED_FILE"
  fi
done < <(find "$APP/Contents/Resources/runtime" -type f -print0)
codesign --force --timestamp --options runtime --keychain "$KEYCHAIN" \
  --entitlements "$ROOT/apps/Trigrams/Configs/NodeCommunity.entitlements" \
  --sign "$DEVELOPER_ID_APPLICATION_IDENTITY" "$APP/Contents/MacOS/node"
codesign --force --timestamp --options runtime --keychain "$KEYCHAIN" \
  --entitlements "$ROOT/apps/Trigrams/Configs/Community.entitlements" \
  --sign "$DEVELOPER_ID_APPLICATION_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/Trigrams-community-notarized.zip"
xcrun notarytool submit "$BUILD_DIR/Trigrams-community-notarized.zip" --wait \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" \
  --output-format json > "$SIGNING_DIR/notarization.json"
if ! /usr/bin/plutil -extract status raw -o - "$SIGNING_DIR/notarization.json" | /usr/bin/grep -qx Accepted; then
  NOTARIZATION_ID="$(/usr/bin/plutil -extract id raw -o - "$SIGNING_DIR/notarization.json")"
  echo "Apple did not accept notarization submission $NOTARIZATION_ID. Inspect it with notarytool log." >&2
  exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/Trigrams-community-notarized.zip"
shasum -a 256 "$BUILD_DIR/Trigrams-community-notarized.zip" > "$BUILD_DIR/Trigrams-community-notarized.zip.sha256"
