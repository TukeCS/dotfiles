#!/usr/bin/env bash
# Bluetooth menu in rofi, using bluetoothctl.
# Click a device to connect / pair it, click a connected one to disconnect or forget it.

NOICON="element { children: [ element-text ]; }"
menu() { rofi -dmenu -i -no-show-icons -theme-str "$NOICON" -p "$1" "${@:2}"; }
notify() { command -v notify-send >/dev/null && notify-send -a bluetooth "$@"; }
bt() { timeout "${BT_TIMEOUT:-10}" bluetoothctl "$@"; }

icon_for() {
  case "$1" in
    audio-headset|audio-headphones) echo "󰋋" ;;
    audio-card)                     echo "󰓃" ;;
    input-mouse)                    echo "󰍽" ;;
    input-keyboard)                 echo "󰌌" ;;
    input-gaming)                   echo "󰊴" ;;
    phone)                          echo "󰏲" ;;
    computer)                       echo "󰟀" ;;
    *)                              echo "󰂯" ;;
  esac
}

main() {
  if ! bt show | grep -q "Powered: yes"; then
    case "$(printf '󰂯  Turn Bluetooth on\n' | menu 'bluetooth')" in
      *on) rfkill unblock bluetooth 2>/dev/null; bt power on >/dev/null && notify "Bluetooth on" ;;
    esac
    return
  fi

  local -a macs names states labels
  local paired; paired=$(bt devices Paired | awk '{print $2}')
  while read -r _ mac name; do
    [ -z "$mac" ] && continue
    local info; info=$(bt info "$mac")
    local ico; ico=$(icon_for "$(sed -n 's/^\s*Icon: //p' <<<"$info")")
    local state="new" extra="  (new)"
    if grep -qx "$mac" <<<"$paired"; then state="paired"; extra=""; fi
    if grep -q "Connected: yes" <<<"$info"; then
      state="connected"; extra="  ✓"
      local bat; bat=$(sed -n 's/.*Battery Percentage:.*(\([0-9]*\)).*/\1/p' <<<"$info")
      [ -n "$bat" ] && extra="  ${bat}%$extra"
    fi
    macs+=("$mac"); names+=("$name"); states+=("$state")
    labels+=("$ico  $name$extra")
  done < <(bt devices)

  # connected first, then paired, then new
  local -a order=()
  for want in connected paired new; do
    for i in "${!states[@]}"; do [ "${states[$i]}" = "$want" ] && order+=("$i"); done
  done

  local extra=$'󰑐  Scan for devices\n󰂲  Turn Bluetooth off\n󰒓  Advanced (bluetui)'
  local choice
  choice=$( { for i in "${order[@]}"; do printf '%s\n' "${labels[$i]}"; done; printf '%s\n' "$extra"; } \
            | menu 'bluetooth' -format i) || return
  [ -z "$choice" ] && return

  local n=${#order[@]}
  if (( choice >= n )); then
    case $(( choice - n )) in
      0) notify "Scanning for 10 seconds…" "Put your device in pairing mode"
         BT_TIMEOUT=12 bluetoothctl --timeout 10 scan on >/dev/null 2>&1; main ;;
      1) bt power off >/dev/null && notify "Bluetooth off" ;;
      2) ghostty --class=tui.float -e bluetui & ;;
    esac
    return
  fi

  local i=${order[$choice]}
  local mac=${macs[$i]} name=${names[$i]} state=${states[$i]}

  case "$state" in
    connected)
      case "$(printf '󰂲  Disconnect\n󰆴  Forget device\n' | menu "$name")" in
        *Disconnect) bt disconnect "$mac" >/dev/null && notify "Disconnected" "$name" ;;
        *Forget*)    bt remove "$mac" >/dev/null && notify "Forgot device" "$name" ;;
      esac ;;
    paired)
      notify "Connecting…" "$name"
      if bt connect "$mac" | grep -q "Connection successful"; then notify "Connected" "$name"
      else notify -u critical "Couldn't connect" "$name"; fi ;;
    new)
      notify "Pairing…" "$name"
      if BT_TIMEOUT=30 bt pair "$mac" | grep -qiE "Pairing successful|AlreadyExists"; then
        bt trust "$mac" >/dev/null
        if bt connect "$mac" | grep -q "Connection successful"; then notify "Connected" "$name"
        else notify "Paired" "$name (connect it from the menu)"; fi
      else
        notify -u critical "Pairing failed" "$name: try Advanced (bluetui) if it needs a PIN"
      fi ;;
  esac
}

main
