#!/bin/bash
# Builds "johorstudio-custom-photobooth.app" (Apple Silicon, release) into ./build
# Usage: ./scripts/build_app.sh [destination folder]
#   e.g. ./scripts/build_app.sh ~/Desktop/MyEvent
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="johorstudio-custom-photobooth"

if ! command -v swift >/dev/null 2>&1 || ! xcode-select -p >/dev/null 2>&1; then
  echo "Swift tidak dijumpai. Pasang dulu dengan: xcode-select --install" >&2
  exit 1
fi

echo "==> Building (release, arm64)… kali pertama ambil masa beberapa minit"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

APP="build/$APP_NAME.app"
echo "==> Packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/JohorBooth" "$APP/Contents/MacOS/JohorBooth"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# App icon: Resources/AppIcon.icns, or generated from Resources/AppIcon.png (1024×1024).
if [ ! -f Resources/AppIcon.icns ] && [ -f Resources/AppIcon.png ]; then
  echo "==> Making AppIcon.icns from AppIcon.png"
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
  ICNS="build/AppIcon.icns"
elif [ -f Resources/AppIcon.icns ]; then
  ICNS="Resources/AppIcon.icns"
else
  ICNS=""
fi
if [ -n "$ICNS" ]; then
  cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" || true
fi

# Ad-hoc signature so macOS can remember the camera permission.
codesign --force --deep --sign - "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

if [ "${1:-}" != "" ]; then
  mkdir -p "$1"
  rm -rf "$1/$APP_NAME.app"
  cp -R "$APP" "$1/"
  echo "==> Copied to $1/$APP_NAME.app"
fi

echo "==> SIAP: $APP"
open build
