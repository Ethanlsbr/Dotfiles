"""
GPU sampling for perfmon.py — Intel (i915, xe), AMD (amdgpu) and NVIDIA
(proprietary driver via nvidia-smi; nouveau shows what sysfs offers).

Sources, all readable without root:
  engines   DRM fdinfo of our own processes: drm-engine-<e> ns (i915, amdgpu)
            or drm-cycles-<e> / drm-total-cycles-<e> (xe); nvidia-smi
            utilization.{gpu,encoder,decoder} for NVIDIA.
  util      amdgpu gpu_busy_percent / nvidia-smi / else the busiest engine.
  freq      i915 gt_act_freq_mhz · xe tile*/gt*/freq0/act_freq · amdgpu hwmon
            freq1_input · nvidia-smi clocks.gr
  memory    amdgpu mem_info_vram_* / gtt · nvidia-smi memory.* · fdinfo
            drm-resident-* (Intel)
  temp/pwr  hwmon temp*_input, power1_{average,input} or energy1_input delta
            · nvidia-smi temperature.gpu / power.draw

Hybrid laptops runtime-suspend the dedicated GPU. Touching its sysfs, hwmon
or nvidia-smi wakes it (or keeps resetting its autosuspend timer), so for a
GPU that can runtime-suspend and isn't the boot display we only read those
while a process of ours is actually using it (fdinfo / open /dev/nvidiaN);
otherwise it's reported idle without poking it.
"""
from __future__ import annotations
import glob, os, re, shlex, subprocess

VENDORS = {"0x8086": "intel", "0x1002": "amd", "0x10de": "nvidia"}

# Driver engine names → canonical keys the UI labels (Windows-style).
ENGINE_KEYS = {
    "render": "3d", "gfx": "3d", "rcs": "3d",
    "copy": "copy", "dma": "copy", "sdma": "copy", "bcs": "copy",
    "video": "video-decode", "dec": "video-decode", "vcs": "video-decode",
    "enc": "video-encode", "enc_1": "video-encode-2",
    "video-enhance": "video-processing", "vecs": "video-processing", "vpe": "video-processing",
    "compute": "compute", "ccs": "compute",
    "jpeg": "jpeg",
}

NV_FIELDS = ["pci.bus_id", "utilization.gpu", "memory.used", "memory.total", "clocks.gr",
             "clocks.max.gr", "temperature.gpu", "power.draw"]
NV_EXTRA = ["utilization.encoder", "utilization.decoder"]


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


def parse_size(v: str) -> int:
    p = v.split()
    if not p:
        return 0
    mult = {"KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3}.get(p[1] if len(p) > 1 else "", 1)
    try:
        return int(p[0]) * mult
    except ValueError:
        return 0


def lspci_name(slot: str) -> str:
    """"Intel UHD Graphics", "AMD Radeon RX 6600", "NVIDIA GeForce RTX 3060"."""
    try:
        out = subprocess.run(["lspci", "-mm", "-s", slot], capture_output=True,
                             text=True, timeout=2).stdout.strip()
        f = shlex.split(out)
        vendor, dev = f[2], f[3]
        vb = re.search(r"\[([^\]]+)\]", vendor)
        vendor = vb.group(1).split("/")[0] if vb else vendor.split()[0]
        m = re.search(r"\[([^\]]+)\]", dev)
        return vendor + " " + (m.group(1) if m else dev)
    except (OSError, IndexError, ValueError, subprocess.SubprocessError):
        return slot


def first(pattern: str) -> str:
    g = sorted(glob.glob(pattern))
    return g[0] if g else ""


# ── fdinfo ──────────────────────────────────────────────────────────────
def drm_fds() -> tuple[list[str], set[str]]:
    """(fdinfo paths of our DRM fds, /dev/nvidiaN nodes we have open)."""
    out, nv = [], set()
    me = os.getuid()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            if os.stat("/proc/" + pid).st_uid != me:
                continue
            fds = os.listdir("/proc/%s/fd" % pid)
        except OSError:
            continue
        for fd in fds:
            try:
                link = os.readlink("/proc/%s/fd/%s" % (pid, fd))
            except OSError:
                continue
            if link.startswith("/dev/dri/"):
                out.append("/proc/%s/fdinfo/%s" % (pid, fd))
            elif re.fullmatch(r"/dev/nvidia\d+", link):
                nv.add(link)
    return out, nv


def parse_fdinfo(text: str) -> dict | None:
    """One fdinfo → {pdev, cid, ns{}, cycles{}, total{}, caps{}, local, system}."""
    info = {}
    for line in text.splitlines():
        k, _, v = line.partition(":")
        if k.startswith("drm-"):
            info[k] = v.strip()
    pdev, cid = info.get("drm-pdev"), info.get("drm-client-id")
    if not pdev or not cid:
        return None
    c = {"pdev": pdev, "cid": cid, "ns": {}, "cycles": {}, "total": {}, "caps": {},
         "local": 0, "system": 0}
    num = lambda v: int((v.split() or ["0"])[0])
    for k, v in info.items():
        try:
            if k.startswith("drm-engine-capacity-"):
                c["caps"][k[20:]] = max(1, num(v))
            elif k.startswith("drm-engine-"):
                c["ns"][k[11:]] = num(v)
            elif k.startswith("drm-total-cycles-"):
                c["total"][k[17:]] = num(v)
            elif k.startswith("drm-cycles-"):
                c["cycles"][k[11:]] = num(v)
            elif k.startswith(("drm-resident-local", "drm-resident-vram", "drm-memory-vram")):
                c["local"] += parse_size(v)
            elif (k.startswith(("drm-resident-system", "drm-resident-gtt", "drm-memory-gtt"))
                  and "stolen" not in k):
                c["system"] += parse_size(v)
        except ValueError:
            pass
    return c


def drm_clients(paths: list[str]) -> dict[tuple[str, str], dict]:
    clients = {}
    for p in paths:
        try:
            with open(p) as f:
                c = parse_fdinfo(f.read())
        except OSError:
            continue
        if c and (c["pdev"], c["cid"]) not in clients:
            clients[(c["pdev"], c["cid"])] = c
    return clients


def engine_busy(cur: dict, prev: dict, pdev: str, dt: float) -> dict[str, float]:
    """Canonical engine → busy fraction for one device, from client deltas."""
    raw: dict[str, float] = {}
    span: dict[str, int] = {}          # xe: GPU timestamp span per engine
    cyc: dict[str, int] = {}
    for key, c in cur.items():
        if key[0] != pdev:
            continue
        old = prev.get(key)
        for e, ns in c["ns"].items():
            raw.setdefault(e, 0.0)
            if old and e in old["ns"] and ns > old["ns"][e]:
                raw[e] += (ns - old["ns"][e]) / (dt * 1e9) / c["caps"].get(e, 1)
        for e, cy in c["cycles"].items():
            raw.setdefault(e, 0.0)
            if old and e in old["cycles"] and e in c["total"] and e in old["total"]:
                cyc[e] = cyc.get(e, 0) + max(0, cy - old["cycles"][e]) // c["caps"].get(e, 1)
                span[e] = max(span.get(e, 0), c["total"][e] - old["total"][e])
    for e, d in cyc.items():
        if span.get(e, 0) > 0:
            raw[e] = d / span[e]
    out: dict[str, float] = {}
    for e, v in raw.items():
        k = ENGINE_KEYS.get(e, e)
        out[k] = round(min(1.0, max(out.get(k, 0.0), v)), 4)
    return out


# ── NVIDIA (proprietary) ────────────────────────────────────────────────
def nv_num(v: str) -> float | None:
    try:
        return float(v)
    except ValueError:
        return None                    # "[N/A]", "[Not Supported]"


class NvidiaSmi:
    def __init__(self) -> None:
        self.fields = NV_FIELDS + NV_EXTRA
        self.ok = bool(subprocess.run(["sh", "-c", "command -v nvidia-smi"],
                                      capture_output=True).stdout)

    def query(self, pdevs: list[str]) -> dict[str, dict]:
        """pdev → {util, enc, dec, mem_used, mem_total, mhz, max_mhz, temp, power}."""
        if not self.ok or not pdevs:
            return {}
        for _ in range(2):
            try:
                r = subprocess.run(["nvidia-smi", "-i", ",".join(pdevs),
                                    "--query-gpu=" + ",".join(self.fields),
                                    "--format=csv,noheader,nounits"],
                                   capture_output=True, text=True, timeout=3)
            except (OSError, subprocess.SubprocessError):
                return {}
            if r.returncode == 0:
                break
            if self.fields != NV_FIELDS:   # old driver: no encoder/decoder fields
                self.fields = NV_FIELDS
                continue
            return {}
        else:
            return {}
        out = {}
        for line in r.stdout.splitlines():
            v = [x.strip() for x in line.split(",")]
            if len(v) < len(NV_FIELDS):
                continue
            pdev = v[0].lower()[-12:]      # 00000000:01:00.0 → 0000:01:00.0
            n = [nv_num(x) for x in v]
            out[pdev] = {
                "util": (n[1] or 0) / 100,
                "mem_used": (n[2] or 0) * 1024 ** 2, "mem_total": (n[3] or 0) * 1024 ** 2,
                "mhz": int(n[4] or 0), "max_mhz": int(n[5] or 0),
                "temp": n[6], "power": n[7],
                "enc": (n[8] / 100) if len(n) > 8 and n[8] is not None else None,
                "dec": (n[9] / 100) if len(n) > 9 and n[9] is not None else None,
            }
        return out


# ── Devices ─────────────────────────────────────────────────────────────
class Gpus:
    def __init__(self) -> None:
        self.devs = []
        for d in glob.glob("/sys/bus/pci/devices/*"):
            if not read(d + "/class").startswith("0x03"):
                continue
            pdev = os.path.basename(d)
            driver = os.path.basename(os.path.realpath(d + "/driver")) if os.path.exists(d + "/driver") else ""
            vendor = VENDORS.get(read(d + "/vendor"), "other")
            boot = read(d + "/boot_vga", "0") == "1"
            dev = {
                "path": d, "pdev": pdev, "driver": driver, "vendor": vendor, "boot": boot,
                "card": first(d + "/drm/card[0-9]*"),
                "hwmon": first(d + "/hwmon/hwmon*"),
                "xe_freq": first(d + "/tile*/gt*/freq0") if driver == "xe" else "",
                # Can runtime-suspend and isn't driving the boot display:
                # only poke it while in use.
                "lazy": not boot and read(d + "/power/control") == "auto",
                "nv_minor": "",
            }
            if driver == "nvidia":
                for line in read("/proc/driver/nvidia/gpus/%s/information" % pdev).splitlines():
                    if line.startswith("Device Minor"):
                        dev["nv_minor"] = "/dev/nvidia" + line.split(":")[1].strip()
            dev["name"] = lspci_name(pdev)
            dev["integrated"] = self._integrated(dev)
            dev["max_mhz"] = self._max_mhz(dev)
            self.devs.append(dev)
        # GPU 0 = the boot / integrated GPU, like Windows.
        self.devs.sort(key=lambda g: (not g["boot"], not g["integrated"], g["pdev"]))
        self.nv = NvidiaSmi() if any(g["driver"] == "nvidia" for g in self.devs) else None
        self.prev: dict = {}
        self.energy: dict[str, int] = {}
        self.last: dict[str, dict] = {}      # NVIDIA: keep last totals while idle

    @staticmethod
    def _integrated(g: dict) -> bool:
        # Intel iGPUs sit right on the root bus; AMD APUs have a small UMA
        # carve-out as "VRAM"; NVIDIA is always discrete.
        if g["vendor"] == "nvidia":
            return False
        if g["pdev"].startswith("0000:00:"):
            return True
        vram = read_int(g["path"] + "/mem_info_vram_total")
        return g["driver"] == "amdgpu" and 0 < vram <= 2 * 1024 ** 3

    @staticmethod
    def _max_mhz(g: dict) -> int:
        if g["driver"] == "i915" and g["card"]:
            return read_int(g["card"] + "/gt_max_freq_mhz") or read_int(g["card"] + "/gt_RP0_freq_mhz")
        if g["driver"] == "xe" and g["xe_freq"]:
            return read_int(g["xe_freq"] + "/rp0_freq") or read_int(g["xe_freq"] + "/max_freq")
        if g["driver"] == "amdgpu" and read(g["path"] + "/power/runtime_status") != "suspended":
            levels = re.findall(r"(\d+)\s*Mhz", read(g["path"] + "/pp_dpm_sclk"), re.I)
            return max(map(int, levels), default=0)
        return 0

    def static(self) -> list[dict]:
        return [{"pdev": g["pdev"], "name": g["name"], "driver": g["driver"] or "none",
                 "vendor": g["vendor"], "max_mhz": g["max_mhz"], "integrated": g["integrated"],
                 "mem_total": read_int(g["path"] + "/mem_info_vram_total")
                              if g["driver"] == "amdgpu" and not g["integrated"] else 0}
                for g in self.devs]

    def _hwmon(self, g: dict, dt: float) -> tuple[float | None, float | None]:
        """(°C, W) from the device's hwmon, if any."""
        h = g["hwmon"]
        if not h:
            return None, None
        temps = [read_int(p) for p in glob.glob(h + "/temp*_input")]
        temp = max(temps) / 1000 if any(temps) else None
        power = None
        for f in ("power1_average", "power1_input"):
            if os.path.exists(h + "/" + f):
                power = read_int(h + "/" + f) / 1e6
                break
        else:
            if os.path.exists(h + "/energy1_input"):
                e = read_int(h + "/energy1_input")
                old = self.energy.get(g["pdev"])
                self.energy[g["pdev"]] = e
                if old is not None and e >= old:
                    power = (e - old) / 1e6 / dt
        return temp, power

    def sample(self, dt: float, fdpaths: list[str], nv_open: set[str]) -> dict[str, dict]:
        cur = drm_clients(fdpaths)
        out = {}
        nv_poll = []
        for g in self.devs:
            p, path = g["pdev"], g["path"]
            suspended = read(path + "/power/runtime_status") == "suspended"
            engines = engine_busy(cur, self.prev, p, dt)
            mem_local = sum(c["local"] for k, c in cur.items() if k[0] == p)
            mem_system = sum(c["system"] for k, c in cur.items() if k[0] == p)
            in_use = (any(v > 0.005 for v in engines.values())
                      or (g["nv_minor"] and g["nv_minor"] in nv_open))
            # Safe to read the hardware without keeping a lazy GPU awake?
            poke = not suspended and (not g["lazy"] or in_use)
            s = {"util": max(engines.values(), default=0.0), "engines": engines,
                 "suspended": suspended, "idle": not suspended and not poke,
                 "mhz": 0, "max_mhz": g["max_mhz"], "mem_local": mem_local,
                 "mem_local_total": 0, "mem_system": mem_system, "temp": None, "power": None}
            if poke:
                s["temp"], s["power"] = self._hwmon(g, dt)
                if g["driver"] == "i915" and g["card"]:
                    s["mhz"] = read_int(g["card"] + "/gt_act_freq_mhz")
                elif g["driver"] == "xe" and g["xe_freq"]:
                    s["mhz"] = read_int(g["xe_freq"] + "/act_freq")
                elif g["driver"] == "amdgpu":
                    if os.path.exists(path + "/gpu_busy_percent"):
                        s["util"] = read_int(path + "/gpu_busy_percent") / 100
                    hz = read_int(g["hwmon"] + "/freq1_input") if g["hwmon"] else 0
                    s["mhz"] = hz // 1_000_000
                    s["mem_local"] = read_int(path + "/mem_info_vram_used") or mem_local
                    s["mem_system"] = read_int(path + "/mem_info_gtt_used") or mem_system
                elif g["driver"] == "nvidia":
                    nv_poll.append(p)
            if g["driver"] == "amdgpu" and not g["integrated"]:
                s["mem_local_total"] = read_int(path + "/mem_info_vram_total")
            out[p] = s
        nv_polled: set[str] = set()
        if self.nv and nv_poll:
            for p, n in self.nv.query(nv_poll).items():
                if p not in out:
                    continue
                s = out[p]
                eng = {"3d": n["util"]}
                if n["dec"] is not None: eng["video-decode"] = n["dec"]
                if n["enc"] is not None: eng["video-encode"] = n["enc"]
                s.update(util=n["util"], engines=eng, mhz=n["mhz"],
                         max_mhz=n["max_mhz"] or s["max_mhz"], mem_local=n["mem_used"],
                         mem_local_total=n["mem_total"], temp=n["temp"], power=n["power"])
                self.last[p] = {"max_mhz": s["max_mhz"], "mem_local_total": n["mem_total"],
                                "engines": list(eng)}
                nv_polled.add(p)
        for p, last in self.last.items():      # idle NVIDIA: keep totals + engine set
            if p in out and p not in nv_polled:
                out[p]["mem_local_total"] = last["mem_local_total"]
                out[p]["max_mhz"] = out[p]["max_mhz"] or last["max_mhz"]
                out[p]["engines"] = {e: 0.0 for e in last["engines"]}
        self.prev = cur
        return out
