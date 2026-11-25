#!/usr/bin/env python3
"""Turn a transparent PNG into coloured text art for fastfetch.

usage: make-text-art.py cutout.png out.txt [width] [--mode=braille|ascii] [--aspect=2.2]
       [--bias=6] [--floor=70] [--radius=3] [--trim=0]

--aspect is terminal cell height / width (JetBrains Mono ~2.2). Getting it
right is what keeps the picture from looking stretched.
braille: each cell is a 2x4 grid of dots -> much more detail.
ascii:   one character per cell, picked by brightness.
"""
import sys
from PIL import Image, ImageFilter, ImageOps

pos = [a for a in sys.argv[1:] if not a.startswith("--")]
opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
src, out = pos[0], pos[1]
width = int(pos[2]) if len(pos) > 2 else 40
mode = opts.get("mode", "braille")
aspect = float(opts.get("aspect", 2.2))

img = Image.open(src).convert("RGBA")
img = img.crop(img.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox())
# --trim=0.15 cuts that fraction off the bottom (e.g. less hoodie, smaller logo).
trim = float(opts.get("trim", 0))
if trim:
    img = img.crop((0, 0, img.width, round(img.height * (1 - trim))))

# Contrast-stretch using the subject's pixels only.
def stretch(im):
    rgb, alpha = im.convert("RGB"), im.getchannel("A")
    lums = sorted(l for l, a in zip(rgb.convert("L").get_flattened_data(), alpha.get_flattened_data()) if a >= 110)
    lo, hi = lums[len(lums) * 2 // 100], lums[len(lums) * 99 // 100]
    s = 255 / max(1, hi - lo)
    rgb = rgb.point(lambda v: max(0, min(255, round((v - lo) * s))))
    return Image.merge("RGBA", (*rgb.split(), alpha))

def esc(c):
    return f"\x1b[38;2;{c[0]};{c[1]};{c[2]}m"

lines = []
if mode == "braille":
    pw = width * 2
    ph = round(img.height / img.width * pw * 2 / aspect)  # dot is aspect/2 tall vs wide
    ph += -ph % 4
    im = stretch(img.resize((pw, ph), Image.LANCZOS))
    lum = im.convert("L")
    # Sharpen so the drawing's outlines survive, then dither to dots.
    # A dot is lit when the pixel is brighter than its neighbourhood, so the
    # drawing's dark lines (eyes, mouth, outlines) show up as gaps.
    local = lum.filter(ImageFilter.GaussianBlur(float(opts.get("radius", 3))))
    bias = int(opts.get("bias", 6))
    floor = int(opts.get("floor", 70))
    dots = Image.new("1", lum.size)
    for y in range(ph):
        for x in range(pw):
            v = lum.getpixel((x, y))
            if v > floor and v + bias >= local.getpixel((x, y)):
                dots.putpixel((x, y), 1)
    alpha = im.getchannel("A")
    bits = [(0, 0, 0x01), (0, 1, 0x02), (0, 2, 0x04), (1, 0, 0x08),
            (1, 1, 0x10), (1, 2, 0x20), (0, 3, 0x40), (1, 3, 0x80)]
    for cy in range(0, ph, 4):
        row, last = [], None
        for cx in range(0, pw, 2):
            code, cols = 0, []
            for dx, dy, b in bits:
                x, y = cx + dx, cy + dy
                if alpha.getpixel((x, y)) >= 110 and dots.getpixel((x, y)):
                    code |= b
                    cols.append(im.getpixel((x, y))[:3])
            if not code:
                row.append(" ")
                continue
            c = tuple(min(255, int(sum(v) / len(cols) * 1.1) + 30) for v in zip(*cols))
            if c != last:
                row.append(esc(c)); last = c
            row.append(chr(0x2800 + code))
        lines.append("".join(row).rstrip() + "\x1b[0m")
else:
    ramp = " .'`^,:;Il!i><~+_-?][}{1)(|/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$"
    h = round(img.height / img.width * width / aspect)
    im = stretch(img.resize((width, h), Image.LANCZOS))
    for y in range(h):
        row, last = [], None
        for x in range(width):
            r, g, b, a = im.getpixel((x, y))
            if a < 110:
                row.append(" "); continue
            l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
            ch = ramp[max(1, min(len(ramp) - 1, round(l * (len(ramp) - 1))))]
            c = (min(255, r + 40), min(255, g + 40), min(255, b + 40))
            if c != last:
                row.append(esc(c)); last = c
            row.append(ch)
        lines.append("".join(row).rstrip() + "\x1b[0m")

strip = lambda s: s.replace("\x1b[0m", "").strip()
while lines and not strip(lines[0]): lines.pop(0)
while lines and not strip(lines[-1]): lines.pop()
with open(out, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"wrote {out}: {width}x{len(lines)}")
