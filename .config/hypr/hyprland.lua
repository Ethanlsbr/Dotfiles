require("modules.monitors")
require("modules.keybinds")
require("modules.env")
require("modules.animation")
require("modules.startup")
require("modules.windowrule")

hl.config({

    input = {
        kb_layout  = "fr",
        repeat_rate = 40,
        repeat_delay = 375,
        follow_mouse = 0,
        sensitivity = 0,
        float_switch_override_focus = 0,
        touchpad = {
            natural_scroll = true,
        },
    },

    general = {
        gaps_in  = 9,
        gaps_out = 13,
        border_size = 1,
        col = {
            active_border   = { colors = {"rgb(b4befe)", "rgb(f5c2e7)"}, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },
        layout = "dwindle",
        resize_on_border = true,
        allow_tearing = false,
    },

    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        mouse_move_enables_dpms = true,
        animate_manual_resizes = false,
        mouse_move_focuses_monitor = true,
        enable_swallow = true,
        focus_on_activate = true,
    },

    hl.gesture({fingers = 3, direction = "horizontal", action = "workspace"}),

    decoration = {
        rounding = 10,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        blur = {
            enabled = true,
            special = true,
            popups = true,
            ignore_opacity = false,
            xray = false,
            size = 7,
            passes = 4,
            contrast = 1,
            brightness = 0.75,
            vibrancy = 0,
            noise = 0
        }
    },

    dwindle = {
        preserve_split = true
    },

    animations = {
        enabled = true,
    },

})
