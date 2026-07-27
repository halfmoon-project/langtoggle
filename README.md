# LangToggle

화면에 항상 떠 있는 키캡 아이콘. 클릭하면 한/영 입력 소스가 바뀐다.

## 설치

[최신 릴리스](https://github.com/halfmoon-project/langtoggle/releases/latest)에서 zip 을 받는다.

1. 압축 해제
2. `LangToggle.app` 을 **응용 프로그램(Applications)** 으로 이동
3. 더블클릭

Developer ID 서명 + 애플 공증(Notarized Developer ID)까지 돼 있어 경고 없이 바로 열린다.
`xattr` 를 떼거나 우클릭 열기를 할 필요가 없다.

## 사용

- **클릭** — 다음 입력 소스로 전환 (ABC ↔ 2세트 한글). 누르면 키캡이 눌렸다 튕겨 올라온다.
- **드래그** — 위치 이동, 위치는 자동 저장
- **우클릭** — 로그인 시 자동 실행 / 아이콘 새로고침 / 종료 (안 먹으면 `pkill -f LangToggle`)

**로그인 시 자동 실행**을 켜면 재부팅 후에도 뜬다(`SMAppService`).
키캡을 클릭해도 지금 쓰던 앱의 포커스는 그대로다 — 창이 `.nonactivatingPanel` 이라 입력을 뺏지 않는다.

## 아이콘 커스텀

`~/Library/Application Support/LangToggle/` 에 `ko.png`, `en.png` 를 두면 그게 우선 적용된다.
바꾼 뒤에는 우클릭 → 아이콘 새로고침.
없으면 번들 안의 기본 키캡을 쓰고, 그것도 없으면 텍스트 배지(`한`/`A`)로 폴백한다.
번들 내부를 직접 고치면 서명이 깨지므로 이 경로를 쓴다.

## 요구사항

- macOS 13 (Ventura) 이상
- **Apple Silicon (arm64) 전용** — Intel Mac 미지원
- 접근성 권한은 필요 없다. 입력 소스 전환에 Carbon `TISSelectInputSource` 를 쓴다.

## 개발

```bash
swiftc -O main.swift -o LangToggle
./LangToggle              # 번들 없이 실행 (Dock 아이콘 없음)
./LangToggle --selftest   # 토글 동작 확인
./LangToggle --dump       # 실제 표시 크기(88px) 렌더를 /tmp/langtoggle-render.png 로

./make_app.sh             # 빌드 → ad-hoc 서명 → /Applications 설치 → 실행
./make_app.sh dist        # Developer ID 서명 → 공증 → staple → build/LangToggle-<버전>.zip
```

버전은 `make_app.sh` 맨 위 `VERSION` 한 곳에서만 고친다 — Info.plist 와 zip 이름이 이걸 따라간다.
`dist` 가 끝나면 그대로 릴리스에 올린다:

```bash
gh release create v1.0.0 build/LangToggle-1.0.0.zip --title "LangToggle 1.0.0"
```

서명·공증 준비물은 `make_app.sh` 주석에 있고, notarytool 프로필이 없으면 스크립트가 등록 방법을 출력한다.

아이콘은 `build_icons.py` 가 만든다. `assets/keycap-master-v2.png` 는 우측 상단에서 본 3/4 대각선
키캡이고 윗면이 `#ff00ff` 로 비워져 있다 — 그 마커 영역을 찾아 윗면 색으로 칠하고 글리프를 원근
변환으로 얹는다. 바디를 두 아이콘이 공유하므로 실루엣이 픽셀 단위로 같아 토글할 때 흔들리지 않는다.
글리프를 바꾸려면 `OUTPUTS` 만 고치고 다시 돌린다.
색은 [halfmoon 디자인 시스템](https://github.com/halfmoon-project/halfmoon-design) 토큰을 따른다
(gray.800 바디, gray.700 윗면, gray.50 글리프, blue.600 액센트).

```bash
uv run --with pillow --with numpy python build_icons.py
```

## 라이센스

[MIT](./LICENSE)
