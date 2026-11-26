#!/usr/bin/env bash
# Installs the "glass" GRUB theme (a centred window matching the desktop) and /etc/default/grub,
# then regenerates grub.cfg.
# Run:  sudo ~/dotfiles/system/grub/install.sh
# (The older "golden" theme is still in golden/; point GRUB_THEME in ./grub at it to switch back.)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
theme=/boot/grub/themes/glass

[ -f /etc/default/grub.bak ] || cp /etc/default/grub /etc/default/grub.bak   # keep the original once
install -m 644 "$here/grub" /etc/default/grub

# A first, quick pass before grub-mkconfig: it only writes the theme lines if theme.txt exists,
# only adds `insmod png` if the folder has PNGs, and adds a loadfont line for every .pf2.
rm -rf "$theme"
install -d "$theme"
install -m 644 "$here"/glass/*.pf2 "$theme"/
python3 "$here/make-glass.py" "$theme" >/dev/null
grub-mkconfig -o /boot/grub/grub.cfg

# then the theme itself, sized for the menu grub-mkconfig just wrote, over your current
# wallpaper drawn as ASCII art. Rerun this after changing the wallpaper or adding an OS.
home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
wall="$home/Pictures/Wallpapers/current.png"
if [ -f "$wall" ] && command -v ffmpeg >/dev/null; then
  python3 "$here/make-glass.py" "$theme" --grubcfg /boot/grub/grub.cfg --wallpaper "$wall"
else
  echo "no wallpaper at $wall: plain background"
  python3 "$here/make-glass.py" "$theme" --grubcfg /boot/grub/grub.cfg
fi
echo "done. original config saved as /etc/default/grub.bak"
