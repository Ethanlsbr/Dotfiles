---------------------
---- KEYBINDINGS ----
---------------------
local mainMod       = "SUPER"
local scriptDir     = os.getenv("HOME") .. "/.config/hypr/scripts"
local volume        = scriptDir .. "/volume_ctl.sh"
local brightness    = scriptDir .. "/brightness_ctl.sh"
local media         = scriptDir .. "/media_ctl.sh"
local toggleShell   = scriptDir .. "/quickshell_toggle.sh"
local reloadShell   = scriptDir .. "/reload_quickshell.sh"
local logout        = "killall -9 wlogout || wlogout"
local screenshot    = "hyprshot -m region -o ~/Pictures/Screenshots"
local terminal      = "kitty"
local fileManager   = "nautilus"
local browser       = "zen-browser"


-- Screenshots
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd(screenshot))
hl.bind("Print", hl.dsp.exec_cmd(screenshot))

-- Applications
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("qs ipc call power toggle"))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("qs ipc call wallpaper toggle"))

-- Toggle Menu : Tips, calculator avalaible throught ">>" in the menu
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("qs ipc call launcher toggle"))

-- Launch App on dedicated GPU
hl.bind(mainMod .. " + SHIFT + SPACE", hl.dsp.exec_cmd("qs ipc call gpulauncher  toggle"))

-- Notifications
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("qs ipc call notifications toggle"))

-- Brightness
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(brightness .. " --inc"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(brightness.. " --dec"), { repeating = true })

-- Volume
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(volume .. " --inc"), { repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(volume .. " --dec"), { repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(volume .. " --toggle"))

-- Media
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(media .. " --pause"))

-- Window Management
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + S", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo({ action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize)

-- Resizing Window
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x = 50, y = 0, relative = true}), { repeating = true })
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.resize({ x = -50, y = 0, relative = true}), { repeating = true })
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.resize({ x = 0, y = 50, relative = true}), { repeating = true })
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.resize({ x = 0, y = -50, relative = true}), { repeating = true })

-- Alt + Tab
hl.bind("ALT + Tab", hl.dsp.window.cycle_next())
hl.bind("ALT + Tab", hl.dsp.window.bring_to_top())

-- Focus
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Switch
hl.bind(mainMod .. " + A", hl.dsp.focus({ workspace = 1 }))
hl.bind(mainMod .. " + Z", hl.dsp.focus({ workspace = 2 }))
hl.bind(mainMod .. " + E", hl.dsp.focus({ workspace = 3 }))
hl.bind(mainMod .. " + R", hl.dsp.focus({ workspace = 4 }))
hl.bind(mainMod .. " + T", hl.dsp.focus({ workspace = 5 }))
hl.bind(mainMod .. " + Y", hl.dsp.focus({ workspace = 6 }))
hl.bind(mainMod .. " + U", hl.dsp.focus({ workspace = 7 }))

-- Move

hl.bind("ALT + A", hl.dsp.window.move({ workspace = 1 }))
hl.bind("ALT + Z", hl.dsp.window.move({ workspace = 2 }))
hl.bind("ALT + E", hl.dsp.window.move({ workspace = 3 }))
hl.bind("ALT + R", hl.dsp.window.move({ workspace = 4 }))
hl.bind("ALT + T", hl.dsp.window.move({ workspace = 5 }))
hl.bind("ALT + Y", hl.dsp.window.move({ workspace = 6 }))
hl.bind("ALT + U", hl.dsp.window.move({ workspace = 7 }))

-- Mouse Behavior
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize())
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1"}))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1"}))

-- Clipboard History
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("qs ipc call clipboard toggle"))

-- Toggle Shell Bar
hl.bind(mainMod .. " + H", hl.dsp.exec_cmd("qs ipc call bar toggle"))

-- Reload Shell
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(reloadShell))

-- Change display mode
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("qs ipc call monitormode toggle"))