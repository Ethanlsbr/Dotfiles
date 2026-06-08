import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Bottom-anchored wallpaper picker. Carousel shows the previous /
// current / next thumbnail; left/right arrows cycle, Enter applies
// (via `awww img`), Esc / click-outside closes. Search bar at the top
// filters the list by filename substring.
PanelWindow {
    id: overlay

    required property var shellRoot
    required property var theme

    readonly property bool _open: shellRoot.wallpaperPickerOpen
    // Destroy immediately on close — see LauncherOverlay for why the
    // exit-anim surface-alive trick breaks keyboard handoff.
    visible: _open
    // Exclusive (not OnDemand): opened from the launcher, whose surface closes
    // in the same frame — Hyprland would otherwise return the keyboard to the
    // underlying app instead of this freshly-mapped picker. Exclusive forces
    // the grab so arrow-key cycling / Esc work even with an app in the workspace.
    WlrLayershell.keyboardFocus: _open ? WlrKeyboardFocus.Exclusive
                                       : WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }
    exclusiveZone: 0
    color: "transparent"

    property string searchText:   ""
    property int    currentIndex: 0

    readonly property var filtered: {
        // Ordered by file modification time (most recently added first).
        const list = shellRoot.recentWallpapers || []
        const q = searchText.trim().toLowerCase()
        if (!q) return list
        return list.filter(p => p.toLowerCase().includes(q))
    }
    readonly property bool folderEmpty: (shellRoot.recentWallpapers || []).length === 0

    function next()  { if (filtered.length) currentIndex = (currentIndex + 1) % filtered.length }
    function prev()  { if (filtered.length) currentIndex = (currentIndex - 1 + filtered.length) % filtered.length }
    function _wrap(i) {
        const n = filtered.length
        if (!n) return ""
        return filtered[((i % n) + n) % n]
    }
    function apply() {
        const p = filtered[currentIndex]
        if (!p) return
        shellRoot.setWallpaper(p)
        shellRoot.closeWallpaperPicker()
    }
    function close() { shellRoot.closeWallpaperPicker() }

    onFilteredChanged: currentIndex = 0
    on_OpenChanged: {
        if (_open) {
            exitAnim.stop()
            searchInput.text = ""           // clears the TextInput itself
            searchText       = ""
            currentIndex     = 0
            enterAnim.restart()
            Qt.callLater(() => searchInput.forceActiveFocus())
        } else {
            enterAnim.stop()
            exitAnim.restart()
        }
    }

    // Click-outside-to-close backdrop.
    MouseArea {
        anchors.fill: parent
        onClicked: overlay.close()
    }

    // Bottom-anchored: slide up from below.
    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: card;      property: "opacity"; from: 0; to: 1; duration: 360; easing.type: Easing.OutCubic }
        NumberAnimation { target: cardSlide; property: "y";    from: 24; to: 0; duration: 360; easing.type: Easing.OutCubic }
    }
    // Reverse: slide back down and fade out.
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: card;      property: "opacity"; to: 0;  duration: 280; easing.type: Easing.InCubic }
        NumberAnimation { target: cardSlide; property: "y";    to: 24; duration: 280; easing.type: Easing.InCubic }
    }

    // ── Carousel card ───────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        width: 1180
        height: 320
        radius: 16
        color: overlay.theme.bg
        border.color: overlay.theme.sep
        border.width: 1
        opacity: 0
        transform: Translate { id: cardSlide; y: 24 }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            anchors { fill: parent; margins: 14 }
            spacing: 10

            // ── Search bar ──────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: 38
                radius: 10
                color: overlay.theme.field
                border.color: searchInput.activeFocus
                              ? overlay.theme.primary
                              : overlay.theme.sep
                border.width: 1

                Text {
                    anchors { left: parent.left; leftMargin: 14
                              verticalCenter: parent.verticalCenter }
                    text: ""
                    color: overlay.theme.outline
                    font.family: overlay.theme.ff
                    font.pixelSize: 16
                }

                TextInput {
                    id: searchInput
                    anchors { left: parent.left;  leftMargin: 38
                              right: parent.right; rightMargin: 12
                              verticalCenter: parent.verticalCenter }
                    color:             overlay.theme.fg
                    selectionColor:    overlay.theme.primary
                    selectedTextColor: overlay.theme.bg
                    font.family:       overlay.theme.ff
                    font.pixelSize:    14
                    activeFocusOnPress: true
                    clip: true
                    onTextChanged: overlay.searchText = text

                    Text {
                        visible: searchInput.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Filter wallpapers…"
                        color: overlay.theme.outline
                        opacity: 0.6
                        font: searchInput.font
                    }

                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Escape) {
                            overlay.close(); e.accepted = true
                        } else if (e.key === Qt.Key_Left) {
                            overlay.prev(); e.accepted = true
                        } else if (e.key === Qt.Key_Right) {
                            overlay.next(); e.accepted = true
                        } else if (e.key === Qt.Key_Return
                                || e.key === Qt.Key_Enter) {
                            overlay.apply(); e.accepted = true
                        }
                    }
                }
            }

            // ── Carousel area ───────────────────────────────────────
            Item {
                width: parent.width
                height: parent.height - 48

                // Empty-folder message
                Text {
                    visible: overlay.folderEmpty
                    anchors.centerIn: parent
                    text: "No wallpapers found in " + overlay.shellRoot.wallpaperFolder
                    color: overlay.theme.outline
                    font.family: overlay.theme.ff
                    font.pixelSize: 14
                }

                // No-match message (folder has wallpapers but filter
                // returned none).
                Text {
                    visible: !overlay.folderEmpty && overlay.filtered.length === 0
                    anchors.centerIn: parent
                    text: "No matching wallpapers"
                    color: overlay.theme.outline
                    font.family: overlay.theme.ff
                    font.pixelSize: 14
                }

                // 5-up carousel: -2 | -1 | current | +1 | +2.
                // Outer pair is smaller + more dimmed for depth.
                Row {
                    visible: overlay.filtered.length > 0
                    anchors.centerIn: parent
                    spacing: 16

                    Thumb {
                        thumbWidth: 130; thumbHeight: 170
                        opacity: overlay.filtered.length > 2 ? 0.30 : 0
                        path: overlay._wrap(overlay.currentIndex - 2)
                        onClicked: { overlay.prev(); overlay.prev() }
                    }
                    Thumb {
                        thumbWidth: 180; thumbHeight: 190
                        opacity: overlay.filtered.length > 1 ? 0.55 : 0
                        path: overlay._wrap(overlay.currentIndex - 1)
                        onClicked: overlay.prev()
                    }
                    Thumb {
                        thumbWidth: 320; thumbHeight: 210
                        highlight: true
                        path: overlay.filtered[overlay.currentIndex] || ""
                        onClicked: overlay.apply()
                    }
                    Thumb {
                        thumbWidth: 180; thumbHeight: 190
                        opacity: overlay.filtered.length > 1 ? 0.55 : 0
                        path: overlay._wrap(overlay.currentIndex + 1)
                        onClicked: overlay.next()
                    }
                    Thumb {
                        thumbWidth: 130; thumbHeight: 170
                        opacity: overlay.filtered.length > 2 ? 0.30 : 0
                        path: overlay._wrap(overlay.currentIndex + 2)
                        onClicked: { overlay.next(); overlay.next() }
                    }
                }

                // Filename + counter
                Text {
                    visible: overlay.filtered.length > 0
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        bottom: parent.bottom
                        bottomMargin: 2
                    }
                    text: {
                        const p = overlay.filtered[overlay.currentIndex] || ""
                        const name = p.split("/").pop()
                        return name + "   "
                            + (overlay.currentIndex + 1) + " / "
                            + overlay.filtered.length
                    }
                    color: overlay.theme.fg
                    font.family: overlay.theme.ff
                    font.pixelSize: 12
                    font.bold: true
                }
            }
        }
    }

    // ── Reusable thumbnail tile ──────────────────────────────────────
    // Loads the small cached thumbnail (already generated for the grid), so
    // cycling is instant. A hidden loader (imgB) always targets the latest
    // requested image while the visible one (imgA) holds the previous frame
    // until the new one is decoded — no black reload, and no crossfade, so
    // rapid cycling can't leave two tiles showing the same image mid-fade.
    component Thumb: ClippingRectangle {
        id: thumb
        property string path: ""
        property real   thumbWidth:  130
        property real   thumbHeight: 180
        property bool   highlight:   false
        signal clicked()

        width:  thumbWidth
        height: thumbHeight
        radius: 10
        color:  overlay.theme.field
        border.color: highlight ? overlay.theme.primary : "transparent"
        border.width: highlight ? 2 : 0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

        readonly property string _thumb: path ? overlay.shellRoot.thumbForWallpaper(path) : ""
        readonly property string _orig:  path ? "file://" + path : ""
        // Falls back to the full image if the thumbnail isn't generated yet.
        property bool _useOrig: false
        on_ThumbChanged: _useOrig = false   // new image → prefer its thumbnail again

        // Visible image — holds the previous frame until the loader has the new
        // one (so cycling never shows black).
        Image {
            id: imgA
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
        }
        // Hidden preloader, bound to the current target so it loads reliably on
        // first show (a one-shot imperative load could fire before the window
        // was mapped and get stuck). When ready it's swapped onto imgA — from
        // Qt's cache, so effectively instant.
        Image {
            id: imgB
            anchors.fill: parent
            visible: false
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            source: thumb._thumb === "" ? "" : (thumb._useOrig ? thumb._orig : thumb._thumb)
            onStatusChanged: {
                if (status === Image.Ready) imgA.source = source
                else if (status === Image.Error && !thumb._useOrig && thumb._orig !== "")
                    thumb._useOrig = true   // thumbnail missing → use the full image
            }
        }
        // Retry the thumbnail as background generation publishes it.
        Connections {
            target: overlay.shellRoot
            function onWallpaperThumbTickChanged() {
                if (thumb._useOrig && thumb._thumb !== "") thumb._useOrig = false
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: thumb.clicked()
        }
    }
}
