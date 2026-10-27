#!/usr/bin/env python3
"""
Performance monitor for the task manager's Performance tab.

  perfmon.py [interval]

First line: {"type": "static", cpu, mem_total, disks, gpus} (hardware facts).
Then one {"type": "sample", cpu, mem, disks, net, gpus} line per interval:
  cpu   = {usage, cores[], mhz, procs, threads, uptime}         usage 0..1
  mem   = {total, used, avail, cached, free, dirty, committed, commit_limit,
           swap_total, swap_used}                               bytes
  disks = {name: {active, read, write, resp, mounts[]}}         0..1, B/s, ms
  net   = {iface: {rx, tx, wifi, ipv4, ipv6}}                   B/s
  gpus  = {pdev: {util, engines{}, mhz, max_mhz, suspended, idle, mem_local,
                 mem_local_total, mem_system, temp, power}}
GPUs (Intel i915/xe, AMD amdgpu, NVIDIA) are sampled by gpumon.py.
"""
from __future__ import annotations
import glob, json, os, re, subprocess, sys, time

from gpumon import Gpus, drm_fds

SKIP_DISK = re.compile(r"^(loop|ram|zram|dm-|md|sr|fd)")
SKIP_NET = re.compile(r"^(lo$|docker|veth|br-|virbr|vnet)")


def read(path: str, default: str = "") -> str:
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def read_int(path: str, default: int = 0) -> int:
    try:
        return int(read(path))
    except ValueError:
        return default


# ── Static facts ────────────────────────────────────────────────────────
def cpu_static() -> dict:
    model = ""
    flags = ""
    for line in read("/proc/cpuinfo").splitlines():
        if not model and line.startswith("model name"):
            model = line.split(":", 1)[1].strip()
        elif not flags and line.startswith("flags"):
            flags = line.split(":", 1)[1]
        if model and flags:
            break
    cpus = sorted(glob.glob("/sys/devices/system/cpu/cpu[0-9]*"),
                  key=lambda p: int(re.sub(r"\D", "", os.path.basename(p))))
    cores, sockets = set(), set()
    caches: dict[int, int] = {}   # level → bytes (unique instances summed)
    seen_cache = set()
    for c in cpus:
        pkg = read(c + "/topology/physical_package_id", "0")
        sockets.add(pkg)
        cores.add((pkg, read(c + "/topology/core_id", c)))
        for idx in glob.glob(c + "/cache/index*"):
            key = (read(idx + "/level"), read(idx + "/type"), read(idx + "/shared_cpu_list"))
            if key in seen_cache:
                continue
            seen_cache.add(key)
            size = read(idx + "/size", "0K")
            m = re.match(r"(\d+)([KMG]?)", size)
            if m:
                mult = {"": 1, "K": 1024, "M": 1024 ** 2, "G": 1024 ** 3}[m.group(2)]
                lvl = int(key[0] or 0)
                caches[lvl] = caches.get(lvl, 0) + int(m.group(1)) * mult
    f0 = "/sys/devices/system/cpu/cpu0/cpufreq/"
    # Base clock: intel_pstate → ACPI CPPC nominal (AMD / newer Intel) →
    # the "@ 2.60GHz" some model names carry.
    base = read_int(f0 + "base_frequency") // 1000
    base = base or read_int("/sys/devices/system/cpu/cpu0/acpi_cppc/nominal_freq")
    if not base:
        m = re.search(r"@\s*([\d.]+)\s*GHz", model)
        base = int(float(m.group(1)) * 1000) if m else 0
    return {
        "model": model,
        "base_mhz": base,
        "max_mhz": read_int(f0 + "cpuinfo_max_freq") // 1000,
        "sockets": len(sockets),
        "cores": len(cores),
        "logical": len(cpus),
        "l1": caches.get(1, 0), "l2": caches.get(2, 0), "l3": caches.get(3, 0),
        "virt": "Enabled" if (" vmx" in flags or " svm" in flags) else "Not available",
    }


def disk_list() -> list[str]:
    return sorted(d for d in os.listdir("/sys/block") if not SKIP_DISK.match(d))


def disks_static() -> list[dict]:
    out = []
    for d in disk_list():
        b = "/sys/block/" + d
        out.append({
            "name": d,
            "model": read(b + "/device/model") or read(b + "/device/name") or d,
            "size": read_int(b + "/size") * 512,
            "ssd": read(b + "/queue/rotational", "1") == "0",
            "removable": read(b + "/removable", "0") == "1",
        })
    return out


# ── Dynamic readers ─────────────────────────────────────────────────────
def cpu_times() -> list[tuple[int, int]]:
    """(total, idle) for the aggregate row then each core."""
    out = []
    for line in read("/proc/stat").splitlines():
        if not line.startswith("cpu"):
            break
        f = [int(x) for x in line.split()[1:]]
        out.append((sum(f[:8]), f[3] + f[4]))
    return out


def meminfo() -> dict:
    m = {}
    for line in read("/proc/meminfo").splitlines():
        k, _, v = line.partition(":")
        p = v.split()
        if p:
            m[k] = int(p[0]) * 1024
    total = m.get("MemTotal", 0)
    avail = m.get("MemAvailable", 0)
    return {
        "total": total, "used": max(0, total - avail), "avail": avail,
        "cached": m.get("Cached", 0) + m.get("Buffers", 0) + m.get("SReclaimable", 0),
        "free": m.get("MemFree", 0), "dirty": m.get("Dirty", 0) + m.get("Writeback", 0),
        "committed": m.get("Committed_AS", 0), "commit_limit": m.get("CommitLimit", 0),
        "swap_total": m.get("SwapTotal", 0),
        "swap_used": max(0, m.get("SwapTotal", 0) - m.get("SwapFree", 0)),
    }


def diskstats() -> dict[str, tuple[int, ...]]:
    out = {}
    for line in read("/proc/diskstats").splitlines():
        f = line.split()
        if len(f) >= 14:
            # rd_ios, rd_sectors, rd_ms, wr_ios, wr_sectors, wr_ms, io_ticks
            out[f[2]] = (int(f[3]), int(f[5]), int(f[6]), int(f[7]), int(f[9]),
                         int(f[10]), int(f[12]))
    return out


def netdev() -> dict[str, tuple[int, int]]:
    out = {}
    for line in read("/proc/net/dev").splitlines()[2:]:
        name, _, rest = line.partition(":")
        name = name.strip()
        f = rest.split()
        if f and not SKIP_NET.match(name):
            out[name] = (int(f[0]), int(f[8]))
    return out


def mounts_by_disk() -> dict[str, list[str]]:
    try:
        out = subprocess.run(["lsblk", "-J", "-o", "NAME,MOUNTPOINTS"], capture_output=True,
                             text=True, timeout=2).stdout
        devs = json.loads(out).get("blockdevices", [])
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}

    def collect(node, acc):
        for mp in node.get("mountpoints") or []:
            if mp and mp not in acc:
                acc.append(mp)
        for ch in node.get("children") or []:
            collect(ch, acc)
        return acc
    # "/" first, then shortest paths (the disk's label in the sidebar).
    return {d["name"]: sorted(collect(d, []), key=lambda m: (m != "/", len(m), m))
            for d in devs}


def ip_addrs() -> dict[str, dict[str, str]]:
    try:
        out = subprocess.run(["ip", "-j", "addr"], capture_output=True, text=True,
                             timeout=2).stdout
        res = {}
        for itf in json.loads(out):
            v4 = next((a["local"] for a in itf.get("addr_info", []) if a.get("family") == "inet"), "")
            v6 = next((a["local"] for a in itf.get("addr_info", [])
                       if a.get("family") == "inet6" and a.get("scope") == "global"), "")
            if not v6:
                v6 = next((a["local"] for a in itf.get("addr_info", [])
                           if a.get("family") == "inet6"), "")
            res[itf["ifname"]] = {"ipv4": v4, "ipv6": v6}
        return res
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        return {}


# ── Main loop ───────────────────────────────────────────────────────────
def main(interval: float) -> None:
    gpus_mon = Gpus()
    print(json.dumps({
        "type": "static", "cpu": cpu_static(), "mem_total": meminfo()["total"],
        "disks": disks_static(), "gpus": gpus_mon.static(),
    }, separators=(",", ":")), flush=True)

    disks = disk_list()
    cpus = sorted(glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq"))
    prev_cpu = cpu_times()
    prev_disk = diskstats()
    prev_net = netdev()
    prev_t = time.monotonic()
    mounts, ips, fdpaths, nv_open = {}, {}, [], set()
    tick = 0
    time.sleep(min(interval, 0.5))

    while True:
        now = time.monotonic()
        dt = max(1e-3, now - prev_t)
        if tick % 10 == 0:
            mounts, ips = mounts_by_disk(), ip_addrs()
        if tick % 5 == 0:
            fdpaths, nv_open = drm_fds()

        # CPU
        cur_cpu = cpu_times()
        usage = []
        for (t0, i0), (t1, i1) in zip(prev_cpu, cur_cpu):
            d = t1 - t0
            usage.append(round(max(0.0, min(1.0, 1 - (i1 - i0) / d)), 4) if d > 0 else 0.0)
        prev_cpu = cur_cpu
        freqs = [read_int(p) for p in cpus]
        load = read("/proc/loadavg").split()
        cpu = {
            "usage": usage[0] if usage else 0, "cores": usage[1:],
            "mhz": round(sum(freqs) / len(freqs) / 1000) if freqs else 0,
            "procs": sum(1 for d in os.listdir("/proc") if d.isdigit()),
            "threads": int(load[3].split("/")[1]) if len(load) > 3 else 0,
            "uptime": float(read("/proc/uptime", "0").split()[0]),
        }

        # Disks
        cur_disk = diskstats()
        dsk = {}
        for d in disks:
            a, b = prev_disk.get(d), cur_disk.get(d)
            if not a or not b:
                continue
            ios = (b[0] - a[0]) + (b[3] - a[3])
            dsk[d] = {
                "active": round(min(1.0, (b[6] - a[6]) / (dt * 1000)), 4),
                "read": (b[1] - a[1]) * 512 / dt,
                "write": (b[4] - a[4]) * 512 / dt,
                "resp": round(((b[2] - a[2]) + (b[5] - a[5])) / ios, 2) if ios > 0 else 0,
                "mounts": mounts.get(d, []),
            }
        prev_disk = cur_disk

        # Network
        cur_net = netdev()
        net = {}
        for n, (rx, tx) in cur_net.items():
            if read("/sys/class/net/%s/operstate" % n) == "down":
                continue
            p = prev_net.get(n, (rx, tx))
            net[n] = {"rx": max(0, rx - p[0]) / dt, "tx": max(0, tx - p[1]) / dt,
                      "wifi": os.path.isdir("/sys/class/net/%s/wireless" % n),
                      **ips.get(n, {"ipv4": "", "ipv6": ""})}
        prev_net = cur_net

        # GPUs
        gpus = gpus_mon.sample(dt, fdpaths, nv_open)
        prev_t = now

        snap = {"type": "sample", "cpu": cpu, "mem": meminfo(), "disks": dsk,
                "net": net, "gpus": gpus}
        try:
            print(json.dumps(snap, separators=(",", ":")), flush=True)
        except BrokenPipeError:
            return
        tick += 1
        time.sleep(max(0.1, interval - (time.monotonic() - now)))


if __name__ == "__main__":
    try:
        main(float(sys.argv[1]) if len(sys.argv) > 1 else 1.0)
    except KeyboardInterrupt:
        pass
