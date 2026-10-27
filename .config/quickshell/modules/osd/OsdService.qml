pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.modules.audio
import qs.modules.brightness

// On-screen display: volume / brightness / media / battery, shown at the
// bottom of the screen and auto-hidden.
Singleton {
    id: root

    property bool   osdVisible:  false
    property string osdKind:     ""    // "audio" | "brightness" | "media" | "battery"
    property int    osdValue:    0     // 0..100 (bar for audio/brightness/battery)
    property bool   osdMuted:    false
    property bool   osdCharging: false // battery: plugged-in state (drives icon)
    property string osdText:     ""    // track text (media) / state label (battery)
    function showOsd(kind, value, muted, text, charging) {
        osdKind     = kind
        osdValue    = Math.max(0, Math.min(100, value))
        osdMuted    = muted || false
        osdCharging = charging || false
        osdText     = text || ""
        osdVisible  = true
        osdHideTimer.restart()
    }
    // Volume/brightness/media/battery notifications are shown here instead
    // of as toasts (NotificationService routes them).
    function showFromNotification(g, n) {
        const s = String(n.summary || "")
        const body = String(n.body || "")
        const m = s.match(/(\d+)\s*%/)
        if (g === "audio") {
            // Only the mute KEY shows muted; "Volume: Muted" from sliding
            // to 0 is just 0%.
            const isMuteKey = /switched off/i.test(s)
            const isUnmute  = /switched on/i.test(s)
            const v = m ? parseInt(m[1]) : (isUnmute ? AudioService.volPct : 0)
            showOsd("audio", v, isMuteKey, "")
        } else if (g === "brightness") {
            showOsd("brightness", m ? parseInt(m[1]) : BrightnessService.brightnessPct, false, "")
        } else if (g === "battery") {
            // Charge-state → icon + text OSD (no bar). Trust UPower, fall
            // back to parsing the text.
            const dev = UPower.displayDevice
            const charging = dev ? !UPower.onBattery : !/discharg/i.test(s)
            const label = /full/i.test(s) ? "Battery fully charged"
                        : charging         ? "Battery charging"
                                           : "Battery discharging"
            showOsd("battery", 0, false, label, charging)
        } else {
            showOsd("media", 0, false, (body || s).replace(/\n+/g, "  —  ").trim())
        }
    }
    // Battery OSDs linger 5 s (readable warning); others 1.6 s.
    Timer { id: osdHideTimer; interval: root.osdKind === "battery" ? 5000 : 1600; repeat: false; onTriggered: root.osdVisible = false }
}
