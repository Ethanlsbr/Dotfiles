#!/usr/bin/env python3
"""Switch monitor presentation mode (like Windows' Win+P).

  extend   - all monitors on, side by side
  mirror   - external(s) mirror the internal panel
  external - only the external monitor(s) on
  internal - only the internal panel on

Hyprland here uses the Lua config (non-legacy parser), so `hyprctl keyword`
is rejected. Instead we rewrite ~/.config/hypr/modules/monitors.lua using the
hl.monitor() API and `hyprctl reload`, exactly like the settings Apply.

Internal = eDP*/LVDS*/DSI* (laptop panel); everything else is external. With no
such panel the first monitor is treated as "internal".
"""
import sys, json, os, subprocess

FILE = os.path.expanduser("~/.config/hypr/modules/monitors.lua")

def hypr_json(args):
    r = subprocess.run(["hyprctl"] + args + ["-j"], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return []

def is_internal(name):
    n = name.lower()
    return n.startswith("edp") or n.startswith("lvds") or n.startswith("dsi")

def block(**kw):
    out = ["hl.monitor({"]
    for k, v in kw.items():
        if isinstance(v, bool):
            out.append(f"    {k} = {'true' if v else 'false'},")
        else:
            out.append(f'    {k} = "{v}",')
    out += ["})", ""]
    return out

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "extend"
    mons = hypr_json(["monitors", "all"])
    names = [m["name"] for m in mons]
    if not names:
        return

    internal = [n for n in names if is_internal(n)]
    external = [n for n in names if not is_internal(n)]
    if not internal:
        internal = names[:1]
        external = names[1:]

    out = ["---------------------",
           "------ MONITOR ------",
           "--- (managed by Quickshell) ---",
           ""]

    if mode == "extend":
        out += block(output=internal[0], mode="preferred", position="0x0", scale="1")
        for n in internal[1:] + external:
            out += block(output=n, mode="preferred", position="auto-right", scale="1")

    elif mode == "mirror":
        src = internal[0]
        out += block(output=src, mode="preferred", position="0x0", scale="1")
        for n in names:
            if n != src:
                out += block(output=n, mode="preferred", position="0x0", scale="1", mirror=src)

    elif mode == "external":
        if external:
            for n in internal:
                out += block(output=n, disabled=True)
            out += block(output=external[0], mode="preferred", position="0x0", scale="1")
            for n in external[1:]:
                out += block(output=n, mode="preferred", position="auto-right", scale="1")
        else:  # no external — keep internal on so we don't go black
            out += block(output=internal[0], mode="preferred", position="0x0", scale="1")

    elif mode == "internal":
        for n in external:
            out += block(output=n, disabled=True)
        out += block(output=internal[0], mode="preferred", position="0x0", scale="1")
        for n in internal[1:]:
            out += block(output=n, mode="preferred", position="auto-right", scale="1")

    with open(FILE, "w") as f:
        f.write("\n".join(out) + "\n")
    subprocess.run(["hyprctl", "reload"], check=False)

if __name__ == "__main__":
    main()
