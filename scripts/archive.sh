#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
PROFILE="${1:-community}"
case "$PROFILE" in
  community) SCHEME=Trigrams ;;
  store) SCHEME=TrigramsStore ;;
  *) echo "Usage: scripts/archive.sh [community|store]" >&2; exit 1 ;;
esac
"$XCODEGEN" generate --spec "$ROOT/apps/Trigrams/project.yml"
xcodebuild -project "$ROOT/apps/Trigrams/Trigrams.xcodeproj" -scheme "$SCHEME" \
  -configuration Release -derivedDataPath "$BUILD_DIR/DerivedData" \
  -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages" \
  -packageCachePath "$BUILD_DIR/PackageCache" \
  -archivePath "$BUILD_DIR/Trigrams-$PROFILE.xcarchive" \
  -destination 'generic/platform=macOS' CODE_SIGN_IDENTITY=- archive
APP="$BUILD_DIR/Trigrams-$PROFILE.xcarchive/Products/Applications/Trigrams.app"
test -x "$APP/Contents/MacOS/node"
test -f "$APP/Contents/Resources/runtime/dist/main.js"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$BUILD_DIR/Trigrams-$PROFILE.xcarchive" "$BUILD_DIR/Trigrams-$PROFILE.xcarchive.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/Trigrams-$PROFILE.zip"
shasum -a 256 "$BUILD_DIR/Trigrams-$PROFILE.zip" > "$BUILD_DIR/Trigrams-$PROFILE.zip.sha256"
