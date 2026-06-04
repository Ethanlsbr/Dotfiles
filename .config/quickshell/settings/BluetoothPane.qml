import QtQuick
import Quickshell
import Quickshell.Bluetooth

Item {
    id: pane

    required property var theme
    required property var shellRoot

    Flickable {
        anchors.fill: parent
        contentHeight: btCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
        id: btCol
        width: parent.width
        spacing: 16

        // ── Adapter toggles row ──────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 90
            radius: 12
            color: Qt.darker(pane.theme.bg, 1.2)
            border.color: pane.theme.sep
            border.width: 1

            Column {
                anchors { fill: parent; margins: 12 }
                spacing: 10

                ToggleRow { label: "Enabled";     value: Bluetooth.defaultAdapter?.enabled ?? false
                            onToggled: { const a = Bluetooth.defaultAdapter; if (a) a.enabled = !a.enabled } }

                ToggleRow { label: "Discoverable"; value: Bluetooth.defaultAdapter?.discoverable ?? false
                            enabled: Bluetooth.defaultAdapter?.enabled ?? false
                            onToggled: { const a = Bluetooth.defaultAdapter; if (a) a.discoverable = !a.discoverable } }
            }
        }

        // ── Linked devices section (bonded) ──────────────────────────────
        Text {
            text: "Linked devices (" + pane.linkedDevices.length + ")"
            color: pane.theme.fg
            font.family: pane.theme.ff
            font.bold: true
            font.pixelSize: pane.theme.fs + 1
        }

        DeviceListCard {
            width: parent.width
            devices: pane.linkedDevices
            emptyText: "No linked devices yet"
        }

        // ── Other devices header + blueman / Scan ────────────────────────
        Row {
            width: parent.width
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Other devices (" + pane.otherDevices.length + ")"
                color: pane.theme.fg
                font.family: pane.theme.ff
                font.bold: true
                font.pixelSize: pane.theme.fs + 1
                width: parent.width - scanBtn.width - bluemanBtn.width - 16
            }

            // Launch blueman-manager
            Rectangle {
                id: bluemanBtn
                anchors.verticalCenter: parent.verticalCenter
                width: 150; height: 28
                radius: 8
                color: bluemanHover.hovered
                       ? Qt.lighter(pane.theme.active, 1.4)
                       : Qt.darker(pane.theme.bg, 1.2)
                border.color: pane.theme.sep
                border.width: 1

                HoverHandler { id: bluemanHover }

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ""
                        color: pane.theme.fg
                        font.family: pane.theme.ff
                        font.pixelSize: pane.theme.fs - 1
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Open in blueman"
                        color: pane.theme.fg
                        font.family: pane.theme.ff
                        font.pixelSize: pane.theme.fs - 1
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pane.shellRoot.launchBlueman()
                }
            }

            // Scan toggle
            Rectangle {
                id: scanBtn
                anchors.verticalCenter: parent.verticalCenter
                width: 90; height: 28
                radius: 8
                color: (Bluetooth.defaultAdapter?.discovering ?? false)
                       ? Qt.lighter(pane.theme.active, 1.6)
                       : Qt.darker(pane.theme.bg, 1.2)
                border.color: pane.theme.sep
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: (Bluetooth.defaultAdapter?.discovering ?? false) ? "Scanning…" : "Scan"
                    color: pane.theme.fg
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 1
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const a = Bluetooth.defaultAdapter
                        if (a) a.discovering = !a.discovering
                    }
                }
            }
        }

        DeviceListCard {
            width: parent.width
            devices: pane.otherDevices
            emptyText: (Bluetooth.defaultAdapter?.discovering ?? false)
                       ? "Scanning for nearby devices…"
                       : "Press Scan to look for devices"
        }
        }
    }

    // A device with no advertised name shows up as its bare MAC address
    // (e.g. "56-67-96-F7-36-84"). The air is full of these BLE beacons /
    // phones with randomised MACs, so we hide nameless devices from the
    // scan list to keep it to things you can actually identify.
    function hasName(d) {
        const n = (d.name || "").trim()
        if (!n) return false
        // name === address, formatted with ':' or '-' separators
        return !/^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$/.test(n)
    }

    // ── Sorted device slices ─────────────────────────────────────────────
    // A device counts as "linked" once it's paired or bonded — some headsets
    // report paired:yes / bonded:no, so keying off bonded alone drops them.
    function isLinked(d) { return d.paired || d.bonded }

    readonly property var linkedDevices: {
        if (!Bluetooth.defaultAdapter?.enabled) return []
        return [...Bluetooth.devices.values]
            .filter(d => pane.isLinked(d))
            .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    }
    readonly property var otherDevices: {
        if (!Bluetooth.defaultAdapter?.enabled) return []
        return [...Bluetooth.devices.values]
            .filter(d => !pane.isLinked(d) && pane.hasName(d))
            .sort((a, b) => (b.paired - a.paired) || a.name.localeCompare(b.name))
    }

    // ── Reusable device list card ────────────────────────────────────────
    component DeviceListCard: Rectangle {
        id: card
        required property var    devices
        required property string emptyText

        // Hug the device rows when there are any; only fall back to the 60px
        // floor for the centred empty/disabled message (otherwise a single
        // device leaves dead space at the bottom of the card).
        height: (card.devices.length > 0 && (Bluetooth.defaultAdapter?.enabled ?? false))
                ? devCol.implicitHeight + 12
                : 60
        color: Qt.darker(pane.theme.bg, 1.2)
        radius: 12
        border.color: pane.theme.sep
        border.width: 1

        Text {
            visible: !(Bluetooth.defaultAdapter?.enabled ?? false)
            anchors.centerIn: parent
            text: "Bluetooth is disabled"
            color: pane.theme.fg
            opacity: 0.6
            font.family: pane.theme.ff
            font.pixelSize: pane.theme.fs
        }

        Text {
            visible: (Bluetooth.defaultAdapter?.enabled ?? false) && card.devices.length === 0
            anchors.centerIn: parent
            text: card.emptyText
            color: pane.theme.fg
            opacity: 0.5
            font.family: pane.theme.ff
            font.pixelSize: pane.theme.fs - 1
        }

        Column {
            id: devCol
            visible: Bluetooth.defaultAdapter?.enabled ?? false
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 2

            Repeater {
                model: card.devices
                delegate: Rectangle {
                    required property var modelData
                    width:  devCol.width
                    height: 38
                    radius: 8
                    color: rowHover.hovered
                            ? Qt.lighter(pane.theme.active, 1.2)
                            : (modelData.connected ? Qt.lighter(pane.theme.active, 1.4) : "transparent")

                    HoverHandler { id: rowHover }

                    Row {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 10

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.connected ? "" : ""
                            color: modelData.connected ? "#89DCEB" : pane.theme.fg
                            font.family: pane.theme.ff
                            font.pixelSize: pane.theme.fs
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                text: modelData.name
                                color: pane.theme.fg
                                font.family: pane.theme.ff
                                font.bold: true
                                font.pixelSize: pane.theme.fs
                                elide: Text.ElideRight
                                width: devCol.width - 260
                            }
                            Text {
                                text: {
                                    if (modelData.state === BluetoothDeviceState.Connecting)    return "Connecting…"
                                    if (modelData.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…"
                                    if (modelData.connected) return modelData.batteryAvailable
                                        ? "Connected  •  " + Math.round(modelData.battery * 100) + "%"
                                        : "Connected"
                                    if (modelData.paired) return "Paired"
                                    return "Available"
                                }
                                color: pane.theme.fg
                                opacity: 0.6
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs - 2
                            }
                        }
                    }

                    Row {
                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 6

                        Rectangle {
                            width: 70; height: 26
                            radius: 7
                            color: connBtnHover.hovered
                                    ? Qt.lighter(pane.theme.active, 1.6)
                                    : Qt.lighter(pane.theme.active, 1.3)
                            HoverHandler { id: connBtnHover }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.connected ? "Disconnect" : "Connect"
                                color: pane.theme.fg
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs - 2
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                // Trust on connect so BlueZ auto-reconnects when
                                // the device powers back on, instead of forcing a
                                // fresh pairing each time.
                                onClicked: {
                                    if (modelData.connected) {
                                        modelData.connected = false
                                    } else {
                                        modelData.trusted = true
                                        modelData.connected = true
                                    }
                                }
                            }
                        }

                        // Trust toggle — a trusted device is auto-reconnected by
                        // BlueZ when it powers back on, without re-pairing.
                        Rectangle {
                            visible: pane.isLinked(modelData)
                            width: 80; height: 26
                            radius: 7
                            color: modelData.trusted
                                    ? (trustBtnHover.hovered ? Qt.lighter(pane.theme.active, 1.6) : Qt.lighter(pane.theme.active, 1.3))
                                    : (trustBtnHover.hovered ? Qt.lighter(pane.theme.bg, 1.3) : Qt.darker(pane.theme.bg, 1.2))
                            border.color: pane.theme.sep
                            border.width: modelData.trusted ? 0 : 1
                            HoverHandler { id: trustBtnHover }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.trusted ? "Untrust" : "Trust"
                                color: pane.theme.fg
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs - 2
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelData.trusted = !modelData.trusted
                            }
                        }

                        Rectangle {
                            visible: pane.isLinked(modelData)
                            width: 70; height: 26
                            radius: 7
                            color: forgetBtnHover.hovered ? "#F38BA8" : Qt.darker(pane.theme.bg, 1.2)
                            border.color: pane.theme.sep
                            border.width: 1
                            HoverHandler { id: forgetBtnHover }
                            Text {
                                anchors.centerIn: parent
                                text: "Forget"
                                color: pane.theme.fg
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs - 2
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelData.forget()
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Inline reusable toggle row ───────────────────────────────────────
    component ToggleRow: Row {
        required property string label
        required property bool   value
        property bool enabled: true
        signal toggled()

        width: parent.width
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: pane.theme.fg
            opacity: parent.enabled ? 1 : 0.5
            font.family: pane.theme.ff
            font.bold: true
            font.pixelSize: pane.theme.fs
            width: parent.width - 50
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 42; height: 22
            radius: 11
            opacity: parent.enabled ? 1 : 0.5
            color: parent.value ? "#A6E3A1" : Qt.darker(pane.theme.bg, 1.4)

            Rectangle {
                width: 16; height: 16; radius: 8
                color: pane.theme.fg
                anchors.verticalCenter: parent.verticalCenter
                x: parent.parent.value ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: 120 } }
            }

            MouseArea {
                anchors.fill: parent
                enabled: parent.parent.enabled
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.parent.toggled()
            }
        }
    }
}
