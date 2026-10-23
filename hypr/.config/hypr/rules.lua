hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },
    move  = "20 monitor_h-120",
    float = true,
})

-- Float and position audio controls (updated class match)
hl.window_rule({
    name  = "float-pavucontrol",
    match = { class = ".*pavucontrol.*" },
    float = true,
    size  = "600 400",
    move  = "100%-610 50",
})

-- Float and position bluetooth controls
hl.window_rule({
    name  = "float-blueman",
    match = { class = "^(blueman-manager)$" },
    float = true,
    size  = "600 400",
    move  = "100%-610 50",
})
