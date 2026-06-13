#!/usr/bin/env python
"""
Generate Connect IQ bitmap fonts (.fnt + .png) from TrueType fonts.

Connect IQ's <font> resource consumes an AngelCode BMFont (text .fnt) plus a PNG
glyph atlas - it cannot rasterize a .ttf at build time. This script renders the
glyphs we need at fixed pixel sizes (tuned for the 454x454 panel) into a white +
alpha atlas so dc.setColor() can tint the text.

Run:  python tools/gen_fonts.py
Outputs into resources/fonts/.
"""
import os
from PIL import Image, ImageFont, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "fonts-src")
OUT = os.path.join(ROOT, "resources", "fonts")
PAD = 2  # transparent padding between glyphs to avoid bleed

# Each font: output id, source ttf, pixel size, and the glyph set to include.
DIGITS = "0123456789"
ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
FONTS = [
    {"name": "exocet_time",  "ttf": "ExocetHeavy.ttf", "size": 96, "chars": DIGITS + ":"},
    {"name": "exocet_value", "ttf": "ExocetHeavy.ttf", "size": 42, "chars": DIGITS + "%-"},
    {"name": "exocet_label", "ttf": "ExocetLight.ttf", "size": 27, "chars": ALPHA + DIGITS + " ,."},
]


def next_pow2(n):
    p = 1
    while p < n:
        p <<= 1
    return p


def gen(spec):
    ttf_path = os.path.join(SRC, spec["ttf"])
    font = ImageFont.truetype(ttf_path, spec["size"])
    ascent, descent = font.getmetrics()
    line_height = ascent + descent

    # Measure every glyph first.
    glyphs = []
    for ch in spec["chars"]:
        bbox = font.getbbox(ch)            # (l, t, r, b) relative to 'la' anchor
        l, t, r, b = bbox
        w, h = r - l, b - t
        advance = int(round(font.getlength(ch)))
        glyphs.append({"ch": ch, "l": l, "t": t, "w": max(w, 0), "h": max(h, 0), "adv": advance})

    # Shelf-pack into an atlas ~ a power-of-two square.
    max_w = max((g["w"] for g in glyphs), default=1)
    atlas_w = next_pow2(max(256, max_w + PAD * 2))
    # Lay out rows to estimate height.
    x, y, row_h = PAD, PAD, 0
    for g in glyphs:
        if x + g["w"] + PAD > atlas_w:
            x = PAD
            y += row_h + PAD
            row_h = 0
        g["x"], g["y"] = x, y
        x += g["w"] + PAD
        row_h = max(row_h, g["h"])
    atlas_h = next_pow2(y + row_h + PAD)

    # Render the atlas: white RGB, glyph coverage in the alpha channel.
    atlas = Image.new("RGBA", (atlas_w, atlas_h), (255, 255, 255, 0))
    for g in glyphs:
        if g["w"] == 0 or g["h"] == 0:
            continue
        cell = Image.new("L", (g["w"], g["h"]), 0)
        d = ImageDraw.Draw(cell)
        d.text((-g["l"], -g["t"]), g["ch"], font=font, fill=255)
        white = Image.new("RGBA", (g["w"], g["h"]), (255, 255, 255, 0))
        white.putalpha(cell)
        atlas.alpha_composite(white, (g["x"], g["y"]))

    png_name = spec["name"] + ".png"
    atlas.save(os.path.join(OUT, png_name))

    # Emit the AngelCode .fnt (text format). RGB=one(white), glyph in alpha so the
    # runtime tints with the foreground color.
    lines = []
    lines.append(
        'info face="%s" size=%d bold=0 italic=0 charset="" unicode=1 '
        'stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1 outline=0'
        % (spec["name"], spec["size"])
    )
    lines.append(
        "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 "
        "alphaChnl=1 redChnl=4 greenChnl=4 blueChnl=4"
        % (line_height, ascent, atlas_w, atlas_h)
    )
    lines.append('page id=0 file="%s"' % png_name)
    lines.append("chars count=%d" % len(glyphs))
    for g in glyphs:
        lines.append(
            "char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d "
            "xadvance=%d page=0 chnl=15"
            % (ord(g["ch"]), g["x"], g["y"], g["w"], g["h"], g["l"], g["t"], g["adv"])
        )
    lines.append("kernings count=0")
    with open(os.path.join(OUT, spec["name"] + ".fnt"), "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print("  %s: %d glyphs, atlas %dx%d, lineHeight=%d base=%d"
          % (spec["name"], len(glyphs), atlas_w, atlas_h, line_height, ascent))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    print("Generating Exocet bitmap fonts -> resources/fonts/")
    for spec in FONTS:
        gen(spec)
    print("Done.")
