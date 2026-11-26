#!/usr/bin/env python3
"""Draws the "glass" GRUB theme: its images and its theme.txt.

    make-glass.py OUTDIR [--wallpaper FILE] [--grubcfg FILE | --entries N]

The card is sized for the menu it will show: with --grubcfg it counts the entries in the
generated grub.cfg (top level and inside each submenu, whichever is largest; capped at
MAX_ENTRIES, beyond that GRUB scrolls). theme.txt is written here too, with every position
computed from the same numbers as the image, so the two always match.

background.png  the whole 2560x1600 screen (must match GRUB_GFXMODE): the wallpaper redrawn
                as coloured ASCII art (JetBrains Mono, one character per 12x24 cell, picked by
                brightness and tinted with the wallpaper's own colour, dimmed), with the
                centred window baked in on top: warm-black glass, 2px rust->gold border at
                135deg, soft rust glow (like Hyprland's focused window) and a cream hairline under the header.
                It is baked in because GRUB draws `image` components over the menu and never
                blends alpha into its background. Without --wallpaper the screen is plain.
select_*        the selected entry, like the active Waybar workspace: rust tint + rust underline
term_*          the box around GRUB's console (c) and editor (e)
theme.txt       the layout
OUTDIR also needs the mono-*.pf2 fonts (kept in ./glass/). Needs ffmpeg for --wallpaper.
"""
import argparse, math, os, re, struct, subprocess, tempfile, zlib

RUST, GOLD, CREAM, CARD = (0xE8, 0x73, 0x2A), (0xF4, 0xB9, 0x42), (0xF6, 0xEA, 0xD8), (0x14, 0x11, 0x0E)
# rust is the main colour, gold the secondary one (same as the desktop)
SW, SH, SCREEN = 2560, 1600, (0x0B, 0x0A, 0x09)
W, G, RAD, BORDER = 1040, 40, 6, 2              # card width, glow margin, corner radius, border
SEP = (76,)                                     # hairline under the header
# vertical layout of the card (px from its top edge); the height follows the number of entries
HEADER_Y, FIRST_ITEM_Y, PAD_BOTTOM = 22, 92, 24
ITEM_H, ITEM_GAP = 60, 8
ITEM_PAD = 20                                   # boot_menu item_padding
SEL_PAD = (1, 3)                                # select_* top / bottom piece heights
MENU_SHIFT = ITEM_PAD                           # GRUB draws the first item this far below `top`
# GRUB shows (height + gap - 2*item_padding - selection pads) / (item height + gap) entries,
# so the menu box needs that padding on top of the entries themselves or the last one scrolls
MENU_EXTRA = 2 * ITEM_PAD + sum(SEL_PAD)
HINTS_GAP = 60                                  # card bottom -> key hints
MIN_ENTRIES, MAX_ENTRIES = 2, 12
H = FIRST_ITEM_Y + 2 * ITEM_H + ITEM_GAP + PAD_BOTTOM   # set by main() for the real entry count
CELL_W, CELL_H, FONT_PX = 12, 24, 20            # ASCII grid
RAMP = " .:-=+*#%@"                             # dark -> bright
DIM = 1.0                                       # how bright the ASCII wallpaper gets
FONT = "/usr/share/fonts/TTF/JetBrainsMonoNerdFontMono-Regular.ttf"


def png(path, w, h, row_bytes, alpha=True):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += row_bytes(y)
    ch = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6 if alpha else 2, 0, 0, 0))
                + ch(b"IDAT", zlib.compress(bytes(raw), 9)) + ch(b"IEND", b""))


def solid(path, w, h, rgba):
    png(path, w, h, lambda y: bytes(rgba) * w)


def ffmpeg_raw(args, fmt):
    return subprocess.run(["ffmpeg", "-v", "error", *args, "-f", "rawvideo", "-pix_fmt", fmt, "-"],
                          check=True, capture_output=True).stdout


def glyph_masks(tmp):
    """One CELL_W x CELL_H coverage mask (0..255 per pixel) per ramp character. The whole ramp
    is drawn as one line, so every character sits on the same baseline, then sliced into cells."""
    tf = os.path.join(tmp, "ramp.txt")
    with open(tf, "w") as f:
        f.write(RAMP)
    n = len(RAMP)
    line = ffmpeg_raw(["-f", "lavfi", "-i", f"color=black:s={CELL_W * n}x{CELL_H}", "-frames:v", "1", "-vf",
                       f"drawtext=fontfile={FONT}:textfile={tf}:expansion=none:fontsize={FONT_PX}"
                       f":fontcolor=white:x=0:y=(h-{FONT_PX})/2-2"], "gray")
    return [b"".join(line[y * CELL_W * n + i * CELL_W:y * CELL_W * n + (i + 1) * CELL_W] for y in range(CELL_H))
            for i in range(n)]


def halo(c, r, cols, rows):
    """Brightness factor for an ASCII cell: a soft dark halo around the centred card (down to
    30%) so the card and the key hints under it stay readable; full brightness at the edges."""
    dx = ((c + 0.5) * CELL_W - SW / 2) / 900
    dy = ((r + 0.5) * CELL_H - SH / 2) / max(430, H / 2 + 310)
    t = max(0.0, min(1.0, (math.hypot(dx, dy) - 0.6) / 0.7))
    return 0.3 + 0.7 * t * t * (3 - 2 * t)


def ascii_screen(wallpaper):
    """The wallpaper as coloured ASCII art, as SH rows of SW*3 bytes."""
    cols, rows = -(-SW // CELL_W), -(-SH // CELL_H)
    cells = ffmpeg_raw(["-i", wallpaper, "-frames:v", "1", "-vf",
                        f"scale={cols * CELL_W}:{rows * CELL_H}:force_original_aspect_ratio=increase,"
                        f"crop={cols * CELL_W}:{rows * CELL_H},scale={cols}:{rows}:flags=area"], "rgb24")
    with tempfile.TemporaryDirectory() as tmp:
        masks = glyph_masks(tmp)
    out = [bytearray(bytes(SCREEN) * SW) for _ in range(SH)]
    lums = [(0.2126 * cells[i] + 0.7152 * cells[i + 1] + 0.0722 * cells[i + 2]) / 255
            for i in range(0, len(cells), 3)]
    ranked = sorted(lums)                              # stretch to the wallpaper's own range
    lo, hi = ranked[len(ranked) * 2 // 100], ranked[len(ranked) * 99 // 100]
    for r in range(rows):
        for c in range(cols):
            p = cells[(r * cols + c) * 3:(r * cols + c) * 3 + 3]
            lum = max(0.0, min(1.0, (lums[r * cols + c] - lo) / ((hi - lo) or 1)))
            k = min(len(RAMP) - 1, int(lum ** 0.7 * len(RAMP)))
            if k == 0:
                continue
            # the cell's own colour, brought up to a common brightness then dimmed, so dark
            # areas still read as their hue and bright ones don't shout
            m = max(p) or 1
            col = [min(255, v / m * 255 * (0.55 + 0.45 * lum)) * DIM * halo(c, r, cols, rows) for v in p]
            mask = masks[k]
            for y in range(CELL_H):
                sy = r * CELL_H + y
                if sy >= SH:
                    break
                line = out[sy]
                for x in range(CELL_W):
                    sx = c * CELL_W + x
                    a = mask[y * CELL_W + x]
                    if a and sx < SW:
                        a /= 255
                        o = sx * 3
                        for i in range(3):
                            line[o + i] = round(col[i] * a + SCREEN[i] * (1 - a))
    return out


def sdf(x, y):  # signed distance to the rounded card
    qx = abs(x - W / 2) - (W / 2 - RAD)
    qy = abs(y - H / 2) - (H / 2 - RAD)
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - RAD


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def card(X, Y):
    """RGBA of the card + glow image at (X, Y); the glow is offset 4px down like the shadow."""
    x, y = X - G + 0.5, Y - G + 0.5
    d, dg = sdf(x, y), sdf(x, y - 4)
    glow = 0.25 * max(0, 1 - dg / 22) ** 2 if dg > 0 else 0.25
    if d > 0.5:
        return (*RUST, glow)
    cov = min(1, 0.5 - d)
    inner = max(0, min(1, 0.5 - BORDER - d))
    body = CARD
    if inner > 0 and 24 <= x <= W - 24 and any(s <= y < s + 1 for s in SEP):
        body = mix(CARD, CREAM, 0.16)
    c = mix(mix(RUST, GOLD, max(0, min(1, (x + y) / (W + H)))), body, inner)
    a = cov + glow * (1 - cov)
    return (*(round((c[i] * cov + RUST[i] * glow * (1 - cov)) / a) for i in range(3)), a)


def count_entries(grubcfg):
    """Largest number of entries GRUB shows on one screen: the top level, or any submenu."""
    counts, stack, n = {}, [], 0
    for line in open(grubcfg, encoding="utf-8", errors="replace"):
        s = line.strip()
        m = re.match(r"(menuentry|submenu)\s", s)
        if m:
            parent = next((b for b in reversed(stack) if b[0] == "submenu"), ("root", -1))
            counts[parent] = counts.get(parent, 0) + 1
        if s.endswith("{"):
            n += 1
            stack.append((m.group(1) if m else "block", n))
        elif s == "}" and stack:
            stack.pop()
    return max(counts.values(), default=MIN_ENTRIES)


THEME = """\
# GRUB theme "glass" - GENERATED by make-glass.py ({entries} entries); edit that, not this.
# Looks like a focused window on the desktop, over the wallpaper drawn as ASCII art: a centred
# warm-black card with Hyprland's active-window border (rust->gold) and rust glow, a header row
# like a Waybar island, the selected entry styled like the active Waybar workspace (rust tint +
# rust underline), the countdown top-right like the Waybar clock, JetBrains Mono.
# The card ({w}x{h}) is baked into background.png: GRUB draws `image` components over the menu.

title-text: ""
desktop-color: "#0b0a09"
desktop-image: "background.png"
desktop-image-scale-method: "stretch"
message-font: "JetBrainsMono NFM Regular 22"
message-color: "#ecdfcc"
message-bg-color: "#0b0a09"
terminal-font: "JetBrainsMono NFM Regular 22"
terminal-box: "term_*.png"

# header: Arch logo + host on the left, the countdown on the right (gone once a key is pressed)
+ label {{
    left = 50%-488
    top = 50%{header:+d}
    width = 976
    height = 32
    text = "\uf303  tux"
    font = "JetBrainsMono NFM Bold 22"
    color = "#e8732a"
}}
+ label {{
    left = 50%-488
    top = 50%{header:+d}
    width = 976
    height = 32
    align = "right"
    id = "__timeout__"
    text = "%ds"
    font = "JetBrainsMono NFM Regular 22"
    color = "#f4b942"
}}

+ boot_menu {{
    left = 50%-500
    top = 50%{menu:+d}
    width = 1000
    height = {menu_h}
    item_font = "JetBrainsMono NFM Regular 26"
    selected_item_font = "JetBrainsMono NFM Bold 26"
    item_color = "#b8a998"
    selected_item_color = "#e8732a"
    selected_item_pixmap_style = "select_*.png"
    item_height = {item_h}
    item_padding = {item_pad}
    item_spacing = {item_gap}
    icon_width = 0
    icon_height = 0
    item_icon_space = 0
    scrollbar = false
}}

# key hints under the card
+ label {{
    left = 0
    top = 50%{hints:+d}
    width = 100%
    height = 32
    align = "center"
    text = "\u2191\u2193 select    enter boot    e edit    c shell"
    font = "JetBrainsMono NFM Regular 22"
    color = "#8a7d70"
}}
"""


def main():
    global H
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("outdir")
    ap.add_argument("--wallpaper")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--grubcfg", help="count the entries in this grub.cfg")
    g.add_argument("--entries", type=int, help="size the card for N entries")
    a = ap.parse_args()
    out, wall = a.outdir, a.wallpaper
    os.makedirs(out, exist_ok=True)

    found = count_entries(a.grubcfg) if a.grubcfg else (a.entries or 3)
    n = max(MIN_ENTRIES, min(MAX_ENTRIES, found))
    block = n * ITEM_H + (n - 1) * ITEM_GAP
    H = FIRST_ITEM_Y + block + PAD_BOTTOM
    top = (SH - H) // 2                       # card top on screen; theme positions are from the centre
    with open(os.path.join(out, "theme.txt"), "w", encoding="utf-8") as f:
        f.write(THEME.format(entries=n, w=W, h=H, header=top + HEADER_Y - SH // 2,
                             menu=top + FIRST_ITEM_Y - MENU_SHIFT - SH // 2, menu_h=block + MENU_EXTRA,
                             item_h=ITEM_H, item_gap=ITEM_GAP, item_pad=ITEM_PAD, hints=top + H + HINTS_GAP - SH // 2))

    screen = ascii_screen(wall) if wall else [bytearray(bytes(SCREEN) * SW) for _ in range(SH)]
    cw, chh = W + 2 * G, H + 2 * G
    cx, cy = (SW - cw) // 2, (SH - chh) // 2
    for y in range(chh):
        line = screen[cy + y]
        for x in range(cw):
            *c, a = card(x, y)
            if a <= 0:
                continue
            o = (cx + x) * 3
            line[o:o + 3] = bytes(round(c[i] * a + line[o + i] * (1 - a)) for i in range(3))
    png(os.path.join(out, "background.png"), SW, SH, lambda y: bytes(screen[y]), alpha=False)

    tint = (*RUST, 40)
    for p in "nw n ne w c e".split():
        solid(os.path.join(out, f"select_{p}.png"), 1, 1, tint)
    for p in "sw s se".split():  # 1px tint, then a 2px gold underline
        png(os.path.join(out, f"select_{p}.png"), 1, 3, lambda y: bytes(tint if y == 0 else (*RUST, 255)))
    for p, (w, h) in {"nw": (2, 2), "ne": (2, 2), "sw": (2, 2), "se": (2, 2),
                      "n": (1, 2), "s": (1, 2), "w": (2, 1), "e": (2, 1)}.items():
        solid(os.path.join(out, f"term_{p}.png"), w, h, (*RUST, 255))
    solid(os.path.join(out, "term_c.png"), 1, 1, (*CARD, 250))
    print(f"wrote {out} (card sized for {n} entries{f', menu has {found}' if found != n else ''})")


if __name__ == "__main__":
    main()
