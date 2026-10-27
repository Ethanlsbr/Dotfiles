pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Screen brightness (brightnessctl), with the same optimistic + hold
// pattern as volume so slider drags don't snap back.
Singleton {
    id: root

    property int brightnessPct: -1

    // Same optimistic + hold pattern as volume.
    property bool _briHold: false
    property int  _briPending: -1
    function refreshBrightness() {
        brightnessQueryProc.running = false
        brightnessQueryProc.running = true
    }
    function setBrightnessPct(pct) {
        const p = Math.max(1, Math.min(100, Math.round(pct)))   // never 0 → black
        root.brightnessPct = p
        root._briHold = true
        briHoldTimer.restart()
        root._briPending = p
        briSetDebounce.restart()
    }
    // Step ±10 snapping to multiples of 10; setBrightnessPct clamps to
    // [1, 100].
    function adjustBrightness(direction) {  // "+" or "-"
        const cur  = root.brightnessPct < 0 ? 0 : root.brightnessPct
        const next = direction === "+" ? (Math.floor(cur / 10) + 1) * 10
                                       : (Math.ceil(cur / 10)  - 1) * 10
        setBrightnessPct(next)
    }
    // No live subscribe for brightness — poll while the panel is open so
    // the slider tracks hardware keys; _briHold protects drags.
    Connections {
        target: PopupService
        function onNotifPopupOpenChanged() {
            if (PopupService.notifPopupOpen) { root.refreshBrightness(); briPollTimer.start() }
            else                               briPollTimer.stop()
        }
    }
    Timer {
        id: briPollTimer
        interval: 800; repeat: true
        onTriggered: root.refreshBrightness()
    }

    Process {
        id: brightnessQueryProc
        running: true
        command: ["sh", "-c", "brightnessctl -m | cut -d, -f4 | tr -d '%'"]
        stdout: SplitParser {
            onRead: line => {
                const v = parseInt(line.trim())
                if (!isNaN(v) && !root._briHold) root.brightnessPct = v
            }
        }
    }
    Process {
        id: briSetProc
        property int target: 0
        command: ["brightnessctl", "-q", "set", target + "%"]
    }
    Timer {
        id: briSetDebounce
        interval: 40; repeat: false
        onTriggered: {
            if (root._briPending < 0) return
            briSetProc.target  = root._briPending
            briSetProc.running = false
            briSetProc.running = true
        }
    }
    Timer {
        id: briHoldTimer
        interval: 450; repeat: false
        onTriggered: { root._briHold = false; root.refreshBrightness() }
    }
}
