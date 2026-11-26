#!/usr/bin/env python3
"""Procedural sepia mountain-range wallpaper.

Every size is rendered from the same "world", so the dual-screen and
ultrawide versions show the same mountains (ultrawide = centre crop).
World units: 1.0 = image height. x=0 is the centre of the image.

usage: make_wallpaper.py OUTDIR [--seed N] [--masks-only]

Besides the images it writes, per size, the masks the live wallpaper uses
(_front cut-out, _sky = open sky, _snow = how early each spot gets snow) and,
once, plasma/wallpaper/.../contents/code/scene.js: tree and peak positions in
world units, which are the same for every size.
"""
import sys, os, argparse, json
import numpy as np
from PIL import Image, ImageFilter

SIZES = {
    "dual-1440p_5120x1440": (5120, 1440),
    "dual-1080p_3840x1080": (3840, 1080),
    "ultrawide_3440x1440": (3440, 1440),
    "ultrawide_2560x1080": (2560, 1080),
    "single_2560x1440": (2560, 1440),
    "single_1920x1080": (1920, 1080),
}

# sepia gradient map: luminance 0..1 -> colour
SEPIA = np.array([
    [0.00, 28, 18, 12],
    [0.25, 74, 50, 33],
    [0.50, 137, 101, 68],
    [0.75, 196, 160, 116],
    [0.90, 228, 204, 162],
    [1.00, 245, 232, 202],
], dtype=np.float64)


def gradient_map(lum):
    lum = np.clip(lum, 0, 1)
    out = np.empty(lum.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(lum, SEPIA[:, 0], SEPIA[:, c + 1])
    return out


class Noise1D:
    """Fractal value noise on a fixed world range (seeded, deterministic)."""
    def __init__(self, rng, lo=-4.0, hi=4.0, res=4096):
        self.lo, self.hi = lo, hi
        self.lattice = [rng.random(res) for _ in range(10)]
        self.res = res

    def _vn(self, x, freq, octave):
        t = (x - self.lo) * freq
        i = np.floor(t).astype(np.int64) % self.res
        f = t - np.floor(t)
        f = f * f * (3 - 2 * f)
        lat = self.lattice[octave]
        return lat[i] * (1 - f) + lat[(i + 1) % self.res] * f

    def fbm(self, x, base_freq, octaves=7, gain=0.5, ridged=0.0):
        total, amp, norm = 0.0, 1.0, 0.0
        for o in range(octaves):
            v = self._vn(x, base_freq * (2 ** o), o)
            if ridged:
                r = 1 - np.abs(v * 2 - 1)
                v = v * (1 - ridged) + r * r * ridged
            total = total + v * amp
            norm += amp
            amp *= gain
        return total / norm


# mountain layers, back -> front:
# (base height, amplitude, freq, ridged, tone, haze strength, detail)
LAYERS = [
    (0.50, 0.22, 0.45, 0.90, 0.76, 0.78, 0.35),
    (0.56, 0.20, 0.60, 0.85, 0.64, 0.62, 0.50),
    (0.63, 0.17, 0.80, 0.80, 0.50, 0.48, 0.65),
    (0.71, 0.13, 1.00, 0.70, 0.36, 0.34, 0.80),
    (0.80, 0.10, 1.30, 0.55, 0.22, 0.20, 0.90),
    (0.90, 0.07, 1.70, 0.35, 0.11, 0.08, 1.00),
]


def ridge_line(noise, li, x):
    """Height (0 top .. 1 bottom) of mountain layer li's ridge at world x."""
    base, amp, freq, ridged = LAYERS[li][:4]
    # bias: tallest peaks left/centre, calmer on the right where widgets sit
    bias = 0.55 + 0.45 * np.exp(-((x + 0.45) / 1.1) ** 2)
    n = noise.fbm(x + li * 7.3, freq, octaves=8, gain=0.5, ridged=ridged)
    n = (n - 0.5) / 0.12                                    # stretch contrast
    return base - amp * 0.5 * n * bias


def value_noise_2d(rng, w, h, cell):
    gw, gh = w // cell + 3, h // cell + 3
    g = rng.random((gh, gw)).astype(np.float32)
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((w + 3 * cell, h + 3 * cell), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32)[:h, :w] / 255.0


def render(W, H, seed, split=3, painted_sun=False):
    """Returns (image, front_mask, valley, sky_mask, snow_level). front_mask = coverage of layers
    >= split; valley = lowest point (0..1 from top) of the split layer's ridge; sky_mask = 1 where
    no mountain covers the sky (the live wallpaper draws clouds and stars only there);
    snow_level = 0..1 on the far layers, high where snow settles first (peaks, crests, gullies)."""
    rng = np.random.default_rng(seed)
    noise = Noise1D(rng)
    ys = (np.arange(H) / H)[:, None]                     # 0 top .. 1 bottom
    xs = ((np.arange(W) - W / 2) / H)[None, :]           # world x
    x1 = xs[0]

    # --- sky -----------------------------------------------------------
    horizon = 0.62
    sky = 0.93 - 0.42 * np.clip((horizon - ys) / horizon, 0, 1) ** 0.9
    sky = np.broadcast_to(sky, (H, W)).copy()

    # The live wallpaper draws the sun where it really is, so by default it isn't painted in.
    # --painted-sun gives the original look (a low sun on the left) for a static wallpaper.
    sun_x, sun_y, sun_r = -0.78, 0.40, 0.055
    d = np.sqrt((xs - sun_x) ** 2 + (ys - sun_y) ** 2)
    if painted_sun:
        sky += 0.22 * np.exp(-(d / 0.16) ** 2) + 0.10 * np.exp(-(d / 0.6) ** 2)
        sky = np.where(d < sun_r, 1.05, sky)
        sky += 0.06 * np.clip(1 - (d - sun_r) / 0.012, 0, 1) * (d >= sun_r)

    # wispy cloud bands (stretched noise, seeded independent of size)
    crng = np.random.default_rng(seed + 1)
    cl = np.zeros((H, W))
    for k, (yc, th, amp) in enumerate([(0.12, 0.05, 0.07), (0.22, 0.035, 0.06), (0.31, 0.03, 0.05)]):
        n = Noise1D(crng).fbm(x1 * 1.0 + k * 3.1, 1.4, octaves=6)
        band = np.exp(-((ys - yc - (n[None, :] - 0.5) * 0.06) / th) ** 2)
        cl += amp * band * np.clip((n[None, :] - 0.42) * 3, 0, 1)
    sky += cl

    img = sky
    front = np.zeros((H, W))
    ground = np.zeros((H, W))
    snowlv = np.zeros((H, W))
    valley = 1.0
    # vertical streaks (gullies) for the snow level; own generator so the image is unchanged
    srng = np.random.default_rng(seed + 11)
    cx, cy = max(2, H // 220), max(8, H // 28)
    g = srng.random((H // cy + 3, W // cx + 3))
    streak = np.asarray(Image.fromarray((g * 255).astype(np.uint8)).resize((W + 3 * cx, H + 3 * cy), Image.BICUBIC),
                        np.float32)[:H, :W] / 255

    # --- mountain layers (back -> front) --------------------------------
    layers = LAYERS
    tex = value_noise_2d(np.random.default_rng(seed + 7), W, H, max(2, H // 250))

    def smooth(a, sigma_world):
        s = max(1.0, sigma_world * H)
        k = np.arange(-int(3 * s), int(3 * s) + 1)
        g = np.exp(-(k / s) ** 2 / 2); g /= g.sum()
        return np.convolve(np.pad(a, len(k) // 2, mode="edge"), g, mode="valid")

    for li, (base, amp, freq, ridged, tone, haze, detail) in enumerate(layers):
        ridge = ridge_line(noise, li, x1)
        # lighting from left, at two scales, from smoothed slopes
        s1 = np.gradient(smooth(ridge, 0.004)) * H
        s2 = np.gradient(smooth(ridge, 0.02)) * H
        lit0 = -(s1 * 0.6 + s2 * 1.4) * 1.5
        # blur the lighting more the further below the ridge we are, so the
        # light/shadow split fans out instead of making vertical curtains
        sig = [0.0, 0.01, 0.03, 0.08]
        lits = np.stack([np.tanh(lit0 if g == 0 else smooth(lit0, g)) for g in sig])
        dy = ys - ridge[None, :]
        t = np.clip(dy / 0.06, 0, len(sig) - 1.001)               # (H, W)
        i0 = np.floor(t).astype(int); fr = t - i0
        cols = np.arange(W)[None, :]
        litmap = lits[i0, cols] * (1 - fr) + lits[i0 + 1, cols] * fr
        lit = lits[0]
        fall = np.exp(-np.clip(dy, 0, None) / (0.08 + 0.03 * li))
        shade = tone + detail * 0.13 * litmap * fall
        shade = shade + (tex - 0.5) * 0.06 * detail * (0.4 + 0.6 * fall)
        # snow caps on the far, tall layers: bright band just under lit peaks
        if li < 3:
            peak = np.clip((base - ridge) / (amp * 0.5), 0, 1)       # higher = 1
            snow = np.clip(1 - dy / (0.035 * (1 + peak[None, :])), 0, 1) * (dy >= 0)
            snow = snow * np.clip(lit[None, :] + 0.3, 0, 1) * peak[None, :] ** 1.5
            shade = shade + 0.20 * snow * (1 - li / 3) * (0.7 + 0.6 * tex)
        # valley mist pooling at the base of each layer
        mist = np.clip(1 - np.abs(ys - (base + 0.07)) / 0.09, 0, 1) ** 2 * haze * 0.6
        layer = shade * (1 - haze * 0.2) + 0.88 * haze * 0.2
        layer = layer * (1 - mist) + 0.86 * mist

        edge = np.clip(dy * H + 0.5, 0, 1)                       # anti-aliased edge
        img = img * (1 - edge) + layer * edge
        ground = ground + edge * (1 - ground)
        # snow level: altitude first, then crests and gullies; the nearer hills never get it
        lv = 0.0
        if li < split:
            alt = np.clip((0.66 - ys) / 0.36, 0, 1)
            crest = np.clip(1 - dy / 0.03, 0, 1) * (dy >= 0)
            lv = np.clip(alt * 0.9 + 0.06 * (split - 1 - li) / max(1, split - 1)
                         + 0.09 * (streak - 0.5) + 0.04 * (tex - 0.5) + 0.08 * crest, 0, 1)
        snowlv = snowlv * (1 - edge) + lv * edge
        if li >= split:
            front = front + edge * (1 - front)
        if li == split:
            valley = float(ridge.max())

    # --- finishing ------------------------------------------------------
    # god-ray-ish glow from sun over everything
    if painted_sun:
        img = img + 0.04 * np.exp(-(d / 0.5) ** 2)
    # vignette
    vx = xs / (W / H / 2)
    v = 1 - 0.28 * np.clip(vx ** 2 * 0.6 + ((ys - 0.5) * 2) ** 2 * 0.5, 0, 1)
    img = img * v
    # film grain
    grain = np.random.default_rng(seed + 99).normal(0, 0.012, (H, W))
    img = img + grain

    rgb = gradient_map(img)
    out = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")
    out = out.filter(ImageFilter.UnsharpMask(radius=1.2, percent=40, threshold=2))
    return out, front, valley, 1 - ground, snowlv


def scene(seed, split=3):
    """Trees on the nearer hills and the tallest far peaks, in world units, for the live
    wallpaper. Uses the same ridge lines as render(), so they sit exactly on the art."""
    noise = Noise1D(np.random.default_rng(seed))               # same draw order as render()
    rng = np.random.default_rng(seed + 21)
    xs = np.arange(-1.85, 1.85, 0.0005)
    ridges = [ridge_line(noise, li, xs) for li in range(len(LAYERS))]
    forest = Noise1D(np.random.default_rng(seed + 22)).fbm(xs, 1.6, octaves=5)
    trees = []
    # (layer, trees per world unit at full density, height range)
    for li, rate, (h0, h1) in ((3, 150, (0.010, 0.016)), (4, 120, (0.015, 0.024)), (5, 90, (0.022, 0.036))):
        if li < split:
            continue
        dens = np.clip((forest - 0.42) * 3.5, 0, 1) * rate * 0.0005
        for i in np.nonzero(rng.random(len(xs)) < dens)[0]:
            h = rng.uniform(h0, h1)
            y = ridges[li][i] + min(rng.exponential(0.006), 0.03) + h * 0.06
            w = int(h * 0.35 / 0.0005) + 1
            lo, hi = max(0, i - w), min(len(xs), i + w + 1)
            # skip trees a nearer hill would hide
            if any((ridges[lj][lo:hi] < y + 0.002).any() for lj in range(li + 1, len(LAYERS))):
                continue
            conifer = rng.random() < 0.45
            trees.append((round(float(xs[i]), 4), round(float(y), 4), round(h, 4), li,
                          0 if conifer else 1, int(rng.integers(0, 2 if conifer else 3)), int(rng.integers(0, 2))))
    trees.sort(key=lambda t: (t[3], t[1]))
    # peaks: highest points of the far ridges that nothing nearer covers
    peaks = []
    for li in range(min(3, split)):
        r = ridges[li]
        for i in np.argsort(r)[:6000]:
            if r[i] > 0.56 or any(abs(xs[i] - p[0]) < 0.2 for p in peaks):
                continue
            if all(ridges[lj][i] > r[i] + 0.01 for lj in range(li + 1, len(LAYERS))):
                alt = float(np.clip((0.66 - r[i]) / 0.36, 0, 1))
                peaks.append((round(float(xs[i]), 4), round(float(r[i]), 4), round(alt, 3)))
            if len(peaks) >= 4 * (li + 1):
                break
    return trees, peaks


def write_scene(path, seed, split):
    trees, peaks = scene(seed, split)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(f"""// Generated by tools/make_wallpaper.py (seed {seed}, split {split}). Don't edit by hand.
// World units: 1.0 = image height, x = 0 is the image centre (the same for every size).
.pragma library
// [x, base y, height, mountain layer, kind 0 conifer / 1 deciduous, shape, mirrored]
var trees = {json.dumps(trees, separators=(",", ":"))}
// [x, y, altitude 0..1] tops of the tall far ridges (blowing snow comes off these)
var peaks = {json.dumps(peaks, separators=(",", ":"))}
""")
    print("wrote", path, f"({len(trees)} trees, {len(peaks)} peaks)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir")
    ap.add_argument("--seed", type=int, default=1942)
    ap.add_argument("--only", default=None)
    ap.add_argument("--split", type=int, default=3, help="first mountain layer drawn in front of the visualiser (0=far .. 5=near)")
    ap.add_argument("--masks-only", "--sky-only", dest="masks_only", action="store_true",
                    help="write only the _sky/_snow masks and scene.js, leave the wallpapers alone")
    ap.add_argument("--painted-sun", action="store_true", help="paint the sun into the images (static use)")
    ap.add_argument("--scene", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                    "plasma/wallpaper/com.nexuskiwi.sepiasummit/contents/code/scene.js"))
    a = ap.parse_args()
    os.makedirs(a.outdir, exist_ok=True)
    write_scene(os.path.normpath(a.scene), a.seed, a.split)
    for name, (w, h) in SIZES.items():
        if a.only and a.only not in name:
            continue
        im, front, valley, sky, snowlv = render(w, h, a.seed, a.split, a.painted_sun)
        p = os.path.join(a.outdir, f"sepia-mountains_{name}.png")
        # sky mask for the live wallpaper's weather (clouds, stars stay behind the mountains)
        # (white, alpha = sky) because Qt's MultiEffect masks by alpha
        sk = Image.merge("LA", (Image.new("L", (w, h), 255),
                                Image.fromarray((np.clip(sky, 0, 1) * 255).astype(np.uint8), "L")))
        # snow level, same format: the wallpaper shows snow where alpha > 1 - (snow amount)
        sn = Image.merge("LA", (Image.new("L", (w, h), 255),
                                Image.fromarray((np.clip(snowlv, 0, 1) * 255).astype(np.uint8), "L")))
        for m, suffix in ((sk, "_sky"), (sn, "_snow")):
            m.save(p.replace(".png", suffix + ".png"), optimize=True)
            if name.startswith("dual"):
                for side, box in (("LEFT", (0, 0, w // 2, h)), ("RIGHT", (w // 2, 0, w, h))):
                    m.crop(box).save(p.replace(".png", f"_{side}{suffix}.png"), optimize=True)
        if a.masks_only:
            print("wrote", p.replace(".png", "_sky.png"), "+ _snow")
            continue
        im.save(p, optimize=True)
        # cut-out of the nearer ranges, for the live wallpaper's top layer
        fg = im.convert("RGBA")
        fg.putalpha(Image.fromarray((np.clip(front, 0, 1) * 255).astype(np.uint8)))
        fp = p.replace(".png", "_front.png")
        fg.save(fp, optimize=True)
        print("wrote", p, "+ front  (valley line %.3f)" % valley)
        if name.startswith("dual"):
            for side, box in (("LEFT", (0, 0, w // 2, h)), ("RIGHT", (w // 2, 0, w, h))):
                im.crop(box).save(p.replace(".png", f"_{side}.png"), optimize=True)
                fg.crop(box).save(p.replace(".png", f"_{side}_front.png"), optimize=True)

if __name__ == "__main__":
    main()
