hl.on("hyprland.start", function () 
  hl.exec_cmd(terminal)
  hl.exec_cmd("waybar & hyprpaper & hypridle")
  hl.exec_cmd("/usr/lib64/libexec/hyprpolkitagent")

  -- gtk themes
  hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
  hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'")
  -- Screen sharing and audio services for OpenRC
  hl.exec_cmd("gentoo-pipewire-launcher")
  hl.exec_cmd("dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")


end)
