pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Monitor layout (Monitors settings pane) and presentation mode switching
// (extend / mirror / external / internal, like Win+P).
Singleton {
    id: root

    // ── Layout: query (hyprctl) + apply (write lua + reload) ────────────
    // Parsed from `hyprctl monitors -j`.
    property var monitorList: []
    function refreshMonitors() {
        monitorQueryProc.running = false
        monitorQueryProc.running = true
    }
    // cfgs: [{output, mode, x, y, scale, disabled}] → monitor_quickshell.lua
    // + hyprctl reload (apply-monitors.py).
    function applyMonitors(cfgs) {
        monitorApplyProc.cfgsJson = JSON.stringify(cfgs)
        monitorApplyProc.running = false
        monitorApplyProc.running = true
    }
    Process {
        id: monitorQueryProc
        command: ["hyprctl", "monitors", "-j"]
        property string _buf: ""
        onRunningChanged: if (running) _buf = ""
        stdout: SplitParser { onRead: line => monitorQueryProc._buf += line }
        onExited: {
            try {
                const arr = JSON.parse(monitorQueryProc._buf)
                root.monitorList = arr.map(m => ({
                    name:        m.name,
                    description: m.description || "",
                    width:       m.width,
                    height:      m.height,
                    refresh:     Math.round((m.refreshRate || 0) * 100) / 100,
                    x:           m.x,
                    y:           m.y,
                    scale:       m.scale,
                    transform:   m.transform || 0,
                    disabled:    !!m.disabled,
                    modes:       (m.availableModes || []).map(s => s.replace(/Hz$/i, ""))
                }))
            } catch (e) { console.log("monitor parse failed:", e) }
        }
    }
    Process {
        id: monitorApplyProc
        property string cfgsJson: "[]"
        command: ["python3", Paths.local(Qt.resolvedUrl("apply-monitors.py")), cfgsJson]
        onExited: root.refreshMonitors()
    }

    // ── Presentation mode ───────────────────────────────────────────────
    // `qs ipc call monitormode toggle|open|close|set <mode>`
    property bool monitorModeOpen: false
    function openMonitorMode()  { monitorModeOpen = true }
    function closeMonitorMode() { monitorModeOpen = false }
    function setMonitorMode(mode) {
        monitorModeProc.modeArg = mode
        monitorModeProc.running = false
        monitorModeProc.running = true
        root.monitorModeOpen = false
    }
    Process {
        id: monitorModeProc
        property string modeArg: "extend"
        command: ["python3", Paths.local(Qt.resolvedUrl("monitor-mode.py")), modeArg]
    }
    IpcHandler {
        target: "monitormode"
        function toggle() { root.monitorModeOpen = !root.monitorModeOpen }
        function open()   { root.openMonitorMode()  }
        function close()  { root.closeMonitorMode() }
        function set(mode: string) { root.setMonitorMode(mode) }
    }
}
