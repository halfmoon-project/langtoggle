"""assets/keycap-master-v2.png(3/4 대각선 키캡, 윗면이 #ff00ff 마커)에서 ko/en 아이콘을 만든다.

imagegen이 만든 키캡 바디의 RGB 음영을 그대로 쓰고, 글리프만 코드로 얹는다.
윗면 마커의 사각형을 찾아 원근 변환으로 글리프를 매핑하므로 두 아이콘의 바디는 픽셀 단위로 같다.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "assets/keycap-master-v2.png"
OUTPUTS = {"한": ROOT / "assets/ko.png", "A": ROOT / "assets/en.png"}

MARKER = (0xFF, 0x00, 0xFF)  # imagegen이 윗면에 칠한 placeholder
FACE = (0x33, 0x41, 0x55, 255)  # halfmoon gray.700 — 윗면
GLYPH = (0xF8, 0xFA, 0xFC, 255)  # gray.50
ACCENT = (0x25, 0x63, 0xEB, 255)  # blue.600
FONT_PATH = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
FONT_INDEX = 4  # SemiBold ≈ font-weight 600
FACE_SQUARE = 512  # 글리프를 그릴 정사각 캔버스 (변환 전)


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


def fitted_font(text: str, target: int) -> ImageFont.FreeTypeFont:
    low, high = 1, FACE_SQUARE
    while low < high:
        size = (low + high + 1) // 2
        bbox = ImageFont.truetype(FONT_PATH, size=size, index=FONT_INDEX).getbbox(text)
        low, high = (size, high) if bbox[3] - bbox[1] <= target else (low, size - 1)
    return ImageFont.truetype(FONT_PATH, size=low, index=FONT_INDEX)


def glyph_square(text: str) -> Image.Image:
    """변환 전 정사각 윗면에 글리프(+ 한글일 때 액센트 점)를 그린다."""
    sq = Image.new("RGBA", (FACE_SQUARE, FACE_SQUARE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(sq)
    font = fitted_font(text, round(FACE_SQUARE * 0.5))
    bbox = draw.textbbox((0, 0), text, font=font)
    draw.text(
        ((FACE_SQUARE - (bbox[2] - bbox[0])) / 2 - bbox[0],
         (FACE_SQUARE - (bbox[3] - bbox[1])) / 2 - bbox[1]),
        text, font=font, fill=GLYPH,
    )
    if text == "한":
        r = FACE_SQUARE * 0.05
        cx = cy = FACE_SQUARE * 0.82
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=ACCENT)
    return sq


def render(master: Image.Image, mask: Image.Image, quad: list, text: str) -> Image.Image:
    icon = master.copy()
    icon.paste(Image.new("RGBA", icon.size, FACE), (0, 0), mask)  # 마커 → 윗면 색
    warped = glyph_square(text).transform(
        icon.size, Image.Transform.PERSPECTIVE,
        find_coeffs(quad, [(0, 0), (FACE_SQUARE, 0), (FACE_SQUARE, FACE_SQUARE), (0, FACE_SQUARE)]),
        Image.Resampling.BICUBIC,
    )
    # 윗면 밖으로 새는 픽셀은 마스크로 잘라낸다.
    from PIL import ImageChops
    warped.putalpha(ImageChops.multiply(warped.getchannel("A"), mask))
    return Image.alpha_composite(icon, warped)


def main() -> None:
    master = Image.open(SOURCE).convert("RGBA")
    mask = face_mask(master)
    quad = face_quad(mask)
    print("top-face quad [TL, TR, BR, BL]:", [(round(x), round(y)) for x, y in quad])
    for glyph, out in OUTPUTS.items():
        out.parent.mkdir(parents=True, exist_ok=True)
        render(master, mask, quad, glyph).save(out, format="PNG", optimize=True)
        print("wrote", out)


if __name__ == "__main__":
    main()
