-- Global program variables shared across modules
terminal    = "kitty"
fileManager = "dolphin"
menu        = "rofi -show drun -show-icons"
browser     = "firefox"
mainMod     = "SUPER"

-- Load configuration modules
require("monitors")
require("autostart")
require("env")
require("settings")
require("keybinds")
require("rules")
require("theme")
