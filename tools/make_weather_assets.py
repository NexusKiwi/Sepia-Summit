#!/usr/bin/env python3
"""Weather sprites for the live wallpaper (numpy + Pillow, like make_wallpaper.py).

Writes into plasma/wallpaper/com.nexuskiwi.sepiasummit/contents/images/:
  cloud1..5.png   soft sepia cumulus, lit from the left like the mountains
  stratus1..2.png long thin cloud bands for overcast skies
  rain.png        one rain streak      snow.png   one soft flake
  veil.png        soft haze laid over the painted sun on cloudy days
Usage: make_weather_assets.py [--seed N]
"""
import argparse, os
import numpy as np
from PIL import Image, ImageFilter

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
    print("wrote", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
