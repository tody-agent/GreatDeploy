#!/bin/bash
# Build and Run GreatDeploy

set -e

echo "=== GreatDeploy Build & Run ==="

# Clean DerivedData
echo "Cleaning DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/GreatDeploy-*

# Regenerate project
echo "Regenerating Xcode project..."
xcodegen generate

# Build Debug
echo "Building Debug..."
xcodebuild -project GreatDeploy.xcodeproj \
  -scheme GreatDeploy \
  -configuration Debug \
  build

# Find built app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/GreatDeploy-*/Build/Products/Debug -name "GreatDeploy.app" -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
  echo "ERROR: Could not find built app"
  exit 1
fi

echo "Built app at: $APP_PATH"

# Kill old instance
pkill -x GreatDeploy 2>/dev/null || true
sleep 1

# Run new build
echo "Running app..."
open "$APP_PATH"

echo "=== Done! ==="
