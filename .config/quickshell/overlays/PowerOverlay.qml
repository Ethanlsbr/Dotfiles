import QtQuick
import Quickshell
import Quickshell.Wayland

// Power menu — Shutdown / Reboot / Lock. Standalone (launch via
// `qs ipc call power toggle`). ←/→ move the highlight, Enter activates,
// Esc closes; S/R/L are direct shortcuts. Shutdown & Reboot use systemctl,
// Lock uses hyprlock (see shellRoot.powerAction).
PanelWindow {
    id: overlay

    required property var shellRoot
    required property var theme

    readonly property bool _open: shellRoot.powerOpen
    // Destroy on close to release the keyboard grab back to the prior window.
    visible: _open
    WlrLayershell.keyboardFocus: _open ? WlrKeyboardFocus.Exclusive
                                       : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }
    exclusiveZone: 0
    color: "transparent"

    readonly property var options: [
        { id: "shutdown", name: "Shutdown", key: "S", icon: "",    accent: overlay.theme.error },
        { id: "reboot",   name: "Reboot",   key: "R", icon: "󰜉", accent: overlay.theme.warn },
        { id: "suspend", name: "Suspend", key: "H", icon: "󰤄", accent: overlay.theme.secondary },
        { id: "lock",     name: "Lock",     key: "L", icon: "",   accent: overlay.theme.primary }
    ]

    property int selIndex: 0
    function _act(id) { shellRoot.powerAction(id) }
    function _actByKey(k) {
        for (let i = 0; i < options.length; i++)
            if (options[i].key === k) { selIndex = i; _act(options[i].id); return true }
        return false
    }

    on_OpenChanged: {
        if (_open) {
            selIndex = 0
            enterAnim.restart()
            Qt.callLater(() => keyScope.forceActiveFocus())
        }
    }

    // Appear: a featureless square spins one full turn, then the app card
    // emerges from it (square fades/grows out as the card fades + pops in).
    SequentialAnimation {
        id: enterAnim
        PropertyAction { target: card;    property: "opacity"; value: 0 }
        PropertyAction { target: card;    property: "scale";   value: 0.4 }
        PropertyAction { target: spinner; property: "scale";   value: 1 }
        // Phase 1 — the square spins in.
        ParallelAnimation {
            NumberAnimation { target: spinner; property: "opacity";  from: 0;    to: 1; duration: 150; easing.type: Easing.OutCubic }
            NumberAnimation { target: spinner; property: "rotation"; from: -360; to: 0; duration: 480; easing.type: Easing.OutCubic }
        }
        // Phase 2 — the square becomes the app.
        ParallelAnimation {
            NumberAnimation { target: spinner; property: "opacity"; to: 0;   duration: 200; easing.type: Easing.InCubic }
            NumberAnimation { target: spinner; property: "scale";   to: 1.6; duration: 240; easing.type: Easing.OutCubic }
            NumberAnimation { target: card;    property: "opacity"; to: 1;   duration: 240; easing.type: Easing.OutCubic }
            NumberAnimation { target: card;    property: "scale"; from: 0.4; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
        }
    }

    // Click-anywhere backdrop closes.
    MouseArea {
        anchors.fill: parent
        onClicked: overlay.shellRoot.closePower()
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: true

        Keys.onPressed: e => {
            if (e.key === Qt.Key_Left) {
                overlay.selIndex = (overlay.selIndex - 1 + overlay.options.length) % overlay.options.length
                e.accepted = true
            } else if (e.key === Qt.Key_Right) {
                overlay.selIndex = (overlay.selIndex + 1) % overlay.options.length
                e.accepted = true
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                overlay._act(overlay.options[overlay.selIndex].id); e.accepted = true
            } else if (e.key === Qt.Key_Escape) {
                overlay.shellRoot.closePower(); e.accepted = true
            } else if (e.key === Qt.Key_S) { overlay._actByKey("S"); e.accepted = true }
            else if   (e.key === Qt.Key_R) { overlay._actByKey("R"); e.accepted = true }
            else if   (e.key === Qt.Key_H) { overlay._actByKey("H"); e.accepted = true }
            else if   (e.key === Qt.Key_L) { overlay._actByKey("L"); e.accepted = true }
        }

        Item {
            id: cardWrap
            anchors.centerIn: parent
            width: card.width
            height: card.height

            // Featureless square shown during the spin phase; it fades/grows
            // away as the card emerges (see enterAnim).
            Rectangle {
                id: spinner
                anchors.centerIn: parent
                width: 76; height: 76
                radius: 16
                color: overlay.theme.surface
                border.color: overlay.theme.primary
                border.width: 2
                opacity: 0
                transformOrigin: Item.Center
            }

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: col.implicitWidth + 48
                height: col.implicitHeight + 44
                radius: 20
                color: overlay.theme.bg
                border.color: overlay.theme.sep
                border.width: 1
                opacity: 0
                transformOrigin: Item.Center

                MouseArea { anchors.fill: parent }

                Column {
                    id: col
                    anchors.centerIn: parent
                    spacing: 20

                    Row {
                        spacing: 18

                        Repeater {
                            model: overlay.options
                            delegate: Rectangle {
                                id: opt
                                required property var modelData
                                required property int index
                                readonly property bool highlighted: index === overlay.selIndex
                                width: 150; height: 160
                                radius: 16
                                color: highlighted ? Qt.lighter(overlay.theme.surface, 1.15) : overlay.theme.surface
                                border.color: highlighted ? opt.modelData.accent : overlay.theme.sep
                                border.width: highlighted ? 3 : 1

                                HoverHandler {
                                    id: optHover
                                    onHoveredChanged: if (hovered) overlay.selIndex = opt.index
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 14

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: opt.modelData.icon
                                        color: opt.modelData.accent
                                        font.family: overlay.theme.ff
                                        font.pixelSize: 46
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: opt.modelData.name
                                        color: overlay.theme.fg
                                        font.family: overlay.theme.ff
                                        font.bold: true
                                        font.pixelSize: overlay.theme.fs
                                    }
                                    // Key-shortcut hint.
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 22; height: 22; radius: 6
                                        color: Qt.darker(overlay.theme.bg, 1.2)
                                        border.color: overlay.theme.sep
                                        border.width: 1
                                        Text {
                                            anchors.centerIn: parent
                                            text: opt.modelData.key
                                            color: overlay.theme.txt2
                                            font.family: overlay.theme.ff
                                            font.bold: true
                                            font.pixelSize: overlay.theme.fs - 4
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: overlay._act(opt.modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
