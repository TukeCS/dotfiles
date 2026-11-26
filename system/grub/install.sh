#!/usr/bin/env bash
# Installs the "glow terminal" GRUB theme and /etc/default/grub, then regenerates grub.cfg.
# Run:  sudo ~/dotfiles/system/grub/install.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"

install -d /boot/grub/themes/golden
install -m 644 "$here"/golden/* /boot/grub/themes/golden/

# GRUB background = your current wallpaper (not kept in the repo), slightly darkened
home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
wall="$home/Pictures/Wallpapers/current.png"
if [ -f "$wall" ] && command -v ffmpeg >/dev/null; then
  ffmpeg -v error -y -i "$wall" -vf "scale=2560:1600:force_original_aspect_ratio=increase,crop=2560:1600,eq=brightness=-0.04" \
    -q:v 3 /boot/grub/themes/golden/background.jpg
else
  echo "no wallpaper at $wall: GRUB gets a plain dark background"
fi

[ -f /etc/default/grub.bak ] || cp /etc/default/grub /etc/default/grub.bak   # keep the original once
install -m 644 "$here/grub" /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg
echo "done. original config saved as /etc/default/grub.bak"
