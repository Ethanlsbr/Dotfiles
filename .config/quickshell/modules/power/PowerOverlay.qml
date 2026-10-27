import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.appearance
import qs.common

// Power menu: Shutdown / Reboot / Lock (`qs ipc call power toggle`).
// ←/→ + Enter, S/R/L shortcuts, Esc closes. Runs PowerService.powerAction.
PanelWindow {
    id: overlay

    required property var theme
    // Shell-size scale of this window's monitor (unset monitors = 100%).
    readonly property real uiScale: AppearanceService.scaleFor(screen?.name ?? "")

    readonly property bool _open: PowerService.powerOpen
    // Unmapped once the close animation ends, releasing the keyboard grab
    // back to the prior window.
    visible: pop.shown
    // Stay mapped through the close animation, but input-transparent and
    // without the keyboard (focus handoff happens once it unmaps).
    mask: _open ? null : noInput
    Region { id: noInput }
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
    function _act(id) { PowerService.powerAction(id) }
    function _actByKey(k) {
        for (let i = 0; i < options.length; i++)
            if (options[i].key === k) { selIndex = i; _act(options[i].id); return true }
        return false
    }

    // Reopening lands on the first option without the outline gliding to it.
    property bool _snapHighlight: false
    on_OpenChanged: {
        if (_open) {
            _snapHighlight = true
            selIndex = 0
            Qt.callLater(() => _snapHighlight = false)
            Qt.callLater(() => keyScope.forceActiveFocus())
        }
    }

    // Click-anywhere closes.
    MouseArea {
        anchors.fill: parent
        onClicked: PowerService.closePower()
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
                PowerService.closePower(); e.accepted = true
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
            // uiScale transform; composes with the card's pop.
            scale: overlay.uiScale

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
                // Shared open motion, from the centre.
                transform: PopAnim { id: pop; item: card; open: overlay._open; origin.x: card.width / 2; origin.y: card.height / 2 }

                MouseArea { anchors.fill: parent }

                Column {
                    id: col
                    anchors.centerIn: parent
                    spacing: 20

                    Item {
                        width: optRow.implicitWidth
                        height: optRow.implicitHeight

                        Row {
                            id: optRow
                            spacing: 18

                            Repeater {
                                id: optRepeater
                                model: overlay.options
                                delegate: Rectangle {
                                    id: opt
                                    required property var modelData
                                    required property int index
                                    readonly property bool highlighted: index === overlay.selIndex
                                    width: 150; height: 160
                                    radius: 16
                                    color: highlighted ? overlay.theme.lift(overlay.theme.surface, 1.15) : overlay.theme.surface
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                    // The accent outline is the shared sliding one below.
                                    border.color: overlay.theme.sep
                                    border.width: 1

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
                                            color: overlay.theme.chip
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

                        // Selection outline: one rectangle that glides between
                        // options (drawn over the tiles; it takes no input).
                        Rectangle {
                            readonly property Item target: optRepeater.itemAt(overlay.selIndex)
                            x: target ? target.x : 0
                            width: 150; height: 160
                            radius: 16
                            color: "transparent"
                            border.color: overlay.theme.primary
                            border.width: 3
                            Behavior on x {
                                enabled: !overlay._snapHighlight
                                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }
            }
        }
    }
}
