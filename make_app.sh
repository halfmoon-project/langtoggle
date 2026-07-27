#!/bin/bash
# LangToggle.app 을 만들어 /Applications 에 설치한다.
# 서명은 ad-hoc(-s -). 로컬 빌드는 격리 속성이 안 붙어서 Gatekeeper가 막지 않는다.
set -euo pipefail
cd "$(dirname "$0")"

APP=/Applications/LangToggle.app
BUILD=build/LangToggle.app

rm -rf build "$BUILD"
mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources/assets"

swiftc -O main.swift -o "$BUILD/Contents/MacOS/LangToggle"
cp assets/ko.png assets/en.png "$BUILD/Contents/Resources/assets/"
# 로그인 항목 목록과 Finder에 보일 아이콘. sips -s format icns 는 실패해서 iconutil 을 쓴다.
ICONSET=build/LangToggle.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/ko.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) assets/ko.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD/Contents/Resources/LangToggle.icns"

cat > "$BUILD/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>LangToggle</string>
  <key>CFBundleDisplayName</key><string>LangToggle</string>
  <key>CFBundleExecutable</key><string>LangToggle</string>
  <key>CFBundleIdentifier</key><string>com.sanghyeon.langtoggle</string>
  <key>CFBundleIconFile</key><string>LangToggle</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

codesign --force --sign - "$BUILD"

pkill -f 'LangToggle.app/Contents/MacOS/LangToggle' 2>/dev/null || true
sleep 1
rm -rf "$APP"
cp -R "$BUILD" "$APP"
rm -rf build

open "$APP"
echo "설치 완료: $APP"
echo "우클릭 메뉴 -> '로그인 시 자동 실행' 켜면 재부팅 후에도 뜬다."
