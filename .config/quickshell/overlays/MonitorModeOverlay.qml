import QtQuick
import Quickshell
import Quickshell.Wayland

// Monitor presentation switcher (like Windows' Win+P). Extend / Mirror /
// External only / Internal only. ←/→ move, Enter applies, Esc closes; clicking
// also applies. Launch with `qs ipc call monitormode toggle`.
PanelWindow {
    id: overlay

    required property var shellRoot
    required property var theme

    readonly property bool _open: shellRoot.monitorModeOpen
    visible: _open
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
    function _act(id) { shellRoot.setMonitorMode(id) }

    on_OpenChanged: {
        if (_open) {
            selIndex = 0
            enterAnim.restart()
            Qt.callLater(() => keyScope.forceActiveFocus())
        }
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: cardWrap; property: "opacity"; from: 0;    to: 1; duration: 280; easing.type: Easing.OutCubic }
        NumberAnimation { target: card;     property: "scale";   from: 0.94; to: 1; duration: 280; easing.type: Easing.OutCubic }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: overlay.shellRoot.closeMonitorMode()
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
                overlay.shellRoot.closeMonitorMode(); e.accepted = true
            }
        }

        Item {
            id: cardWrap
            anchors.centerIn: parent
            width: card.width
            height: card.height
            opacity: 0

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
                                color: highlighted ? Qt.lighter(overlay.theme.surface, 1.15) : overlay.theme.surface
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
