#!/usr/bin/env bash
# Package mcpc-gui as a .app bundle and create a compressed DMG for distribution.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
APP_NAME="${APP_NAME:-MCPC}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"

export BUILD_CONFIG APP_NAME DIST_DIR BUNDLE_ID APP_VERSION CODE_SIGN_IDENTITY

"$ROOT/scripts/package_app.sh"

APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: app bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

VERSION="${APP_VERSION:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
fi
if [[ -z "$VERSION" ]]; then
  VERSION="1.0.0"
fi

DMG_NAME="${DMG_NAME:-${APP_NAME}-${VERSION}.dmg}"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/mcpc-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT

cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

if [[ -f "$ROOT/packaging/config.toml.example" ]]; then
  cp "$ROOT/packaging/config.toml.example" "$STAGING/config.toml.example"
fi

if [[ -f "$ROOT/packaging/DMG_README.txt" ]]; then
  cp "$ROOT/packaging/DMG_README.txt" "$STAGING/README.txt"
fi

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

echo "Creating $DMG_PATH ..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Created $DMG_PATH"
