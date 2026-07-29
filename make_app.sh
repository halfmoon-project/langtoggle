#!/bin/bash
# LangToggle.app 을 빌드한다.
#
#   ./make_app.sh          로컬 설치용. ad-hoc(-s -) 서명 -> /Applications 설치 -> 실행.
#                          직접 빌드하면 격리 속성이 안 붙어서 Gatekeeper가 막지 않는다.
#   ./make_app.sh dist     배포용. Developer ID 서명 + 하드닝 런타임 -> (공증) -> zip.
#                          이 zip 은 남의 맥에서 받아도 열린다(공증까지 된 경우).
#
# 공증(notarize)은 notarytool 키체인 프로필이 있어야 돈다. 프로필 이름은 NOTARY_PROFILE.
# 프로필이 없으면 dist 는 서명+검증까지만 하고 공증 방법을 안내하고 멈춘다.
set -euo pipefail
cd "$(dirname "$0")"

# 버전은 여기 한 곳만 고친다. Info.plist 와 배포 zip 이름이 이걸 따라간다.
# 릴리스 태그도 같은 숫자를 쓴다: gh release create v$VERSION build/LangToggle-$VERSION.zip
VERSION=1.1.0

MODE="${1:-local}"
NOTARY_PROFILE="${NOTARY_PROFILE:-langtoggle}"

# VERSION 을 안 올린 채 dist 를 돌리면 공증(수 분)을 다 태운 뒤에야 릴리스 단계에서 막힌다.
# 태그는 gh release create 가 서버에 만들어서 로컬엔 없을 수 있으니 원격까지 본다.
# 네트워크가 없으면 ls-remote 가 조용히 비고 로컬 검사만 남는다.
if [ "$MODE" = "dist" ] && { git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null \
    || git ls-remote --tags origin "v$VERSION" 2>/dev/null | grep -q .; }; then
  echo "v$VERSION 은 이미 나간 버전이다. 맨 위 VERSION 을 올렸는지 확인." >&2
  exit 1
fi

APP=/Applications/LangToggle.app
BUILD=build/LangToggle.app

# --- 공통 빌드 ---------------------------------------------------------------
rm -rf build "$BUILD"
mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources/assets"

# main.swift 하나가 아니라 루트의 .swift 를 다 넘긴다 — 파일이 늘어도 여기는 안 고친다.
swiftc -O ./*.swift -o "$BUILD/Contents/MacOS/LangToggle"
# 키캡 바디 한 장 + 언어별 글리프 레이어. assets/design/ 은 빌드 입력이라 안 들어간다.
cp assets/*.png "$BUILD/Contents/Resources/assets/"
# 로그인 항목 목록과 Finder에 보일 아이콘. sips -s format icns 는 실패해서 iconutil 을 쓴다.
# 표시용 아이콘은 176px 라 .icns 에는 축소 전 원본(assets/design/appicon.png)을 쓴다.
ICONSET=build/LangToggle.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/design/appicon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) assets/design/appicon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD/Contents/Resources/LangToggle.icns"

# 따옴표 없는 heredoc — $VERSION 을 치환한다. 본문에 다른 $ 나 백틱이 없어야 한다.
cat > "$BUILD/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>LangToggle</string>
  <key>CFBundleDisplayName</key><string>LangToggle</string>
  <key>CFBundleExecutable</key><string>LangToggle</string>
  <key>CFBundleIdentifier</key><string>com.sanghyeon.langtoggle</string>
  <key>CFBundleIconFile</key><string>LangToggle</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

# --- 로컬 설치 모드 -----------------------------------------------------------
if [ "$MODE" = "local" ]; then
  codesign --force --sign - "$BUILD"

  pkill -f 'LangToggle.app/Contents/MacOS/LangToggle' 2>/dev/null || true
  sleep 1
  rm -rf "$APP"
  cp -R "$BUILD" "$APP"
  rm -rf build

  open "$APP"
  echo "설치 완료: $APP"
  echo "우클릭 메뉴 -> '로그인 시 자동 실행' 켜면 재부팅 후에도 뜬다."
  exit 0
fi

# --- 배포 모드 ----------------------------------------------------------------
if [ "$MODE" != "dist" ]; then
  echo "알 수 없는 모드: $MODE  (local | dist)" >&2
  exit 2
fi

# Developer ID Application 인증서의 해시를 찾는다. login/System 양쪽에 있어
# 이름으로 서명하면 ambiguous 라, 해시(첫 열)로 서명한다.
SIGN_ID=$(security find-identity -v -p codesigning \
  | awk '/Developer ID Application/ {print $2; exit}')
if [ -z "$SIGN_ID" ]; then
  echo "Developer ID Application 인증서가 없다. 키체인에 설치했는지 확인." >&2
  exit 1
fi
echo "서명 ID: $SIGN_ID"

# 하드닝 런타임(--options runtime) + 보안 타임스탬프(--timestamp)는 공증의 필수 조건.
# 중첩 번들이 없어 루트 한 번 서명으로 실행 파일까지 봉인된다.
codesign --force --timestamp --options runtime --sign "$SIGN_ID" "$BUILD"
codesign --verify --strict --verbose=2 "$BUILD"
echo "서명 검증 통과."

ZIP="build/LangToggle-$VERSION.zip"

# 공증 프로필이 없으면 여기서 멈추고 방법을 안내한다.
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo
  echo "=== 서명까지 완료. 공증(notarize)은 아직이다. ==="
  echo "공증 자격증명을 아래처럼 한 번 저장하면 다음부터 자동으로 공증까지 된다:"
  echo
  echo "  # App Store Connect API 키(.p8) 방식 — 이메일 불필요"
  echo "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
  echo "    --key <AuthKey_XXXX.p8 경로> --key-id <KEY_ID> --issuer <ISSUER_UUID>"
  echo
  echo "저장 뒤 './make_app.sh dist' 를 다시 돌리면 공증+staple 까지 진행된다."
  echo "지금 상태로도 자기 맥에서는 쓸 수 있지만, 남한테 주려면 공증이 필요하다."
  exit 0
fi

# 공증: zip 으로 제출하고 결과를 기다린다.
ditto -c -k --keepParent "$BUILD" "$ZIP"
echo "공증 제출 중... (수 초~수 분)"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

# staple: 공증 티켓을 .app 에 박아 오프라인에서도 Gatekeeper가 통과시킨다.
xcrun stapler staple "$BUILD"

# 배포용 zip 을 staple 된 .app 으로 다시 만든다.
rm -f "$ZIP"
ditto -c -k --keepParent "$BUILD" "$ZIP"

echo
echo "Gatekeeper 최종 확인:"
spctl -a -vvv --type execute "$BUILD" || true
echo
echo "배포 파일: $ZIP  (이 zip 을 남한테 주면 경고 없이 열린다)"
echo "릴리스: gh release create v$VERSION $ZIP --title \"LangToggle $VERSION\""
