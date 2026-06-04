import QtQuick
import Quickshell
import Quickshell.Wayland

// Theme picker — opened from the launcher (> Theme). ←/→ move the highlight,
// Enter applies, Esc / click-outside closes; clicking a card applies it too.
// The chosen theme recolours the whole shell and is persisted (theme.txt).
PanelWindow {
    id: overlay

    required property var shellRoot
    required property var theme

    readonly property bool _open: shellRoot.themeOpen
    // Destroy immediately on close so the Wayland keyboard grab is released
    // back to the previously-focused window (see the other keyboard overlays).
    visible: _open
    WlrLayershell.keyboardFocus: _open ? WlrKeyboardFocus.Exclusive
                                       : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }
    exclusiveZone: 0
    color: "transparent"

    // Preview palettes (key roles only) — mirror the definitions in shell.qml.
    readonly property var palettes: [
        { id: "dark",  name: "Default",
          bg: "#1E1E2E", fg: "#f1dfda", surface: "#313244",
          primary: "#89B4FA", secondary: "#F5C2E7", tertiary: "#A6E3A1" },
        { id: "light", name: "Light",
          bg: "#EFF1F5", fg: "#4C4F69", surface: "#E6E9EF",
          primary: "#1E66F5", secondary: "#EA76CB", tertiary: "#40A02B" }
    ]

    // Keyboard-highlighted option.
    property int selIndex: 0
    function _curIndex() {
        for (let i = 0; i < palettes.length; i++)
            if (palettes[i].id === shellRoot.themeName) return i
        return 0
    }
    function _apply(i) {
        shellRoot.setTheme(palettes[i].id)
        shellRoot.closeTheme()
    }

    on_OpenChanged: {
        if (_open) {
            selIndex = _curIndex()
            enterAnim.restart()
            Qt.callLater(() => keyScope.forceActiveFocus())
        }
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: cardWrap; property: "opacity"; from: 0;    to: 1; duration: 300; easing.type: Easing.OutCubic }
        NumberAnimation { target: card;     property: "scale";   from: 0.94; to: 1; duration: 300; easing.type: Easing.OutCubic }
    }

    // Click-anywhere backdrop closes.
    MouseArea {
        anchors.fill: parent
        onClicked: overlay.shellRoot.closeTheme()
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: true

        Keys.onPressed: e => {
            if (e.key === Qt.Key_Left) {
                overlay.selIndex = (overlay.selIndex - 1 + overlay.palettes.length) % overlay.palettes.length
                e.accepted = true
            } else if (e.key === Qt.Key_Right) {
                overlay.selIndex = (overlay.selIndex + 1) % overlay.palettes.length
                e.accepted = true
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                overlay._apply(overlay.selIndex); e.accepted = true
            } else if (e.key === Qt.Key_Escape) {
                overlay.shellRoot.closeTheme(); e.accepted = true
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
                width: col.implicitWidth + 40
                height: col.implicitHeight + 40
                radius: 18
                color: overlay.theme.bg
                border.color: overlay.theme.sep
                border.width: 1
                transformOrigin: Item.Center

                // Swallow clicks so they don't fall through to the backdrop.
                MouseArea { anchors.fill: parent }

                Column {
                    id: col
                    anchors.centerIn: parent
                    spacing: 16

                    Text {
                        text: "Theme"
                        color: overlay.theme.fg
                        font.family: overlay.theme.ff
                        font.bold: true
                        font.pixelSize: overlay.theme.fs + 6
                    }

                    Row {
                        spacing: 16

                        Repeater {
                            model: overlay.palettes
                            delegate: Rectangle {
                                id: opt
                                required property var modelData
                                required property int index
                                readonly property bool applied:     modelData.id === overlay.shellRoot.themeName
                                readonly property bool highlighted: index === overlay.selIndex
                                width: 200; height: 150
                                radius: 14
                                color: (highlighted || optHover.hovered)
                                       ? Qt.lighter(overlay.theme.surface, 1.15) : overlay.theme.surface
                                border.color: highlighted ? overlay.theme.primary : overlay.theme.sep
                                border.width: highlighted ? 3 : 1

                                HoverHandler {
                                    id: optHover
                                    onHoveredChanged: if (hovered) overlay.selIndex = opt.index
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 10

                                    // Mini mockup of the palette.
                                    Rectangle {
                                        width: 168; height: 84
                                        radius: 10
                                        color: opt.modelData.bg
                                        border.color: Qt.rgba(0, 0, 0, 0.15)
                                        border.width: 1

                                        Rectangle {
                                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                            height: 16; radius: 6
                                            color: opt.modelData.surface
                                            Row {
                                                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                                spacing: 5
                                                Rectangle { width: 8; height: 8; radius: 4; color: opt.modelData.primary }
                                                Rectangle { width: 8; height: 8; radius: 4; color: opt.modelData.secondary }
                                                Rectangle { width: 8; height: 8; radius: 4; color: opt.modelData.tertiary }
                                            }
                                        }
                                        Column {
                                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
                                            spacing: 5
                                            Rectangle { width: 110; height: 7; radius: 3; color: opt.modelData.fg; opacity: 0.9 }
                                            Rectangle { width: 70;  height: 7; radius: 3; color: opt.modelData.fg; opacity: 0.45 }
                                        }
                                    }

                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: 8
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: opt.applied
                                            text: "\uf00c"   // check
                                            color: overlay.theme.primary
                                            font.family: overlay.theme.ff
                                            font.pixelSize: overlay.theme.fs
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: opt.modelData.name
                                            color: overlay.theme.fg
                                            font.family: overlay.theme.ff
                                            font.bold: true
                                            font.pixelSize: overlay.theme.fs
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: overlay._apply(opt.index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
