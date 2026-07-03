#!/bin/bash
# 在「本機」的登入鑰匙圈建立一把自簽的程式碼簽署身分，供 build.sh 固定簽章用。
# 純本機產生、不連網、不會寫進這個 repo，每個 clone 這份程式碼的人都要在自己電腦上跑一次。
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY_NAME="MacCut Local Signing"

if security find-certificate -c "$IDENTITY_NAME" >/dev/null 2>&1; then
    echo "✅ 已經有「$IDENTITY_NAME」這把身分，不用重建。"
    exit 0
fi

echo "▶︎ 在登入鑰匙圈建立本機自簽的程式碼簽署憑證「$IDENTITY_NAME」…"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

OPENSSL_CONFIG="$TMP_DIR/codesign.cnf"
cat > "$OPENSSL_CONFIG" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_req
prompt = no
[dn]
CN = $IDENTITY_NAME
[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$TMP_DIR/key.pem" -out "$TMP_DIR/cert.pem" \
    -config "$OPENSSL_CONFIG" -extensions v3_req >/dev/null 2>&1

P12_PASSWORD="$(openssl rand -base64 24)"
openssl pkcs12 -export \
    -inkey "$TMP_DIR/key.pem" -in "$TMP_DIR/cert.pem" \
    -out "$TMP_DIR/identity.p12" -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

DEFAULT_KEYCHAIN="$(security default-keychain | awk -F'"' '{print $2}')"

# -T /usr/bin/codesign：只授權 codesign 這支工具可以用這把私鑰，之後簽章不會再跳互動視窗要密碼。
security import "$TMP_DIR/identity.p12" -k "$DEFAULT_KEYCHAIN" \
    -P "$P12_PASSWORD" -T /usr/bin/codesign

echo ""
echo "✅ 建立完成，之後 ./build.sh 會自動偵測到並改用這個身分簽章。"
echo ""
echo "如果你之前已經在「系統設定 → 隱私權與安全性 → 螢幕錄製」授權過 MacCut，"
echo "麻煩把舊的那筆移除（選取後按「−」），重新 ./build.sh 後再授權一次——"
echo "這是最後一次要重新授權，之後身分固定了就不會再變。"
