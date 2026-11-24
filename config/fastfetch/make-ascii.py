#!/usr/bin/env python3
"""Turn a transparent PNG into coloured ASCII art for fastfetch.

usage: make-ascii.py cutout.png logo.txt [width] [--blocks]
--blocks draws with half-block characters (2 pixels per cell) for a sharper picture.
Transparent pixels become spaces, so only the subject is drawn.
"""
import sys
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
args = [a for a in sys.argv[3:] if not a.startswith("--")]
width = int(args[0]) if args else 42
blocks = "--blocks" in sys.argv
ramp = " .:-=+*#%@"  # dark -> bright

img = Image.open(src).convert("RGBA")
img = img.crop(img.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox())
# Terminal cells are ~2x taller than wide, so halve the height.
height = max(1, round(img.height / img.width * width * (1.0 if blocks else 0.5)))
if blocks and height % 2:
    height += 1
img = img.resize((width, height), Image.LANCZOS)

# Stretch contrast using only the subject's pixels, so a grey character
# still uses the whole brightness range.
rgb, alpha = img.convert("RGB"), img.getchannel("A")
lums = sorted(l for l, a in zip(rgb.convert("L").get_flattened_data(), alpha.get_flattened_data()) if a >= 110)
lo, hi = lums[len(lums) * 2 // 100], lums[len(lums) * 98 // 100]
scale = 255 / max(1, hi - lo)
rgb = rgb.point(lambda v: max(0, min(255, round((v - lo) * scale))))
img = Image.merge("RGBA", (*rgb.split(), alpha))

def block_lines():
    out = []
    for y in range(0, height, 2):
        row = []
        for x in range(width):
            t = img.getpixel((x, y)); b = img.getpixel((x, y + 1))
            ton, bon = t[3] >= 110, b[3] >= 110
            if ton and bon:
                row.append(f"\x1b[38;2;{t[0]};{t[1]};{t[2]}m\x1b[48;2;{b[0]};{b[1]};{b[2]}m▀\x1b[0m")
            elif ton:
                row.append(f"\x1b[38;2;{t[0]};{t[1]};{t[2]}m▀\x1b[0m")
            elif bon:
                row.append(f"\x1b[38;2;{b[0]};{b[1]};{b[2]}m▄\x1b[0m")
            else:
                row.append(" ")
        out.append("".join(row).rstrip())
    return out

lines = []
for y in range(0 if not blocks else height, height):
    row, last = [], None
    for x in range(width):
        r, g, b, a = img.getpixel((x, y))
        if a < 110:
            row.append(" ")
            continue
        lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
        ch = ramp[min(len(ramp) - 1, max(1, round(lum * (len(ramp) - 1))))]
        col = (r, g, b)
        if col != last:
            row.append(f"\x1b[38;2;{r};{g};{b}m")
            last = col
        row.append(ch)
    lines.append(("".join(row)).rstrip() + "\x1b[0m")

if blocks:
    lines = block_lines()

# Drop fully empty lines at top/bottom.
while lines and lines[0].strip("\x1b[0m ") == "":
    lines.pop(0)
while lines and lines[-1].strip("\x1b[0m ") == "":
    lines.pop()

with open(out, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"wrote {out}: {width}x{len(lines)}")
