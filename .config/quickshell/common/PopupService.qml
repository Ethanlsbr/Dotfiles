pragma Singleton
import QtQuick
import Quickshell
import qs.modules.network

// Bar hover popups (audio, battery, bluetooth, wifi, clock, notifications):
// open flags, mutual exclusion, the 500 ms hover-in dwell and the shared
// 600 ms hover-out grace.
Singleton {
    id: root

    property bool sinkPopupOpen:      false
    property bool batteryPopupOpen:   false
    property bool bluetoothPopupOpen: false
    property bool wifiPopupOpen:      false
    property bool clockPopupOpen:     false
    property bool notifPopupOpen:     false

    // Monitor whose bar was last hovered — the popup panel opens there
    // (null → first screen).
    property var  popupScreen: null
    // How far the panel under the pill has opened (0 = closed, 1 = full
    // width). The pill's bottom corners square off in step with it, so the
    // two only read as one shape once the panel actually spans the pill.
    property real rightPopupProgress: 0

    // What the cursor is on right now: a pill module, and/or the popup
    // panel. Qt sends the new hover target's enter *before* the old one's
    // leave, so a hide timer started by a leave can't be trusted on its
    // own — on expiry it only closes a popup that nothing is holding.
    property string hoveredModule: ""
    property bool   panelHovered:  false
    function held(name) { return panelHovered || hoveredModule === name }

    // Pill module hover: entering opens after a 500 ms dwell (instantly when
    // another popup is already open, so sweeping across the pill switches
    // straight away); leaving cancels a pending open and starts the grace.
    function hoverModule(name, on) {
        if (on) {
            hoveredModule = name
            if (openPopup() !== "") { showTimer.stop(); showPopup(name) }
            else showTimer.restart()
        } else {
            if (hoveredModule === name) { hoveredModule = ""; showTimer.stop() }
            startHideTimer(name)
        }
    }
    Timer {
        id: showTimer
        interval: 500
        onTriggered: if (root.hoveredModule !== "") root.showPopup(root.hoveredModule)
    }
    // Popup panel hover: leaving it starts the open popup's grace.
    function setPanelHovered(on) {
        panelHovered = on
        if (!on) startHideTimer(openPopup())
    }
    function openPopup() {
        return bluetoothPopupOpen ? "bluetooth" : sinkPopupOpen  ? "sink"
             : batteryPopupOpen   ? "battery"   : wifiPopupOpen  ? "wifi"
             : clockPopupOpen     ? "clock"     : notifPopupOpen ? "notif" : ""
    }

    // Mutually-exclusive popups — close the others so sweeping across the
    // bar doesn't stack overlays.
    function showPopup(name) {
        if (name !== "sink")      { sinkHideTimer.stop();    sinkPopupOpen      = false }
        if (name !== "battery")   { batteryHideTimer.stop(); batteryPopupOpen   = false }
        if (name !== "bluetooth") { btHideTimer.stop();      bluetoothPopupOpen = false }
        if (name !== "wifi")      { wifiHideTimer.stop();    wifiPopupOpen      = false }
        if (name !== "clock")     { clockHideTimer.stop();   clockPopupOpen     = false }
        if (name !== "notif")     { notifHideTimer.stop();   notifPopupOpen     = false }
        if (name === "sink")      sinkPopupOpen      = true
        if (name === "battery")   batteryPopupOpen   = true
        if (name === "bluetooth") bluetoothPopupOpen = true
        if (name === "wifi")      wifiPopupOpen      = true
        if (name === "clock")     clockPopupOpen     = true
        if (name === "notif")     notifPopupOpen     = true
    }

    // Hide-timer control (shared between bar + overlays).
    function startHideTimer(name) {
        if (name === "sink")      sinkHideTimer.start()
        if (name === "battery")   batteryHideTimer.start()
        if (name === "bluetooth") btHideTimer.start()
        if (name === "wifi" && !NetworkService.wifiPasswordOpen) wifiHideTimer.start()
        if (name === "clock")     clockHideTimer.start()
        if (name === "notif")     notifHideTimer.start()
    }

    Timer { id: sinkHideTimer;    interval: 600; onTriggered: if (!root.held("sink"))      root.sinkPopupOpen      = false }
    Timer { id: batteryHideTimer; interval: 600; onTriggered: if (!root.held("battery"))   root.batteryPopupOpen   = false }
    Timer { id: btHideTimer;      interval: 600; onTriggered: if (!root.held("bluetooth")) root.bluetoothPopupOpen = false }
    Timer { id: wifiHideTimer;    interval: 600; onTriggered: if (!root.held("wifi"))      root.wifiPopupOpen      = false }
    Timer { id: clockHideTimer;   interval: 600; onTriggered: if (!root.held("clock"))     root.clockPopupOpen     = false }
    Timer { id: notifHideTimer;   interval: 600; onTriggered: if (!root.held("notif"))     root.notifPopupOpen     = false }
}
