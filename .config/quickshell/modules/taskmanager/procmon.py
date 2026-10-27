#!/usr/bin/env python3
"""
Process monitor for the task manager.

  procmon.py watch [interval]   one JSON snapshot per line, every `interval` s
  procmon.py kill SIG PID...    send SIG (TERM/KILL/...) to each PID; prints
                                "pid<TAB>error" for each failure, exits 1 if any
  procmon.py users              one JSON line: every account and its groups

Snapshot: {"uid": <own uid>, "mem_total": bytes, "procs": [...], "clients": [...]}
  proc   = {pid, ppid, uid, user, name, cmd, cpu (% of the whole machine, like
            Windows), mem (private resident bytes), threads, state}
  client = {pid, cls, title, address} for each Hyprland window.
Kernel threads are skipped.

Users: {"uid": <own uid>, "users": [...]}
  user = {name, uid, gid, fullname, home, shell, login (has a real shell),
          regular (root or UID_MIN..UID_MAX), sessions (logind),
          groups: [{name, gid, primary}] (primary group first)}
"""
from __future__ import annotations
import grp, json, os, pwd, signal, subprocess, sys, time

CLK = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")
NCPU = os.cpu_count() or 1
PF_KTHREAD = 0x00200000

_users: dict[int, str] = {}


def user_name(uid: int) -> str:
    if uid not in _users:
        try:
            _users[uid] = pwd.getpwuid(uid).pw_name
        except KeyError:
            _users[uid] = str(uid)
    return _users[uid]


def mem_total() -> int:
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    return int(line.split()[1]) * 1024
    except OSError:
        pass
    return 0


def read_proc(pid: str):
    """(info dict, cpu ticks, start time) or None if gone / kernel thread."""
    base = "/proc/" + pid
    with open(base + "/stat", "rb") as f:
        stat = f.read().decode(errors="replace")
    # comm may contain spaces/parens: it spans the first "(" to the last ")".
    l, r = stat.index("("), stat.rindex(")")
    comm = stat[l + 1:r]
    rest = stat[r + 2:].split()
    if int(rest[6]) & PF_KTHREAD:
        return None
    with open(base + "/cmdline", "rb") as f:
        argv = [a.decode(errors="replace") for a in f.read().split(b"\0") if a]
    # statm: size resident shared … — resident minus file/shmem pages is the
    # anonymous (private) working set, closest to Windows' "Memory" column.
    with open(base + "/statm") as f:
        sm = f.read().split()
    uid = os.stat(base).st_uid
    # comm is truncated to 15 chars; argv[0]'s basename is the full name
    # when it agrees with it.
    name = comm
    if argv:
        a0 = os.path.basename(argv[0].split(" ")[0])
        if a0.startswith(comm) or comm.startswith(a0[:15]):
            name = a0 or comm
    info = {
        "pid": int(pid),
        "ppid": int(rest[1]),
        "uid": uid,
        "user": user_name(uid),
        "name": name,
        "cmd": " ".join(argv) if argv else "[" + comm + "]",
        "mem": max(0, int(sm[1]) - int(sm[2])) * PAGE,
        "threads": int(rest[17]),
        "state": rest[0],
    }
    return info, int(rest[11]) + int(rest[12]), int(rest[19])


def clients() -> list[dict]:
    try:
        out = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True,
                             text=True, timeout=1.5).stdout
        return [{"pid": c.get("pid", -1), "cls": c.get("class", ""),
                 "title": c.get("title", ""), "address": c.get("address", "")}
                for c in json.loads(out or "[]") if c.get("pid", -1) > 0]
    except (OSError, ValueError, subprocess.SubprocessError):
        return []


def watch(interval: float) -> None:
    prev: dict[int, tuple[int, int]] = {}
    prev_t = 0.0
    first = True
    while True:
        now = time.monotonic()
        dt = now - prev_t
        cur: dict[int, tuple[int, int]] = {}
        procs = []
        for pid in os.listdir("/proc"):
            if not pid.isdigit():
                continue
            try:
                r = read_proc(pid)
            except (OSError, ValueError, IndexError):
                continue      # exited mid-read
            if r is None:
                continue
            info, ticks, start = r
            p = prev.get(info["pid"])
            cpu = 0.0
            if p and p[1] == start and dt > 0:
                cpu = (ticks - p[0]) / CLK / dt / NCPU * 100
            info["cpu"] = round(max(0.0, cpu), 1)
            cur[info["pid"]] = (ticks, start)
            procs.append(info)
        prev, prev_t = cur, now
        if first:
            # Prime the CPU deltas, then emit a real sample shortly after.
            first = False
            time.sleep(0.5)
            continue
        snap = {"uid": os.getuid(), "mem_total": mem_total(),
                "procs": procs, "clients": clients()}
        try:
            print(json.dumps(snap, separators=(",", ":")), flush=True)
        except BrokenPipeError:
            return
        time.sleep(max(0.2, interval - (time.monotonic() - now)))


def kill(sig_name: str, pids: list[str]) -> int:
    sig = getattr(signal, "SIG" + sig_name.upper().removeprefix("SIG"))
    failed = 0
    for pid in pids:
        try:
            os.kill(int(pid), sig)
        except ProcessLookupError:
            pass              # already gone: that's what was wanted
        except PermissionError:
            failed += 1
            print(f"{pid}\tpermission denied", flush=True)
        except (OSError, ValueError) as e:
            failed += 1
            print(f"{pid}\t{e}", flush=True)
    return 1 if failed else 0


def login_defs() -> tuple[int, int]:
    lo, hi = 1000, 60000
    try:
        with open("/etc/login.defs") as f:
            for line in f:
                k, _, v = line.partition(" ")
                v = v.strip()
                if k == "UID_MIN" and v.isdigit():
                    lo = int(v)
                elif k == "UID_MAX" and v.isdigit():
                    hi = int(v)
    except OSError:
        pass
    return lo, hi


def sessions() -> dict[int, int]:
    """uid → open logind sessions (excluding the per-user manager)."""
    try:
        out = subprocess.run(["loginctl", "list-sessions", "--json=short"],
                             capture_output=True, text=True, timeout=1.5).stdout
        counts: dict[int, int] = {}
        for s in json.loads(out or "[]"):
            if s.get("class", "user") in ("user", "greeter") and "uid" in s:
                counts[s["uid"]] = counts.get(s["uid"], 0) + 1
        return counts
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}


def users() -> None:
    lo, hi = login_defs()
    sess = sessions()
    groups = grp.getgrall()
    gname = {g.gr_gid: g.gr_name for g in groups}
    member_of: dict[str, list] = {}
    for g in groups:
        for m in g.gr_mem:
            member_of.setdefault(m, []).append(g)
    out = []
    for p in sorted(pwd.getpwall(), key=lambda p: p.pw_uid):
        gl = [{"name": gname.get(p.pw_gid, str(p.pw_gid)), "gid": p.pw_gid, "primary": True}]
        for g in sorted(member_of.get(p.pw_name, []), key=lambda g: g.gr_name):
            if g.gr_gid != p.pw_gid:
                gl.append({"name": g.gr_name, "gid": g.gr_gid, "primary": False})
        shell = p.pw_shell or ""
        out.append({
            "name": p.pw_name,
            "uid": p.pw_uid,
            "gid": p.pw_gid,
            "fullname": p.pw_gecos.split(",")[0],
            "home": p.pw_dir,
            "shell": shell,
            "login": bool(shell) and os.path.basename(shell) not in ("nologin", "false"),
            "regular": p.pw_uid == 0 or lo <= p.pw_uid <= hi,
            "sessions": sess.get(p.pw_uid, 0),
            "groups": gl,
        })
    print(json.dumps({"uid": os.getuid(), "users": out}, separators=(",", ":")), flush=True)


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "kill" and len(args) >= 3:
        sys.exit(kill(args[1], args[2:]))
    if args and args[0] == "users":
        users()
        sys.exit(0)
    if args and args[0] == "watch":
        try:
            watch(float(args[1]) if len(args) > 1 else 2.0)
        except KeyboardInterrupt:
            pass
        sys.exit(0)
    print(__doc__, file=sys.stderr)
    sys.exit(2)
