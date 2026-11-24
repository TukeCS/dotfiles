#!/usr/bin/env python3
"""Turn a wallpaper into a full-screen block-art background for Ly.

    python make-ly-art.py WALLPAPER OUTDIR [COLUMNS ROWS]

Writes OUTDIR/wallpaper.dur (a durdraw file Ly plays as its "animation") and
OUTDIR/palette (16 hex colours that startup.sh loads into the console).

The Linux console only has 16 colours, so the palette is picked from the
wallpaper itself. A few slots stay fixed because Ly's UI uses them:
  0 black (background)   2 moss (box border)   7 light grey (text)   9 red (errors)

Each character cell shows two pixels with a half block (top = foreground colour,
bottom = background colour). Background colours can only come from slots 0-7.
Needs ffmpeg; no Python packages.
"""
import gzip
import json
import random
import subprocess
import sys

FIXED = {0: (0x00, 0x00, 0x00), 2: (0xA8, 0xBF, 0x4A), 7: (0xE6, 0xE6, 0xE6), 9: (0xE0, 0x7A, 0x5F)}
BG_SLOTS = [0, 1, 2, 3, 4, 5, 6, 7]  # bold (bright) only works for the foreground

# Ly maps durdraw 16-colour numbers to console colours with a lookup table; this is its inverse
DUR_FG = [0, 5, 3, 7, 2, 6, 4, 8, 9, 13, 11, 15, 10, 14, 12, 16]


def load_pixels(path, w, h):
    # crop to the screen's aspect ratio (cells are twice as tall as wide), then scale
    vf = (f"crop='min(iw,ih*{w}/{h})':'min(ih,iw*{h}/{w})',"
          f"scale={w}:{h}:flags=lanczos,eq=saturation=1.25:contrast=1.08")
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-vf", vf, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        check=True, capture_output=True).stdout
    return [tuple(raw[i:i + 3]) for i in range(0, len(raw), 3)]


def dist(a, b):
    # weighted RGB distance (closer to how bright/green things look to us)
    dr, dg, db = a[0] - b[0], a[1] - b[1], a[2] - b[2]
    return 2 * dr * dr + 4 * dg * dg + 3 * db * db


def nearest(c, pal, slots):
    return min(slots, key=lambda i: dist(c, pal[i]))


def kmeans(pixels, fixed, k, iters=20):
    random.seed(1)
    free = random.sample(pixels, k)
    for _ in range(iters):
        cents = fixed + free
        groups = [[] for _ in cents]
        for p in pixels:
            groups[min(range(len(cents)), key=lambda i: dist(p, cents[i]))].append(p)
        new = []
        for j, g in enumerate(groups[len(fixed):]):
            new.append(tuple(sum(c[i] for c in g) // len(g) for i in range(3)) if g else free[j])
        free = new
    counts = [0] * k
    for p in pixels:
        cents = fixed + free
        j = min(range(len(cents)), key=lambda i: dist(p, cents[i]))
        if j >= len(fixed):
            counts[j - len(fixed)] += 1
    return free, counts


def build_palette(pixels):
    sample = pixels[::3]
    free, counts = kmeans(sample, [FIXED[i] for i in FIXED if i != 9], 16 - len(FIXED))
    order = sorted(range(len(free)), key=lambda i: -counts[i])
    pal = dict(FIXED)
    # most common colours get the slots that can also be used as background
    slots = [s for s in BG_SLOTS if s not in FIXED] + [s for s in range(8, 16) if s not in FIXED]
    for slot, i in zip(slots, order):
        pal[slot] = free[i]
    return [pal[i] for i in range(16)]


def dither(pixels, w, h, pal):
    """Floyd-Steinberg onto the 16-colour palette."""
    buf = [list(map(float, p)) for p in pixels]
    out = [0] * (w * h)
    allslots = [i for i in range(16) if i != 9]  # 9 is reserved for error text
    for y in range(h):
        for x in range(w):
            i = y * w + x
            c = tuple(max(0, min(255, v)) for v in buf[i])
            j = nearest(c, pal, allslots)
            out[i] = j
            err = [c[k] - pal[j][k] for k in range(3)]
            for dx, dy, f in ((1, 0, 7 / 16), (-1, 1, 3 / 16), (0, 1, 5 / 16), (1, 1, 1 / 16)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and ny < h:
                    n = buf[ny * w + nx]
                    for k in range(3):
                        n[k] += err[k] * f * 0.5  # softened: full error diffusion looks noisy at this size
    return out


def to_cells(idx, w, rows, pal):
    """Pair pixel rows into half-block cells. Returns contents and colorMap[x][y] = [fg, bg]."""
    lines, cmap = [], [[None] * rows for _ in range(w)]
    for r in range(rows):
        line = []
        for x in range(w):
            top, bot = idx[(2 * r) * w + x], idx[(2 * r + 1) * w + x]
            if top == bot:
                ch, fg, bg = ("█", top, 0) if top >= 8 else (" ", 7, top)
            elif bot < 8:
                ch, fg, bg = "▀", top, bot
            elif top < 8:
                ch, fg, bg = "▄", bot, top
            else:  # both colours are foreground-only: keep the top, approximate the bottom
                ch, fg, bg = "▀", top, nearest(pal[bot], pal, BG_SLOTS)
            line.append(ch)
            cmap[x][r] = [DUR_FG[fg], DUR_FG[bg] - 1 if bg else 0]
        lines.append("".join(line))
    return lines, cmap


def main():
    if len(sys.argv) not in (3, 5):
        sys.exit(__doc__)
    src, outdir = sys.argv[1], sys.argv[2]
    cols, rows = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) == 5 else (160, 50)
    pixels = load_pixels(src, cols, rows * 2)
    pal = build_palette(pixels)
    idx = dither(pixels, cols, rows * 2, pal)
    lines, cmap = to_cells(idx, cols, rows, pal)
    movie = {"DurMovie": {
        "formatVersion": 7, "colorFormat": "16", "preferredFont": "fixed", "encoding": "utf-8",
        "name": "wallpaper", "artist": "", "framerate": 1.0, "sizeX": cols, "sizeY": rows, "extra": None,
        "frames": [{"frameNumber": 1, "delay": 0, "contents": lines, "colorMap": cmap}]}}
    with gzip.open(f"{outdir}/wallpaper.dur", "wt", encoding="utf-8") as f:
        json.dump(movie, f)
    with open(f"{outdir}/palette", "w") as f:
        f.write("\n".join("%02x%02x%02x" % c for c in pal) + "\n")
    print(f"wrote {outdir}/wallpaper.dur ({cols}x{rows}) and {outdir}/palette")


if __name__ == "__main__":
    main()
