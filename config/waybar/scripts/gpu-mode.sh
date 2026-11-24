#!/usr/bin/env bash
# Waybar module for supergfxctl. Hidden until supergfxctl is installed.
command -v supergfxctl >/dev/null || exit 0
if [ "$1" = "next" ]; then
  cur="$(supergfxctl -g 2>/dev/null)"
  case "$cur" in
    Hybrid) new="Integrated" ;;
    *)      new="Hybrid" ;;
  esac
  supergfxctl -m "$new" >/dev/null 2>&1
  command -v notify-send >/dev/null && notify-send "GPU mode → $new" "Log out and back in to apply."
  pkill -RTMIN+9 waybar
  exit 0
fi
mode="$(supergfxctl -g 2>/dev/null)"
[ -z "$mode" ] && exit 0
pending="$(supergfxctl -P 2>/dev/null)"
tip="GPU mode: $mode"
[ -n "$pending" ] && [ "$pending" != "None" ] && tip="$tip\\nPending: $pending"
cls="$(echo "$mode" | tr '[:upper:]' '[:lower:]')"
printf '{"text":"󰢮 %s","tooltip":"%s\\nClick: toggle Hybrid/Integrated","class":"%s"}\n' "$mode" "$tip" "$cls"
