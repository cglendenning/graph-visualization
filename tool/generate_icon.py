#!/usr/bin/env python3
"""Render the Constellation launch icon and write every iOS AppIcon size.

The mark is the app's own rosette: one lit centre, six satellites, filaments
between them, and the tick ring that reports node degree inside the app.
Drawn at 2x and downsampled so the hairlines survive at 40px.

Usage:  python3 tool/generate_icon.py
"""

import json
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_SET = os.path.join(
    ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset"
)

MASTER = 1024
SS = 2
S = MASTER * SS

VOID = (5, 7, 12)
DEEP = (13, 24, 37)
AQUA = (86, 232, 255)

CENTER_R = 0.108
ORBIT_R = 0.292
SAT_R = 0.050
TICKS = 11  # a well-connected node's degree ring, as the app would draw it


def radial_field(size):
    """Near-black ground lifted slightly toward aqua at the centre.

    Computed small and scaled up — it is a smooth gradient, so the
    interpolation costs nothing visually and saves millions of iterations.
    """
    small = 192
    img = Image.new("RGB", (small, small))
    px = img.load()
    c = small / 2
    max_d = small * 0.62
    for y in range(small):
        for x in range(small):
            t = max(0.0, 1.0 - math.hypot(x - c, y - c) / max_d) ** 2.2
            px[x, y] = (
                round(VOID[0] + (DEEP[0] - VOID[0]) * t),
                round(VOID[1] + (DEEP[1] - VOID[1]) * t),
                round(VOID[2] + (DEEP[2] - VOID[2]) * t),
            )
    return img.resize((size, size), Image.BICUBIC)


def seat_positions(size):
    c = size / 2
    r = size * ORBIT_R
    return [
        (
            c + r * math.cos(-math.pi / 2 + i * math.pi / 3),
            c + r * math.sin(-math.pi / 2 + i * math.pi / 3),
        )
        for i in range(6)
    ]


def glow_layer(size):
    """Every luminous element, solid, ready to be blurred and added back."""
    layer = Image.new("RGB", (size, size), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    c = size / 2
    cr, sr = size * CENTER_R, size * SAT_R

    for x, y in seat_positions(size):
        d.line([(c, c), (x, y)], fill=(26, 84, 99), width=round(size * 0.0055))
    for x, y in seat_positions(size):
        d.ellipse([x - sr, y - sr, x + sr, y + sr], fill=AQUA)
    d.ellipse([c - cr, c - cr, c + cr, c + cr], fill=AQUA)
    return layer


def draw_marks(img):
    """Crisp geometry over the bloom."""
    size = img.size[0]
    d = ImageDraw.Draw(img, "RGBA")
    c = size / 2
    cr, sr = size * CENTER_R, size * SAT_R
    ring = round(size * 0.0060)

    for x, y in seat_positions(size):
        d.line([(c, c), (x, y)], fill=(86, 232, 255, 130), width=round(size * 0.0042))

    tick_r = cr + size * 0.030
    tick_len = size * 0.026
    for i in range(TICKS):
        a = -math.pi / 2 + i * (2 * math.pi / TICKS)
        dx, dy = math.cos(a), math.sin(a)
        d.line(
            [
                (c + dx * tick_r, c + dy * tick_r),
                (c + dx * (tick_r + tick_len), c + dy * (tick_r + tick_len)),
            ],
            fill=(86, 232, 255, 190),
            width=round(size * 0.0050),
        )

    orb = size * ORBIT_R
    d.ellipse(
        [c - orb, c - orb, c + orb, c + orb],
        outline=(86, 232, 255, 40),
        width=round(size * 0.0030),
    )

    for x, y in seat_positions(size):
        d.ellipse([x - sr, y - sr, x + sr, y + sr], fill=(86, 232, 255, 70))
        d.ellipse(
            [x - sr, y - sr, x + sr, y + sr],
            outline=(150, 240, 255, 235),
            width=ring,
        )

    d.ellipse([c - cr, c - cr, c + cr, c + cr], fill=(86, 232, 255, 105))
    d.ellipse(
        [c - cr, c - cr, c + cr, c + cr],
        outline=(200, 248, 255, 255),
        width=round(ring * 1.6),
    )
    core = cr * 0.30
    d.ellipse([c - core, c - core, c + core, c + core], fill=(220, 250, 255, 255))
    return img


def build_master():
    base = radial_field(S)
    glow = glow_layer(S)
    lit = ImageChops.add(base, glow.filter(ImageFilter.GaussianBlur(S * 0.030)))
    lit = ImageChops.add(lit, glow.filter(ImageFilter.GaussianBlur(S * 0.060)))
    return draw_marks(lit).resize((MASTER, MASTER), Image.LANCZOS)


def main():
    master = build_master()
    master.save(os.path.join(ROOT, "tool", "icon_master.png"))

    with open(os.path.join(ICON_SET, "Contents.json")) as f:
        contents = json.load(f)

    written = set()
    for entry in contents["images"]:
        name = entry["filename"]
        w = float(entry["size"].split("x")[0])
        px = round(w * float(entry["scale"].rstrip("x")))
        if name in written:
            continue
        # iOS rejects alpha in app icons; the radial ground is fully opaque.
        master.resize((px, px), Image.LANCZOS).save(os.path.join(ICON_SET, name))
        written.add(name)
        print(f"  {name:34s} {px:4d}px")

    print(f"\n{len(written)} icons written")


if __name__ == "__main__":
    main()
