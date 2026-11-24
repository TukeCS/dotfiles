#!/bin/sh
# Runs before Ly takes over the TTY.
# The Linux console only has 16 colours, so the palette itself is replaced with
# colours picked from the wallpaper (/etc/ly/palette, written by make-ly-art.py).
# Slots Ly's UI uses stay fixed: 0 black, 2 moss (border), 7 light grey (text), 9 red (errors).

[ "$TERM" = "linux" ] || exit 0

PALETTE=/etc/ly/palette
if [ -r "$PALETTE" ]; then
	COLORS=$(cat "$PALETTE")
else
	COLORS="000000 e07a5f a8bf4a e6c35c 6f98a8 a9b3a5 8fb8c4 e6e6e6 666666 e07a5f b8d14e d4e09b 8fb8c4 a9b3a5 8fb8c4 ffffff"
fi

i=0
for c in $COLORS; do
	printf "\033]P%x%s" "$i" "$c"
	i=$((i + 1))
done

clear # repaint the background with the new black
