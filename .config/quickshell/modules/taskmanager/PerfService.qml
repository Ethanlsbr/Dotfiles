pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.modules.network

// Performance tab data (Windows-style): perfmon.py streams one sample per
// second while the task manager is open; this keeps 60 s of history per
// series and builds the resource list (CPU, Memory, Disk N, Wi-Fi /
// Ethernet, GPU N) shown in the sidebar.
Singleton {
    id: root

    readonly property int capacity: 60

    property var  hw:     null     // static facts (perfmon "static" line)
    property var  sample: null     // latest sample
    // Series key → last `capacity` values, e.g. "cpu", "core:3", "mem",
    // "disk:nvme0n1:active|read|write", "net:wlan0:rx|tx",
    // "gpu:<pdev>:util", "gpu:<pdev>:eng:render".
    property var  hist:   ({})

    function series(key) { return hist[key] || [] }

    // Sidebar entries: {id, kind, key, title, color-role, ...}.
    readonly property var resources: {
        const out = []
        if (!hw || !sample) return out
        out.push({ id: "cpu", kind: "cpu", title: "CPU" })
        out.push({ id: "mem", kind: "mem", title: "Memory" })
        let i = 0
        for (const d of hw.disks) {
            if (!sample.disks[d.name]) continue
            const m = sample.disks[d.name].mounts
            out.push({ id: "disk:" + d.name, kind: "disk", key: d.name, disk: d,
                       title: "Disk " + (i++) + " (" + (m.length ? m[0] : d.name) + ")" })
        }
        for (const n of Object.keys(sample.net).sort()) {
            const s = sample.net[n]
            out.push({ id: "net:" + n, kind: "net", key: n,
                       title: s.wifi ? "Wi-Fi" : (n.startsWith("e") ? "Ethernet" : n) })
        }
        i = 0
        for (const g of hw.gpus)
            out.push({ id: "gpu:" + g.pdev, kind: "gpu", key: g.pdev, gpu: g,
                       title: "GPU " + (i++) })
        return out
    }

    // Active Wi-Fi network (from NetworkService's nmcli scan).
    readonly property var wifi: (NetworkService.wifiList || []).find(w => w.active) || null

    // ── Formatting ─────────────────────────────────────────────────────
    function fmtBytes(b) {
        if (b >= 1024 ** 4) return (b / 1024 ** 4).toFixed(1) + " TB"
        if (b >= 1024 ** 3) return (b / 1024 ** 3).toFixed(1) + " GB"
        if (b >= 1024 ** 2) return (b / 1024 ** 2).toFixed(1) + " MB"
        if (b >= 1024)      return (b / 1024).toFixed(0) + " KB"
        return Math.round(b) + " B"
    }
    function fmtRate(bps) {
        if (bps >= 1024 ** 3) return (bps / 1024 ** 3).toFixed(1) + " GB/s"
        if (bps >= 1024 ** 2) return (bps / 1024 ** 2).toFixed(1) + " MB/s"
        return (bps / 1024).toFixed(0) + " KB/s"
    }
    // Network rates read in bits, like Windows (B/s in → Kbps / Mbps).
    function fmtBits(bps) {
        const b = bps * 8
        if (b >= 1e9) return (b / 1e9).toFixed(1) + " Gbps"
        if (b >= 1e6) return (b / 1e6).toFixed(1) + " Mbps"
        return (b / 1e3).toFixed(b >= 1e5 ? 0 : 1) + " Kbps"
    }
    function fmtPct(f) { return Math.round(f * 100) + "%" }
    function fmtGHz(mhz) { return (mhz / 1000).toFixed(2) + " GHz" }
    function fmtUptime(s) {
        s = Math.floor(s)
        const d = Math.floor(s / 86400), h = Math.floor(s / 3600) % 24
        const m = Math.floor(s / 60) % 60, sec = s % 60
        const p = n => (n < 10 ? "0" : "") + n
        return d + ":" + p(h) + ":" + p(m) + ":" + p(sec)
    }
    // Canonical GPU engine keys from gpumon.py (Intel / AMD / NVIDIA alike),
    // in display order.
    readonly property var engineOrder: ["3d", "video-decode", "video-encode", "video-encode-2",
                                        "video-processing", "copy", "compute", "jpeg"]
    readonly property var engineNames: ({
        "3d": "3D", "copy": "Copy", "video-decode": "Video Decode",
        "video-encode": "Video Encode", "video-encode-2": "Video Encode 2",
        "video-processing": "Video Processing", "compute": "Compute", "jpeg": "JPEG"
    })
    function gpuState(g) { return !g ? "" : g.suspended ? "Suspended" : g.idle ? "Idle" : "Active" }
    function fmtTemp(c) { return Math.round(c) + "°C" }

    // ── Sampling ───────────────────────────────────────────────────────
    function _ingest(s) {
        const old = hist, h = {}, cap = capacity
        const add = (k, v) => {
            const a = (old[k] || []).concat([v])
            h[k] = a.length > cap ? a.slice(a.length - cap) : a
        }
        add("cpu", s.cpu.usage)
        for (let i = 0; i < s.cpu.cores.length; i++) add("core:" + i, s.cpu.cores[i])
        add("mem", s.mem.used)
        for (const d in s.disks) {
            add("disk:" + d + ":active", s.disks[d].active)
            add("disk:" + d + ":read",   s.disks[d].read)
            add("disk:" + d + ":write",  s.disks[d].write)
        }
        for (const n in s.net) {
            add("net:" + n + ":rx", s.net[n].rx)
            add("net:" + n + ":tx", s.net[n].tx)
        }
        for (const g in s.gpus) {
            add("gpu:" + g + ":util", s.gpus[g].util)
            if (s.gpus[g].mem_local_total > 0) add("gpu:" + g + ":mem", s.gpus[g].mem_local)
            for (const e in s.gpus[g].engines) add("gpu:" + g + ":eng:" + e, s.gpus[g].engines[e])
        }
        hist = h
        sample = s
    }

    Connections {
        target: TaskManagerService
        function onTaskManagerOpenChanged() {
            if (TaskManagerService.taskManagerOpen) { root.hist = ({}); root.sample = null }
        }
    }

    Process {
        id: perfProc
        running: TaskManagerService.taskManagerOpen
        command: ["python3", Paths.local(Qt.resolvedUrl("perfmon.py")), "1"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line)
                    if (d.type === "static") root.hw = d
                    else                     root._ingest(d)
                } catch (e) { console.log("[perf] bad sample:", e) }
            }
        }
        onExited: if (TaskManagerService.taskManagerOpen) perfRestart.restart()
    }
    Timer {
        id: perfRestart
        interval: 1000; repeat: false
        onTriggered: if (TaskManagerService.taskManagerOpen) perfProc.running = true
    }
}
