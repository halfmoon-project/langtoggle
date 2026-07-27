"""assets/design/keycap-master-v2.png(3/4 대각선 키캡, 윗면이 #ff00ff 마커)에서 아이콘을 만든다.

바디는 모든 언어가 똑같으므로 `keycap.png` 한 장만 굽고, 언어별로는 투명 배경에
글리프만 얹은 레이어를 굽는다. main.swift 가 둘을 겹쳐 그린다 — 언어를 늘려도
바디가 중복되지 않아 번들이 언어당 몇 KB 씩만 는다.

imagegen이 만든 키캡 바디의 RGB 음영은 그대로 쓰고, 글리프만 코드로 얹는다.
윗면 마커의 사각형을 찾아 원근 변환으로 매핑하므로 바디와 글리프가 정확히 맞물린다.

    uv run --with pillow --with numpy --with fonttools python build_icons.py
"""

from functools import lru_cache
from pathlib import Path

import numpy as np
from fontTools.ttLib import TTCollection, TTFont
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "assets/design/keycap-master-v2.png"
OUT = ROOT / "assets"
APPICON = ROOT / "assets/design/appicon.png"  # .icns 용 원본. 번들엔 안 들어간다.

# 언어 코드 → 키캡에 얹을 글리프. main.swift 의 `glyphs` 와 같이 고쳐야 한다.
# 코드는 입력 소스의 kTISPropertyInputSourceLanguages 첫 값이다. 라틴 자판을 쓰는
# 언어(독일어·프랑스어…)는 여기 없어도 en 으로 폴백되니 넣지 않는다.
GLYPHS = {
    "en": "A",
    "ko": "한",
    "ja": "あ",
    "zh": "中",
    "ru": "Я",
    "el": "Ω",
    "th": "ก",
    "ar": "ع",
    "he": "א",
    "hi": "अ",
    "vi": "Ư",
}

# (경로, .ttc 인덱스). 키캡 굵기(SemiBold/W6)에 맞춰 스크립트별로 고른다.
# 전용 폰트에 없는 글리프는 Arial Unicode MS 로 떨어진다 — 위 글리프를 전부 가진
# 유일한 시스템 폰트지만 Regular 한 종류뿐이라 우선순위가 맨 뒤다.
SD_GOTHIC = ("/System/Library/Fonts/AppleSDGothicNeo.ttc", 4)  # SemiBold
HIRAGINO = ("/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc", 0)  # Hiragino Sans W6
HIRAGINO_GB = ("/System/Library/Fonts/Hiragino Sans GB.ttc", 2)  # W6
KOHINOOR = ("/System/Library/Fonts/Kohinoor.ttc", 2)  # Devanagari SemiBold
GEEZA = ("/System/Library/Fonts/GeezaPro.ttc", 1)  # Bold
ARIAL_UNICODE = ("/System/Library/Fonts/Supplemental/Arial Unicode.ttf", 0)

FONTS = {"ja": HIRAGINO, "zh": HIRAGINO_GB, "hi": KOHINOOR, "ar": GEEZA}
FALLBACKS = [SD_GOTHIC, ARIAL_UNICODE]

MARKER = (0xFF, 0x00, 0xFF)  # imagegen이 윗면에 칠한 placeholder
FACE = (0x33, 0x41, 0x55, 255)  # halfmoon gray.700 — 윗면
GLYPH = (0xF8, 0xFA, 0xFC, 255)  # gray.50
ACCENT = (0x25, 0x63, 0xEB, 255)  # blue.600
FACE_SQUARE = 512  # 글리프를 그릴 정사각 캔버스 (변환 전)
GLYPH_HEIGHT = round(FACE_SQUARE * 0.5)
GLYPH_MAX_WIDTH = round(FACE_SQUARE * 0.62)  # ع·ก 처럼 납작하고 넓은 글자용 상한
ICON_PX = 176  # 패널이 44pt 라 레티나에서 88px. 그 이상은 용량만 먹는다.


def face_mask(img: Image.Image) -> Image.Image:
    """윗면 마커(#ff00ff) 영역 마스크. 압축·안티에일리어싱을 감안해 넉넉히 판정한다."""
    a = np.asarray(img.convert("RGB"), dtype=np.int16)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    hit = (r > 150) & (b > 150) & (g < 110) & (abs(r - b) < 90)
    if hit.sum() < 1000:
        raise RuntimeError("윗면 마커(#ff00ff)를 못 찾았다 — 마스터를 다시 생성해야 한다.")
    return Image.fromarray((hit * 255).astype(np.uint8), mode="L")


def face_quad(mask: Image.Image) -> list[tuple[float, float]]:
    """마스크의 볼록 사각형 꼭짓점을 대각선 극값으로 찾아 [TL, TR, BR, BL] 순서로 반환."""
    ys, xs = np.nonzero(np.asarray(mask) > 127)
    s, d = xs + ys, xs - ys
    pick = lambda i: (float(xs[i]), float(ys[i]))
    return [pick(s.argmin()), pick(d.argmax()), pick(s.argmax()), pick(d.argmin())]


def find_coeffs(dst: list, src: list) -> np.ndarray:
    """PIL PERSPECTIVE 계수 — 출력 좌표를 입력 좌표로 되돌리는 매핑."""
    m = []
    for (dx, dy), (sx, sy) in zip(dst, src):
        m.append([dx, dy, 1, 0, 0, 0, -sx * dx, -sx * dy])
        m.append([0, 0, 0, dx, dy, 1, -sy * dx, -sy * dy])
    return np.linalg.solve(np.array(m, dtype=float), np.array(src, dtype=float).reshape(8))


@lru_cache(maxsize=None)
def covered(path: str, index: int) -> frozenset:
    font = TTCollection(path).fonts[index] if path.endswith(".ttc") else TTFont(path)
    return frozenset(font.getBestCmap())


def font_for(lang: str, text: str) -> tuple[str, int]:
    """글리프를 실제로 가진 첫 폰트. 없으면 두부(.notdef)가 구워지므로 여기서 끊는다."""
    for font in ([FONTS[lang]] if lang in FONTS else []) + FALLBACKS:
        if Path(font[0]).exists() and all(ord(c) in covered(*font) for c in text):
            return font
    raise RuntimeError(f"{lang}: {text!r} 를 가진 폰트가 시스템에 없다")


def fitted_font(font: tuple[str, int], text: str) -> ImageFont.FreeTypeFont:
    """글리프 높이를 GLYPH_HEIGHT 에 맞춘다. 폭이 상한을 넘으면 폭 기준으로 한 번 더 줄인다."""
    path, index = font
    at = lambda size: ImageFont.truetype(path, size=size, index=index)
    low, high = 1, FACE_SQUARE
    while low < high:
        size = (low + high + 1) // 2
        bbox = at(size).getbbox(text)
        low, high = (size, high) if bbox[3] - bbox[1] <= GLYPH_HEIGHT else (low, size - 1)
    bbox = at(low).getbbox(text)
    if (width := bbox[2] - bbox[0]) > GLYPH_MAX_WIDTH:
        low = max(1, low * GLYPH_MAX_WIDTH // width)
    return at(low)


def glyph_square(lang: str, text: str) -> Image.Image:
    """변환 전 정사각 윗면에 글리프(+ 라틴 자판이 아니면 액센트 점)를 그린다."""
    sq = Image.new("RGBA", (FACE_SQUARE, FACE_SQUARE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(sq)
    font = fitted_font(font_for(lang, text), text)
    bbox = draw.textbbox((0, 0), text, font=font)
    draw.text(
        ((FACE_SQUARE - (bbox[2] - bbox[0])) / 2 - bbox[0],
         (FACE_SQUARE - (bbox[3] - bbox[1])) / 2 - bbox[1]),
        text, font=font, fill=GLYPH,
    )
    if lang != "en":
        r = FACE_SQUARE * 0.05
        cx = cy = FACE_SQUARE * 0.82
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=ACCENT)
    return sq


def glyph_layer(size: tuple[int, int], quad: list, mask: Image.Image, lang: str, text: str) -> Image.Image:
    """윗면에 원근 변환으로 얹힌 글리프만 담은 투명 레이어."""
    warped = glyph_square(lang, text).transform(
        size, Image.Transform.PERSPECTIVE,
        find_coeffs(quad, [(0, 0), (FACE_SQUARE, 0), (FACE_SQUARE, FACE_SQUARE), (0, FACE_SQUARE)]),
        Image.Resampling.BICUBIC,
    )
    # 윗면 밖으로 새는 픽셀은 마스크로 잘라낸다.
    warped.putalpha(ImageChops.multiply(warped.getchannel("A"), mask))
    return warped


def save(img: Image.Image, path: Path, px: int = ICON_PX) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.resize((px, px), Image.Resampling.LANCZOS).save(path, format="PNG", optimize=True)
    print(f"  {path.relative_to(ROOT)!s:24} {path.stat().st_size / 1024:5.1f} KB")


def main() -> None:
    master = Image.open(SOURCE).convert("RGBA")
    mask = face_mask(master)
    quad = face_quad(mask)
    print("top-face quad [TL, TR, BR, BL]:", [(round(x), round(y)) for x, y in quad])

    keycap = master.copy()
    keycap.paste(Image.new("RGBA", keycap.size, FACE), (0, 0), mask)  # 마커 → 윗면 색
    save(keycap, OUT / "keycap.png")

    for lang, text in GLYPHS.items():
        layer = glyph_layer(master.size, quad, mask, lang, text)
        save(layer, OUT / f"{lang}.png")
        if lang == "ko":
            # .icns 는 1024px 까지 요구해서 축소 전 합성본을 따로 남긴다.
            save(Image.alpha_composite(keycap, layer), APPICON, px=master.size[0])

    total = sum(p.stat().st_size for p in OUT.glob("*.png"))
    print(f"번들에 들어가는 assets/*.png 합계: {total / 1024:.1f} KB")


if __name__ == "__main__":
    main()
