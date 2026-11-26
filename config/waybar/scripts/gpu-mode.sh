#!/usr/bin/env bash
# Waybar module + rofi menu for supergfxctl. Hidden until supergfxctl is installed.
#   gpu-mode.sh        -> JSON for waybar
#   gpu-mode.sh menu   -> pick a mode in rofi
command -v supergfxctl >/dev/null || exit 0

short() {
  case "$1" in
    AsusMuxDgpu) echo "dGPU" ;;
    Hybrid)      echo "Hybrid" ;;
    Integrated)  echo "iGPU" ;;
    AsusEgpu)    echo "eGPU" ;;
    Vfio)        echo "VFIO" ;;
    *)           echo "$1" ;;
  esac
}
describe() {
  case "$1" in
    AsusMuxDgpu) echo "dGPU only: fastest, uses the most battery" ;;
    Hybrid)      echo "Hybrid: iGPU by default, dGPU when needed" ;;
    Integrated)  echo "iGPU only: best battery life" ;;
    *)           echo "$1" ;;
  esac
}

cur=$(supergfxctl -g 2>/dev/null)
[ -z "$cur" ] && exit 0
pend=$(supergfxctl -P 2>/dev/null)
case "$pend" in ""|None|Unknown|"$cur") pend="" ;; esac
# The MUX switch only takes effect on reboot; read it directly as the source of truth.
# gpu_mux_mode: 0 = dGPU only, 1 = iGPU/hybrid
mux=/sys/devices/platform/asus-nb-wmi/gpu_mux_mode
if [ -z "$pend" ] && [ -r "$mux" ]; then
  m=$(cat "$mux")
  if   [ "$cur" = "AsusMuxDgpu" ] && [ "$m" = "1" ]; then pend="Hybrid"
  elif [ "$cur" != "AsusMuxDgpu" ] && [ "$m" = "0" ]; then pend="AsusMuxDgpu"; fi
fi
action=$(supergfxctl -p 2>/dev/null)

if [ "$1" = "menu" ]; then
  notify() { command -v notify-send >/dev/null && notify-send -a gpu "$@"; }
  modes=(Hybrid Integrated AsusMuxDgpu)
  labels=""
  for m in "${modes[@]}"; do
    tag=""
    [ "$m" = "$cur" ]  && tag="  ● now"
    [ "$m" = "$pend" ] && tag="  ⟳ after reboot"
    labels+="$(short "$m")  ·  $(describe "$m")$tag"$'\n'
  done
  msg="Now: $(short "$cur")"
  [ -n "$pend" ] && msg+="   →   $(short "$pend") after reboot (pick $(short "$cur") to cancel)"
  idx=$(printf '%s' "$labels" | rofi -dmenu -i -no-show-icons -format i -p 'gpu' -mesg "$msg" \
        -theme-str 'element { children: [ element-text ]; } listview { lines: 3; } window { width: 640px; } mainbox { children: [ inputbar, message, listview ]; } textbox { text-color: #f29a38; padding: 0 4px; }') || exit 0
  [ -z "$idx" ] && exit 0
  new=${modes[$idx]}
  # Nothing to do if it's already the mode we're in with nothing pending, or already pending
  if { [ "$new" = "$cur" ] && [ -z "$pend" ]; } || [ "$new" = "$pend" ]; then exit 0; fi
  if out=$(supergfxctl -m "$new" 2>&1); then
    after=$(supergfxctl -P 2>/dev/null); act=$(supergfxctl -p 2>/dev/null)
    if [ "$new" = "$cur" ]; then
      notify "GPU switch cancelled" "Staying on $(short "$cur")"
    elif [ -n "$after" ] && [ "$after" != "None" ] && [ "$after" != "$cur" ]; then
      notify "GPU → $(short "$new") after reboot" "${act:-Reboot to apply}"
    else
      notify "GPU → $(short "$new")" "${act:-Done}"
    fi
  else
    notify -u critical "Couldn't switch GPU mode" "$out"
  fi
  pkill -RTMIN+9 waybar
  exit 0
fi

text="󰢮  $(short "$cur")"
tip="GPU: $(describe "$cur")"
cls=$(echo "$cur" | tr '[:upper:]' '[:lower:]')
if [ -n "$pend" ]; then
  text+=" → $(short "$pend")"
  tip+="\\nAfter reboot: $(describe "$pend")"
  cls="pending"
fi
[ -n "$action" ] && [ "$action" != "No action required" ] && tip+="\\n$action"
tip+="\\nClick: choose mode"
printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tip" "$cls"
