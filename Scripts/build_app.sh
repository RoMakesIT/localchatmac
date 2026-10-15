#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$ROOT/build/Lantern.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"
ICON_FILE="$RES_DIR/AppIcon.icns"
PNG_ICON="$ROOT/Assets/icon-1024.png"
MACHINE_ARCH="$(uname -m)"

case "$MACHINE_ARCH" in
  arm64|x86_64) ;;
  *)
    echo "Unsupported Mac architecture: $MACHINE_ARCH" >&2
    exit 1
    ;;
esac

mkdir -p "$BIN_DIR" "$RES_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT/build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$ROOT/build/ModuleCache"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$ROOT/Assets/AppIcon.icns" ]; then
  cp "$ROOT/Assets/AppIcon.icns" "$ICON_FILE"
fi
if [ -f "$PNG_ICON" ]; then
  cp "$PNG_ICON" "$RES_DIR/AppIcon.png"
fi

swiftc \
  -sdk "$SDK_PATH" \
  -target "$MACHINE_ARCH-apple-macosx15.0" \
  -parse-as-library \
  -o "$BIN_DIR/Lantern" \
  "$ROOT"/Sources/*.swift

codesign --force --deep --sign - "$APP_DIR"

echo "Built app at: $APP_DIR"
