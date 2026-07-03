#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MacCut"
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

SIGN_IDENTITY_NAME="MacCut Local Signing"

if security find-certificate -c "$SIGN_IDENTITY_NAME" >/dev/null 2>&1; then
    echo "▶︎ 使用固定身分簽章（$SIGN_IDENTITY_NAME）…"
    codesign --force --sign "$SIGN_IDENTITY_NAME" "$APP_BUNDLE"
else
    echo "▶︎ 找不到「$SIGN_IDENTITY_NAME」憑證，改用 Ad-hoc 簽章（每次重編譯可能要重新授權螢幕錄製權限）"
    echo "   一次性解法：先跑 ./setup-signing.sh，再重新 ./build.sh。"
    codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true
fi

echo ""
echo "✅ 完成： $(pwd)/$APP_BUNDLE"
echo "   啟動： open \"$APP_BUNDLE\""
echo "   或：  ./$APP_BUNDLE/Contents/MacOS/$APP_NAME"
