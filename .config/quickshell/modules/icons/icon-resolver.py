#!/usr/bin/env python3
"""
Resolve every icon-name -> absolute path for the given GTK icon theme,
following Inherits= chains and always falling back to hicolor.

Usage: icon-resolver.py <theme-name>
Output: one "<name>\t<path>" line per icon, biggest/SVG-preferred winner.
"""
from __future__ import annotations
import configparser, os, re, sys
from pathlib import Path

SEARCH_DIRS = [
    Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "icons",
    *[Path(d) / "icons" for d in os.environ.get(
        "XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if d],
]

SIZE_RE = re.compile(r"/(\d+)x\d+/")


def parse_inherits(theme: str) -> list[str]:
    for d in SEARCH_DIRS:
        idx = d / theme / "index.theme"
        if not idx.is_file():
            continue
        try:
            cp = configparser.ConfigParser(strict=False, interpolation=None)
            cp.read(idx, encoding="utf-8")
            for sect in ("Icon Theme", "icon theme"):
                if cp.has_option(sect, "Inherits"):
                    return [p.strip() for p in cp.get(sect, "Inherits").split(",") if p.strip()]
        except Exception:
            pass
    return []


def build_chain(start: str) -> list[str]:
    chain: list[str] = []
    seen: set[str] = set()
    queue = [start]
    while queue:
        t = queue.pop(0)
        if t in seen:
            continue
        seen.add(t)
        chain.append(t)
        queue.extend(parse_inherits(t))
    if "hicolor" not in seen:
        chain.append("hicolor")
    return chain


def size_score(p: Path) -> int:
    s = str(p)
    if "/scalable/" in s:
        return 9000
    m = SIZE_RE.search(s)
    return int(m.group(1)) if m else 0


def main() -> None:
    theme = sys.argv[1] if len(sys.argv) > 1 else "hicolor"
    chain = build_chain(theme)

    # name -> (theme_rank, size, is_svg, path)
    best: dict[str, tuple[int, int, int, str]] = {}

    for rank, t in enumerate(chain):
        # earlier in chain = strictly preferred. We invert so larger=better.
        theme_pref = len(chain) - rank
        for d in SEARCH_DIRS:
            root = d / t
            if not root.is_dir():
                continue
            for p in root.rglob("*"):
                if p.suffix not in (".svg", ".png"):
                    continue
                name = p.stem
                cur = best.get(name)
                cand = (theme_pref, size_score(p), 1 if p.suffix == ".svg" else 0, str(p))
                if cur is None or cand > cur:
                    best[name] = cand

    for name, (_, _, _, path) in best.items():
        sys.stdout.write(f"{name}\t{path}\n")


if __name__ == "__main__":
    main()
