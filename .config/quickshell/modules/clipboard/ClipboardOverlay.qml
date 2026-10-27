import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.appearance
import qs.common

// Clipboard history picker (launcher-style). Type to filter; Enter copies;
// Delete / Ctrl+Backspace removes the entry.
PanelWindow {
    id: overlay

    required property var theme
    // Shell-size scale of this window's monitor (unset monitors = 100%).
    readonly property real uiScale: AppearanceService.scaleFor(screen?.name ?? "")

    readonly property bool _open: ClipboardService.clipboardOpen
    // Unmapped once the close animation ends: a kept-alive layer would hold
    // the keyboard grab (FocusService refocuses after the animation).
    visible: pop.shown
    // Stay mapped through the close animation, but input-transparent and
    // without the keyboard (focus handoff happens once it unmaps).
    mask: _open ? null : noInput
    Region { id: noInput }
    // Exclusive: the launcher's surface closes the same frame, so OnDemand
    // would hand the keyboard back to the underlying app.
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
        const list = ClipboardService.clipboardList || []
        const q = searchText.trim().toLowerCase()
        if (!q) return list
        return list.filter(e => (e.preview || "").toLowerCase().includes(q))
    }
    readonly property bool hasResults: filtered.length > 0

    // Back to the first row without the highlight gliding up to it.
    property bool _snapHighlight: false
    function resetSelection() {
        _snapHighlight = true
        selectedIndex  = 0
        listView.positionViewAtBeginning()
        Qt.callLater(() => _snapHighlight = false)
    }

    function close()       { ClipboardService.closeClipboard() }
    function copySelected() {
        const e = filtered[selectedIndex]
        if (!e) return
        ClipboardService.copyClipboardEntry(e.id)
        close()
    }
    function deleteSelected() {
        const e = filtered[selectedIndex]
        if (!e) return
        ClipboardService.deleteClipboardEntry(e.id)
        if (selectedIndex >= filtered.length - 1)
            selectedIndex = Math.max(0, filtered.length - 2)
    }

    // A new filter starts from the top; a list refresh (e.g. after a
    // delete) keeps the selection in place instead of jumping back up.
    onSearchTextChanged: resetSelection()
    onFilteredChanged: if (selectedIndex >= filtered.length) selectedIndex = Math.max(0, filtered.length - 1)
    on_OpenChanged: {
        if (_open) {
            searchInput.text = ""
            searchText       = ""
            resetSelection()
            Qt.callLater(() => searchInput.forceActiveFocus())
        }
    }

    // Click-outside closes.
    MouseArea {
        anchors.fill: parent
        onClicked: overlay.close()
    }

    Column {
        id: floater
        anchors.horizontalCenter: parent.horizontalCenter
        y: overlay.topOffset
        width: overlay.panelWidth
        // uiScale transform from the top edge; composes with the pop.
        scale: overlay.uiScale
        transformOrigin: Item.Top
        spacing: 8
        opacity: 0
        // Shared open motion, growing down from the top centre.
        transform: PopAnim { id: pop; item: floater; open: overlay._open; origin.x: floater.width / 2; origin.y: 0 }

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
                        // Wraps: Down on the last entry goes to the first.
                        if (overlay.hasResults) {
                            const n = overlay.filtered.length
                            overlay.selectedIndex = (overlay.selectedIndex + 1) % n
                        }
                        e.accepted = true
                    } else if (e.key === Qt.Key_Up) {
                        // Wraps: Up on the first entry goes to the last.
                        if (overlay.hasResults) {
                            const n = overlay.filtered.length
                            overlay.selectedIndex = (overlay.selectedIndex - 1 + n) % n
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

                // One shared highlight that glides to the selected row (and
                // scrolls the view along) instead of rows recolouring in place.
                currentIndex: overlay.selectedIndex
                highlightFollowsCurrentItem: true
                highlightMoveDuration: overlay._snapHighlight ? 0 : 160
                highlightMoveVelocity: -1
                highlightResizeDuration: 0
                highlight: Rectangle {
                    radius: 10
                    color: overlay.theme.active
                }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width:  ListView.view.width
                    height: overlay.rowHeight
                    radius: 10
                    color: index !== overlay.selectedIndex && rowHover.hovered
                           ? overlay.theme.surface
                           : "transparent"

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
