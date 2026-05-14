#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

APP_NAME="GreatDeploy"
PROJECT_NAME="GreatDeploy"
SCHEME_NAME="GreatDeploy"
CONFIGURATION="Release"
DESTINATION="${GREATDEPLOY_PACKAGE_DESTINATION:-platform=macOS,arch=arm64}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/build/PackageDerivedData"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
ENTITLEMENTS="$ROOT_DIR/GreatDeploy/GreatDeploy.entitlements"
INSTALL_DOC="$ROOT_DIR/docs/INSTALL_ADHOC.md"

VERSION="$(
  /usr/bin/awk -F': ' '/MARKETING_VERSION:/ {
    gsub(/"/, "", $2)
    print $2
    exit
  }' "$ROOT_DIR/project.yml"
)"

if [[ -z "$VERSION" ]]; then
  echo "Could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi

PACKAGE_BASENAME="$APP_NAME-$VERSION-macos-ad-hoc"
STAGING_DIR="$DIST_DIR/$PACKAGE_BASENAME"
ZIP_PATH="$DIST_DIR/$PACKAGE_BASENAME.zip"

echo "==> Generating Xcode project"
cd "$ROOT_DIR"
xcodegen generate

echo "==> Building $APP_NAME $VERSION ($CONFIGURATION)"
/usr/bin/xcodebuild \
  -project "$ROOT_DIR/$PROJECT_NAME.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM="" \
  build

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Built app not found at $APP_BUNDLE" >&2
  exit 1
fi

echo "==> Applying ad-hoc signature"
/usr/bin/codesign \
  --force \
  --deep \
  --sign - \
  --timestamp=none \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  "$APP_BUNDLE"

echo "==> Verifying code signature"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> Creating ZIP package"
/bin/rm -rf "$STAGING_DIR" "$ZIP_PATH"
/bin/mkdir -p "$STAGING_DIR"
/bin/cp -R "$APP_BUNDLE" "$STAGING_DIR/"

if [[ -f "$INSTALL_DOC" ]]; then
  /bin/cp "$INSTALL_DOC" "$STAGING_DIR/"
fi

/usr/bin/find "$STAGING_DIR" -name '._*' -delete

(
  cd "$STAGING_DIR"
  COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc -c -k . "$ZIP_PATH"
)

echo "==> Package ready"
echo "$ZIP_PATH"
