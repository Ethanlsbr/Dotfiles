pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.common
import qs.modules.osd

// Battery: the bar's percentage toggle, charger plug/unplug notifications
// and low-battery warning OSDs.
Singleton {
    id: root

    // ── Bar battery percentage (state/battery-percent.txt) ──────────────
    // Shown by default; only an explicit "0" hides it.
    property bool batteryPercentEnabled: true
    function setBatteryPercent(on) {
        root.batteryPercentEnabled = !!on
        batteryPercentFile.save(on ? "1" : "0")
    }
    StateFile {
        id: batteryPercentFile
        name: "battery-percent.txt"
        onLoaded: lines => { if (lines.some(l => l.trim() === "0")) root.batteryPercentEnabled = false }
    }

    // ── Battery charge-state popups ──────────────────────────────────────
    // Notify on charger plug/unplug; _batReady suppresses the startup
    // UPower population.
    property bool _batReady: false
    Timer { interval: 4000; repeat: false; running: true; onTriggered: { root._batReady = true; root._checkLowBattery() } }
    Process {
        id: batteryNotifyProc
        property string title: ""
        property string body:  ""
        property string icon:  "battery"
        command: ["notify-send", "-a", "Battery", "-u", "low",
                  "-h", "string:x-canonical-private-synchronous:battery-state",
                  "-i", icon, title, body]
    }
    function _notifyBattery() {
        const d = UPower.displayDevice
        const pct = (d && d.isPresent) ? "  •  " + Math.round(d.percentage * 100) + "%" : ""
        if (!UPower.onBattery) {
            const full = d && d.state === UPowerDeviceState.FullyCharged
            batteryNotifyProc.title = full ? "Fully charged" : "Charging"
            batteryNotifyProc.icon  = full ? "battery-full" : "battery-charging"
            batteryNotifyProc.body  = "Plugged in" + pct
        } else {
            batteryNotifyProc.title = "Discharging"
            batteryNotifyProc.icon  = "battery"
            batteryNotifyProc.body  = "On battery" + pct
        }
        batteryNotifyProc.running = false
        batteryNotifyProc.running = true
    }
    Connections {
        target: UPower
        function onOnBatteryChanged() {
            if (root._batReady) { root._notifyBattery(); root._checkLowBattery() }
        }
    }

    // ── Low-battery warning OSDs ─────────────────────────────────────────
    // OSD when charge crosses 15/10/5% on battery; each level fires once
    // per discharge cycle, re-armed on charge or climbing back above.
    readonly property var _batLowLevels: [5, 10, 15]   // ascending = most-urgent first
    property var          _batWarned:    []             // levels already shown this cycle
    function _checkLowBattery() {
        const d = UPower.displayDevice
        if (!d || !d.isPresent) return
        const pct = Math.round(d.percentage * 100)
        // Charging / plugged in → clear all warnings so they can re-fire.
        if (!UPower.onBattery) { if (root._batWarned.length) root._batWarned = []; return }
        // Re-arm any levels we've since climbed back above.
        let warned = root._batWarned.filter(l => pct <= l)
        // The lowest crossed level not yet warned is the one to show.
        let fire = -1
        for (const lvl of root._batLowLevels)
            if (pct <= lvl && warned.indexOf(lvl) < 0) { fire = lvl; break }
        if (fire >= 0) {
            // Mark all crossed levels — a big jump shows only the most
            // urgent OSD.
            for (const lvl of root._batLowLevels) if (pct <= lvl) warned.push(lvl)
            const label = (fire <= 5 ? "Battery critically low" : "Battery low") + "  •  " + pct + "%"
            OsdService.showOsd("battery", pct, false, label, false)
        }
        root._batWarned = warned
    }
    // Rebinds if the active battery device changes.
    Connections {
        target: UPower.displayDevice
        function onPercentageChanged() { if (root._batReady) root._checkLowBattery() }
    }
}
