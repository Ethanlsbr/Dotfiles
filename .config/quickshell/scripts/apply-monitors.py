#!/usr/bin/env python3
"""Write the Quickshell-managed Hyprland monitor config and reload.

Invoked by the settings Monitor pane with a JSON array of monitor configs:
  [{ "output": "...", "mode": "1920x1200@59.95", "x": 0, "y": 0,
     "scale": "1", "disabled": false }, ...]

Generates ~/.config/hypr/modules/monitors.lua using the hl.monitor() Lua API
(required by hyprland.lua) and runs `hyprctl reload` so the change applies live.
"""
import sys, json, os, subprocess

FILE = os.path.expanduser("~/.config/hypr/modules/monitors.lua")

def main():
    cfgs = json.loads(sys.argv[1]) if len(sys.argv) > 1 else []
    out = ["---------------------",
           "------ MONITOR ------",
           "--- (managed by Quickshell settings) ---",
           ""]
    for c in cfgs:
        output = str(c.get("output", ""))
        if not output:
            continue
        if c.get("disabled"):
            out += ["hl.monitor({",
                    f'    output   = "{output}",',
                    "    disabled = true,",
                    "})", ""]
        else:
            pos   = f'{int(c.get("x", 0))}x{int(c.get("y", 0))}'
            mode  = str(c.get("mode") or "preferred")
            scale = str(c.get("scale") or "1")
            transform = int(c.get("transform", 0) or 0)
            block = ["hl.monitor({",
                     f'    output    = "{output}",',
                     f'    mode      = "{mode}",',
                     f'    position  = "{pos}",',
                     f'    scale     = "{scale}",']
            if transform:
                block.append(f'    transform = {transform},')
            block += ["})", ""]
            out += block
    with open(FILE, "w") as f:
        f.write("\n".join(out) + "\n")
    subprocess.run(["hyprctl", "reload"], check=False)

if __name__ == "__main__":
    main()
