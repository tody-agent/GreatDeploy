#!/usr/bin/env bash
set -euo pipefail

DESTINATION="${GREATDEPLOY_TEST_DESTINATION:-platform=macOS,arch=arm64}"
COMMON_XCODEBUILD_ARGS=(
  -project GreatDeploy.xcodeproj
  -scheme GreatDeploy
  -destination "$DESTINATION"
  CODE_SIGN_IDENTITY=""
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
)

echo "=== Running xcodegen ==="
xcodegen generate

echo "=== Running xcodebuild test ($DESTINATION) ==="
xcodebuild test "${COMMON_XCODEBUILD_ARGS[@]}"

echo "=== Running xcodebuild clean build ($DESTINATION) ==="
xcodebuild clean build "${COMMON_XCODEBUILD_ARGS[@]}"

echo "=== Test Gate and Build Passed ==="
