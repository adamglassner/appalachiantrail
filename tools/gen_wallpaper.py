#!/usr/bin/env python3
"""Paints the title-menu wallpaper: layered Blue Ridge ridgelines at golden hour,
valley mist, and a thru-hiker on a rocky overlook. Output is split into parallax
layers in ../art/menu/ (sky, far, mid, near, fore, mist).  Requires numpy + Pillow.

    python3 tools/gen_wallpaper.py
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 2560, 1440
SS = 2                      # supersampling for smooth edges
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "menu")
rng = np.random.default_rng(2198)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ---------------------------------------------------------------- palette (October golden hour)
SKY_TOP = hexc("1b2f52")
SKY_MID = hexc("6d6f9a")
SKY_GLOW = hexc("f2a766")
SKY_HORIZON = hexc("fbd9a4")
SUN = hexc("fff3d6")
HAZE = hexc("e9c3a6")       # what distant ridges fade toward
SUN_X, SUN_Y = 0.71, 0.47   # fraction of the frame


def value_noise(n, freq, seed):
    r = np.random.default_rng(seed)
    pts = r.uniform(-1, 1, int(n * freq) + 3)
    x = np.arange(n) * freq
    i = np.floor(x).astype(int)
    f = x - i
    f = f * f * (3 - 2 * f)
    return pts[i] * (1 - f) + pts[i + 1] * f


def ridge_profile(n, base, amp, seed, roughness=0.5):
    y = np.full(n, base, dtype=float)
    a = amp
    freq = 1.6 / n
    for o in range(7):
        y += value_noise(n, freq, seed + o * 31) * a
        a *= roughness
        freq *= 2.1
    # a couple of broad rounded summits
    r = np.random.default_rng(seed)
    x = np.arange(n)
    for _ in range(3):
        c = r.uniform(0, n)
        wdt = r.uniform(0.08, 0.2) * n
        y -= amp * r.uniform(0.3, 0.8) * np.exp(-((x - c) / wdt) ** 2)
    return y


def sky_layer():
    w, h = W, H
    y = np.linspace(0, 1, h)[:, None]
    x = np.linspace(0, 1, w)[None, :]
    top = np.array(SKY_TOP, float)
    mid = np.array(SKY_MID, float)
    glow = np.array(SKY_GLOW, float)
    hor = np.array(SKY_HORIZON, float)
    t = np.clip(y / 0.62, 0, 1)
    col = np.where(t[..., None] < 0.45,
                   top + (mid - top) * (t[..., None] / 0.45),
                   mid + (glow - mid) * ((t[..., None] - 0.45) / 0.55))
    col = np.where(y[..., None] > 0.62, glow + (hor - glow) * np.clip((y[..., None] - 0.62) / 0.15, 0, 1), col)
    col = np.broadcast_to(col, (h, w, 3)).copy()
    # sun glow
    dx = (x - SUN_X) * (w / h)
    dy = y - SUN_Y
    d = np.sqrt(dx * dx + dy * dy)
    glow_a = np.exp(-d / 0.16)[..., None] * 0.75 + np.exp(-d / 0.035)[..., None] * 0.6
    col = col + (np.array([255, 226, 170.0]) - col) * np.clip(glow_a, 0, 1)
    disk = np.clip((0.022 - d) / 0.002, 0, 1)[..., None]
    col = col + (np.array(SUN, float) - col) * disk
    # soft streaky clouds
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    clouds = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cd = ImageDraw.Draw(clouds)
    for _ in range(26):
        cy = rng.uniform(0.08, 0.42) * h
        cx = rng.uniform(-0.1, 1.1) * w
        cw = rng.uniform(0.12, 0.35) * w
        ch = rng.uniform(0.006, 0.018) * h
        warm = 1 - abs(cy / h - 0.45) / 0.45
        c = lerp(hexc("8a7aa8"), hexc("ffc890"), np.clip(warm * 1.2 - 0.1, 0, 1))
        cd.ellipse([cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2], fill=c + (int(rng.uniform(60, 120)),))
    clouds = clouds.filter(ImageFilter.GaussianBlur(14))
    img.alpha_composite(clouds)
    # a few birds
    bd = ImageDraw.Draw(img)
    for i in range(5):
        bx = (0.56 + i * 0.025 + rng.uniform(-0.01, 0.01)) * w
        by = (0.30 + rng.uniform(-0.03, 0.03) + (i % 2) * 0.012) * h
        s = rng.uniform(9, 14)
        bd.line([(bx - s, by - s * 0.35), (bx, by), (bx + s, by - s * 0.4)], fill=(52, 40, 60, 200), width=3)
    return img


def ridge_band(profile, top_col, bot_col, mist_strength, rim=0.0):
    """Fill below a ridge profile with a vertical gradient (crest -> hazy base)."""
    w, h = W * SS, H * SS
    prof = np.interp(np.arange(w) / SS, np.arange(len(profile)), profile) * SS
    yy = np.arange(h)[:, None]
    inside = yy >= prof[None, :]
    depth = np.clip((yy - prof[None, :]) / (0.28 * h), 0, 1)
    tc = np.array(top_col, float)
    bc = np.array(bot_col, float)
    col = tc + (bc - tc) * (depth[..., None] ** 0.8)
    # rim light along the crest from the low sun
    if rim > 0:
        xs = np.arange(w)[None, :] / w
        sun_side = np.exp(-((xs - SUN_X) / 0.35) ** 2)
        rim_a = np.exp(-(yy - prof[None, :]) / (6 * SS)) * rim * sun_side
        col = col + (np.array([255, 205, 150.0]) - col) * np.clip(rim_a, 0, 1)[..., None]
    alpha = inside.astype(float)
    # antialias the crest edge
    edge = np.clip(yy - prof[None, :] + 1, 0, 1)
    alpha = np.minimum(alpha + edge * 0, 1) * edge
    rgba = np.dstack([np.clip(col, 0, 255), alpha * 255]).astype(np.uint8)
    img = Image.fromarray(rgba, "RGBA")
    if mist_strength > 0:
        # valley fog pooling at the base of this ridge
        mist = np.zeros((h, w))
        base = prof + 0.18 * h
        fog = np.exp(-((yy - base[None, :]) / (0.05 * h)) ** 2) * mist_strength
        fog *= (0.7 + 0.3 * value_noise(w, 6 / w, int(mist_strength * 1000))[None, :])
        mrgba = np.dstack([np.full((h, w), 245), np.full((h, w), 222), np.full((h, w), 205), np.clip(fog, 0, 1) * 255]).astype(np.uint8)
        img.alpha_composite(Image.fromarray(mrgba, "RGBA"))
    return img


def tree_line(img, profile, color, count, size, seed, autumn=None):
    """Silhouette trees standing along a ridge crest."""
    r = np.random.default_rng(seed)
    d = ImageDraw.Draw(img)
    for _ in range(count):
        x = r.uniform(0, W)
        y = np.interp(x, np.arange(len(profile)), profile) + r.uniform(0, size * 0.6)
        s = size * r.uniform(0.6, 1.25)
        c = color
        if autumn is not None and r.random() < 0.55:
            c = lerp(color, autumn[r.integers(0, len(autumn))], r.uniform(0.25, 0.55))
        if r.random() < 0.45:
            d.polygon([(x * SS, (y - s * 1.9) * SS), ((x - s * 0.45) * SS, y * SS), ((x + s * 0.45) * SS, y * SS)], fill=c + (255,))
        else:
            rr = s * 0.6
            d.ellipse([(x - rr) * SS, (y - s * 1.3) * SS, (x + rr) * SS, (y - s * 0.1) * SS], fill=c + (255,))


def downsample(img):
    return img.resize((W, H), Image.LANCZOS)


def forest_fill(img, profile, top, bot, density, size, seed, autumn, depth_frac=0.3, t=0.5):
    """Cover a ridge with a canopy of tree crowns that fades into the haze below."""
    r = np.random.default_rng(seed)
    d = ImageDraw.Draw(img)
    n = int(density)
    xs = r.uniform(-20, W + 20, n)
    ds = r.uniform(0, 1, n) ** 1.6
    order = np.argsort(ds)  # crest first, then work downhill so lower trees overlap
    for k in order:
        x = xs[k]
        crest = np.interp(x, np.arange(len(profile)), profile)
        y = crest + ds[k] * depth_frac * H + size * 0.3
        c = lerp(top, bot, min(1.0, ds[k] * 1.15))
        if autumn is not None and r.random() < 0.7:
            c = lerp(c, autumn[r.integers(0, len(autumn))], r.uniform(0.2, 0.5) * (0.5 + 0.7 * t) * (1 - ds[k] * 0.6))
        c = lerp(c, (0, 0, 0), r.uniform(0.0, 0.12))
        s = size * r.uniform(0.7, 1.3) * (1 - ds[k] * 0.25)
        if r.random() < 0.35:
            pts = [(x, y - s * 1.9), (x - s * 0.5, y), (x + s * 0.5, y)]
            d.polygon([(px * SS, py * SS) for px, py in pts], fill=c + (255,))
        else:
            rr = s * r.uniform(0.5, 0.7)
            d.ellipse([(x - rr) * SS, (y - s * 1.2) * SS, (x + rr) * SS, (y - s * 0.05) * SS], fill=c + (255,))


def build_ridges():
    n = W
    layers = []
    specs = [
        # base(y frac), amp, t (0 far .. 1 near), mist, rim, forest density, tree size
        (0.545, 55, 0.00, 0.5, 0.0, 0, 0),
        (0.585, 70, 0.13, 0.5, 0.0, 0, 0),
        (0.630, 85, 0.27, 0.5, 0.1, 0, 0),
        (0.680, 105, 0.43, 0.45, 0.2, 2500, 6),
        (0.735, 125, 0.60, 0.38, 0.3, 4000, 9),
        (0.800, 140, 0.78, 0.25, 0.4, 6000, 13),
        (0.885, 130, 0.94, 0.0, 0.5, 6500, 18),
    ]
    far_col = hexc("c4a2b4")
    near_col = hexc("16252a")
    autumn = [hexc("c0562a"), hexc("d79a35"), hexc("9c3a28"), hexc("b5742c")]
    profiles = []
    for i, (b, amp, t, mist, rim, dens, tsize) in enumerate(specs):
        prof = ridge_profile(n, b * H, amp, 100 + i * 17, 0.5)
        profiles.append(prof)
        top = lerp(lerp(far_col, near_col, t ** 0.9), HAZE, ((1 - t) ** 2) * 0.35)
        bot = lerp(top, HAZE, 0.55 * (1 - t) ** 1.4 + 0.06)
        band = ridge_band(prof, top, bot, 0, rim)
        if dens:
            forest_fill(band, prof, top, bot, dens, tsize, 400 + i, autumn, 0.22 + t * 0.12, t)
        if mist > 0:
            band = add_mist(band, prof, mist, i)
        layers.append(band)
    return layers, profiles


def add_mist(img, prof, strength, seed):
    w, h = W * SS, H * SS
    p = np.interp(np.arange(w) / SS, np.arange(len(prof)), prof) * SS
    yy = np.arange(h)[:, None]
    base = p + 0.16 * h
    fog = np.exp(-((yy - base[None, :]) / (0.045 * h)) ** 2) * strength
    fog *= (0.65 + 0.35 * value_noise(w, 7 / w, seed + 5)[None, :])
    m = np.dstack([np.full((h, w), 246), np.full((h, w), 224), np.full((h, w), 206), np.clip(fog, 0, 1) * 255]).astype(np.uint8)
    img.alpha_composite(Image.fromarray(m, "RGBA"))
    return img


def foreground():
    w, h = W * SS, H * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rock = (22, 24, 27, 255)
    rock_hi = (58, 52, 50, 255)
    # rocky overlook jutting out from the lower left (McAfee-Knob style ledge)
    ledge_top = 0.80 * H
    pts = [(0, H * 0.70), (W * 0.06, H * 0.715), (W * 0.13, H * 0.745), (W * 0.20, ledge_top - 6),
           (W * 0.285, ledge_top), (W * 0.305, ledge_top + 14), (W * 0.29, ledge_top + 40), (W * 0.24, H * 0.86),
           (W * 0.27, H * 0.93), (W * 0.36, H), (0, H)]
    d.polygon([(x * SS, y * SS) for x, y in pts], fill=rock)
    # warm rim of sunlight on the ledge top
    d.line([(W * 0.13 * SS, H * 0.745 * SS), (W * 0.20 * SS, (ledge_top - 6) * SS), (W * 0.285 * SS, ledge_top * SS),
            (W * 0.305 * SS, (ledge_top + 14) * SS)], fill=(150, 98, 64, 255), width=3 * SS)
    # a few lit facets on the rock face
    for _ in range(9):
        x0 = rng.uniform(0.02, 0.24) * W
        y0 = rng.uniform(0.80, 0.97) * H
        ww = rng.uniform(30, 90)
        d.polygon([(x0 * SS, y0 * SS), ((x0 + ww) * SS, (y0 - ww * 0.15) * SS), ((x0 + ww * 0.8) * SS, (y0 + 6) * SS)], fill=(30, 31, 34, 255))
    # a wind-bent pitch pine clinging to the ledge
    tx, ty = W * 0.075, H * 0.718
    pine = (16, 22, 21, 255)
    trunk = [(tx, ty), (tx + 6, ty - 70), (tx - 6, ty - 140), (tx + 14, ty - 205), (tx + 40, ty - 255)]
    for k in range(len(trunk) - 1):
        wdt = int((11 - k * 2) * SS)
        d.line([(trunk[k][0] * SS, trunk[k][1] * SS), (trunk[k + 1][0] * SS, trunk[k + 1][1] * SS)], fill=pine, width=max(wdt, 3 * SS))
    branches = [((tx - 6, ty - 140), (tx + 95, ty - 165)), ((tx + 14, ty - 205), (tx - 60, ty - 225)), ((tx + 6, ty - 85), (tx + 110, ty - 95)), ((tx + 40, ty - 255), (tx + 130, ty - 270))]
    for (a, b) in branches:
        d.line([(a[0] * SS, a[1] * SS), (b[0] * SS, b[1] * SS)], fill=pine, width=4 * SS)
    clusters = [(tx + 90, ty - 170, 60), (tx - 55, ty - 230, 50), (tx + 105, ty - 100, 50), (tx + 120, ty - 275, 55), (tx + 30, ty - 262, 45), (tx + 20, ty - 180, 40)]
    for cx, cy, cr in clusters:
        for _ in range(26):
            ox = rng.normal(0, cr * 0.45)
            oy = rng.normal(0, cr * 0.16)
            rr = rng.uniform(cr * 0.18, cr * 0.32)
            d.ellipse([(cx + ox - rr * 1.4) * SS, (cy + oy - rr * 0.6) * SS, (cx + ox + rr * 1.4) * SS, (cy + oy + rr * 0.6) * SS], fill=pine)
    # the hiker, standing at the tip of the ledge looking out at the ridges
    hx, hy = W * 0.262, ledge_top + 1
    s = 1.45
    sil = (14, 15, 18, 255)
    def P(x, y):
        return ((hx + x * s) * SS, (hy - y * s) * SS)
    # legs
    d.polygon([P(-11, 0), P(-4, 0), P(-1, 62), P(-12, 62)], fill=sil)
    d.polygon([P(4, 0), P(12, 0), P(9, 62), P(-1, 62)], fill=sil)
    # torso
    d.polygon([P(-14, 60), P(12, 60), P(13, 112), P(-13, 112)], fill=sil)
    # big pack with a bedroll on top
    d.rounded_rectangle([P(-34, 122)[0], P(-34, 122)[1], P(-8, 58)[0], P(-8, 58)[1]], radius=6 * SS, fill=sil)
    d.ellipse([P(-38, 134)[0], P(-38, 134)[1], P(-4, 118)[0], P(-4, 118)[1]], fill=sil)
    # head and hat
    d.ellipse([P(-8, 132)[0], P(-8, 132)[1], P(10, 112)[0], P(10, 112)[1]], fill=sil)
    d.ellipse([P(-15, 133)[0], P(-15, 133)[1], P(17, 127)[0], P(17, 127)[1]], fill=sil)
    # arm resting on a trekking pole planted forward
    d.line([P(10, 106), P(26, 78)], fill=sil, width=6 * SS)
    d.line([P(28, 92), P(40, 0)], fill=sil, width=3 * SS)
    # sunlit rim on the hiker's sun-facing side
    d.line([P(12, 60), P(13, 110)], fill=(170, 110, 70, 255), width=2 * SS)
    # framing spruces on the right edge, with ragged tiers
    spr = (12, 18, 18, 255)
    for i, (cx, base, hgt, wid) in enumerate([(0.915, 1.03, 0.47, 0.062), (0.968, 1.02, 0.66, 0.08), (1.015, 1.0, 0.8, 0.085)]):
        x = cx * W
        yb = base * H
        top = yb - hgt * H
        d.line([(x * SS, top * SS), (x * SS, yb * SS)], fill=spr, width=10 * SS)
        tiers = 16
        for tier in range(tiers):
            f = (tier + 1) / tiers
            ty0 = top + (yb - top) * tier / tiers
            ty1 = ty0 + (yb - top) * 1.9 / tiers
            ww = wid * W * (0.18 + 0.82 * f) * rng.uniform(0.8, 1.1)
            jag = []
            for k in range(9):
                u = k / 8
                px = x - ww / 2 + ww * u
                droop = ty1 - (1 - abs(u - 0.5) * 2) * (ty1 - ty0) * 0.25 + rng.uniform(-6, 6)
                jag.append((px * SS, droop * SS))
            d.polygon([(x * SS, ty0 * SS)] + [jag[0]] + jag + [jag[-1]], fill=spr)
    # white blaze on the nearest trunk — the trail goes on
    d.rectangle([(0.915 * W - 6) * SS, (0.905 * H) * SS, (0.915 * W + 6) * SS, (0.905 * H + 28) * SS], fill=(232, 228, 214, 255))
    return img


def mist_strip():
    """A horizontally tileable band of mist to drift slowly across the valleys."""
    w, h = W, 420
    yy = np.linspace(-1, 1, h)[:, None]
    n1 = value_noise(w + 1, 5 / w, 7)[:w]
    n2 = value_noise(w + 1, 13 / w, 8)[:w]
    # make it tile: blend the ends
    ramp = np.linspace(0, 1, w)
    tile = n1 * (1 - ramp) + np.roll(n1, w // 2) * ramp
    dens = np.clip(0.55 + 0.35 * tile + 0.15 * n2, 0, 1)[None, :]
    a = np.exp(-(yy / 0.45) ** 2) * dens * 0.55
    rgba = np.dstack([np.full((h, w), 250), np.full((h, w), 232), np.full((h, w), 218), a * 255]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA").filter(ImageFilter.GaussianBlur(6))


def main():
    os.makedirs(OUT, exist_ok=True)
    sky = sky_layer()
    ridges, _ = build_ridges()
    far = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    for r in ridges[:3]:
        far.alpha_composite(r)
    mid = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    for r in ridges[3:5]:
        mid.alpha_composite(r)
    near = ridges[5]
    fore = foreground()
    layers = {"sky": sky, "far": downsample(far), "mid": downsample(mid), "near": downsample(near), "fore": downsample(fore)}
    for name, im in layers.items():
        im.save(os.path.join(OUT, f"{name}.png"), optimize=True)
        print("wrote", name)
    mist_strip().save(os.path.join(OUT, "mist.png"), optimize=True)
    # flattened preview / desktop wallpaper
    flat = sky.copy()
    for name in ("far", "mid", "near", "fore"):
        flat.alpha_composite(layers[name])
    flat.convert("RGB").save(os.path.join(OUT, "wallpaper_preview.jpg"), quality=92)
    print("wrote preview")


if __name__ == "__main__":
    main()
