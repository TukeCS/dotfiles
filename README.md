# dotfiles

Hyprland setup for Arch Linux. Black and white, square corners, with a moss-green accent.

| Part | What |
|---|---|
| Window manager | Hyprland (Lua config), hyprpaper, hyprlock |
| Bar | Waybar with fan-profile (asusctl), GPU mode (supergfxctl), power menu |
| Launcher | rofi |
| Terminal | ghostty + fastfetch with a block-art logo |
| Notifications | mako |
| Theme | Monochrome Qt/KDE colour scheme, dark GTK |

## Install

```sh
git clone https://github.com/TukeCS/dotfiles ~/dotfiles
cd ~/dotfiles
./install.sh            # installs packages, then links configs
./install.sh --no-pkgs  # only link configs
```

Existing files are moved to `~/.dotfiles-backup/<date>/` before being replaced.
The configs are symlinks into this repo, so edits you make show up in `git status`.

Wallpaper is not included: put any image at `~/Pictures/Wallpapers/wallpaper.jpg`.

## Keys

| Key | Action |
|---|---|
| `Super + R` | app launcher (rofi) |
| `Super + L` | lock screen |
| `Print` | screenshot of the whole screen |
| `Super + Print` | screenshot of a selected area |

Screenshots are saved to `~/Pictures/Screenshots/Screenshot_YYYY-MM-DD_HH-MM-SS.png` and copied to the clipboard.

## Waybar

- **Fan profile**: click to cycle Quiet / Balanced / Performance (needs `asusctl`).
- **GPU mode**: click for a rofi menu (Hybrid / iGPU / dGPU). Shows `dGPU → Hybrid` while a switch waits for a reboot (needs `supergfxctl`; hidden otherwise).
- **Coffee cup**: idle inhibitor, keeps the screen awake.
- **Bluetooth icon**: click for a rofi menu (connect, pair, disconnect, forget, scan); right-click for bluetui.
- **Wi-Fi icon**: click for a rofi Wi-Fi menu (connect, password prompt, disconnect, forget); right-click for nmtui.
- **Power icon**: lock, logout, suspend, reboot, shutdown.

## fastfetch logo

The logo is generated from `config/fastfetch/logo-source.png` (a transparent PNG).
To use your own picture, remove its background (for example with `rembg`), then:

```sh
cd ~/.config/fastfetch
python make-ascii.py your.png logo-blocks.txt 38 --blocks        # full size
python make-ascii.py your.png logo-blocks-small.txt 24 --blocks  # medium terminals
python make-ascii.py your.png logo-blocks-tiny.txt 16 --blocks   # narrow terminals
```

`make-ascii.py` needs Pillow (`pacman -S python-pillow`).
The `fastfetch` shell function in `bashrc` picks the logo size that fits the terminal width.
