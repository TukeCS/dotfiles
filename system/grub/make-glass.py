#!/usr/bin/env python3
"""Draws the PNGs for the "glass" GRUB theme (run from anywhere; writes into ./glass/).

background.png  the whole 2560x1600 screen with the centred window baked in: warm-black
           glass, 2px gold->orange border at 135deg, soft gold glow (same as Hyprland's
           focused window), two cream hairlines. GRUB draws its background opaque and
           never blends alpha there, so the glow is composited onto the screen colour here.
select_*   the selected entry, like the active Waybar workspace: gold tint + gold underline
term_*     the box around GRUB's console (c) and editor (e)
Card geometry here must match theme.txt: W x H card, G px of glow around it.
"""
import math, os, struct, zlib

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "glass")
GOLD, ORANGE, CREAM, CARD = (0xF4, 0xB9, 0x42), (0xE3, 0x76, 0x2B), (0xF6, 0xEA, 0xD8), (0x14, 0x11, 0x0E)
W, H, G, RAD, BORDER = 1040, 330, 40, 6, 2
SW, SH, SCREEN = 2560, 1600, (0x0B, 0x0A, 0x09)   # must match GRUB_GFXMODE
SEP = (76, 240)          # hairline under the header, hairline above the countdown

def png(name, w, h, px, rgb_rows=None):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        if rgb_rows:
            raw += rgb_rows(y)
            continue
        for x in range(w):
            raw += bytes(px(x, y))
    ch = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2 if rgb_rows else 6, 0, 0, 0))
                + ch(b"IDAT", zlib.compress(bytes(raw), 9)) + ch(b"IEND", b""))

def sdf(x, y):  # signed distance to the rounded card
    qx = abs(x - W / 2) - (W / 2 - RAD)
    qy = abs(y - H / 2) - (H / 2 - RAD)
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - RAD

def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

def card(X, Y):
    x, y = X - G + 0.5, Y - G + 0.5
    d, dg = sdf(x, y), sdf(x, y - 4)                     # glow is offset 4px down, like the shadow
    glow = 0.25 * max(0, 1 - dg / 22) ** 2 if dg > 0 else 0.25
    if d > 0.5:
        return (*GOLD, round(glow * 255))
    cov = min(1, 0.5 - d)                                # antialiased outer edge
    inner = max(0, min(1, 0.5 - BORDER - d))             # 0 in the border band, 1 inside
    body = CARD
    if inner > 0 and 24 <= x <= W - 24 and any(s <= y < s + 1 for s in SEP):
        body = mix(CARD, CREAM, 0.16)
    c = mix(mix(GOLD, ORANGE, max(0, min(1, (x + y) / (W + H)))), body, inner)
    a = cov + glow * (1 - cov)
    rgb = tuple(round((c[i] * cov + GOLD[i] * glow * (1 - cov)) / a) for i in range(3))
    return (*rgb, round(a * 255))

os.makedirs(OUT, exist_ok=True)
# card (with glow) composited onto the screen colour, centred on a full-size opaque background
CW, CH = W + 2 * G, H + 2 * G
cx, cy = (SW - CW) // 2, (SH - CH) // 2
blank = bytes(SCREEN) * SW
def row(y):
    if not cy <= y < cy + CH:
        return blank
    r = bytearray(blank)
    for x in range(CW):
        *c, a = card(x, y - cy)
        a /= 255
        r[(cx + x) * 3:(cx + x) * 3 + 3] = bytes(round(c[i] * a + SCREEN[i] * (1 - a)) for i in range(3))
    return bytes(r)
png("background.png", SW, SH, None, rgb_rows=row)
tint = (*GOLD, 36)
for p in "nw n ne w c e".split():
    png(f"select_{p}.png", 1, 1, lambda x, y: tint)
for p in "sw s se".split():
    png(f"select_{p}.png", 1, 3, lambda x, y: tint if y == 0 else (*GOLD, 255))
for p, (w, h) in {"nw": (2, 2), "ne": (2, 2), "sw": (2, 2), "se": (2, 2), "n": (1, 2), "s": (1, 2), "w": (2, 1), "e": (2, 1)}.items():
    png(f"term_{p}.png", w, h, lambda x, y: (*GOLD, 255))
png("term_c.png", 1, 1, lambda x, y: (*CARD, 250))
print("wrote", OUT)
