#!/bin/bash
# Builds "JohorStudio Booth.app" (Apple Silicon, release) into ./build
# Usage: ./scripts/build_app.sh [destination folder]
#   e.g. ./scripts/build_app.sh ~/Desktop/"20261017 ptp"
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v swift >/dev/null 2>&1; then
  echo "swift not found. Install Xcode or run: xcode-select --install" >&2
  exit 1
fi

echo "==> Building (release, arm64)…"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

APP="build/JohorStudio Booth.app"
echo "==> Packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/JohorBooth" "$APP/Contents/MacOS/JohorBooth"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" || true
fi

# Ad-hoc signature so macOS can remember the camera permission.
codesign --force --deep --sign - "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

if [ "${1:-}" != "" ]; then
  mkdir -p "$1"
  rm -rf "$1/JohorStudio Booth.app"
  cp -R "$APP" "$1/"
  echo "==> Copied to $1/JohorStudio Booth.app"
fi

echo "==> Done: $APP"
