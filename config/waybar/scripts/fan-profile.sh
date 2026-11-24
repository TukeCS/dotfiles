#!/usr/bin/env bash
# Waybar module for asusctl fan/power profiles. Arg "next" cycles.
if [ "$1" = "next" ]; then
  asusctl profile next >/dev/null 2>&1
  pkill -RTMIN+8 waybar
  exit 0
fi
p="$(asusctl profile get 2>/dev/null | awk -F': ' '/Active profile/{print $2}')"
case "$p" in
  Quiet)       icon="󰾆" ;;
  Balanced)    icon="󰾅" ;;
  Performance) icon="󰓅" ;;
  *)           icon="󰈐"; p="${p:-unknown}" ;;
esac
cls="$(echo "$p" | tr '[:upper:]' '[:lower:]')"
printf '{"text":"%s %s","tooltip":"Fan profile: %s\\nClick: next profile","class":"%s"}\n' "$icon" "$p" "$p" "$cls"
