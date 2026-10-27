#!/usr/bin/env python3
"""Switch monitor presentation mode (like Windows' Win+P).

  extend   - all monitors on, side by side
  mirror   - external(s) mirror the internal panel
  external - only the external monitor(s) on
  internal - only the internal panel on

Hyprland here uses the Lua config (non-legacy parser), so `hyprctl keyword`
is rejected. Instead we rewrite ~/.config/hypr/modules/monitors.lua using the
hl.monitor() API and `hyprctl reload`, exactly like the settings Apply.

Each output keeps the mode / scale / rotation (and, when extending, the
arrangement) it last had while enabled: those are read from monitors.lua
before it's rewritten and remembered in quickshell/state/monitor-layout.json,
so switching modes no longer resets a screen to its preferred mode (e.g. a
100 Hz monitor back to 60 Hz) or scale 1.

Internal = eDP*/LVDS*/DSI* (laptop panel); everything else is external. With no
such panel the first monitor is treated as "internal".
"""
import sys, json, os, re, subprocess

FILE = os.path.expanduser("~/.config/hypr/modules/monitors.lua")
STATE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "..", "..", "state", "monitor-layout.json")

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
        elif isinstance(v, int):
            out.append(f"    {k} = {v},")
        else:
            out.append(f'    {k} = "{v}",')
    out += ["})", ""]
    return out

# ── Remembered per-output settings ──────────────────────────────────────
def lua_blocks(text):
    """{key: value} for each hl.monitor({...}) block (quotes stripped)."""
    out = []
    for body in re.findall(r"hl\.monitor\(\{(.*?)\}\)", text, re.S):
        out.append({k: v.strip().strip('"')
                    for k, v in re.findall(r'(\w+)\s*=\s*("[^"]*"|[^,\n]+)', body)})
    return out

def load_saved():
    """The state file, updated from what the current monitors.lua enables
    (settings Apply writes it too). Positions are only taken from
    multi-screen layouts: a screen shown alone sits at 0x0, which says
    nothing about its place beside the others."""
    try:
        with open(STATE) as f:
            saved = json.load(f)
    except (OSError, ValueError):
        saved = {}
    try:
        with open(FILE) as f:
            text = f.read()
    except OSError:
        return saved
    enabled = [b for b in lua_blocks(text)
               if b.get("output") and b.get("disabled") != "true" and "mirror" not in b]
    for b in enabled:
        s = saved.setdefault(b["output"], {})
        s.update(mode=b.get("mode", "preferred"), scale=b.get("scale", "1"),
                 transform=b.get("transform", "0"))
        if len(enabled) > 1 and "position" in b:
            s["position"] = b["position"]
    return saved

def parse_mode(m):
    r = re.match(r"(\d+)x(\d+)(?:@([\d.]+))?", m or "")
    return (int(r[1]), int(r[2]), float(r[3]) if r[3] else None) if r else None

def offered(mode, available):
    """`mode` ("WxH@Hz") is one the monitor lists (refresh within 0.5 Hz:
    a saved 100.00 is hyprctl's 99.93)."""
    want = parse_mode(mode)
    for a in available:
        have = parse_mode(a)
        if want and have and have[:2] == want[:2] and (
                want[2] is None or have[2] is None or abs(have[2] - want[2]) < 0.5):
            return True
    return False

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "extend"
    mons = hypr_json(["monitors", "all"])
    names = [m["name"] for m in mons]
    if not names:
        return
    modes = {m["name"]: m.get("availableModes", []) for m in mons}
    saved = load_saved()

    def resolved(name):
        """Remembered (mode, scale, transform); a mode the screen no longer
        offers (another monitor on that port) falls back to preferred."""
        s = saved.get(name, {})
        m = s.get("mode", "preferred")
        if m != "preferred" and not offered(m, modes.get(name, [])):
            m = "preferred"
        return m, s.get("scale", "1"), int(s.get("transform", 0) or 0)

    def on(name, position, **extra):
        m, scale, t = resolved(name)
        kw = dict(output=name, mode=m, position=position, scale=scale)
        if t:
            kw["transform"] = t
        return block(**kw, **extra)

    def box(name, position):
        """Layout rectangle of a screen placed at `position`."""
        m, scale, t = resolved(name)
        w, h, _ = parse_mode(m) or parse_mode((modes.get(name) or ["1920x1080"])[0])
        if t % 2:
            w, h = h, w
        try:
            f = float(scale) or 1
        except ValueError:
            f = 1
        x, y = (int(v) for v in re.fullmatch(r"(-?\d+)x(-?\d+)", position).groups())
        return x, y, x + w / f, y + h / f

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
        # Restore the remembered arrangement when every screen has one and
        # none overlap (e.g. after a scale change); otherwise lay them out
        # left to right from the internal panel.
        ordered = internal + external
        pos = [saved.get(n, {}).get("position", "") for n in ordered]
        boxes = ([box(n, p) for n, p in zip(ordered, pos)]
                 if all(re.fullmatch(r"-?\d+x-?\d+", p) for p in pos) else None)
        if boxes and not any(a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]
                             for i, a in enumerate(boxes) for b in boxes[i + 1:]):
            for n, p in zip(ordered, pos):
                out += on(n, p)
        else:
            out += on(internal[0], "0x0")
            for n in ordered[1:]:
                out += on(n, "auto-right")

    elif mode == "mirror":
        src = internal[0]
        out += on(src, "0x0")
        for n in names:
            if n != src:
                out += block(output=n, mode="preferred", position="0x0", scale="1", mirror=src)

    elif mode == "external":
        if external:
            for n in internal:
                out += block(output=n, disabled=True)
            out += on(external[0], "0x0")
            for n in external[1:]:
                out += on(n, "auto-right")
        else:  # no external — keep internal on so we don't go black
            out += on(internal[0], "0x0")

    elif mode == "internal":
        for n in external:
            out += block(output=n, disabled=True)
        out += on(internal[0], "0x0")
        for n in internal[1:]:
            out += on(n, "auto-right")

    with open(FILE, "w") as f:
        f.write("\n".join(out) + "\n")
    try:
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        with open(STATE, "w") as f:
            json.dump(saved, f, indent=1)
    except OSError:
        pass
    subprocess.run(["hyprctl", "reload"], check=False)

if __name__ == "__main__":
    main()
