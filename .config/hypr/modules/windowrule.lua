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

hl.window_rule ({
    name = "Quickshell task manager floating",
    match = {
        class = "org.quickshell",
        title = "Task Manager"
    },
    float = true,
    size = { 1000, 680 }
})

hl.window_rule ({
    name = "File picker dialogs floating",
    match = {
        class = "xdg-desktop-portal-gtk"
    },
    float = true,
    size = { 1000, 650 }
})

hl.window_rule ({
    name = "Spotify floating size",
    match = {
        class = "Spotify"
    },
    size = { 1300, 800}
})

hl.window_rule ({
    name = "Minecraft floating",
    match = {
        class = "Minecraft Launcher",
        title = "Minecraft Launcher"
    },
    float = true,
    size = { 1300, 800}
})

-- hl.window_rule ({
--     name = "Vscode Transparency",
--     match = {
--         class = "code"
--     },
--     opacity = "0.8 0.8"
-- })
hl.window_rule({
    name = "Quickshell uninstall terminal floating",
    match = {
        class = "qs-uninstall"
    },
    float = true,
    size = { 900, 550 }
})
