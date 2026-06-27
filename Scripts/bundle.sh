#!/usr/bin/env bash
# ビルド成果物を .app バンドルにまとめる。
# 使い方: bash Scripts/bundle.sh [debug|release]   (既定: release)
#
# ローカル検証用ビルド: LOCAL=1 bash Scripts/bundle.sh debug
#   本番アプリ(com.mtkg.whisperkun)と TCC 権限が衝突しないよう、バンドルID と
#   表示名を分けた「Whisperkun (Local)」を生成する。これによりシステム設定の
#   権限一覧に本番と別エントリとして並び、独立して許可できる。
#   再ビルドで権限が外れるのを避けたい場合は、安定した自己署名IDを併用する:
#     SIGN_IDENTITY="Apple Development: ..." LOCAL=1 bash Scripts/bundle.sh debug
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
LOCAL="${LOCAL:-0}"

# APP_NAME は配布する .app／実行バイナリの名前、DISPLAY_NAME は Finder・メニュー・システム設定に
# 出る表示名（CFBundleName/CFBundleDisplayName）。どちらも先頭大文字 Whisperkun で揃える
# （バンドルID com.mtkg.whisperkun は小文字のまま）。ローカル検証ビルドは「(Local)」を付けて区別する。
if [[ "$LOCAL" == "1" ]]; then
  APP_NAME="Whisperkun (Local)"
  DISPLAY_NAME="Whisperkun (Local)"
  BUNDLE_ID="com.mtkg.whisperkun.local"
else
  APP_NAME="Whisperkun"
  DISPLAY_NAME="whisperkun"
  BUNDLE_ID="com.mtkg.whisperkun"
fi
APP="$ROOT/$APP_NAME.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

echo "==> Bundling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN_DIR/whisperkun" "$APP/Contents/MacOS/Whisperkun"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# ローカライズ（OS の言語に追従）。各 *.lproj を Resources へコピーする。
for lproj in "$ROOT"/Resources/*.lproj; do
  [[ -d "$lproj" ]] && cp -R "$lproj" "$APP/Contents/Resources/"
done

# ローカル検証ビルドはバンドルID/表示名を差し替えて本番と権限を分離する。
if [[ "$LOCAL" == "1" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $DISPLAY_NAME" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$APP/Contents/Info.plist"
fi

# メニューバー用アイコン（実行時に Bundle.main から読み込む）
if [[ -f "$ROOT/Resources/MenuBarIcon.png" ]]; then
  cp "$ROOT/Resources/MenuBarIcon.png" "$APP/Contents/Resources/MenuBarIcon.png"
fi

# アプリアイコン: Resources/AppIcon.png から .icns を生成する。
ICON_SRC="$ROOT/Resources/AppIcon.png"
if [[ -f "$ICON_SRC" ]]; then
  echo "==> Generating app icon"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

# コード署名。マイク用エンタイトルメントはどちらの署名でも必須。
# SIGN_IDENTITY が指定されていれば、その安定した署名アイデンティティで署名する。
# 安定署名にすると、アップデートで .app を入れ替えても TCC 権限
# （マイク/音声認識/アクセシビリティ）が保持される
# （アドホック署名はビルドごとに署名が変わり、権限が無効化されてしまう）。
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
ENTITLEMENTS="$ROOT/Resources/whisperkun.entitlements"
if [[ -n "$SIGN_IDENTITY" ]]; then
  # Developer ID 署名 + Hardened Runtime + セキュアタイムスタンプ（notarization の要件）。
  echo "==> Codesign ($SIGN_IDENTITY)"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$APP"
else
  # ad-hoc 署名（Hardened Runtime + マイク用エンタイトルメント）。
  echo "==> Codesign (ad-hoc)"
  codesign --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign - "$APP"
fi

echo "==> Done: $APP"
echo "起動: open \"$APP\"   （初回はシステム設定 > プライバシーとセキュリティ で マイク/音声認識/アクセシビリティ を許可）"
