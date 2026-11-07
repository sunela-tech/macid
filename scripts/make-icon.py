#!/usr/bin/env python3
"""Draws the Mac ID app icon and writes Resources/Assets.xcassets/AppIcon.appiconset.

Graphite squircle, white face-scan glyph, a thin infrared scan line. Needs Pillow:
    python3 -m pip install pillow && python3 scripts/make-icon.py
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources", "Assets.xcassets", "AppIcon.appiconset")
S = 4096  # supersampled canvas; scaled down at the end


def squircle_mask(size, inset, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([inset, inset, size - inset, size - inset], radius=radius, fill=255)
    return m


def vertical_gradient(size, top, bottom):
    g = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((size, size), Image.BICUBIC)


def draw_icon():
    inset = int(S * 100 / 1024)          # macOS icon grid: 824pt body in a 1024 canvas
    radius = int(S * 185 / 1024)
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # soft drop shadow
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [inset, inset + S * 0.012, S - inset, S - inset + S * 0.012], radius=radius, fill=(0, 0, 0, 120))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(S * 0.012)))

    body = vertical_gradient(S, (58, 64, 86), (12, 14, 22)).convert("RGBA")
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([S * 0.05, -S * 0.25, S * 0.95, S * 0.55], fill=(150, 170, 255, 60))
    body.alpha_composite(glow.filter(ImageFilter.GaussianBlur(S * 0.08)))
    canvas.paste(body, (0, 0), squircle_mask(S, inset, radius))

    # inner rim highlight
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle([inset, inset, S - inset, S - inset], radius=radius,
                                          outline=(255, 255, 255, 46), width=int(S * 0.004))
    canvas.alpha_composite(rim)

    # glyph: 100-unit box mapped to 52% of the canvas
    d = ImageDraw.Draw(canvas)
    box = S * 0.52
    ox = oy = (S - box) / 2
    u = box / 100
    w = int(6.4 * u)
    white = (255, 255, 255, 255)

    def P(x, y):
        return (ox + x * u, oy + y * u)

    def line(a, b):
        d.line([P(*a), P(*b)], fill=white, width=w)
        for p in (a, b):
            cx, cy = P(*p)
            d.ellipse([cx - w / 2, cy - w / 2, cx + w / 2, cy + w / 2], fill=white)

    def arc(cx, cy, r, a0, a1):
        x0, y0 = P(cx - r, cy - r)
        x1, y1 = P(cx + r, cy + r)
        d.arc([x0 - w / 2, y0 - w / 2, x1 + w / 2, y1 + w / 2], a0, a1, fill=white, width=w)

    # corner brackets (radius 10 corners)
    for (sx, sy) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        cx = 50 + sx * 22
        cy = 50 + sy * 22
        ex = 50 + sx * 32
        ey = 50 + sy * 32
        line((ex, cy), (ex, 50 + sy * 14))          # vertical leg
        line((cx, ey), (50 + sx * 14, ey))          # horizontal leg
        start = {(-1, -1): 180, (1, -1): 270, (1, 1): 0, (-1, 1): 90}[(sx, sy)]
        arc(cx, cy, 10, start, start + 90)
    # eyes, nose, smile
    line((38, 40), (38, 47))
    line((62, 40), (62, 47))
    line((51, 41), (51, 57))
    line((51, 57), (46, 57))
    pts = []
    for i in range(41):
        t = i / 40
        x = (1 - t) ** 2 * 37 + 2 * (1 - t) * t * 50 + t ** 2 * 63
        y = (1 - t) ** 2 * 64 + 2 * (1 - t) * t * 74 + t ** 2 * 64
        pts.append(P(x, y))
    d.line(pts, fill=white, width=w, joint="curve")
    for p in (pts[0], pts[-1]):
        d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=white)

    # infrared scan line across the glyph
    scan = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(scan)
    y = oy + 52 * u
    sd.rounded_rectangle([ox + 6 * u, y - u * 0.9, ox + 94 * u, y + u * 0.9], radius=u, fill=(255, 77, 109, 235))
    canvas.alpha_composite(scan.filter(ImageFilter.GaussianBlur(u * 1.6)))
    canvas.alpha_composite(scan)
    return canvas


def main():
    os.makedirs(OUT, exist_ok=True)
    icon = draw_icon()
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            icon.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
            images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{scale}x", "filename": name})
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, f, indent=2)
    with open(os.path.join(os.path.dirname(OUT), "Contents.json"), "w") as f:
        json.dump({"info": {"version": 1, "author": "xcode"}}, f, indent=2)
    preview = os.path.join(ROOT, "marketing", "AppIcon-1024.png")
    icon.resize((1024, 1024), Image.LANCZOS).save(preview)
    print("wrote", OUT, "and", preview)


if __name__ == "__main__":
    sys.exit(main())
