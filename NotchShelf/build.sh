#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="NotchShelf"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"

echo "▶︎ 編譯中 (release)…"
swift build -c release

echo "▶︎ 組裝 .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "▶︎ Ad-hoc 簽章…"
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "✅ 完成： $(pwd)/$APP_BUNDLE"
echo "   啟動： open \"$APP_BUNDLE\""
echo "   或：  ./$APP_BUNDLE/Contents/MacOS/$APP_NAME"
