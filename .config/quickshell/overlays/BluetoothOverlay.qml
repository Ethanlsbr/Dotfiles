import QtQuick
import Quickshell
import Quickshell.Bluetooth

PanelWindow {
    id: overlay

    required property var  shellRoot
    required property var  theme
    required property real anchorWidth

    readonly property bool _open: shellRoot.bluetoothPopupOpen

    visible: _open || exitAnim.running

    on_OpenChanged: {

        if (_open) { exitAnim.stop(); enterAnim.restart() }

        else       { enterAnim.stop(); exitAnim.restart() }

    }

    anchors { top: true; right: true }
    margins.right: 10
    margins.top:   6      // sit just below the bar (bar exclusiveZone is 34)
    exclusiveZone: 0
    color: "transparent"

    implicitWidth:  Math.max(anchorWidth, 320)
    implicitHeight: col.implicitHeight + 20

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: card;      property: "opacity"; from: 0; to: 1; duration: 360; easing.type: Easing.OutCubic }
        NumberAnimation { target: card;      property: "scale"; from: 0.96; to: 1; duration: 360; easing.type: Easing.OutCubic }
    }
    // Reverse of enterAnim — plays before the panel is hidden so it slides
    // back out instead of snapping away. `visible` stays true while running.
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: card;      property: "opacity"; to: 0;   duration: 280; easing.type: Easing.InCubic }
        NumberAnimation { target: card;      property: "scale"; to: 0.96; duration: 280; easing.type: Easing.InCubic }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        color: overlay.theme.bg
        radius: overlay.theme.pr
        opacity: 0
        scale: 0.96
        transformOrigin: Item.Top

        HoverHandler {
            onHoveredChanged: hovered ? overlay.shellRoot.stopHideTimer("bluetooth")
                                      : overlay.shellRoot.startHideTimer("bluetooth")
        }

        Column {
            id: col
            anchors { fill: parent; margins: 12 }
            spacing: 8

            // ── Enable toggle ────────────────────────────────────────
            Rectangle {
                width: col.width
                height: 32
                radius: 8
                color: overlay.theme.hi(1.3)

                Row {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Bluetooth"
                        color: overlay.theme.fg
                        font.family: overlay.theme.ff; font.bold: true; font.pixelSize: overlay.theme.fs - 1
                        width: parent.width - btToggle.width - 8
                    }

                    Rectangle {
                        id: btToggle
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42; height: 22
                        radius: 11
                        color: Bluetooth.defaultAdapter?.enabled
                               ? overlay.theme.tertiary : Qt.darker(overlay.theme.bg, 1.4)

                        Rectangle {
                            width: 16; height: 16; radius: 8
                            color: overlay.theme.fg
                            anchors.verticalCenter: parent.verticalCenter
                            x: Bluetooth.defaultAdapter?.enabled ? parent.width - width - 3 : 3
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const a = Bluetooth.defaultAdapter
                                if (a) a.enabled = !a.enabled
                            }
                        }
                    }
                }
            }

            // ── Device list ──────────────────────────────────────────
            Text {
                visible: Bluetooth.defaultAdapter?.enabled ?? false
                text: {
                    const devs = Bluetooth.devices.values
                    const conn = devs.filter(d => d.connected).length
                    return devs.length + " device" + (devs.length === 1 ? "" : "s")
                           + (conn > 0 ? "  •  " + conn + " connected" : "")
                }
                color: overlay.theme.fg
                font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 2
                opacity: 0.7
            }

            Repeater {
                model: {
                    if (!Bluetooth.defaultAdapter?.enabled) return []
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
                delegate: Rectangle {
                    required property var modelData
                    width: col.width
                    height: 30
                    radius: 7
                    color: rowHover.hovered
                            ? overlay.theme.hi(1.2)
                            : (modelData.connected ? overlay.theme.hi(1.4) : "transparent")

                    HoverHandler { id: rowHover }

                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.connected ? "" : ""
                            color: modelData.connected ? "#89DCEB" : overlay.theme.fg
                            font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 1
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            color: overlay.theme.fg
                            font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 1
                            elide: Text.ElideRight
                            width: col.width - 60
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.connected) {
                                modelData.connected = false
                            } else if (modelData.paired || modelData.bonded) {
                                // Already bonded — reconnect, keep trusted so
                                // BlueZ auto-reconnects on power-on.
                                modelData.trusted = true
                                modelData.connected = true
                            } else {
                                // New device: bond it with Quickshell's native
                                // pair() (a bare Connect() never stores a link key,
                                // so reconnects fail with "br-connection-key-
                                // missing"). pair() needs an agent alive — shell.qml
                                // keeps a session-long bluetoothctl agent for this.
                                // Trust up front so BlueZ auto-reconnects later.
                                modelData.pair()
                                modelData.trusted = true
                            }
                        }
                    }
                }
            }

            // ── Open settings pill ────────────────────────────────────
            Rectangle {
                width: col.width
                height: 32
                radius: 9
                color: settingsBtnHover.hovered
                        ? overlay.theme.hi(1.6)
                        : overlay.theme.hi(1.3)

                HoverHandler { id: settingsBtnHover }

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: ""; color: overlay.theme.fg; font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs }
                    Text { text: "Open settings"; color: overlay.theme.fg; font.family: overlay.theme.ff; font.bold: true; font.pixelSize: overlay.theme.fs - 1 }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        overlay.shellRoot.bluetoothPopupOpen = false
                        overlay.shellRoot.openSettings("bluetooth")
                    }
                }
            }
        }
    }
}
