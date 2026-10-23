-- ~/.config/hypr/theme.lua  --  Twilight Peak (soft)
-- Put  require("theme")  at the END of hyprland.lua.

hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
     general = {
        gaps_in  = 4,
        gaps_out = 8,
        border_size = 2,
        col = {
            active_border   = { colors = {"rgba(8f7bb8dd)", "rgba(c9a0b4dd)"}, angle = 45 },
            inactive_border = "rgba(2e275088)",
        },
    },

    decoration = {
        rounding = 8,
        inactive_opacity = 0.97,
        shadow = {
            enabled = true,
            range = 10,
            render_power = 3,
            color = "rgba(0d0a1acc)",
        },
        blur = {
            enabled = true,
            size = 4,
            passes = 2,
        },
    },

    misc = {
        background_color = "rgb(1a1530)",
    },
})
