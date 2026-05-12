#!/bin/bash
#
# Sync Xcode Project
# This script regenerates the Xcode project from project.yml
# Run this anytime you add/remove files in VSCode or command line

set -e

echo "🔄 Regenerating Xcode project from project.yml..."
xcodegen generate

echo "✅ Done! All files in GreatDeploy/ are now synced to the Xcode project."
echo ""
echo "You can now:"
echo "  • Open the project: open GreatDeploy.xcodeproj"
echo "  • Build: xcodebuild -project GreatDeploy.xcodeproj -scheme GreatDeploy build"
