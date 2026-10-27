import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.modules.appearance
import qs.common

// Bottom wallpaper carousel: sliding prev / current / next thumbs, ←/→ cycles,
// Enter applies (awww img), Esc closes. Search filters by filename.
PanelWindow {
    id: overlay

    required property var theme
    // Shell-size scale of this window's monitor (unset monitors = 100%).
    readonly property real uiScale: AppearanceService.scaleFor(screen?.name ?? "")

    readonly property bool _open: WallpaperService.wallpaperPickerOpen
    // Unmapped once the close animation ends: a kept-alive layer breaks
    // keyboard handoff (FocusService refocuses after the animation).
    visible: pop.shown
    // Stay mapped through the close animation, but input-transparent and
    // without the keyboard (focus handoff happens once it unmaps).
    mask: _open ? null : noInput
    Region { id: noInput }
    // Exclusive: the launcher closes the same frame; OnDemand would hand
    // the keyboard back to the underlying app.
    WlrLayershell.keyboardFocus: _open ? WlrKeyboardFocus.Exclusive
                                       : WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }
    exclusiveZone: 0
    color: "transparent"

    property string searchText:   ""
    // Unbounded step counter (←/→ ±1); currentIndex is it wrapped onto the
    // list, and visualPos trails it so the carousel slides between steps.
    property int    step: 0
    readonly property int currentIndex: filtered.length ? ((step % filtered.length) + filtered.length) % filtered.length : 0
    property bool   _animate: true
    property real   visualPos: step
    Behavior on visualPos {
        enabled: overlay._animate
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    readonly property var filtered: {
        // Ordered by file modification time (most recently added first).
        const list = WallpaperService.recentWallpapers || []
        const q = searchText.trim().toLowerCase()
        if (!q) return list
        return list.filter(p => p.toLowerCase().includes(q))
    }
    readonly property bool folderEmpty: (WallpaperService.recentWallpapers || []).length === 0

    function next()  { if (filtered.length > 1) step++ }
    function prev()  { if (filtered.length > 1) step-- }
    // Jump back to the first wallpaper without sliding.
    function resetPos() { _animate = false; step = 0; _animate = true }
    function _wrap(i) {
        const n = filtered.length
        if (!n) return ""
        return filtered[((i % n) + n) % n]
    }
    function apply() {
        const p = filtered[currentIndex]
        if (!p) return
        WallpaperService.setWallpaper(p)
        WallpaperService.closeWallpaperPicker()
    }
    function close() { WallpaperService.closeWallpaperPicker() }

    onFilteredChanged: resetPos()
    on_OpenChanged: {
        if (_open) {
            searchInput.text = ""           // clears the TextInput itself
            searchText       = ""
            resetPos()
            Qt.callLater(() => searchInput.forceActiveFocus())
        }
    }

    // Click-outside closes.
    MouseArea {
        anchors.fill: parent
        onClicked: overlay.close()
    }

    // ── Carousel card ───────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        width: Math.min(1180, overlay.width / overlay.uiScale - 40)
        height: 320
        // uiScale transform from the bottom anchor; composes with the pop.
        scale: overlay.uiScale
        transformOrigin: Item.Bottom
        radius: 16
        color: overlay.theme.bg
        border.color: overlay.theme.sep
        border.width: 1
        opacity: 0
        // Shared open motion, growing up from the bottom centre.
        transform: PopAnim { id: pop; item: card; open: overlay._open; origin.x: card.width / 2; origin.y: card.height }

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
                    text: "No wallpapers found in " + WallpaperService.wallpaperFolder
                    color: overlay.theme.outline
                    font.family: overlay.theme.ff
                    font.pixelSize: 14
                }

                // Filter matched nothing.
                Text {
                    visible: !overlay.folderEmpty && overlay.filtered.length === 0
                    anchors.centerIn: parent
                    text: "No matching wallpapers"
                    color: overlay.theme.outline
                    font.family: overlay.theme.ff
                    font.pixelSize: 14
                }

                // Sliding carousel: 7 slots, slot s shows the step ≡ s (mod 7)
                // nearest visualPos, so a tile keeps its image while it glides
                // and is only recycled off-screen. Size / spread / opacity
                // follow the distance d from the centre (keyframes at |d| = 0..3).
                Item {
                    id: strip
                    visible: overlay.filtered.length > 0
                    anchors.fill: parent

                    readonly property var kW:  [320, 180, 130, 100]
                    readonly property var kH:  [210, 190, 170, 150]
                    readonly property var kX:  [0, 266, 437, 568]
                    readonly property var kOp: [1, 0.55, 0.30, 0]
                    function key(arr, a) {
                        const t = Math.min(3, a), i = Math.min(2, Math.floor(t))
                        return arr[i] + (arr[i + 1] - arr[i]) * (t - i)
                    }
                    // Fewer wallpapers than slots: don't show wrapped duplicates.
                    readonly property int reach: overlay.filtered.length <= 1 ? 0
                                               : overlay.filtered.length === 2 ? 1 : 2

                    Repeater {
                        model: 7
                        delegate: Thumb {
                            id: tile
                            required property int index
                            readonly property int  logical: index + 7 * Math.round((overlay.visualPos - index) / 7)
                            readonly property real d: logical - overlay.visualPos
                            readonly property real a: Math.abs(d)

                            thumbWidth:  strip.key(strip.kW, a)
                            thumbHeight: strip.key(strip.kH, a)
                            x: strip.width / 2 + Math.sign(d) * strip.key(strip.kX, a) - width / 2
                            y: (strip.height - height) / 2
                            z: 10 - a
                            opacity: strip.key(strip.kOp, a) * Math.max(0, Math.min(1, strip.reach + 1 - a))
                            highlight: a < 0.5
                            path: overlay._wrap(logical)
                            onClicked: {
                                const k = Math.round(d)
                                if (k === 0) overlay.apply()
                                else overlay.step += k
                            }
                        }
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
    // Shows the cached thumb (instant cycling). Hidden loader imgB fetches
    // the latest target while imgA keeps the previous frame — no black
    // reload, no crossfade.
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

        readonly property string _thumb: path ? WallpaperService.thumbForWallpaper(path) : ""
        readonly property string _orig:  path ? "file://" + path : ""
        // Falls back to the full image if the thumbnail isn't generated yet.
        property bool _useOrig: false
        on_ThumbChanged: _useOrig = false   // new image → prefer its thumbnail again

        // Visible image — keeps the previous frame while loading.
        Image {
            id: imgA
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
        }
        // Hidden preloader bound to the target (an imperative load could fire
        // before the window mapped and stall); swaps onto imgA from cache.
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
            target: WallpaperService
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
