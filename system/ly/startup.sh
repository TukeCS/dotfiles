#!/bin/sh
# Runs before Ly takes over the TTY.
# The Linux console only has 16 colours, so instead of true colour the palette itself is
# replaced: black/white/greys, moss green, and the muted tones used elsewhere in the rice.

if [ "$TERM" = "linux" ]; then
	BLACK="000000"
	DARK_RED="e07a5f"     # lava: errors
	DARK_GREEN="a8bf4a"   # moss: box border, accent
	DARK_YELLOW="e6c35c"  # sulfur
	DARK_BLUE="6f98a8"    # fjord
	DARK_MAGENTA="a9b3a5" # ash (no magenta in this theme)
	DARK_CYAN="8fb8c4"    # glacier
	LIGHT_GRAY="e6e6e6"   # main text
	DARK_GRAY="666666"
	RED="e07a5f"
	GREEN="b8d14e"
	YELLOW="d4e09b"
	BLUE="8fb8c4"
	MAGENTA="a9b3a5"
	CYAN="8fb8c4"
	WHITE="ffffff"

	COLORS="${BLACK} ${DARK_RED} ${DARK_GREEN} ${DARK_YELLOW} ${DARK_BLUE} ${DARK_MAGENTA} ${DARK_CYAN} ${LIGHT_GRAY} ${DARK_GRAY} ${RED} ${GREEN} ${YELLOW} ${BLUE} ${MAGENTA} ${CYAN} ${WHITE}"

	i=0
	for c in $COLORS; do
		printf "\033]P%x%s" "$i" "$c"
		i=$((i + 1))
	done

	clear # repaint the background with the new black
fi
