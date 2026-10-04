#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
mkdir -p "$BUILD_DIR/coverage/v8"
# Clear only output owned by this run; unrelated checkout/build files remain.
rm -rf "$BUILD_DIR/coverage/v8" "$BUILD_DIR/coverage/runtime" "$BUILD_DIR/UITests.xcresult"
mkdir -p "$BUILD_DIR/coverage/v8"
cd "$ROOT/agent"
npm run build
NODE_V8_COVERAGE="$BUILD_DIR/coverage/v8" node --test ../tests/runtime/*.test.mjs
cd "$ROOT"
"$ROOT/agent/node_modules/.bin/c8" report --temp-directory "$BUILD_DIR/coverage/v8" \
  --report-dir "$BUILD_DIR/coverage/runtime" --all --src agent/src --extension .ts \
  --include 'agent/src/**/*.ts' --exclude-after-remap --reporter lcov --reporter json-summary
"$XCODEGEN" generate --spec "$ROOT/apps/Trigrams/project.yml"
# The app and sidecar are real processes. Only the local model response is a
# deterministic DEBUG fixture, because hosted runners cannot enable Apple Intelligence.
xcodebuild -project "$ROOT/apps/Trigrams/Trigrams.xcodeproj" -scheme Trigrams \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" -resultBundlePath "$BUILD_DIR/UITests.xcresult" \
  -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages" \
  -packageCachePath "$BUILD_DIR/PackageCache" \
  -enableCodeCoverage YES -parallel-testing-enabled NO \
  TRIGRAMS_TEST_TEMP="$TRIGRAMS_TMP" CODE_SIGN_IDENTITY=- test
node scripts/coverage-swift.mjs "$BUILD_DIR/UITests.xcresult" "$BUILD_DIR/coverage/swift.lcov"
node scripts/coverage-gate.mjs build/coverage/swift.lcov build/coverage/runtime/lcov.info
