pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// System info + performance stats for the dashboard Performance tab and
// the System settings pane. While `active` (bound in shell.qml: dashboard,
// settings or task manager open) perfTimer re-reads CPU/temp/memory every
// 2 s, disk every 30 s and uptime every minute; network keeps sampling while
// closed so its graph has continuous history; distro and the static sysinfo
// blob once. /proc + hwmon are read in-process (FileView, blockAllReads so
// text() returns this read, not the previous one) — no subprocess per value.
Singleton {
    id: root

    // ── System info ─────────────────────────────────────────────────────
    property string sysDistro: ""
    property string sysUptime: ""
    readonly property string sysWM: "Hyprland"
    // Static key=value details from system-info.sh (System pane).
    property var sysInfo: ({})

    // ── Performance ─────────────────────────────────────────────────────
    property real cpuPerc:        0
    property real cpuTempC:       0
    property real memPerc:        0
    property real memUsedKib:     0
    property real memTotalKib:    0
    property real diskPerc:       0
    property real diskUsedB:      0
    property real diskTotalB:     0
    property string diskMount:    "/"
    property real netDownBps:     0
    property real netUpBps:       0
    property real netDownTotal:   0
    property real netUpTotal:     0
    property var  netDownHistory: []
    property var  netUpHistory:   []

    property bool active: false
    // Re-prime the CPU delta on open so the first value isn't averaged over
    // the whole time the panels were closed.
    onActiveChanged: {
        if (!active) return
        cpu.prevTotal = 0
        sampleNow()
        primeTimer.restart()
    }
    function sampleNow() {
        sampleCpu()
        sampleTemp()
        sampleMem()
    }
    // CPU % needs two samples; take the second one quickly after opening.
    Timer {
        id: primeTimer
        interval: 500; repeat: false
        onTriggered: if (root.active) root.sampleNow()
    }

    // ── CPU usage (delta of /proc/stat aggregate row) ───────────────────
    FileView { id: statFile; path: "/proc/stat"; blockAllReads: true }
    QtObject {
        id: cpu
        property real prevTotal: 0
        property real prevIdle:  0
    }
    function sampleCpu() {
        statFile.reload()
        // "cpu  user nice system idle iowait irq softirq steal ..."
        const f = statFile.text().split("\n", 1)[0].trim().split(/\s+/).slice(1).map(Number)
        if (f.length < 4) return
        const idle  = f[3] + (f[4] || 0)
        const total = f.reduce((a, b) => a + b, 0)
        const dt = total - cpu.prevTotal
        const di = idle  - cpu.prevIdle
        if (cpu.prevTotal > 0 && dt > 0)
            root.cpuPerc = Math.max(0, Math.min(1, 1 - (di / dt)))
        cpu.prevTotal = total
        cpu.prevIdle  = idle
    }

    // ── CPU temperature (hwmon, °C) ─────────────────────────────────────
    // hwmon indices change across boots; resolve by chip name: coretemp
    // "Package id 0" → k10temp Tctl/Tdie → x86_pkg_temp zone, once (the
    // search forks ~20 processes); then just read that file. Reads m°C.
    property string _tempPath: ""
    Process {
        id: cpuTempFindProc
        running: true
        command: ["sh", "-c",
            "read_label() { " +
            "for h in /sys/class/hwmon/hwmon*; do " +
            "  [ \"$(cat \"$h/name\" 2>/dev/null)\" = \"$1\" ] || continue; " +
            "  for lf in \"$h\"/temp*_label; do " +
            "    [ -e \"$lf\" ] || continue; " +
            "    case \"$(cat \"$lf\" 2>/dev/null)\" in " +
            "      $2) echo \"${lf%_label}_input\"; return 0;; " +
            "    esac; " +
            "  done; " +
            "done; return 1; }; " +
            "read_label coretemp 'Package id 0' || " +
            "read_label k10temp 'Tctl' || " +
            "read_label k10temp 'Tdie' || " +
            "for z in /sys/class/thermal/thermal_zone*; do " +
            "  [ \"$(cat \"$z/type\" 2>/dev/null)\" = x86_pkg_temp ] && " +
            "  echo \"$z/temp\" && break; " +
            "done"]
        stdout: SplitParser { onRead: line => { if (line.trim()) root._tempPath = line.trim() } }
    }
    FileView { id: tempFile; path: root._tempPath; blockAllReads: true }
    function sampleTemp() {
        if (!root._tempPath) return
        tempFile.reload()
        const v = parseInt(tempFile.text())
        if (!isNaN(v) && v > 0) root.cpuTempC = v / 1000
    }

    // ── Memory (/proc/meminfo) ──────────────────────────────────────────
    FileView { id: memFile; path: "/proc/meminfo"; blockAllReads: true }
    function sampleMem() {
        memFile.reload()
        const t = memFile.text()
        const total = parseInt((t.match(/^MemTotal:\s+(\d+)/m) || [])[1])
        const avail = parseInt((t.match(/^MemAvailable:\s+(\d+)/m) || [])[1]) || 0
        if (!(total > 0)) return
        root.memTotalKib = total
        root.memUsedKib  = Math.max(0, total - avail)
        root.memPerc     = root.memUsedKib / total
    }

    // ── System info: distro name (once) + uptime (every minute, shown) ──
    Process {
        id: sysDistroProc
        running: true
        command: ["sh", "-c", ". /etc/os-release 2>/dev/null; echo \"$NAME\""]
        stdout: SplitParser { onRead: line => { const s = line.trim(); if (s) root.sysDistro = s } }
    }
    Process {
        id: sysUptimeProc
        command: ["uptime", "-p"]
        stdout: SplitParser { onRead: line => root.sysUptime = line.trim() }
    }
    Timer {
        id: sysUptimeTimer
        interval: 60000; repeat: true; running: root.active; triggeredOnStart: true
        onTriggered: { sysUptimeProc.running = false; sysUptimeProc.running = true }
    }

    // Static hardware/OS details, gathered once as key=value lines →
    // root.sysInfo (settings System pane).
    Process {
        id: sysInfoProc
        running: true
        command: ["sh", Paths.local(Qt.resolvedUrl("system-info.sh"))]
        property var _acc: ({})
        onRunningChanged: if (running) _acc = ({})
        stdout: SplitParser {
            onRead: line => {
                const i = line.indexOf("=")
                if (i > 0) sysInfoProc._acc[line.slice(0, i)] = line.slice(i + 1).trim()
            }
        }
        onExited: root.sysInfo = sysInfoProc._acc
    }

    // ── Disk (df / in bytes) ────────────────────────────────────────────
    // Usage barely moves: read on open, then every 30 s.
    Process {
        id: diskProc
        command: ["df", "-B1", "--output=target,used,size", "/"]
        stdout: SplitParser {
            onRead: line => {
                const p = line.trim().split(/\s+/)
                // Also skips df's header ("Mounted on  Used  1B-blocks").
                if (p.length < 3 || isNaN(parseFloat(p[1]))) return
                root.diskMount  = p[0]
                root.diskUsedB  = parseFloat(p[1])
                root.diskTotalB = parseFloat(p[2])
                root.diskPerc   = root.diskTotalB > 0 ? root.diskUsedB / root.diskTotalB : 0
            }
        }
    }
    Timer {
        interval: 30000; repeat: true; running: root.active; triggeredOnStart: true
        onTriggered: { diskProc.running = false; diskProc.running = true }
    }

    // ── Network (/proc/net/dev — sum of all non-lo interfaces) ──────────
    // Read with FileView rather than a subprocess: cheap enough to run all
    // the time, so the graph never restarts from a gap when reopened.
    FileView { id: netFile; path: "/proc/net/dev"; blockAllReads: true }
    QtObject {
        id: net
        property real prevRx: 0
        property real prevTx: 0
        property real prevT:  0
    }
    function sampleNet() {
        netFile.reload()
        let rx = 0, tx = 0
        for (const line of netFile.text().split("\n")) {
            const i = line.indexOf(":")
            if (i < 0 || line.slice(0, i).trim() === "lo") continue
            const f = line.slice(i + 1).trim().split(/\s+/).map(Number)
            if (f.length < 9) continue
            rx += f[0]; tx += f[8]
        }
        const now = Date.now() / 1000
        if (net.prevT > 0) {
            const dt = Math.max(0.001, now - net.prevT)
            root.netDownBps = Math.max(0, (rx - net.prevRx) / dt)
            root.netUpBps   = Math.max(0, (tx - net.prevTx) / dt)
            root.netDownHistory = root.netDownHistory.concat([root.netDownBps]).slice(-30)
            root.netUpHistory   = root.netUpHistory.concat([root.netUpBps]).slice(-30)
        }
        root.netDownTotal = rx
        root.netUpTotal   = tx
        net.prevRx = rx
        net.prevTx = tx
        net.prevT  = now
    }
    Timer {
        interval: 2000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: root.sampleNet()
    }

    Timer {
        id: perfTimer
        interval: 2000; repeat: true; running: root.active
        onTriggered: root.sampleNow()
    }
}
