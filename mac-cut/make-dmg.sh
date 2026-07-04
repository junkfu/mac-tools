#!/bin/bash
# 把 MacCut.app 包成一個可以拖進 Applications 安裝的 .dmg。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MacCut"
APP_BUNDLE="$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "▶︎ 找不到 $APP_BUNDLE，先跑 build.sh…"
    ./build.sh
fi

echo "▶︎ 準備 DMG 內容…"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_BUNDLE"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_NAME"

echo "▶︎ 組裝 $DMG_NAME…"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME" >/dev/null

echo ""
echo "✅ 完成：$(pwd)/$DMG_NAME"
echo "   打開後把 $APP_NAME.app 拖到 Applications 捷徑就能安裝。"
