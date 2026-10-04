#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
cd "$ROOT"
npm --prefix agent run build
mkdir -p "$BUILD_DIR/OnDeviceModuleCache"
xcrun swiftc -parse-as-library -module-cache-path "$BUILD_DIR/OnDeviceModuleCache" \
  apps/Trigrams/Sources/Models/JSONValue.swift \
  apps/Trigrams/Sources/Inference/InferenceInput.swift \
  apps/Trigrams/Sources/Inference/FoundationModelService.swift \
  tests/inference/AFMDriver.swift -o "$BUILD_DIR/AFMDriver"
node tests/inference/on-device.mjs "$BUILD_DIR/AFMDriver"
