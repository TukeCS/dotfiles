# Twilight Peak Dotfiles (Gentoo + Hyprland + OpenRC)

My personal dotfiles for Gentoo Linux using Hyprland, OpenRC, and the Twilight Peak theme. Managed with GNU Stow.

---

## 📦 Required Dependencies

### 1. System & Session (OpenRC)
* `sys-auth/elogind` - Power and session management (handles `loginctl suspend`)
* `sys-apps/dbus` - Inter-process communication
* `x11-misc/xdg-user-dirs` - Standard folder generation (`Pictures`, `Documents`, etc.)

### 2. Desktop & Window Manager
* `gui-wm/hyprland` - Wayland compositor
* `gui-apps/waybar` - Status bar
* `gui-apps/rofi-wayland` - Application launcher
* `gui-apps/hypridle` - Idle daemon (auto-sleep / lock timer)
* `gui-apps/hyprlock` - Screen locker
* `gui-apps/hyprpaper` - Wallpaper daemon

### 3. Applications & Terminal
* `x11-terms/kitty` - Terminal emulator
* `www-client/firefox` - Web browser
* `kde-apps/dolphin` - File manager
* `app-misc/fastfetch` - System information display

### 4. Utilities & Media Controls
* `media-video/wireplumber` - Audio control (`wpctl`)
* `media-sound/playerctl` - Media key support
* `sys-power/brightnessctl` - Screen brightness control
* `gui-apps/nwg-look` - GTK theme customizer
* `dev-vcs/git` - Version control
* `app-admin/stow` - Symlink manager for dotfiles

### 5. Fonts & Themes
* `media-fonts/nerd-fonts` (or JetBrainsMono Nerd Font)
* `media-fonts/noto`
* GTK Icons: `breeze-dark`
* Cursor Theme: `breeze_cursors`

---

## ⚡ Quick Install (Fresh Gentoo Setup)

### 1. Install all packages:
```bash
sudo emerge -av \
  sys-auth/elogind sys-apps/dbus x11-misc/xdg-user-dirs \
  gui-wm/hyprland gui-apps/waybar gui-apps/rofi-wayland \
  gui-apps/hypridle gui-apps/hyprlock gui-apps/hyprpaper \
  x11-terms/kitty www-client/firefox kde-apps/dolphin \
  app-misc/fastfetch media-video/wireplumber media-sound/playerctl \
  sys-power/brightnessctl gui-apps/nwg-look dev-vcs/git app-admin/stow
```

### 2. Enable OpenRC Services:
```bash
sudo rc-update add dbus default
sudo rc-update add elogind boot
```

### 3. Clone and Deploy Dotfiles:
```bash
git clone git@github.com:TukeCS/dotfiles.git ~/dotfiles
cd ~/dotfiles
./sync.sh
xdg-user-dirs-update
```