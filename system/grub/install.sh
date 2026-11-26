#!/usr/bin/env bash
# Installs the "glass" GRUB theme (a centred window matching the desktop) and /etc/default/grub,
# then regenerates grub.cfg.
# Run:  sudo ~/dotfiles/system/grub/install.sh
# (The older "golden" theme is still in golden/; point GRUB_THEME in ./grub at it to switch back.)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
theme=/boot/grub/themes/glass

rm -rf "$theme"
install -d "$theme"
install -m 644 "$here"/glass/* "$theme"/

# background.png = your current wallpaper as ASCII art with the card baked in (make-glass.py).
# Not kept in the repo; rerun this after changing the wallpaper.
home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
wall="$home/Pictures/Wallpapers/current.png"
if [ -f "$wall" ] && command -v ffmpeg >/dev/null; then
  python3 "$here/make-glass.py" "$theme" "$wall"
else
  echo "no wallpaper at $wall: plain background"
  python3 "$here/make-glass.py" "$theme"
fi

[ -f /etc/default/grub.bak ] || cp /etc/default/grub /etc/default/grub.bak   # keep the original once
install -m 644 "$here/grub" /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg
echo "done. original config saved as /etc/default/grub.bak"
