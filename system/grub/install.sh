#!/usr/bin/env bash
# Installs the "ember" GRUB theme and /etc/default/grub, then regenerates grub.cfg.
# Run:  sudo ~/dotfiles/system/grub/install.sh
# (The older "golden" theme is still in golden/; point GRUB_THEME in ./grub at it to switch back.)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
theme=/boot/grub/themes/ember

install -d "$theme"
install -m 644 "$here"/ember/*.png "$here"/ember/*.pf2 "$here"/ember/theme.txt "$theme"/

# GRUB background = your current wallpaper (not kept in the repo), with the left side
# faded to warm black so the menu reads. yuvj420p matters: GRUB's JPEG decoder only
# handles standard 4:2:0 / 4:4:4 sampling and silently drops the whole theme otherwise.
home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
wall="$home/Pictures/Wallpapers/current.png"
if [ -f "$wall" ] && command -v ffmpeg >/dev/null; then
  f='st(0,clip((X-380)/1300,0,1));st(0,0.12+0.88*ld(0)*ld(0)*(3-2*ld(0)))'
  ffmpeg -v error -y -i "$wall" -vf "scale=2560:1600:force_original_aspect_ratio=increase,crop=2560:1600,format=gbrp,\
geq=r='$f;r(X,Y)*ld(0)+14*(1-ld(0))':g='$f;g(X,Y)*ld(0)+12*(1-ld(0))':b='$f;b(X,Y)*ld(0)+10*(1-ld(0))',format=yuvj420p" \
    -q:v 2 "$theme/background.jpg"
else
  echo "no wallpaper at $wall: GRUB gets a plain warm-black background"
fi

[ -f /etc/default/grub.bak ] || cp /etc/default/grub /etc/default/grub.bak   # keep the original once
install -m 644 "$here/grub" /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg
echo "done. original config saved as /etc/default/grub.bak"
