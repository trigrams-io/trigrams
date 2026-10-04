#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
PROFILE="${1:-community}"
CONFIGURATION="${2:-Debug}"
case "$PROFILE" in
  community) SCHEME=Trigrams ;;
  store) SCHEME=TrigramsStore ;;
  *) echo "Usage: scripts/build.sh [community|store] [Debug|Release]" >&2; exit 1 ;;
esac
"$XCODEGEN" generate --spec "$ROOT/apps/Trigrams/project.yml"
xcodebuild -project "$ROOT/apps/Trigrams/Trigrams.xcodeproj" -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" -derivedDataPath "$BUILD_DIR/DerivedData" \
  -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages" \
  -packageCachePath "$BUILD_DIR/PackageCache" \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- build
