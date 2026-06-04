---------------------
----- ANIMATION -----
---------------------

hl.curve("been",        { type = "bezier", points = {{0.24, 0.9}, {0.25, 0.91}} })
hl.curve("linear",      { type = "bezier", points = {{0, 0}, {1, 1}} })
hl.curve("slow",        { type = "bezier", points = {{0, 0.85}, {0.3, 1}} })
hl.curve("overshot",    { type = "bezier", points = {{0.7, 0.6}, {0.1, 1.1}} })
hl.curve("bounce",      { type = "bezier", points = {{1.1, 1.6}, {0.1, 0.85}} })
hl.curve("easeOut",     { type = "bezier", points = {{0.16, 1}, {0.3, 1}} })

hl.animation({ leaf = "windowsIn",      enabled = true, speed = 5, bezier = "slow", style = "popin"})
hl.animation({ leaf = "windowsOut",     enabled = true, speed = 7, bezier = "been", style = "popin 70%"})
hl.animation({ leaf = "windowsMove",    enabled = true, speed = 5, bezier = "slow", style = "slide"})
hl.animation({ leaf = "border",         enabled = true, speed = 1, bezier = "linear"})
hl.animation({ leaf = "fade",           enabled = true, speed = 5, bezier = "overshot"})
hl.animation({ leaf = "workspaces",     enabled = true, speed = 5, bezier = "slow"})
hl.animation({ leaf = "windows",        enabled = true, speed = 5, bezier = "bounce", style = "popin"})
hl.animation({ leaf = "layers",         enabled = true, speed = 6.9, bezier = "easeOut", style = "slide"})


-- Layer Rule for Animation
hl.layer_rule({
    name    = "no-anim-quickshell",
    match   = { namespace = "^quickshell$" },
    no_anim = true,
})

hl.layer_rule({
    name    = "no-anim-selection",
    match   = { namespace = "^selection$" },
    no_anim = true,
})

hl.layer_rule({
    name    = "no-anim-hyprpicker",
    match   = { namespace = "^hyprpicker$" },
    no_anim = true,
})
