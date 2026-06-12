#!/usr/bin/env bash
# Build mcpc-gui and package it as a macOS .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
APP_NAME="${APP_NAME:-MCP Client}"
BUNDLE_ID="${BUNDLE_ID:-com.mcpc.gui}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
BINARY="$ROOT/.build/$BUILD_CONFIG/mcpc-gui"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
TEMPLATE="$ROOT/packaging/mcpc-gui/Info.plist.template"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "error: missing Info.plist template at $TEMPLATE" >&2
  exit 1
fi

if [[ ! -x "$BINARY" ]]; then
  echo "Building mcpc-gui ($BUILD_CONFIG)..."
  swift build -c "$BUILD_CONFIG" --product mcpc-gui --package-path "$ROOT"
fi

VERSION="${APP_VERSION:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(grep -E '^[[:space:]]*version[[:space:]]*=' "$ROOT/config.toml" | head -1 \
    | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')"
fi
if [[ -z "$VERSION" ]]; then
  VERSION="1.0.0"
fi

echo "Packaging $APP_BUNDLE (version $VERSION)..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/mcpc-gui"
chmod +x "$APP_BUNDLE/Contents/MacOS/mcpc-gui"

sed \
  -e "s/@APP_NAME@/$APP_NAME/g" \
  -e "s/@BUNDLE_ID@/$BUNDLE_ID/g" \
  -e "s/@VERSION@/$VERSION/g" \
  "$TEMPLATE" >"$APP_BUNDLE/Contents/Info.plist"

printf 'APPL????' >"$APP_BUNDLE/Contents/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$APP_BUNDLE"
  echo "Signed with identity: ${CODE_SIGN_IDENTITY:--}"
fi

echo "Created $APP_BUNDLE"
