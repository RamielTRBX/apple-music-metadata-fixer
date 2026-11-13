#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/Apple Music 音乐信息订正.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

if [[ -z "${SDKROOT:-}" ]]; then
  export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
fi
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFT_MODULE_CACHE_PATH="$ROOT_DIR/.build/swift-module-cache"
swift build \
  --package-path "$ROOT_DIR" \
  --scratch-path "$ROOT_DIR/.build" \
  -c release \
  --disable-sandbox

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT_DIR/.build/release/AppleMusicMetadataFixer" "$MACOS/"
cp "$ROOT_DIR/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT_DIR/Sources/AppleMusicMetadataFixer/Resources/"*.js "$RESOURCES/"
cp "$ROOT_DIR/Sources/AppleMusicMetadataFixer/Resources/"*.json "$RESOURCES/"
cp "$ROOT_DIR/Sources/AppleMusicMetadataFixer/Resources/"*.icns "$RESOURCES/"

codesign --force --deep --sign - "$APP_DIR" >/dev/null
echo "$APP_DIR"
