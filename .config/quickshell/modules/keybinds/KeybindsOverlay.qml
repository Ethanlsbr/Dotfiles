import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.appearance
import qs.common

// Keybind cheat-sheet parsed from keybinds.lua. Esc / click / ✕ dismiss.
PanelWindow {
    id: overlay

    required property var theme
    // Shell-size scale of this window's monitor (unset monitors = 100%).
    readonly property real uiScale: AppearanceService.scaleFor(screen?.name ?? "")

    readonly property bool _open: KeybindsService.keybindsOpen
    visible: pop.shown
    // Grab the keyboard while open so Esc works; released the moment _open
    // flips, so the exit animation still plays.
    WlrLayershell.keyboardFocus: _open ? WlrKeyboardFocus.Exclusive
                                       : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }
    exclusiveZone: 0
    color: "transparent"

    readonly property string ff: "CaskaydiaCove Nerd Font Propo"

    // Group the flat list into [{ section, items: [...] }] preserving order.
    readonly property var groups: {
        const out = []
        const idx = {}
        for (const e of (KeybindsService.keybindsList || [])) {
            if (!(e.section in idx)) { idx[e.section] = out.length; out.push({ section: e.section, items: [] }) }
            out[idx[e.section]].items.push(e)
        }
        return out
    }

    on_OpenChanged: {
        if (_open) Qt.callLater(() => cardWrap.forceActiveFocus())
    }

    // Click-anywhere closes.
    MouseArea {
        anchors.fill: parent
        onClicked: KeybindsService.closeKeybinds()
    }

    Item {
        id: cardWrap
        anchors.centerIn: parent
        width: card.width
        height: card.height
        // uiScale transform; composes with the card's pop.
        scale: overlay.uiScale
        opacity: 0
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) { KeybindsService.closeKeybinds(); e.accepted = true }
        }

        Rectangle {
            id: card
            // Shared open/close motion, from the centre.
            transform: PopAnim { id: pop; item: cardWrap; open: overlay._open; origin.x: card.width / 2; origin.y: card.height / 2 }
            width: 760
            height: Math.min(overlay.height / overlay.uiScale - 80, contentCol.implicitHeight + 72)
            color: overlay.theme.bg
            radius: 18
            border.color: overlay.theme.sep
            border.width: 1

            // Swallow clicks — don't trigger backdrop close.
            MouseArea { anchors.fill: parent; onClicked: {} }

            // Card-wide hover reveals the scrollbar.
            HoverHandler { id: cardHover }

            // ── Header ───────────────────────────────────────────────
            Text {
                id: title
                anchors { left: parent.left; top: parent.top; leftMargin: 22; topMargin: 18 }
                text: "Keyboard Shortcuts"
                color: overlay.theme.fg
                font.family: overlay.ff
                font.bold: true
                font.pixelSize: overlay.theme.fs + 6
            }
            Text {
                anchors { left: title.right; verticalCenter: title.verticalCenter; leftMargin: 12 }
                text: KeybindsService.keybindsList.length + " bindings"
                color: overlay.theme.outline
                font.family: overlay.ff
                font.pixelSize: overlay.theme.fs - 1
            }
            Rectangle {
                id: closeBtn
                anchors { right: parent.right; top: parent.top; margins: 14 }
                width: 30; height: 30; radius: 15
                color: closeHover.hovered ? overlay.theme.error : overlay.theme.chip
                border.color: overlay.theme.sep; border.width: 1
                HoverHandler { id: closeHover }
                Text {
                    anchors.centerIn: parent; text: "✕"
                    color: overlay.theme.fg; font.family: overlay.ff
                    font.bold: true; font.pixelSize: overlay.theme.fs
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: KeybindsService.closeKeybinds()
                }
            }

            // ── Body (scrollable, two-column section flow) ───────────
            Flickable {
                id: listFlick
                anchors {
                    left: parent.left;   leftMargin: 22
                    right: parent.right; rightMargin: 20   // room for the scrollbar
                    top: title.bottom;   topMargin: 16
                    bottom: parent.bottom; bottomMargin: 18
                }
                clip: true
                contentHeight: contentCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: contentCol
                    width: parent.width
                    spacing: 16

                    Repeater {
                        model: overlay.groups
                        delegate: Column {
                            required property var modelData
                            width: contentCol.width
                            spacing: 6

                            Text {
                                text: modelData.section
                                color: overlay.theme.primary
                                font.family: overlay.ff
                                font.bold: true
                                font.pixelSize: overlay.theme.fs
                            }

                            Repeater {
                                model: modelData.items
                                delegate: Item {
                                    required property var modelData
                                    width: contentCol.width
                                    height: 30

                                    // Key combo chips on the left.
                                    Row {
                                        id: chips
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        Repeater {
                                            model: modelData.keys.split(" + ")
                                            delegate: Rectangle {
                                                required property var modelData
                                                height: 22
                                                width: keyText.implicitWidth + 16
                                                radius: 6
                                                color: overlay.theme.hi(1.3)
                                                border.color: overlay.theme.sep
                                                border.width: 1
                                                Text {
                                                    id: keyText
                                                    anchors.centerIn: parent
                                                    text: modelData
                                                    color: overlay.theme.fg
                                                    font.family: overlay.ff
                                                    font.bold: true
                                                    font.pixelSize: overlay.theme.fs - 3
                                                }
                                            }
                                        }
                                    }

                                    // Description on the right.
                                    Text {
                                        anchors {
                                            left: chips.right; leftMargin: 14
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                        }
                                        text: modelData.desc
                                        color: overlay.theme.txt2
                                        font.family: overlay.ff
                                        font.pixelSize: overlay.theme.fs - 1
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Scrollbar (right edge, fades in on hover) ────────────
            Rectangle {
                id: scrollbar
                readonly property bool active: listFlick.contentHeight > listFlick.height
                anchors {
                    right: parent.right; rightMargin: 6
                    top: listFlick.top
                    bottom: listFlick.bottom
                }
                width: 6
                radius: 3
                color: "transparent"
                visible: active
                opacity: (cardHover.hovered || listFlick.moving) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }

                Rectangle {
                    id: thumb
                    width: parent.width
                    radius: parent.radius
                    color: overlay.theme.hi(1.6)
                    height: Math.max(28, scrollbar.height * listFlick.visibleArea.heightRatio)
                    y: listFlick.visibleArea.yPosition * scrollbar.height

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        drag.target: thumb
                        drag.axis: Drag.YAxis
                        drag.minimumY: 0
                        drag.maximumY: scrollbar.height - thumb.height
                        onPositionChanged: if (drag.active) {
                            listFlick.contentY = (thumb.y / (scrollbar.height - thumb.height))
                                * (listFlick.contentHeight - listFlick.height)
                        }
                    }
                }
            }
        }
    }
}
