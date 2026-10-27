import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common

// Theme picker (launcher > Theme). ←/→ + Enter or click applies; Esc /
// click-outside closes. Persisted to theme.txt.
PanelWindow {
    id: overlay

    required property var theme
    // Shell-size scale of this window's monitor (unset monitors = 100%).
    readonly property real uiScale: AppearanceService.scaleFor(screen?.name ?? "")

    readonly property bool _open: AppearanceService.themeOpen
    // Unmapped once the close animation ends, releasing the keyboard grab
    // (see other overlays).
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

    // Preview palettes (key roles only) — canonical list in AppearanceService.
    readonly property var palettes: AppearanceService.themePalettes
    // Picker grid width, shared by the Grid and arrow-key navigation.
    readonly property int cols: 4

    // Keyboard-highlighted option.
    property int selIndex: 0
    function _curIndex() {
        for (let i = 0; i < palettes.length; i++)
            if (palettes[i].id === AppearanceService.themeName) return i
        return 0
    }
    // Up/Down within the grid's columns. Down from a cell with nothing below
    // goes to the last theme; from the bottom row it wraps to the top. Up
    // wraps from the top row to the bottom of the same column.
    function _down(i) {
        const n = palettes.length
        if (i + cols < n) return i + cols
        const lastRow = Math.floor((n - 1) / cols)
        return Math.floor(i / cols) === lastRow ? i % cols : n - 1
    }
    function _up(i) {
        if (i - cols >= 0) return i - cols
        let j = i
        while (j + cols < palettes.length) j += cols
        return j
    }
    function _apply(i) {
        AppearanceService.setTheme(palettes[i].id)
        AppearanceService.closeTheme()
    }

    // Opening lands on the current theme without the outline gliding to it.
    property bool _snapHighlight: false
    on_OpenChanged: {
        if (_open) {
            _snapHighlight = true
            selIndex = _curIndex()
            Qt.callLater(() => _snapHighlight = false)
            Qt.callLater(() => keyScope.forceActiveFocus())
        }
    }

    // Click-anywhere closes.
    MouseArea {
        anchors.fill: parent
        onClicked: AppearanceService.closeTheme()
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
            } else if (e.key === Qt.Key_Down) {
                overlay.selIndex = overlay._down(overlay.selIndex)
                e.accepted = true
            } else if (e.key === Qt.Key_Up) {
                overlay.selIndex = overlay._up(overlay.selIndex)
                e.accepted = true
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                overlay._apply(overlay.selIndex); e.accepted = true
            } else if (e.key === Qt.Key_Escape) {
                AppearanceService.closeTheme(); e.accepted = true
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
                width: col.implicitWidth + 40
                height: col.implicitHeight + 40
                radius: 18
                color: overlay.theme.bg
                border.color: overlay.theme.sep
                border.width: 1
                transformOrigin: Item.Center
                // Shared open motion, from the centre.
                transform: PopAnim { id: pop; item: cardWrap; open: overlay._open; origin.x: card.width / 2; origin.y: card.height / 2 }

                // Swallow clicks — don't trigger backdrop close.
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

                    Item {
                        width: optGrid.implicitWidth
                        height: optGrid.implicitHeight

                        Grid {
                            id: optGrid
                            columns: overlay.cols
                            spacing: 16

                            Repeater {
                                id: optRepeater
                                model: overlay.palettes
                                delegate: Rectangle {
                                    id: opt
                                    required property var modelData
                                    required property int index
                                    readonly property bool applied:     modelData.id === AppearanceService.themeName
                                    readonly property bool highlighted: index === overlay.selIndex
                                    width: 200; height: 150
                                    radius: 14
                                    color: (highlighted || optHover.hovered)
                                           ? overlay.theme.lift(overlay.theme.surface, 1.15) : overlay.theme.surface
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

                        // Selection outline: one rectangle that glides between
                        // themes (drawn over the tiles; it takes no input).
                        Rectangle {
                            readonly property Item target: optRepeater.itemAt(overlay.selIndex)
                            x: target ? target.x : 0
                            y: target ? target.y : 0
                            width: 200; height: 150
                            radius: 14
                            color: "transparent"
                            border.color: overlay.theme.primary
                            border.width: 3
                            Behavior on x {
                                enabled: !overlay._snapHighlight
                                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                            }
                            Behavior on y {
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
