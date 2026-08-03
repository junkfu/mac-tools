#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="AppJump"
BUILD_DIR=".build/release"

# 直接組裝到 /Applications：整台機器只留一份 App。
# 在 repo 裡另外留一份 .app 的話，Alfred、Spotlight、登入項目都會看到兩個同名程式。
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"

echo "▶︎ 編譯中 (release)…"
swift build -c release

echo "▶︎ 更新 ${APP_BUNDLE}…"
# 就地覆蓋，不整包刪掉重建：bundle 路徑與簽章身分都不變，TCC 的「輔助使用」授權才留得住。
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "   （沒有 Resources/AppIcon.icns，先跑 ./make-icon.sh 才會有 App 圖示）"
fi

SIGN_IDENTITY_NAME="AppJump Local Signing"

if security find-certificate -c "$SIGN_IDENTITY_NAME" >/dev/null 2>&1; then
    echo "▶︎ 使用固定身分簽章（${SIGN_IDENTITY_NAME}）…"
    codesign --force --sign "$SIGN_IDENTITY_NAME" "$APP_BUNDLE"
else
    echo "▶︎ 找不到「${SIGN_IDENTITY_NAME}」憑證，改用 Ad-hoc 簽章（每次重編譯都要重新授權輔助使用權限）"
    echo "   一次性解法：先跑 ./setup-signing.sh，再重新 ./build.sh。"
    codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true
fi

echo ""
echo "✅ 完成： $APP_BUNDLE"
echo "   啟動： open \"$APP_BUNDLE\""
