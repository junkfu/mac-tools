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

if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "   （沒有 Resources/AppIcon.icns，先跑 ./make-icon.sh 才會有 App 圖示）"
fi

echo "▶︎ Ad-hoc 簽章…"
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "✅ 完成： $(pwd)/$APP_BUNDLE"
echo "   啟動： open \"$APP_BUNDLE\""
echo "   或：  ./$APP_BUNDLE/Contents/MacOS/$APP_NAME"
