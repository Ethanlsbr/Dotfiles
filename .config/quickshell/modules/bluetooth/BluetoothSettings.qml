import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.common.ui

// Settings pane: adapter toggles, linked (paired/bonded) devices and
// nearby devices from discovery.
Item {
    id: pane

    required property var theme

    readonly property var  adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: adapter?.enabled ?? false
    readonly property bool scanning: adapter?.discovering ?? false
    // A scan started here stops when the pane goes away (pane switch or
    // window close); BlueZ otherwise keeps discovering indefinitely.
    property bool _scanStarted: false
    Component.onDestruction: if (_scanStarted && adapter?.discovering) adapter.discovering = false

    // Nameless devices (name == bare MAC) are hidden — the air is full of
    // BLE beacons and randomised-MAC phones.
    function hasName(d) {
        const n = (d.name || "").trim()
        if (!n) return false
        return !/^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$/.test(n)
    }
    // "Linked" = paired or bonded (some headsets report paired:yes,
    // bonded:no).
    function isLinked(d) { return d.paired || d.bonded }

    readonly property var linkedDevices: {
        if (!btOn) return []
        return [...Bluetooth.devices.values]
            .filter(d => pane.isLinked(d))
            .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    }
    readonly property var otherDevices: {
        if (!btOn) return []
        return [...Bluetooth.devices.values]
            .filter(d => !pane.isLinked(d) && pane.hasName(d))
            .sort((a, b) => (b.paired - a.paired) || a.name.localeCompare(b.name))
    }

    // Device-type glyph from BlueZ's freedesktop icon name.
    function deviceIcon(d) {
        const i = (d.icon || "").toLowerCase()
        if (i.indexOf("audio") >= 0 || i.indexOf("headset") >= 0 || i.indexOf("headphone") >= 0) return ""
        if (i.indexOf("phone") >= 0)    return ""
        if (i.indexOf("keyboard") >= 0) return ""
        if (i.indexOf("mouse") >= 0)    return ""
        if (i.indexOf("computer") >= 0) return ""
        if (i.indexOf("gaming") >= 0 || i.indexOf("joystick") >= 0) return ""
        return ""
    }
    function statusText(d) {
        if (d.state === BluetoothDeviceState.Connecting)    return "Connecting…"
        if (d.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…"
        if (d.connected) return d.batteryAvailable
            ? "Connected  ·  " + Math.round(d.battery * 100) + "% battery"
            : "Connected"
        if (isLinked(d)) return d.trusted ? "Paired  ·  Trusted" : "Paired"
        return "Available"
    }
    function connectOrDisconnect(d) {
        if (d.connected) {
            d.connected = false
        } else if (isLinked(d)) {
            // Bonded — reconnect; keep trusted so BlueZ auto-reconnects on
            // power-on.
            d.trusted = true
            d.connected = true
        } else {
            // New device: pair() bonds (stores a link key; a bare Connect()
            // doesn't → reconnects fail). Needs BluetoothService's agent;
            // trust up front for auto-reconnect.
            d.pair()
            d.trusted = true
        }
    }

    // One device row with its actions.
    component DeviceRow: UiRow {
        id: devRow
        required property var modelData
        theme: pane.theme
        icon: pane.deviceIcon(modelData)
        iconColor: modelData.connected ? pane.theme.primary : pane.theme.txt2
        title: modelData.name
        subtitle: pane.statusText(modelData)
        highlighted: modelData.connected

        UiButton {
            theme: pane.theme
            kind: devRow.modelData.connected ? "secondary" : "primary"
            text: devRow.modelData.connected ? "Disconnect"
                : (pane.isLinked(devRow.modelData) ? "Connect" : "Pair")
            onClicked: pane.connectOrDisconnect(devRow.modelData)
        }
        UiButton {
            visible: pane.isLinked(devRow.modelData)
            theme: pane.theme
            // Trusted devices auto-reconnect without re-pairing.
            text: devRow.modelData.trusted ? "Untrust" : "Trust"
            onClicked: devRow.modelData.trusted = !devRow.modelData.trusted
        }
        UiButton {
            visible: pane.isLinked(devRow.modelData)
            theme: pane.theme
            kind: "danger"
            icon: ""
            onClicked: devRow.modelData.forget()
        }
    }

    // Centred placeholder line inside an empty group.
    component EmptyRow: Item {
        property string text: ""
        width: parent ? parent.width : 0
        implicitHeight: 56
        Text {
            anchors.centerIn: parent
            text: parent.text
            color: pane.theme.txt2
            font.family: pane.theme.ff
            font.pixelSize: pane.theme.fs - 2
        }
    }

    UiPage {
        anchors.fill: parent
        theme: pane.theme

        // ── Adapter ───────────────────────────────────────────────────────
        UiGroup {
            theme: pane.theme

            UiRow {
                theme: pane.theme
                icon: ""
                title: "Bluetooth"
                subtitle: !pane.adapter ? "No adapter found"
                        : pane.btOn ? "On" + (pane.adapter.discoverable ? "  ·  Discoverable as “" + (pane.adapter.name || "this device") + "”" : "")
                        : "Off"
                UiSwitch {
                    theme: pane.theme
                    checked: pane.btOn
                    onToggled: value => { if (pane.adapter) pane.adapter.enabled = value }
                }
            }
            UiRow {
                theme: pane.theme
                icon: ""
                title: "Discoverable"
                subtitle: "Let nearby devices find this computer"
                opacity: pane.btOn ? 1 : 0.5
                UiSwitch {
                    theme: pane.theme
                    enabled: pane.btOn
                    checked: pane.adapter?.discoverable ?? false
                    onToggled: value => { if (pane.adapter) pane.adapter.discoverable = value }
                }
            }
        }

        // ── Linked devices ────────────────────────────────────────────────
        UiGroup {
            theme: pane.theme
            title: "Your devices"

            Repeater {
                model: pane.linkedDevices
                delegate: DeviceRow {}
            }
            EmptyRow {
                visible: pane.linkedDevices.length === 0
                text: pane.btOn ? "No paired devices yet" : "Bluetooth is off"
            }
        }

        // ── Nearby devices ────────────────────────────────────────────────
        UiGroup {
            theme: pane.theme
            title: "Other devices"
            description: pane.scanning ? "Searching for nearby devices…" : ""
            actions: [
                UiButton {
                    theme: pane.theme
                    icon: ""
                    text: "Blueman"
                    onClicked: BluetoothService.launchBlueman()
                },
                UiButton {
                    theme: pane.theme
                    kind: pane.scanning ? "secondary" : "primary"
                    enabled: pane.btOn
                    icon: pane.scanning ? "" : ""
                    text: pane.scanning ? "Stop" : "Scan"
                    onClicked: {
                        if (!pane.adapter) return
                        pane._scanStarted = !pane.adapter.discovering
                        pane.adapter.discovering = pane._scanStarted
                    }
                }
            ]

            Repeater {
                model: pane.otherDevices
                delegate: DeviceRow {}
            }
            EmptyRow {
                visible: pane.otherDevices.length === 0
                text: !pane.btOn ? "Bluetooth is off"
                    : pane.scanning ? "Looking for devices…"
                    : "Press Scan to look for devices"
            }
        }
    }
}
