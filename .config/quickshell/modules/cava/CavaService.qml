pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Cava audio visualiser values (cavaBarCount bars, 0..1), smoothed so the
// wallpaper strip and media pane glide.
// cava only runs while `active` (bound in shell.qml: wallpaper strip on or
// dashboard open) — it streams 60 lines/s even in silence.
Singleton {
    id: root

    readonly property int cavaBarCount: 64
    property var cavaValues: new Array(64).fill(0)
    // Smoothing approach factor (0..1, lower = smoother); rises faster
    // than it falls so beats stay punchy.
    readonly property real cavaSmoothUp:   0.45
    readonly property real cavaSmoothDown: 0.18

    property bool active: false
    // Cleared while waiting to restart after a crash.
    property bool _up: true
    onActiveChanged: if (!active) cavaValues = new Array(cavaBarCount).fill(0)

    // stdout lines "v1;v2;...;vN;", normalised 0..1 (ascii_max_range 1000).
    Process {
        id: cavaProc
        running: root.active && root._up
        command: ["cava", "-p", Paths.local(Qt.resolvedUrl("cava.conf"))]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(";")
                const n = Math.min(parts.length - 1, root.cavaBarCount)
                const prev = root.cavaValues
                const arr = new Array(root.cavaBarCount).fill(0)
                // Exponential smoothing (fast rise, soft decay).
                for (let i = 0; i < n; i++) {
                    const target = Math.max(0, Math.min(1, (parseInt(parts[i]) || 0) / 1000))
                    const p = prev[i] || 0
                    const a = target > p ? root.cavaSmoothUp : root.cavaSmoothDown
                    arr[i] = p + (target - p) * a
                }
                root.cavaValues = arr
            }
        }
        onExited: (code, status) => {
            if (!root.active) return
            root._up = false
            cavaRestartTimer.start()
        }
    }
    Timer {
        id: cavaRestartTimer
        interval: 3000; repeat: false
        onTriggered: root._up = true
    }
}
