#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="GreatDeploy"
PROJECT_NAME="GreatDeploy"
SCHEME_NAME="GreatDeploy"
BUNDLE_ID="com.greatdeploy.app"
CONFIGURATION="${GREATDEPLOY_CONFIGURATION:-Debug}"
DESTINATION="${GREATDEPLOY_RUN_DESTINATION:-platform=macOS,arch=arm64}"
SIGNING_ARGS=()

if [[ -n "${GREATDEPLOY_DEVELOPMENT_TEAM:-}" ]]; then
  SIGNING_ARGS+=("GREATDEPLOY_DEVELOPMENT_TEAM=$GREATDEPLOY_DEVELOPMENT_TEAM")
else
  SIGNING_ARGS+=(
    CODE_SIGN_IDENTITY=""
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
  )
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

build_app() {
  xcodebuild \
    -project "$ROOT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    "${SIGNING_ARGS[@]}" \
    build
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    usage
    exit 2
    ;;
esac
