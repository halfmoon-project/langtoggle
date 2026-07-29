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
VERSION=1.2.2

MODE="${1:-local}"
NOTARY_PROFILE="${NOTARY_PROFILE:-langtoggle}"

# --- 자동 업데이트(Sparkle) ---------------------------------------------------
# 프레임워크는 리포에 안 넣는다. 없으면 아래 버전을 받아서 vendor/ 에 캐시하고,
# 그 뒤로는 네트워크 없이 빌드된다. 버전을 올릴 땐 SHA256 도 같이 갈아야 받는다.
SPARKLE_VERSION=2.9.4
SPARKLE_SHA256=ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9
VENDOR=vendor

# 업데이트 서명용 EdDSA 공개키. 개인키는 키체인에만 있다 — vendor/bin/generate_keys 가 넣는다.
# 공개키라서 리포에 있어도 되고, 비어 있으면 dist 가 만드는 법을 알려 주고 멈춘다.
# 이 키를 잃으면 기존 사용자에게 업데이트를 영영 못 보낸다(새 키로 서명한 걸 안 받는다).
SPARKLE_PUBKEY=8EueKaIIlZa0mxS2D/68ftBLP7xgViyRWuyAO3jay94=

# 앱이 업데이트를 확인하러 가는 곳. 릴리스 zip 은 GitHub Releases 에서 받아 간다.
FEED_URL=https://raw.githubusercontent.com/halfmoon-project/langtoggle/main/appcast.xml
DOWNLOAD_PREFIX=https://github.com/halfmoon-project/langtoggle/releases/download/v$VERSION/

# vendor/Sparkle.framework 를 보장한다. 이미 있으면 아무것도 안 한다.
ensure_sparkle() {
  [ -d "$VENDOR/Sparkle.framework" ] && return 0
  echo "Sparkle $SPARKLE_VERSION 내려받는 중..."
  mkdir -p "$VENDOR"
  local tar=$VENDOR/sparkle.tar.xz
  curl -fsSL -o "$tar" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  # 체크섬이 안 맞으면 여기서 죽는다 — 서명 도구까지 들어 있는 물건이라 그냥 믿고 쓰면 안 된다.
  echo "$SPARKLE_SHA256  $tar" | shasum -a 256 -c -
  tar -xf "$tar" -C "$VENDOR" Sparkle.framework bin
  rm -f "$tar"
}

# 원본 3.0MB 짜리를 이 앱에 필요한 것만 남겨 1.1MB 로 만들어 번들에 넣는다.
# 원본은 vendor/ 에 그대로 두고(빌드가 이걸 본다) 복사본만 깎는다.
slim_sparkle() {
  local dst=$BUILD/Contents/Frameworks/Sparkle.framework
  mkdir -p "$BUILD/Contents/Frameworks"
  rm -rf "$dst"
  cp -R "$VENDOR/Sparkle.framework" "$dst"
  local v=$dst/Versions/B
  # 샌드박스 앱 전용이다. 이 앱은 샌드박스가 아니라 Sparkle 공식 문서도 떼라고 안내한다. (-424KB)
  rm -rf "$v/XPCServices"
  # 헤더는 빌드할 때만 필요하고 빌드는 vendor/ 원본을 본다. (-224KB)
  rm -rf "$v/Headers" "$v/PrivateHeaders" "$v/Modules" \
         "$dst/Headers" "$dst/PrivateHeaders" "$dst/Modules"
  # 무음 업데이트라 Sparkle UI 를 볼 일이 거의 없다. Base(영어) + 한국어만 남긴다. (-292KB)
  local keep
  for d in "$v"/Resources/*.lproj; do
    keep=$(basename "$d")
    [ "$keep" = Base.lproj ] || [ "$keep" = ko.lproj ] || rm -rf "$d"
  done
  # arm64 전용 앱이라 x86_64 슬라이스는 순수 낭비다. (-950KB)
  for f in "$v/Sparkle" "$v/Autoupdate" "$v/Updater.app/Contents/MacOS/Updater"; do
    lipo -thin arm64 "$f" -output "$f.thin"
    mv "$f.thin" "$f"
  done
}

# 중첩 번들은 안쪽부터 서명한다 — 바깥을 먼저 서명해 봐야 안쪽을 건드리는 순간 봉인이 깨진다.
# --deep 은 안 쓴다. 중첩 번들에 바깥 앱의 서명 옵션을 덮어써서 공증에서 걸린다.
sign_all() {
  local spk=$BUILD/Contents/Frameworks/Sparkle.framework
  codesign --force "$@" "$spk/Versions/B/Updater.app"
  codesign --force "$@" "$spk/Versions/B/Autoupdate"
  codesign --force "$@" "$spk"
  codesign --force "$@" "$BUILD"
}

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
ensure_sparkle
rm -rf build "$BUILD"
mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources/assets"

# main.swift 하나가 아니라 루트의 .swift 를 다 넘긴다 — 파일이 늘어도 여기는 안 고친다.
# rpath 가 둘인 이유: 번들은 Contents/Frameworks 에서, 리포 루트에 그냥 빌드한 맨 바이너리는
# vendor/ 에서 Sparkle 을 찾는다. 안 맞는 쪽은 dyld 가 그냥 지나간다.
swiftc -O ./*.swift \
  -F "$VENDOR" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -Xlinker -rpath -Xlinker @executable_path/vendor \
  -o "$BUILD/Contents/MacOS/LangToggle"
slim_sparkle
# 키캡 바디 한 장 + 언어별 글리프 레이어. assets/design/ 은 빌드 입력이라 안 들어간다.
cp assets/*.png "$BUILD/Contents/Resources/assets/"
# 실제 타건 샘플 세 벌과 해당 라이선스. 14KB가 안 돼 합성음보다 자연스러운 쪽을 택했다.
cp -R assets/sounds "$BUILD/Contents/Resources/assets/"
# 로그인 항목 목록과 Finder에 보일 아이콘. sips -s format icns 는 실패해서 iconutil 을 쓴다.
# 표시용 아이콘은 176px 라 .icns 에는 축소 전 원본(assets/design/appicon.png)을 쓴다.
ICONSET=build/LangToggle.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/design/appicon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) assets/design/appicon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD/Contents/Resources/LangToggle.icns"

# 로컬 빌드는 자동 확인을 끈다. 개발 중인 빌드가 배포판으로 조용히 덮이면 곤란하다 —
# 수동 확인(우클릭 메뉴)은 로컬에서도 그대로 된다.
AUTOCHECK=false
[ "$MODE" = "dist" ] && AUTOCHECK=true

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
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBKEY</string>
  <key>SUEnableAutomaticChecks</key><$AUTOCHECK/>
  <key>SUAutomaticallyUpdate</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict></plist>
PLIST

# --- 로컬 설치 모드 -----------------------------------------------------------
if [ "$MODE" = "local" ]; then
  # ad-hoc 이라 하드닝 런타임을 안 켠다 — 켜면 라이브러리 검증이 팀 ID 없는 프레임워크를 막는다.
  sign_all --sign -

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

# 공개키 없이 낸 배포판은 업데이트를 못 받는다. 공증까지 다 태운 뒤에 알면 늦으니 여기서 막는다.
if [ -z "$SPARKLE_PUBKEY" ]; then
  echo
  echo "=== 업데이트 서명 키가 없다. ===" >&2
  echo "아래를 한 번 돌리면 개인키가 키체인에 들어가고 공개키가 출력된다:" >&2
  echo >&2
  echo "  $VENDOR/bin/generate_keys" >&2
  echo >&2
  echo "출력된 SUPublicEDKey 값을 이 스크립트 위쪽 SPARKLE_PUBKEY 에 박으면 된다." >&2
  echo "개인키는 키체인에만 있다 — 잃으면 기존 사용자에게 업데이트를 영영 못 보낸다." >&2
  echo "백업: $VENDOR/bin/generate_keys -x <안전한곳>/langtoggle-eddsa.key" >&2
  exit 1
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
# 하드닝 런타임은 라이브러리 검증도 켠다 — 앱과 Sparkle 을 같은 팀 ID 로 서명해야 로드된다.
sign_all --timestamp --options runtime --sign "$SIGN_ID"
codesign --verify --strict --deep --verbose=2 "$BUILD"
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

# appcast: 기존 사용자의 앱이 여기를 보고 새 버전을 알아챈다. zip 을 EdDSA 개인키로 서명해
# 항목을 만드는데, 그 키가 키체인에 있어서 대화상자가 뜬다 — "항상 허용" 을 눌러야 다음부터 안 묻는다.
# 그냥 "허용" 을 누르면 릴리스 때마다 여기서 멈춘 채로 기다리게 된다.
# 아직 안 올라간 릴리스 URL 을 미리 적어 두는 것이라, appcast.xml 커밋은 릴리스 뒤에 해야 한다.
echo
echo "appcast 생성 중..."
# 넘긴 디렉터리를 통째로 훑는 도구라 build/ 를 그대로 주면 .app 과 iconset 까지 본다. zip 만 담아서 준다.
mkdir -p build/updates
cp "$ZIP" build/updates/
"$VENDOR/bin/generate_appcast" --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link https://github.com/halfmoon-project/langtoggle \
  -o appcast.xml build/updates

echo
echo "배포 파일: $ZIP  (이 zip 을 남한테 주면 경고 없이 열린다)"
echo
echo "남은 순서 — appcast.xml 은 zip 이 올라간 뒤에 커밋해야 한다:"
echo "  gh release create v$VERSION $ZIP --title \"LangToggle $VERSION\""
echo "  git add appcast.xml && git commit -m 'appcast: $VERSION' && git push"
echo
echo "탭 리포의 Casks/langtoggle.rb 도 같이 갈아 준다:"
echo "  version \"$VERSION\""
echo "  sha256 \"$(shasum -a 256 "$ZIP" | cut -d' ' -f1)\""
