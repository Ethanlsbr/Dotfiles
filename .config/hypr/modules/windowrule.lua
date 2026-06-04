--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

hl.window_rule({
    name = "Bluetooth app floating",
    match = {
        class = "blueman-manager"
    },
    float = true,
    size = { 1000, 600 }
})

hl.window_rule({
    name = "Sound app floating",
    match = {
        class = "org.pulseaudio.pavucontrol"
    },
    float = true,
    size = { 1000, 600 }
})

hl.window_rule({
    name = "File explorer app floating",
    match = {
        class = "org.gnome.Nautilus"
    },
    float = true,
    size = { 1400, 800 }
})

hl.window_rule({
    name = "Wallpaper app floating",
    match = {
        class = "waypaper"
    },
    float = true,
    size = { 1000, 600 }
})

hl.window_rule ({
    name = "Kitty flaoting size",
    match = {
        class = "kitty"
    },
    size = { 1300, 800 }
})

hl.window_rule ({
    name = "Quickshell settings app floating",
    match = {
        class = "org.quickshell",
        title = "Quickshell settings"
    },
    float = true,
    size = { 1300, 800 }
})
