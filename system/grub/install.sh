#!/usr/bin/env bash
# Installs the "term" GRUB theme (amber-phosphor terminal) and /etc/default/grub,
# then regenerates grub.cfg.
# Run:  sudo ~/dotfiles/system/grub/install.sh
# (The older "golden" theme is still in golden/; point GRUB_THEME in ./grub at it to switch back.)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
theme=/boot/grub/themes/term

rm -rf "$theme"
install -d "$theme"
install -m 644 "$here"/term/* "$theme"/

[ -f /etc/default/grub.bak ] || cp /etc/default/grub /etc/default/grub.bak   # keep the original once
install -m 644 "$here/grub" /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg
echo "done. original config saved as /etc/default/grub.bak"
