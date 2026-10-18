#!/bin/bash
# MirrorAudio.app を組み立てて ~/Applications にインストールする。
#   UXPLAY_BIN: 同梱する uxplay のパス（既定: ~/Dev/github.com/FDH2/UxPlay/build/uxplay）
#   INSTALL_DIR: インストール先（既定: ~/Applications）
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UXPLAY_BIN="${UXPLAY_BIN:-$HOME/Dev/github.com/FDH2/UxPlay/build/uxplay}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP_NAME="MirrorAudio"

if [[ ! -x "$UXPLAY_BIN" ]]; then
  echo "uxplay が見つかりません: $UXPLAY_BIN" >&2
  exit 1
fi

# Command Line Tools の swift はソースのパスに空白があるとマクロプラグイン（@Observable 等）を
# 解決できないため、空白を含む場合は一時ディレクトリにコピーしてビルドする
BUILD_SRC="$PROJECT_DIR"
if [[ "$PROJECT_DIR" == *" "* ]]; then
  BUILD_SRC="${TMPDIR:-/tmp}/mirroraudio-src"
  BUILD_SRC="${BUILD_SRC// /_}"
  rm -rf "$BUILD_SRC"
  mkdir -p "$BUILD_SRC"
  cp -R "$PROJECT_DIR/Package.swift" "$PROJECT_DIR/Sources" "$PROJECT_DIR/Tests" "$BUILD_SRC/"
fi

(cd "$BUILD_SRC" && swift build -c release --product "$APP_NAME")
BIN_DIR="$(cd "$BUILD_SRC" && swift build -c release --show-bin-path)"

APP="$PROJECT_DIR/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
# Contents/MacOS に置くとアプリ本体と同一視されて Apple Event を横取りするため Helpers に置く
cp "$UXPLAY_BIN" "$APP/Contents/Helpers/uxplay"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.elecdeer.MirrorAudio</string>
  <key>CFBundleName</key><string>MirrorAudio</string>
  <key>CFBundleExecutable</key><string>MirrorAudio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>iPhone からの AirPlay 画面ミラーリングを受信するために使用します。</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_airplay._tcp</string>
    <string>_raop._tcp</string>
  </array>
</dict>
</plist>
PLIST

# 内側の uxplay から順に ad-hoc 署名する（--deep は非推奨のため使わない）
codesign --force --sign - "$APP/Contents/Helpers/uxplay"
codesign --force --sign - "$APP"

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP" "$INSTALL_DIR/"
echo "インストールしました: $INSTALL_DIR/$APP_NAME.app"
