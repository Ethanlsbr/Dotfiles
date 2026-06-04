#!/usr/bin/env python3
"""
Parse Hyprland's keybinds.lua into readable shortcut entries.

Emits one TAB-separated line per binding: section<TAB>keys<TAB>description
Obvious media keys (Volume / Brightness / Media sections, and XF86* keys)
are skipped — they're not worth listing in a shortcuts cheat-sheet.
"""
from __future__ import annotations
import re, sys
from pathlib import Path

LUA = Path.home() / ".config/hypr/modules/keybinds.lua"

SKIP_SECTIONS = {"brightness", "volume", "media"}

# Friendly descriptions for known exec_cmd targets (matched as substrings).
CMD_DESC = [
    ("qs ipc call launcher",   "App launcher"),
    ("qs ipc call clipboard",  "Clipboard history"),
    ("swaync-client",          "Toggle notifications"),
    ("hyprshot",               "Screenshot (region)"),
    ("waypaper",               "Wallpaper picker"),
    ("wlogout",                "Logout menu"),
    ("quickshell_toggle",      "Toggle shell / bar"),
    ("kitty",                  "Open terminal"),
    ("nautilus",               "Open file manager"),
    ("zen-browser",            "Open browser"),
]


def load_vars(text: str) -> dict[str, str]:
    """Collect `local x = "..."` / concatenations into a value map."""
    vars: dict[str, str] = {}
    for m in re.finditer(r'local\s+(\w+)\s*=\s*(.+)', text):
        name, raw = m.group(1), m.group(2).strip()
        # Resolve simple string concatenations using already-known vars.
        parts = []
        for tok in raw.split(".."):
            tok = tok.strip()
            sm = re.match(r'^"(.*)"$', tok)
            if sm:
                parts.append(sm.group(1))
            elif tok in vars:
                parts.append(vars[tok])
            elif "getenv" in tok:
                parts.append(str(Path.home()))
            else:
                parts.append("")
        vars[name] = "".join(parts)
    return vars


def resolve_keys(spec: str, vars: dict[str, str]) -> str:
    out = []
    for tok in spec.split(".."):
        tok = tok.strip()
        sm = re.match(r'^"(.*)"$', tok)
        if sm:
            out.append(sm.group(1))
        elif tok in vars:
            out.append(vars[tok])
        else:
            out.append(tok)
    s = "".join(out)
    s = re.sub(r'\s*\+\s*', " + ", s.strip())       # normalise separators
    return re.sub(r'\s+', " ", s)


def describe(dispatch: str, vars: dict[str, str]) -> str:
    d = dispatch.strip()

    m = re.search(r'exec_cmd\(\s*(.+?)\s*\)', d)
    if m:
        arg = m.group(1).strip()
        # resolve var or string
        sm = re.match(r'^"(.*)"$', arg)
        cmd = sm.group(1) if sm else vars.get(arg.split("..")[0].strip(), arg)
        low = cmd.lower()
        for key, label in CMD_DESC:
            if key in low:
                return label
        return "Run: " + cmd

    m = re.search(r'focus\(\{([^}]*)\}\)', d)
    if m:
        body = m.group(1)
        wm = re.search(r'workspace\s*=\s*"?([^",}]+)"?', body)
        if wm:
            v = wm.group(1).strip()
            if v == "e+1": return "Focus next workspace"
            if v == "e-1": return "Focus previous workspace"
            return "Focus workspace " + v
        dm = re.search(r'direction\s*=\s*"(\w+)"', body)
        if dm:
            return "Focus window " + dm.group(1)
        return "Focus"

    m = re.search(r'window\.move\(\{([^}]*)\}\)', d)
    if m:
        wm = re.search(r'workspace\s*=\s*"?([^",}]+)"?', m.group(1))
        if wm:
            return "Move window to workspace " + wm.group(1).strip()
        return "Move window"

    WINDOW = {
        "window.close":        "Close window",
        "window.float":        "Toggle floating",
        "window.fullscreen":   "Toggle fullscreen",
        "window.pseudo":       "Toggle pseudo-tile",
        "window.resize":       "Resize window",
        "window.cycle_next":   "Cycle windows",
        "window.bring_to_top": "Bring window to top",
        "window.drag":         "Drag window",
    }
    for key, label in WINDOW.items():
        if key in d:
            return label

    return d  # fallback: raw dispatcher


def main() -> None:
    if not LUA.is_file():
        return
    text = LUA.read_text()
    vars = load_vars(text)

    section = "General"
    seen: dict[str, tuple[str, str]] = {}    # keys -> (section, desc)
    order: list[str] = []

    for line in text.splitlines():
        s = line.strip()
        cm = re.match(r'^--\s*(.+)', s)
        if cm and not cm.group(1).startswith("-"):
            section = cm.group(1).strip()
            continue
        bm = re.match(r'hl\.bind\(\s*(.+)', s)
        if not bm:
            continue
        if section.lower() in SKIP_SECTIONS:
            continue
        args = bm.group(1)
        # split first top-level comma (key spec vs dispatcher)
        depth = 0
        comma = -1
        for i, ch in enumerate(args):
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
            elif ch == "," and depth == 0:
                comma = i
                break
        if comma < 0:
            continue
        keyspec = args[:comma]
        rest = args[comma + 1:]
        keys = resolve_keys(keyspec, vars)
        if keys.lower().startswith("xf86"):    # media/brightness hardware keys
            continue
        desc = describe(rest, vars)
        if keys not in seen:        # keep the first binding for a given combo
            order.append(keys)
            seen[keys] = (section, desc)

    for keys in order:
        section_name, desc = seen[keys]
        sys.stdout.write(f"{section_name}\t{keys}\t{desc}\n")


if __name__ == "__main__":
    main()
