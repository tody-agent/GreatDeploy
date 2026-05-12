#!/bin/bash
set -e

echo "=== Running xcodegen ==="
xcodegen generate

echo "=== Running xcodebuild test ==="
xcodebuild test -project GreatDeploy.xcodeproj -scheme GreatDeploy -destination 'platform=macOS,arch=x86_64' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

echo "=== Running xcodebuild ==="
xcodebuild clean build -project GreatDeploy.xcodeproj -scheme GreatDeploy -destination 'platform=macOS,arch=x86_64' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

echo "=== Test Gate and Build Passed ==="
