#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="NotchShelf"
BUILD_DIR=".build/release"

# 直接組裝到 /Applications：整台機器只留一份 App。
# 在 repo 裡另外留一份 .app 的話，Alfred、Spotlight、登入項目都會看到兩個同名程式。
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"

echo "▶︎ 編譯中 (release)…"
swift build -c release

echo "▶︎ 更新 ${APP_BUNDLE}…"
# 就地覆蓋，不整包刪掉重建：bundle 路徑不變，登入項目和既有授權才不會失效。
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
echo "✅ 完成： $APP_BUNDLE"
echo "   啟動： open \"$APP_BUNDLE\""
