#!/usr/bin/env bash
# Wi-Fi menu in rofi, using NetworkManager (nmcli).
# Click a network to connect (asks for a password if needed),
# click the connected one to disconnect or forget it.

menu() { rofi -dmenu -i -no-show-icons -theme-str 'element { children: [ element-text ]; }' -p "$1" "${@:2}"; }
notify() { command -v notify-send >/dev/null && notify-send -a wifi "$@"; }
askpw() { menu "${1:-password}" -password -l 0 -theme-str 'entry { placeholder: ""; }' </dev/null; }

# UUID of the saved profile for an SSID (matched on SSID, not profile name)
saved_con() {
  local uuid type
  while IFS=: read -r uuid type; do
    [ "$type" = 802-11-wireless ] || continue
    [ "$(nmcli --escape no -g 802-11-wireless.ssid con show uuid "$uuid")" = "$1" ] && { echo "$uuid"; return; }
  done < <(nmcli -t -f UUID,TYPE con show)
}

# 802.1X (eduroam etc.): always ask for the password, never store it
connect_eap() {
  local uuid=$1 ssid=$2 user pw out
  user=$(nmcli --escape no -g 802-1x.identity con show uuid "$uuid")
  pw=$(askpw "${user:+$user }password") || return
  [ -z "$pw" ] && return
  notify "Connecting…" "$ssid"
  if out=$(nmcli con up uuid "$uuid" passwd-file <(printf '802-1x.identity:%s\n802-1x.password:%s\n' "$user" "$pw") 2>&1); then
    notify "Connected" "$ssid"
  else
    notify -u critical "Couldn't connect" "$ssid: ${out##*Error: }"
  fi
}

bars() {
  local s=$1
  if   (( s >= 75 )); then echo "󰤨"
  elif (( s >= 50 )); then echo "󰤥"
  elif (( s >= 25 )); then echo "󰤢"
  else                     echo "󰤟"; fi
}

main() {
  local radio; radio=$(nmcli radio wifi)
  if [ "$radio" != "enabled" ]; then
    case "$(printf '󰖩  Turn Wi-Fi on\n' | menu 'wifi')" in
      *on) nmcli radio wifi on && notify "Wi-Fi on" ;;
    esac
    return
  fi

  local -a ssids secs actives labels
  local seen="|"
  # ACTIVE:SIGNAL:SECURITY:SSID  (SSID last so colons in names are safe)
  while IFS= read -r line; do
    local active=${line%%:*}; line=${line#*:}
    local signal=${line%%:*}; line=${line#*:}
    local sec=${line%%:*};    local ssid=${line#*:}
    [ -z "$ssid" ] && continue
    case "$seen" in *"|$ssid|"*) continue ;; esac   # one entry per network name
    seen+="$ssid|"
    local lock=""; [ -n "$sec" ] && [ "$sec" != "--" ] && lock="  󰌾"
    local mark=""; [ "$active" = "yes" ] && mark="  ✓"
    ssids+=("$ssid"); secs+=("$sec"); actives+=("$active")
    labels+=("$(bars "$signal")  $ssid$lock$mark")
  done < <(nmcli -t --escape no -f ACTIVE,SIGNAL,SECURITY,SSID dev wifi list --rescan auto | sort -t: -k1,1r -k2,2nr)

  local extra=$'󰑐  Rescan\n󰖪  Turn Wi-Fi off\n󰒓  Advanced (nmtui)'
  local choice
  choice=$( { printf '%s\n' "${labels[@]}"; printf '%s\n' "$extra"; } | menu 'wifi' -format i) || return
  [ -z "$choice" ] && return

  local n=${#labels[@]}
  if (( choice >= n )); then
    case $(( choice - n )) in
      0) notify "Scanning…"; nmcli dev wifi rescan 2>/dev/null; sleep 2; main ;;
      1) nmcli radio wifi off && notify "Wi-Fi off" ;;
      2) ghostty --class=tui.float -e nmtui & ;;
    esac
    return
  fi

  local ssid=${ssids[$choice]} sec=${secs[$choice]} active=${actives[$choice]}

  local con; con=$(saved_con "$ssid")

  if [ "$active" = "yes" ]; then
    case "$(printf '󰖪  Disconnect\n󰆴  Forget network\n' | menu "$ssid")" in
      *Disconnect) nmcli dev disconnect "$(nmcli -t -f DEVICE,TYPE dev | awk -F: '$2=="wifi"{print $1; exit}')" >/dev/null && notify "Disconnected" "$ssid" ;;
      *Forget*)    [ -n "$con" ] && nmcli con delete uuid "$con" >/dev/null && notify "Forgot network" "$ssid" ;;
    esac
    return
  fi

  # Saved network: bring it up with the stored password, no prompt
  if [ -n "$con" ]; then
    if [ "$(nmcli -g 802-11-wireless-security.key-mgmt con show uuid "$con")" = wpa-eap ]; then
      connect_eap "$con" "$ssid"; return
    fi
    notify "Connecting…" "$ssid"
    if nmcli con up uuid "$con" >/dev/null 2>&1; then notify "Connected" "$ssid"; return; fi
    # Stored password missing or wrong: ask once and save it for next time
    if [ -n "$sec" ] && [ "$sec" != "--" ]; then
      local pw; pw=$(askpw) || return
      [ -z "$pw" ] && return
      nmcli con modify uuid "$con" wifi-sec.psk "$pw" wifi-sec.psk-flags 0
      if nmcli con up uuid "$con" >/dev/null 2>&1; then notify "Connected" "$ssid"; return; fi
    fi
    notify -u critical "Couldn't connect" "$ssid"
    return
  fi

  if [[ "$sec" == *802.1X* ]]; then
    notify -u critical "Enterprise network" "No saved profile for $ssid. Use eduroam-connect or nmtui."
    return
  fi

  # New network
  local out
  if [ -z "$sec" ] || [ "$sec" = "--" ]; then
    out=$(nmcli dev wifi connect "$ssid" 2>&1)
  else
    local pw; pw=$(askpw) || return
    [ -z "$pw" ] && return
    notify "Connecting…" "$ssid"
    out=$(nmcli dev wifi connect "$ssid" password "$pw" 2>&1)
  fi
  if [ $? -eq 0 ]; then
    notify "Connected" "$ssid"
  else
    nmcli con delete id "$ssid" >/dev/null 2>&1   # don't keep a broken profile
    notify -u critical "Couldn't connect" "$ssid: ${out##*Error: }"
  fi
}

main
