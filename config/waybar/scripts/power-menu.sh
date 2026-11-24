#!/usr/bin/env bash
choice="$(printf '󰌾  Lock\n󰍃  Logout\n󰒲  Suspend\n󰜉  Reboot\n󰐥  Shutdown' | rofi -dmenu -p '' -l 5)"
case "$choice" in
  *Lock)     hyprlock ;;
  *Logout)   hyprctl dispatch 'hl.dsp.exit()' ;;
  *Suspend)  systemctl suspend ;;
  *Reboot)   systemctl reboot ;;
  *Shutdown) systemctl poweroff ;;
esac
