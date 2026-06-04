import QtQuick
import Quickshell.Widgets

// Standard wallpaper selector for the settings window: a filter box plus a
// scrollable grid of thumbnails. Click a thumbnail to apply it (via `awww`,
// syncing hyprlock); the applied one gets a highlighted border + check badge.
Item {
    id: pane

    required property var shellRoot
    required property var theme

    property string searchText:  ""
    property string appliedPath:  ""

    readonly property var filtered: {
        const list = pane.shellRoot.wallpaperList || []
        const q = searchText.trim().toLowerCase()
        if (!q) return list
        return list.filter(p => p.toLowerCase().includes(q))
    }
    readonly property bool folderEmpty: (pane.shellRoot.wallpaperList || []).length === 0

    function apply(p) {
        if (!p) return
        pane.appliedPath = p
        pane.shellRoot.setWallpaper(p)
    }

    Component.onCompleted: pane.shellRoot.refreshWallpapers()

    Column {
        anchors.fill: parent
        spacing: 12

        // ── Search / filter bar ──────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 38
            radius: 10
            color: pane.theme.field
            border.color: searchInput.activeFocus ? pane.theme.primary : pane.theme.sep
            border.width: 1

            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: ""
                color: pane.theme.outline
                font.family: pane.theme.ff
                font.pixelSize: 16
            }

            TextInput {
                id: searchInput
                anchors { left: parent.left;  leftMargin: 38
                          right: parent.right; rightMargin: 12
                          verticalCenter: parent.verticalCenter }
                color:             pane.theme.fg
                selectionColor:    pane.theme.primary
                selectedTextColor: pane.theme.bg
                font.family:       pane.theme.ff
                font.pixelSize:    14
                activeFocusOnPress: true
                clip: true
                onTextChanged: pane.searchText = text

                Text {
                    visible: searchInput.text.length === 0
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "Filter wallpapers…"
                    color: pane.theme.outline
                    opacity: 0.6
                    font: searchInput.font
                }
            }
        }

        // ── Thumbnail grid ────────────────────────────────────────────────
        Item {
            width: parent.width
            height: parent.height - 50

            Text {
                visible: pane.folderEmpty
                anchors.centerIn: parent
                text: "No wallpapers found in " + pane.shellRoot.wallpaperFolder
                color: pane.theme.outline
                font.family: pane.theme.ff
                font.pixelSize: 14
            }
            Text {
                visible: !pane.folderEmpty && pane.filtered.length === 0
                anchors.centerIn: parent
                text: "No matching wallpapers"
                color: pane.theme.outline
                font.family: pane.theme.ff
                font.pixelSize: 14
            }

            GridView {
                id: grid
                visible: pane.filtered.length > 0
                anchors.fill: parent
                anchors.rightMargin: 10        // leave room for the scrollbar
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 600

                readonly property int columns: Math.max(2, Math.floor(width / 210))
                cellWidth:  Math.floor(width / columns)
                cellHeight: Math.round(cellWidth * 0.62)

                model: pane.filtered

                delegate: Item {
                    id: cell
                    required property var modelData
                    width:  grid.cellWidth
                    height: grid.cellHeight

                    readonly property bool isApplied: modelData === pane.appliedPath

                    ClippingRectangle {
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: 10
                        color: pane.theme.field
                        border.color: cell.isApplied ? pane.theme.tertiary
                                    : (cellHover.hovered ? pane.theme.primary : pane.theme.sep)
                        border.width: cell.isApplied ? 3 : (cellHover.hovered ? 2 : 1)

                        HoverHandler { id: cellHover }

                        Image {
                            id: thumbImg
                            anchors.fill: parent
                            anchors.margins: cell.isApplied ? 3 : 1
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: 420

                            readonly property string thumb: pane.shellRoot.thumbForWallpaper(cell.modelData)
                            readonly property string orig:  cell.modelData ? "file://" + cell.modelData : ""
                            // Prefer the cached thumbnail; decoding the full
                            // multi-MB original per cell is what made the grid slow.
                            source: thumb

                            onStatusChanged: {
                                // Thumb not generated yet: keep waiting while the
                                // background job runs, otherwise fall back to the
                                // original so a cell is never permanently blank.
                                if (status === Image.Error && !pane.shellRoot.wallpaperThumbBusy)
                                    source = orig
                            }
                            // Retry the thumb as generation progresses (clearing
                            // first forces a reload after a prior error).
                            Connections {
                                target: pane.shellRoot
                                function onWallpaperThumbTickChanged() {
                                    if (thumbImg.status === Image.Error) {
                                        thumbImg.source = ""
                                        thumbImg.source = thumbImg.thumb
                                    }
                                }
                            }
                        }

                        // Filename caption strip along the bottom.
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 22
                            color: Qt.rgba(0, 0, 0, 0.55)
                            Text {
                                anchors { left: parent.left; right: parent.right; margins: 8
                                          verticalCenter: parent.verticalCenter }
                                text: (modelData || "").split("/").pop()
                                color: "white"
                                font.family: pane.theme.ff
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }

                        // Applied badge.
                        Rectangle {
                            visible: cell.isApplied
                            anchors { top: parent.top; right: parent.right; margins: 6 }
                            width: 22; height: 22; radius: 11
                            color: pane.theme.tertiary
                            Text {
                                anchors.centerIn: parent
                                text: "\uf00c"           // check
                                color: pane.theme.bg
                                font.family: pane.theme.ff
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pane.apply(cell.modelData)
                        }
                    }
                }
            }

            // ── Scrollbar ─────────────────────────────────────────────────
            Rectangle {
                id: sbTrack
                visible: grid.contentHeight > grid.height
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 6
                radius: 3
                color: "transparent"

                Rectangle {
                    id: sbThumb
                    width: parent.width
                    radius: 3
                    color: sbDrag.active ? pane.theme.primary : pane.theme.outline
                    opacity: 0.7
                    height: Math.max(30, grid.height * grid.visibleArea.heightRatio)
                    y: grid.visibleArea.yPosition * grid.height

                    DragHandler {
                        id: sbDrag
                        target: null
                        yAxis.enabled: true
                        onCentroidChanged: {
                            if (!active) return
                            const span = sbTrack.height - sbThumb.height
                            if (span <= 0) return
                            const ny = Math.max(0, Math.min(span, sbThumb.y + centroid.position.y - sbThumb.height / 2))
                            grid.contentY = (ny / span) * Math.max(0, grid.contentHeight - grid.height)
                        }
                    }
                }
            }
        }
    }
}
