import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.common
import qs.common.ui
import qs.modules.settings

// Bar popup page: Bluetooth toggle + nearby/paired devices (hover the BT
// module). Clicking a device connects / disconnects it.
Item {
    id: popup

    required property var theme
    implicitHeight: col.implicitHeight + 24

    readonly property var  adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: adapter?.enabled ?? false
    readonly property var  devices: {
        if (!btOn) return []
        // Hide nameless BLE devices that show up as a bare MAC.
        const named = n => {
            const s = (n || "").trim()
            return s && !/^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$/.test(s)
        }
        return [...Bluetooth.devices.values]
            .filter(d => d.connected || d.paired || named(d.name))
            .sort((a, b) => (b.connected - a.connected)
                          || (b.paired - a.paired)
                          || a.name.localeCompare(b.name))
            .slice(0, 5)
    }
    readonly property int connectedCount: devices.filter(d => d.connected).length

    function deviceIcon(d) {
        const i = (d.icon || "").toLowerCase()
        if (i.indexOf("audio") >= 0 || i.indexOf("headset") >= 0 || i.indexOf("headphone") >= 0) return ""
        if (i.indexOf("phone") >= 0)    return ""
        if (i.indexOf("keyboard") >= 0) return ""
        if (i.indexOf("mouse") >= 0)    return ""
        if (i.indexOf("computer") >= 0) return ""
        return ""
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 10

        // ── Header ───────────────────────────────────────────────
        UiRow {
            theme: popup.theme
            compact: true
            showDivider: false
            icon: ""
            title: "Bluetooth"
            subtitle: !popup.btOn ? "Off"
                    : popup.connectedCount > 0 ? popup.connectedCount + " connected" : "On"
            UiSwitch {
                anchors.verticalCenter: parent.verticalCenter
                theme: popup.theme
                checked: popup.btOn
                onToggled: value => { if (popup.adapter) popup.adapter.enabled = value }
            }
            GearButton {
                theme: popup.theme
                onClicked: {
                    PopupService.bluetoothPopupOpen = false
                    SettingsService.openSettings("bluetooth")
                }
            }
        }

        // ── Devices ──────────────────────────────────────────────
        UiCard {
            theme: popup.theme
            height: devCol.implicitHeight
            Column {
                id: devCol
                width: parent.width

                Repeater {
                    model: popup.devices
                    delegate: UiRow {
                        required property var modelData
                        theme: popup.theme
                        compact: true
                        clickable: true
                        highlighted: modelData.connected
                        icon: popup.deviceIcon(modelData)
                        iconColor: modelData.connected ? popup.theme.primary : popup.theme.txt2
                        title: modelData.name
                        subtitle: modelData.state === BluetoothDeviceState.Connecting ? "Connecting…"
                                : modelData.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                                : modelData.connected
                                  ? (modelData.batteryAvailable ? "Connected  ·  " + Math.round(modelData.battery * 100) + "%" : "Connected")
                                : (modelData.paired || modelData.bonded) ? "Paired" : "Available"
                        onClicked: {
                            if (modelData.connected) {
                                modelData.connected = false
                            } else if (modelData.paired || modelData.bonded) {
                                // Bonded — reconnect; keep trusted so BlueZ
                                // auto-reconnects on power-on.
                                modelData.trusted = true
                                modelData.connected = true
                            } else {
                                // New device: pair() (a bare Connect() stores
                                // no link key → reconnects fail). Needs
                                // BluetoothService's agent; trust for
                                // auto-reconnect.
                                modelData.pair()
                                modelData.trusted = true
                            }
                        }
                    }
                }
                Item {
                    visible: popup.devices.length === 0
                    width: parent.width
                    implicitHeight: 48
                    Text {
                        anchors.centerIn: parent
                        text: popup.btOn ? "No devices nearby" : "Bluetooth is off"
                        color: popup.theme.txt2
                        font.family: popup.theme.ff; font.pixelSize: popup.theme.fs - 2
                    }
                }
            }
        }
    }
}
