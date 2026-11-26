#!/bin/sh
# Runs before Ly takes over the TTY.
# The Linux console only has 16 colours, so the palette itself is replaced with
# colours picked from the wallpaper (/etc/ly/palette, written by make-ly-art.py).
# Slots Ly's UI uses stay fixed: 0 warm black, 2 gold (border), 7 cream (text), 9 red (errors).

[ "$TERM" = "linux" ] || exit 0

PALETTE=/etc/ly/palette
if [ -r "$PALETTE" ]; then
	COLORS=$(cat "$PALETTE")
else
	COLORS="0e0d0c e5534b f4b942 f5ad42 7fa6c4 d690ad 78bfa8 ecdfcc 8a7564 e0463a f2913d f7c862 a3c3db e6aec6 98d4c0 fff4e3"
fi

i=0
for c in $COLORS; do
	printf "\033]P%x%s" "$i" "$c"
	i=$((i + 1))
done

clear # repaint the background with the new black
