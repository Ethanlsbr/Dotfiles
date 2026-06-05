import QtQuick
import Quickshell
import Quickshell.Wayland

// Spotlight-style clipboard history picker — same layout as the launcher
// but lists `cliphist` entries. Type to filter. Enter copies the selected
// entry back to the clipboard. Delete (or Ctrl+Backspace) removes it.
PanelWindow {
    id: overlay

    required property var shellRoot
    required property var theme

    readonly property bool _open: shellRoot.clipboardOpen
    // Destroy immediately on close — see LauncherOverlay for why the
    // exit-anim surface-alive trick breaks keyboard handoff.
    visible: _open
    // Exclusive (not OnDemand): opened from the launcher, whose surface closes
    // in the same frame — Hyprland would otherwise hand the keyboard back to the
    // underlying app instead of this picker. Exclusive forces the grab so typing
    // to filter / Esc work even with an app in the workspace.
    WlrLayershell.keyboardFocus: _open ? WlrKeyboardFocus.Exclusive
                                       : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }
    exclusiveZone: 0
    color: "transparent"

    readonly property string ff: "CaskaydiaCove Nerd Font Propo"

    readonly property int panelWidth:     640
    readonly property int topOffset:      140
    readonly property int searchHeight:   64
    readonly property int rowHeight:      54
    readonly property int maxVisibleRows: 8

    property string searchText:    ""
    property int    selectedIndex: 0

    readonly property var filtered: {
        const list = shellRoot.clipboardList || []
        const q = searchText.trim().toLowerCase()
        if (!q) return list
        return list.filter(e => (e.preview || "").toLowerCase().includes(q))
    }
    readonly property bool hasResults: filtered.length > 0

    function close()       { shellRoot.closeClipboard() }
    function copySelected() {
        const e = filtered[selectedIndex]
        if (!e) return
        shellRoot.copyClipboardEntry(e.id)
        close()
    }
    function deleteSelected() {
        const e = filtered[selectedIndex]
        if (!e) return
        shellRoot.deleteClipboardEntry(e.id)
        if (selectedIndex >= filtered.length - 1)
            selectedIndex = Math.max(0, filtered.length - 2)
    }

    onFilteredChanged: selectedIndex = 0
    on_OpenChanged: {
        if (_open) {
            exitAnim.stop()
            searchInput.text = ""
            searchText       = ""
            selectedIndex    = 0
            enterAnim.restart()
            Qt.callLater(() => searchInput.forceActiveFocus())
        } else {
            enterAnim.stop()
            exitAnim.restart()
        }
    }

    // Backdrop closes on click outside the card.
    MouseArea {
        anchors.fill: parent
        onClicked: overlay.close()
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: floater;      property: "opacity"; from: 0; to: 1;  duration: 360; easing.type: Easing.OutCubic }
        NumberAnimation { target: floaterSlide; property: "y"; from: -24; to: 0;   duration: 360; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: floater;      property: "opacity"; to: 0;    duration: 280; easing.type: Easing.InCubic }
        NumberAnimation { target: floaterSlide; property: "y"; to: -24;    duration: 280; easing.type: Easing.InCubic }
    }

    Column {
        id: floater
        anchors.horizontalCenter: parent.horizontalCenter
        y: overlay.topOffset
        width: overlay.panelWidth
        spacing: 8
        opacity: 0
        transform: Translate { id: floaterSlide; y: -24 }

        // ── Search bar ───────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: overlay.searchHeight
            radius: 14
            color: overlay.theme.bg
            border.color: searchInput.activeFocus
                          ? overlay.theme.primary
                          : overlay.theme.sep
            border.width: 1

            MouseArea { anchors.fill: parent; onClicked: {} }

            Text {
                anchors { left: parent.left; leftMargin: 22
                          verticalCenter: parent.verticalCenter }
                text: ""
                color: overlay.theme.outline
                font.family: overlay.ff
                font.pixelSize: 22
            }

            TextInput {
                id: searchInput
                anchors { left: parent.left;  leftMargin: 60
                          right: parent.right; rightMargin: 20
                          verticalCenter: parent.verticalCenter }
                color:             overlay.theme.fg
                selectionColor:    overlay.theme.primary
                selectedTextColor: overlay.theme.bg
                font.family:       overlay.ff
                font.pixelSize:    18
                activeFocusOnPress: true
                clip: true
                onTextChanged: overlay.searchText = text

                Text {
                    visible: searchInput.text.length === 0
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "Filter clipboard history…"
                    color: overlay.theme.outline
                    opacity: 0.55
                    font: searchInput.font
                }

                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Escape) {
                        overlay.close(); e.accepted = true
                    } else if (e.key === Qt.Key_Down) {
                        if (overlay.hasResults) {
                            overlay.selectedIndex = Math.min(
                                overlay.filtered.length - 1,
                                overlay.selectedIndex + 1)
                            listView.positionViewAtIndex(overlay.selectedIndex, ListView.Contain)
                        }
                        e.accepted = true
                    } else if (e.key === Qt.Key_Up) {
                        if (overlay.hasResults) {
                            overlay.selectedIndex = Math.max(0, overlay.selectedIndex - 1)
                            listView.positionViewAtIndex(overlay.selectedIndex, ListView.Contain)
                        }
                        e.accepted = true
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        overlay.copySelected(); e.accepted = true
                    } else if (e.key === Qt.Key_Delete
                            || (e.key === Qt.Key_Backspace
                                && (e.modifiers & Qt.ControlModifier))) {
                        overlay.deleteSelected(); e.accepted = true
                    }
                }
            }
        }

        // ── Results card ─────────────────────────────────────────────
        Rectangle {
            id: resultsCard
            width: parent.width
            radius: 14
            color: overlay.theme.bg
            border.color: overlay.theme.sep
            border.width: 1

            readonly property int contentHeight: overlay.hasResults
                ? Math.min(overlay.filtered.length, overlay.maxVisibleRows)
                  * (overlay.rowHeight + listView.spacing)
                : 56
            height: contentHeight + 12

            MouseArea { anchors.fill: parent; onClicked: {} }

            Text {
                visible: !overlay.hasResults
                anchors.centerIn: parent
                text: overlay.searchText.length
                      ? "No matching entries"
                      : "Clipboard history is empty"
                color: overlay.theme.outline
                font.family: overlay.ff
                font.pixelSize: 15
            }

            ListView {
                id: listView
                visible: overlay.hasResults
                anchors { fill: parent; margins: 6 }
                clip: true
                model: overlay.filtered
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 240

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width:  ListView.view.width
                    height: overlay.rowHeight
                    radius: 10
                    color: index === overlay.selectedIndex
                           ? overlay.theme.active
                           : (rowHover.hovered
                              ? overlay.theme.surface
                              : "transparent")

                    HoverHandler {
                        id: rowHover
                        onHoveredChanged: if (hovered) overlay.selectedIndex = row.index
                    }

                    Row {
                        anchors { left: parent.left;   leftMargin: 14
                                  right: parent.right; rightMargin: 14
                                  verticalCenter: parent.verticalCenter }
                        spacing: 14

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "#" + (row.modelData?.id ?? "")
                            color: overlay.theme.outline
                            font.family: overlay.ff
                            font.pixelSize: 12
                            width: 56
                            elide: Text.ElideRight
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData?.preview ?? ""
                            color: overlay.theme.fg
                            font.family: overlay.ff
                            font.bold: true
                            font.pixelSize: 14
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            width: parent.width - 60 - 24
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: mouse => {
                            overlay.selectedIndex = row.index
                            if (mouse.button === Qt.MiddleButton)
                                overlay.deleteSelected()
                            else
                                overlay.copySelected()
                        }
                    }
                }
            }
        }
    }
}
