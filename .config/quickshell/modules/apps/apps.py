#!/usr/bin/env python3
"""Installed applications + default apps for the settings Applications pane.

  apps.py list
      Prints {"defaults": [...], "types": [...], "apps": [...]}:
        defaults: [{ key, label, current, candidates: [id] }]
        types:    [{ mime, ext, desc, category, current, candidates: [id] }]
                  (`ext` is a display string such as ".jpg, .jpeg, .jpe")
        apps:     [{ id, name, icon, comment, pkg, version, size, shown }]
      `apps` holds every entry referenced above; `shown` ones are the
      launcher-visible apps. `pkg` is the owning pacman package ("" for
      entries no package owns, e.g. ones in ~/.local/share/applications).

  apps.py set <category-key> <desktop-id>
      Makes <desktop-id> the default for every MIME type of the category.
  apps.py set-type <mime> <desktop-id>
      Makes <desktop-id> the default for one MIME type.
      Both go through xdg-mime default, i.e. ~/.config/mimeapps.list.
"""
import configparser, json, os, re, subprocess, sys

# key, label, MIME types (the first one decides the "current" default).
CATEGORIES = [
    ("browser", "Web browser", ["x-scheme-handler/https", "x-scheme-handler/http",
                                "text/html", "application/xhtml+xml"]),
    ("files",   "File manager", ["inode/directory"]),
    ("editor",  "Text editor", ["text/plain", "text/markdown", "application/x-shellscript"]),
    ("image",   "Image viewer", ["image/png", "image/jpeg", "image/gif", "image/webp",
                                 "image/bmp", "image/tiff", "image/avif"]),
    ("video",   "Video player", ["video/mp4", "video/x-matroska", "video/webm",
                                 "video/quicktime", "video/x-msvideo", "video/mpeg"]),
    ("music",   "Music player", ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav",
                                 "audio/mp4", "audio/aac", "audio/x-opus+ogg"]),
    ("pdf",     "PDF viewer", ["application/pdf"]),
    ("mail",    "Email", ["x-scheme-handler/mailto"]),
    ("archive", "Archive manager", ["application/zip", "application/x-tar", "application/gzip",
                                    "application/x-7z-compressed", "application/vnd.rar"]),
]

def load_aliases():
    out = {}
    try:
        with open("/usr/share/mime/aliases", encoding="utf-8") as f:
            for line in f:
                a, _, c = line.strip().partition(" ")
                if c:
                    out[a] = c
    except OSError:
        pass
    return out

ALIASES = load_aliases()

def canon(mime):
    return ALIASES.get(mime, mime)

def with_aliases(mimes):
    """The given types plus their canonical names (apps may list either)."""
    out = []
    for m in mimes:
        for x in (m, canon(m)):
            if x not in out:
                out.append(x)
    return out

# Preferred extension per type, shown first.
COMMON = {"txt", "md", "sh", "html", "jpg", "png", "mp3", "m4a", "ogg", "wav", "mp4",
          "mkv", "avi", "mov", "tar", "zip", "pdf"}

# Link types have no MIME database entry; describe them here.
SCHEMES = {"x-scheme-handler/https": ("https://", "HTTPS link"),
           "x-scheme-handler/http":  ("http://", "HTTP link"),
           "x-scheme-handler/mailto": ("mailto:", "Email link"),
           "inode/directory": ("Folder", "Folder")}

def app_dirs():
    home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    dirs = [home] + (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    return [os.path.join(d, "applications") for d in dirs if d]

def read_entries():
    """{ desktop-id: entry } — earlier dirs win, as in the XDG spec."""
    entries = {}
    for base in app_dirs():
        if not os.path.isdir(base):
            continue
        for root, _, files in os.walk(base):
            for f in files:
                if not f.endswith(".desktop"):
                    continue
                path = os.path.join(root, f)
                did = os.path.relpath(path, base).replace("/", "-")
                if did in entries:
                    continue
                cp = configparser.ConfigParser(interpolation=None, strict=False)
                cp.optionxform = str
                try:
                    cp.read(path, encoding="utf-8")
                    e = cp["Desktop Entry"]
                except Exception:
                    continue
                entries[did] = {
                    "id": did, "path": path,
                    "name": e.get("Name", did[:-8]),
                    "icon": e.get("Icon", ""),
                    "comment": e.get("Comment", "") or e.get("GenericName", ""),
                    "mimes": [m for m in e.get("MimeType", "").split(";") if m],
                    "type": e.get("Type", ""),
                    "hidden": e.get("NoDisplay", "false").lower() == "true"
                              or e.get("Hidden", "false").lower() == "true",
                }
    return entries

def owners(paths):
    """{ path: pkg } via one `pacman -Qo` call."""
    if not paths:
        return {}
    r = subprocess.run(["pacman", "-Qo", *paths], capture_output=True, text=True)
    out = {}
    for line in r.stdout.splitlines():
        # "/usr/share/applications/x.desktop is owned by pkg 1.2-3"
        if " is owned by " in line:
            p, rest = line.split(" is owned by ", 1)
            out[p] = rest.split()[0]
    return out

def pkg_info(pkgs):
    """{ pkg: (version, installed size) } via one `pacman -Qi` call."""
    if not pkgs:
        return {}
    r = subprocess.run(["pacman", "-Qi", *sorted(pkgs)], capture_output=True, text=True)
    info, name, ver = {}, None, ""
    for line in r.stdout.splitlines():
        k, _, v = line.partition(":")
        k, v = k.strip(), v.strip()
        if k == "Name":
            name = v
        elif k == "Version":
            ver = v
        elif k == "Installed Size" and name:
            info[name] = (ver, v.replace("iB", "B"))
    return info

def data_dirs():
    home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return [home] + [d for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if d]

def read_section(path, section):
    out, cur = {}, None
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("["):
                    cur = line[1:-1]
                elif cur == section and "=" in line:
                    k, v = line.split("=", 1)
                    out.setdefault(k.strip(), [x for x in v.strip().split(";") if x])
    except OSError:
        pass
    return out

def default_table(entries):
    """{ mime: desktop-id } following the XDG mime-apps spec lookup order
    (desktop-specific and plain mimeapps.list in config then data dirs,
    then mimeinfo.cache), the same answers as `xdg-mime query default`."""
    desktops = [d.lower() for d in (os.environ.get("XDG_CURRENT_DESKTOP") or "").split(":") if d]
    cfg = [os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")]
    cfg += [d for d in (os.environ.get("XDG_CONFIG_DIRS") or "/etc/xdg").split(":") if d]
    lists = []
    for d in cfg + [os.path.join(x, "applications") for x in data_dirs()]:
        lists += [os.path.join(d, f"{de}-mimeapps.list") for de in desktops]
        lists.append(os.path.join(d, "mimeapps.list"))
    table = {}
    for path in lists:
        for mime, ids in read_section(path, "Default Applications").items():
            if mime not in table:
                hit = next((i for i in ids if i in entries), None)
                if hit:
                    table[mime] = hit
    for d in data_dirs():
        for mime, ids in read_section(os.path.join(d, "applications", "mimeinfo.cache"), "MIME Cache").items():
            if mime not in table:
                hit = next((i for i in ids if i in entries), None)
                if hit:
                    table[mime] = hit
    return table

def mime_info(mime):
    """(extensions, description) from shared-mime-info."""
    if mime in SCHEMES:
        return SCHEMES[mime]
    exts, desc = [], mime
    try:
        with open("/usr/share/mime/globs2", encoding="utf-8") as f:
            for line in f:
                parts = line.strip().split(":")
                if len(parts) >= 3 and parts[1] == mime and re.fullmatch(r"\*\.[\w+-]+", parts[2]):
                    e = parts[2][1:].lower()
                    if e not in exts:
                        exts.append(e)
    except OSError:
        pass
    try:
        with open(f"/usr/share/mime/{mime}.xml", encoding="utf-8") as f:
            m = re.search(r"<comment>([^<]+)</comment>", f.read())
            if m:
                desc = m.group(1)
    except OSError:
        pass
    # The subtype's own extension first (".bmp" before ".dib"), then by length.
    sub = mime.split("/")[-1].replace("x-", "")
    exts.sort(key=lambda e: (e[1:] not in COMMON, e[1:] != sub, len(e), e))
    return ", ".join(exts[:4]) or mime, desc

def cmd_list():
    entries = read_entries()
    apps_ok = {i: e for i, e in entries.items() if e["type"] == "Application"}
    shown = [e for e in apps_ok.values() if not e["hidden"]]
    table = default_table(apps_ok)

    def cands(mimes, current):
        ids = [e["id"] for e in sorted(shown, key=lambda e: e["name"].lower())
               if any(m in e["mimes"] for m in mimes)]
        if current and current not in ids:
            ids.insert(0, current)
        return ids

    def lookup(mime):
        return table.get(mime) or table.get(canon(mime)) or ""

    defaults, types, used = [], [], set()
    for key, label, mimes in CATEGORIES:
        current = lookup(mimes[0])
        c = cands(with_aliases(mimes), current)
        used.update(c)
        defaults.append({"key": key, "label": label, "current": current, "candidates": c})
        for mime in mimes:
            ext, desc = mime_info(canon(mime))
            cur = lookup(mime)
            c = cands(with_aliases([mime]), cur)
            used.update(c)
            types.append({"mime": mime, "ext": ext, "desc": desc, "category": label,
                          "current": cur, "candidates": c})
    types.sort(key=lambda t: t["desc"].lower())

    listed = shown + [apps_ok[i] for i in used if i in apps_ok and apps_ok[i]["hidden"]]
    own = owners([e["path"] for e in listed])
    info = pkg_info(set(own.values()))
    apps = []
    for e in sorted(listed, key=lambda e: e["name"].lower()):
        pkg = own.get(e["path"], "")
        ver, size = info.get(pkg, ("", ""))
        apps.append({"id": e["id"], "name": e["name"], "icon": e["icon"], "comment": e["comment"],
                     "pkg": pkg, "version": ver, "size": size, "shown": not e["hidden"]})
    print(json.dumps({"defaults": defaults, "types": types, "apps": apps}))

def cmd_set(key, did):
    mimes = next((m for k, _, m in CATEGORIES if k == key), None)
    if not mimes:
        sys.exit(f"apps: unknown category {key}")
    subprocess.run(["xdg-mime", "default", did, *with_aliases(mimes)], check=True)

def cmd_set_type(mime, did):
    subprocess.run(["xdg-mime", "default", did, *with_aliases([mime])], check=True)

if __name__ == "__main__":
    if len(sys.argv) > 3 and sys.argv[1] == "set":
        cmd_set(sys.argv[2], sys.argv[3])
    elif len(sys.argv) > 3 and sys.argv[1] == "set-type":
        cmd_set_type(sys.argv[2], sys.argv[3])
    else:
        cmd_list()
