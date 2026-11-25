#!/usr/bin/env python3
"""Weather sprites for the live wallpaper (numpy + Pillow, like make_wallpaper.py).

Writes into plasma/wallpaper/com.nexuskiwi.sepiasummit/contents/images/:
  cloud1..5.png   soft sepia cumulus, lit from the left like the mountains
  stratus1..2.png long thin cloud bands for overcast skies
  rain.png        one rain streak      snow.png   one soft flake
  veil.png        soft haze laid over the painted sun on cloudy days
  trees.png       tree sprite sheet: a row per hill (layers 3, 4, 5, coloured like that hill)
                  and 16 columns: conifer A, B, A snowy, B snowy, then three deciduous trees
                  in summer, autumn, winter, spring (same branches, so the seasons blend)
  leaf.png        one falling autumn leaf
Usage: make_weather_assets.py [--seed N]
"""
import argparse, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_wallpaper import gradient_map            # the wallpaper's sepia colours

OUT = os.path.join(os.path.dirname(__file__), "..", "plasma/wallpaper/com.nexuskiwi.sepiasummit/contents/images")
LIGHT = np.array([0xf2, 0xe2, 0xc4]) / 255     # sunlit tops (near the cream text colour)
SHADE = np.array([0x8e, 0x6e, 0x52]) / 255     # undersides (between dim labels and dark base)


def fbm(rng, w, h, cell, octaves=5):
    """Smooth value noise in 0..1, built by upscaling random grids."""
    out = np.zeros((h, w))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = max(1, cell >> o)
        g = rng.random((h // c + 2, w // c + 2))
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((w + 2 * c, h + 2 * c), Image.BICUBIC)
        out += amp * (np.asarray(im, float)[c:c + h, c:c + w] / 255)
        total += amp
        amp *= 0.5
    return out / total


def cumulus(rng, w=1000, h=460):
    ys, xs = np.mgrid[0:h, 0:w].astype(float)
    dens = np.zeros((h, w))
    base = h * 0.74                                       # flat-ish bottom
    for _ in range(rng.integers(8, 13)):                  # stacked puffs, biggest in the middle
        cx = rng.normal(w / 2, w * 0.15)
        r = rng.uniform(0.09, 0.17) * w * (1 - 1.2 * abs(cx - w / 2) / w)
        cy = base - r * rng.uniform(0.3, 0.9)
        dens += np.exp(-(((xs - cx) / (r * 1.25)) ** 2 + ((ys - cy) / (r * 0.75)) ** 2) * 1.4)
    dens *= np.clip((base + h * 0.05 - ys) / (h * 0.14), 0, 1)   # soft flat base
    dens = dens * (0.85 + 0.3 * fbm(rng, w, h, 96, octaves=4))
    alpha = 0.85 * np.clip((dens - 0.3) * 1.3, 0, 1) ** 1.4
    # light from the upper left (like the sun in the wallpaper): edges facing it are brighter
    up_left = np.roll(dens, (14, 14), (0, 1))             # density of the up-left neighbour
    lit = np.clip(0.6 + 0.8 * (dens - up_left) + 0.35 * (1 - ys / base), 0, 1)
    return to_rgba(lit, alpha, blur=5)


def stratus(rng, w=2400, h=260):
    ys, xs = np.mgrid[0:h, 0:w].astype(float)
    n = fbm(rng, w, h, 128)
    stretch = np.asarray(Image.fromarray((fbm(rng, w // 8, h, 32) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), float) / 255
    band = np.exp(-((ys - h / 2 - (n - 0.5) * h * 0.5) / (h * 0.22)) ** 2)
    alpha = np.clip((band * (0.4 + stretch) - 0.35) * 1.4, 0, 1)
    alpha *= np.clip(np.minimum(xs, w - xs) / (w * 0.15), 0, 1)   # fade the ends
    lit = np.clip(0.75 - 0.4 * (ys / h) + 0.15 * n, 0, 1)
    return to_rgba(lit, alpha, blur=3)


def to_rgba(lit, alpha, blur):
    rgb = SHADE[None, None, :] * (1 - lit[..., None]) + LIGHT[None, None, :] * lit[..., None]
    im = Image.fromarray((np.dstack([rgb, alpha]) * 255).astype(np.uint8), "RGBA")
    return im.filter(ImageFilter.GaussianBlur(blur))


def rain():
    """A thin, faint streak in a square image: Qt draws every particle as a square, so a
    tall narrow image would be stretched into a blob."""
    s = 64
    ys = np.linspace(0, 1, s)[:, None]
    xs = np.arange(s) - (s - 1) / 2
    a = (ys ** 1.2) * np.exp(-(xs / 0.7) ** 2)[None, :] * (ys > 0.1)
    return Image.fromarray((np.dstack([np.ones((s, s, 3)), a]) * 255).astype(np.uint8), "RGBA")


def snow():
    s = 24
    ys, xs = np.mgrid[0:s, 0:s] - (s - 1) / 2
    a = np.clip(1 - np.sqrt(xs ** 2 + ys ** 2) / (s / 2), 0, 1) ** 1.6
    return Image.fromarray((np.dstack([np.ones((s, s, 3)), a]) * 255).astype(np.uint8), "RGBA")


def veil(colour=(0xa0, 0x80, 0x5e), s=512):
    """Soft round haze in the overcast sky colour, laid over the painted sun when it's cloudy."""
    ys, xs = np.mgrid[0:s, 0:s] - (s - 1) / 2
    a = np.exp(-((xs ** 2 + ys ** 2) / (s * 0.26) ** 2))
    a *= np.clip(1 - np.sqrt(xs ** 2 + ys ** 2) / (s / 2), 0, 1)        # reach 0 at the edge
    rgb = np.broadcast_to(np.array(colour) / 255, (s, s, 3))
    return Image.fromarray((np.dstack([rgb, a]) * 255).astype(np.uint8), "RGBA")


CELL, SS = 128, 3                       # sprite cell size, supersampling
# per hill: (trunk/foliage luminance, snow luminance); a little darker than the hill itself
TREE_TONES = {3: (0.33, 0.62), 4: (0.19, 0.60), 5: (0.085, 0.56)}


def conifer(rng, snowy, tone, snow_tone):
    C = CELL * SS
    ys, xs = np.mgrid[0:C, 0:C].astype(float)
    cx, base, h = C / 2, C - 2 * SS, C * 0.94
    t = (base - ys) / h                                         # 0 at the base .. 1 at the tip
    tiers = rng.integers(5, 8)
    frac = (t * tiers) % 1                                      # 0 at the bottom of each tier
    rag = 1 + 0.16 * (fbm(rng, C, C, 6 * SS, octaves=3) - 0.5)
    width = np.clip(1 - t, 0, 1) ** 0.85 * C * 0.23 * (0.7 + 0.3 * (1 - frac)) * rag
    foliage = (np.abs(xs - cx) < width) & (t > 0.06) & (t < 1)
    trunk = (np.abs(xs - cx) < C * 0.02) & (t >= 0) & (t <= 0.1)
    a = (foliage | trunk).astype(float)
    lum = tone + 0.05 * np.clip((cx - xs) / (C * 0.2), -1, 1) - 0.03 * (1 - frac) ** 3
    if snowy:
        lay = foliage & (frac > 0.05) & (frac < 0.38) & (fbm(rng, C, C, 3 * SS, octaves=2) > 0.42)
        lum = np.where(lay | (foliage & (t > 0.9)), snow_tone - 0.06 * (xs > cx), lum)
    return lum, a


def deciduous(rng, tone, snow_tone):
    """Returns the four seasons of one tree (summer, autumn, winter, spring) as (lum, alpha)."""
    C = CELL * SS
    cx, base, h = C / 2, C - 2 * SS, C * 0.92
    wood = Image.new("L", (C, C), 0)
    d = ImageDraw.Draw(wood)
    tips = []

    def branch(x, y, ang, length, width, depth):
        x2, y2 = x + np.sin(ang) * length, y - np.cos(ang) * length
        d.line([(x, y), (x2, y2)], fill=255, width=max(1, int(width)))
        if depth == 0 or length < 2 * SS:
            tips.append((x2, y2))
            return
        for k in range(2 if depth > 1 else 3):
            spread = rng.uniform(0.3, 0.6) * (1 if k % 2 else -1)
            branch(x2, y2, ang * 0.6 + spread, length * rng.uniform(0.6, 0.7), width * 0.65, depth - 1)

    trunk = h * rng.uniform(0.32, 0.4)
    d.line([(cx, base), (cx, base - trunk * 0.5)], fill=255, width=int(C * 0.045))
    branch(cx, base - trunk * 0.5, rng.normal(0, 0.05), trunk * 0.55, C * 0.04, 5)
    ys, xs = np.mgrid[0:C, 0:C].astype(float)
    crown_y, rx, ry = base - h * 0.64, h * rng.uniform(0.27, 0.34), h * 0.32
    dens = np.exp(-(((xs - cx) / rx) ** 2 + ((ys - crown_y) / ry) ** 2) * 1.4)
    for tx, ty in tips:
        dens += 0.3 * np.exp(-(((xs - tx) ** 2 + (ys - ty) ** 2) / (C * 0.04) ** 2))
    dens *= 0.8 + 0.4 * fbm(rng, C, C, 8 * SS, octaves=3)
    # keep the crown well inside its cell: a soft rounded envelope
    env = ((xs - cx) / (C * 0.46)) ** 2 + ((ys - (crown_y + h * 0.02)) / (h * 0.42)) ** 2
    dens *= np.clip((1 - env) * 4, 0, 1)
    wood = wood.copy()
    wmask = np.asarray(wood, float) * np.clip((1 - env) * 6, 0, 1) ** 0.3
    wood = Image.fromarray(np.where(ys > crown_y, np.asarray(wood, float), wmask).astype(np.uint8))
    holes = fbm(rng, C, C, 5 * SS, octaves=2)
    specks = rng.random((C, C))
    w = np.asarray(wood, float) / 255
    lit = 0.05 * np.clip((cx - xs) / rx, -1, 1) + 0.04 * np.clip((crown_y - ys) / ry, -1, 1)
    out = []
    for season in ("summer", "autumn", "winter", "spring"):
        leaves = {"summer": dens > 0.55, "autumn": (dens > 0.58) & (holes > 0.3),
                  "winter": np.zeros_like(dens, bool), "spring": dens > 0.6}[season]
        shade = {"summer": 0.0, "autumn": 0.09, "winter": 0.0, "spring": 0.035}[season]
        lum = np.where(leaves, tone + shade + lit, tone - 0.02)
        if season == "spring":                      # pale blossom flecks
            lum = np.where(leaves & (specks < 0.025), tone + 0.25, lum)
        out.append((lum, np.maximum(w, leaves.astype(float))))
    return out


def trees(rng):
    cols = 16
    sheet = Image.new("RGBA", (CELL * cols, CELL * 3))
    for row, layer in enumerate((3, 4, 5)):
        tone, snow_tone = TREE_TONES[layer]
        sprites = []
        for k in range(2):                                      # conifers, then snowy twins
            seed = int(rng.integers(1 << 30))
            sprites.append((seed, False))
        sprites += [(s, True) for s, _ in sprites]
        cells = [conifer(np.random.default_rng(s), snowy, tone, snow_tone) for s, snowy in sprites]
        for k in range(3):
            cells += deciduous(np.random.default_rng(int(rng.integers(1 << 30))), tone, snow_tone)
        for col, (lum, a) in enumerate(cells):
            rgb = gradient_map(lum)
            im = Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8), "RGBA")
            im = im.resize((CELL, CELL), Image.LANCZOS)
            sheet.paste(im, (col * CELL, row * CELL))
    return sheet


def leaf(s=32):
    ys, xs = np.mgrid[0:s, 0:s] - (s - 1) / 2
    u, v = (xs + ys) / np.sqrt(2), (xs - ys) / np.sqrt(2)          # diagonal leaf
    a = np.clip(1 - (u / (s * 0.42)) ** 2 - (v / (s * 0.17)) ** 2, 0, 1) ** 0.5
    lum = 0.42 + 0.08 * np.clip(-v / (s * 0.17), -1, 1) - 0.1 * (np.abs(v) < 0.8)   # midrib
    rgb = gradient_map(lum)
    return Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8), "RGBA")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1942)
    a = ap.parse_args()
    rng = np.random.default_rng(a.seed + 300)
    os.makedirs(OUT, exist_ok=True)
    for i in range(1, 6):
        cumulus(rng).save(os.path.join(OUT, f"cloud{i}.png"), optimize=True)
    for i in range(1, 3):
        stratus(rng).save(os.path.join(OUT, f"stratus{i}.png"), optimize=True)
    rain().save(os.path.join(OUT, "rain.png"))
    snow().save(os.path.join(OUT, "snow.png"))
    veil().save(os.path.join(OUT, "veil.png"), optimize=True)
    trees(np.random.default_rng(a.seed + 400)).save(os.path.join(OUT, "trees.png"), optimize=True)
    leaf().save(os.path.join(OUT, "leaf.png"), optimize=True)
    print("wrote", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
