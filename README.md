# LangToggle

화면에 항상 떠 있는 키캡 아이콘. 클릭하면 한/영 입력 소스가 바뀐다.

## 설치

```bash
./make_app.sh   # 빌드 -> ad-hoc 서명 -> /Applications 설치 -> 실행
```

설치 후엔 터미널이 필요 없다. 우클릭 메뉴의 **로그인 시 자동 실행**을 켜면 재부팅 후에도 뜬다
(`SMAppService`, macOS 13+). 개발자 계정·공증·DMG 전부 불필요 — 로컬 빌드는 격리 속성이
안 붙어서 Gatekeeper가 막지 않는다.

## 배포 (남한테 주기)

```bash
./make_app.sh dist   # 빌드 -> Developer ID 서명 + 하드닝 런타임 -> 공증 -> staple -> zip
```

`build/LangToggle.zip` 이 나온다. 이 zip 은 아무 맥에서 받아도 경고 없이 열린다
(Gatekeeper: `Notarized Developer ID`). 로컬 설치와 달리 이건 애플 공증까지 거치므로,
받는 쪽에서 `xattr` 를 떼거나 우클릭 열기를 할 필요가 없다.

준비물(최초 1회):
- **Developer ID Application** 인증서 (유료 Apple Developer Program). 키체인에 설치돼 있으면
  스크립트가 해시로 자동으로 찾아 쓴다.
- 공증용 notarytool 키체인 프로필. 이름은 `langtoggle`(환경변수 `NOTARY_PROFILE` 로 변경 가능):

  ```bash
  xcrun notarytool store-credentials "langtoggle" \
    --key <AuthKey_XXXX.p8 경로> --key-id <KEY_ID> --issuer <ISSUER_UUID>
  ```

  프로필이 없으면 `dist` 는 서명·검증까지만 하고 이 안내를 출력한 뒤 멈춘다.

개발 중에는 번들 없이 그냥 돌려도 된다:

```bash
swiftc -O main.swift -o LangToggle
./LangToggle              # 실행 (Dock 아이콘 없음)
./LangToggle --selftest   # 토글 동작 확인
```

- **클릭** — 다음 입력 소스로 전환 (ABC ↔ 2세트 한글). 누르면 키캡이 눌렸다 튕겨 올라온다.
- **드래그** — 위치 이동, 위치는 자동 저장
- **우클릭** — 로그인 시 자동 실행 / 아이콘 새로고침 / 종료 (안 먹으면 `pkill -f LangToggle`)

## 아이콘 커스텀

`~/Library/Application Support/LangToggle/` 에 `ko.png`, `en.png`를 두면 그게 우선 적용된다.
없으면 번들 안의 기본 키캡을 쓰고, 그것도 없으면 텍스트 배지(`한`/`A`)로 폴백한다.
번들 내부를 직접 고치면 ad-hoc 서명이 깨지므로 이 경로를 쓴다.
바꾼 뒤에는 우클릭 → 아이콘 새로고침.

기본 아이콘은 [halfmoon 디자인 시스템](https://github.com/halfmoon-project/halfmoon-design)
토큰(gray.800 바디, gray.50 글리프, blue.600 액센트, radius.xl 라운딩)을 따른다.
키캡 바디는 codex `imagegen`으로 생성한 `assets/keycap-master-v2.png` 하나다 —
우측 상단에서 본 3/4 대각선 뷰이고, 윗면이 `#ff00ff`로 비워져 있다.
`build_icons.py`가 그 마커 영역의 사각형을 찾아 윗면 색(gray.700)으로 바꾸고,
Apple SD Gothic Neo로 그린 글리프를 원근 변환으로 얹는다. 바디는 두 아이콘이 공유하므로
실루엣이 픽셀 단위로 같고 토글할 때 흔들리지 않는다.
글리프를 바꾸려면 `OUTPUTS`만 고치고 다시 돌린다.

```bash
uv run --with pillow --with numpy python build_icons.py
```

`./LangToggle --dump` 은 실제 표시 크기(88px)로 렌더한 결과를 `/tmp/langtoggle-render.png`에 쓴다.

## 참고

- macOS 13+ 와 Xcode Command Line Tools(`swiftc`)가 필요하다.
- 입력 소스 전환은 Carbon `TISSelectInputSource` — 접근성 권한이 필요 없다.
- 창은 `.nonactivatingPanel`이라 클릭해도 현재 앱의 포커스를 빼앗지 않는다.
- `make_app.sh`(인자 없음)의 서명은 ad-hoc(`codesign -s -`)이다. 직접 빌드하면 격리 속성이
  안 붙어서 자기 맥에선 문제없지만, 이 `.app`을 그대로 zip으로 배포하면 받는 쪽에서
  Gatekeeper가 막는다. 남한테 주려면 위 **배포** 절의 `./make_app.sh dist`(Developer ID
  서명 + 공증)를 쓴다.

## 라이센스

[MIT](./LICENSE)
