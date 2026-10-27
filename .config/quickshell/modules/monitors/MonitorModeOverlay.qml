import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.appearance
import qs.common

// Presentation switcher (Win+P style): Extend / Mirror / External / Internal.
// ←/→ + Enter or click applies; Esc closes. `qs ipc call monitormode toggle`.
PanelWindow {
    id: overlay

    required property var theme
    // Shell-size scale of this window's monitor (unset monitors = 100%).
    readonly property real uiScale: AppearanceService.scaleFor(screen?.name ?? "")

    readonly property bool _open: MonitorService.monitorModeOpen
    // Unmapped once the close animation ends, releasing the keyboard grab.
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
        { id: "extend",   name: "Extend",        icon: "󰚖",   desc: "Span across all screens" },
        { id: "mirror",   name: "Mirror",        icon: "󰉌",   desc: "Duplicate onto external" },
        { id: "external", name: "External only", icon: "󰍹", desc: "Only the external screen" },
        { id: "internal", name: "Internal only", icon: "󰌢", desc: "Only the built-in screen" }
    ]

    property int selIndex: 0
    function _act(id) { MonitorService.setMonitorMode(id) }

    on_OpenChanged: {
        if (_open) {
            selIndex = 0
            Qt.callLater(() => keyScope.forceActiveFocus())
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: MonitorService.closeMonitorMode()
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
                MonitorService.closeMonitorMode(); e.accepted = true
            }
        }

        Item {
            id: cardWrap
            anchors.centerIn: parent
            width: card.width
            height: card.height
            opacity: 0
            // uiScale transform; composes with the card's pop.
            scale: overlay.uiScale

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: col.implicitWidth + 44
                height: col.implicitHeight + 40
                radius: 20
                color: overlay.theme.bg
                border.color: overlay.theme.sep
                border.width: 1
                transformOrigin: Item.Center
                // Shared open motion, from the centre.
                transform: PopAnim { id: pop; item: cardWrap; open: overlay._open; origin.x: card.width / 2; origin.y: card.height / 2 }

                MouseArea { anchors.fill: parent }

                Column {
                    id: col
                    anchors.centerIn: parent
                    spacing: 18

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Displays"
                        color: overlay.theme.fg
                        font.family: overlay.theme.ff
                        font.bold: true
                        font.pixelSize: overlay.theme.fs + 5
                    }

                    Row {
                        spacing: 14

                        Repeater {
                            model: overlay.options
                            delegate: Rectangle {
                                id: opt
                                required property var modelData
                                required property int index
                                readonly property bool highlighted: index === overlay.selIndex
                                width: 150; height: 150
                                radius: 16
                                color: highlighted ? overlay.theme.lift(overlay.theme.surface, 1.15) : overlay.theme.surface
                                border.color: highlighted ? overlay.theme.primary : overlay.theme.sep
                                border.width: highlighted ? 3 : 1

                                HoverHandler {
                                    id: optHover
                                    onHoveredChanged: if (hovered) overlay.selIndex = opt.index
                                }

                                Column {
                                    anchors.centerIn: parent
                                    anchors.margins: 8
                                    spacing: 10
                                    width: parent.width - 16

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: opt.modelData.icon
                                        color: highlighted ? overlay.theme.primary : overlay.theme.fg
                                        font.family: overlay.theme.ff
                                        font.pixelSize: 40
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: opt.modelData.name
                                        color: overlay.theme.fg
                                        font.family: overlay.theme.ff
                                        font.bold: true
                                        font.pixelSize: overlay.theme.fs
                                    }
                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: opt.modelData.desc
                                        color: overlay.theme.outline
                                        font.family: overlay.theme.ff
                                        font.pixelSize: overlay.theme.fs - 4
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
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
