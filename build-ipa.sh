#!/usr/bin/env bash
# 在 macOS 上生成未签名 IPA。用法：chmod +x build-ipa.sh && ./build-ipa.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="NodeProbe"
OUT="${APP_NAME}-unsigned.ipa"

echo "==> 清理旧产物"
rm -rf build Payload "$OUT"

echo "==> 编译（不签名）"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -target "$APP_NAME" \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP=$(find . -maxdepth 8 -type d -name "$APP_NAME.app" | head -n 1)
if [ -z "$APP" ]; then
  echo "找不到 $APP_NAME.app，构建可能失败了" >&2
  exit 1
fi
echo "==> 找到产物：$APP"
lipo -info "$APP/$APP_NAME" || true

echo "==> 打包 Payload"
mkdir -p Payload
cp -R "$APP" Payload/
zip -qry "$OUT" Payload
rm -rf Payload

echo "==> 完成：$(pwd)/$OUT"
ls -lh "$OUT"
echo
echo "接下来用你自己的签名方式（TrollStore / Esign / Sideloadly / 证书重签）装进手机。"
