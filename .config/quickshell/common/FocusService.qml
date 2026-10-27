pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Keyboard-grabbing overlays (launcher, clipboard, wallpaper picker) steal
// focus from the active window. captureThenOpen() snapshots that window
// first; refocusLastWindow() hands focus back once the overlay closes.
Singleton {
    id: root

    // Toplevel focused just before the overlay opened. ("last" lags: layer
    // surfaces don't bump it.)
    property string lastFocusedAddr: ""
    property var    _pendingOpen: null

    // `open` runs once the active window has been captured.
    function captureThenOpen(open) {
        _pendingOpen = open
        captureActiveProc.running = false
        captureActiveProc.running = true
    }
    function refocusLastWindow() {
        if (lastFocusedAddr) refocusDelay.restart()
    }

    Process {
        id: captureActiveProc
        command: ["hyprctl", "activewindow", "-j"]
        property string _buf: ""
        onRunningChanged: if (running) _buf = ""
        stdout: SplitParser {
            onRead: line => captureActiveProc._buf += line
        }
        onExited: {
            try {
                const d = JSON.parse(captureActiveProc._buf)
                root.lastFocusedAddr = d.address || ""
            } catch(e) { root.lastFocusedAddr = "" }
            const open = root._pendingOpen
            root._pendingOpen = null
            if (open) open()
        }
    }

    // Refocus a toplevel by address (Lua-wrapped Hyprland dispatch).
    Process {
        id: refocusByAddrProc
        property string target: ""
        command: ["hyprctl", "dispatch",
                  "hl.dsp.focus({window = \"address:" + target + "\"})"]
    }

    // Wait for the overlay's close animation (PopAnim, 200 ms) to unmap the
    // surface + Hyprland's auto-refocus to settle, then focus the
    // previously-active window.
    Timer {
        id: refocusDelay
        interval: 200 + 120; repeat: false
        onTriggered: {
            if (!root.lastFocusedAddr) return
            refocusByAddrProc.target  = root.lastFocusedAddr
            refocusByAddrProc.running = false
            refocusByAddrProc.running = true
        }
    }
}
