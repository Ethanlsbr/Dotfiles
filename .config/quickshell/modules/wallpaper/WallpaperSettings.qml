import QtQuick
import Quickshell.Widgets
import qs.common.ui

// Wallpaper grid for the settings window: filter box + thumbnail grid.
// Click applies (awww); the applied one gets a border
// and check badge.
Item {
    id: pane

    required property var theme

    property string searchText:  ""
    property string appliedPath:  ""

    // Wallpapers newest-first, with the filename filter applied.
    readonly property var filtered: {
        const base = WallpaperService.recentWallpapers || []
        const q = searchText.trim().toLowerCase()
        if (!q) return base
        return base.filter(p => p.toLowerCase().includes(q))
    }
    readonly property bool folderEmpty: (WallpaperService.recentWallpapers || []).length === 0

    function apply(p) {
        if (!p) return
        pane.appliedPath = p
        WallpaperService.setWallpaper(p)
    }

    Component.onCompleted: WallpaperService.refreshWallpapers()

    Column {
        anchors.fill: parent
        spacing: 14

        // ── Desktop widgets ──────────────────────────────────────────────
        UiGroup {
            id: togglesCard
            theme: pane.theme
            title: "Desktop widgets"

            UiRow {
                theme: pane.theme
                icon: "\uf001"
                title: "Audio visualiser"
                subtitle: "Animated equaliser strip along the bottom of the wallpaper"
                UiSwitch {
                    theme: pane.theme
                    checked: WallpaperService.wpCavaEnabled
                    onToggled: value => WallpaperService.setWpCava(value)
                }
            }
            UiRow {
                theme: pane.theme
                icon: "\uf017"
                title: "Clock & date"
                subtitle: "Large clock floated at the top-centre of the wallpaper"
                UiSwitch {
                    theme: pane.theme
                    checked: WallpaperService.wpClockEnabled
                    onToggled: value => WallpaperService.setWpClock(value)
                }
            }
        }

        // ── Search / filter ──────────────────────────────────────────────
        Item {
            width: parent.width
            height: 4
        }
        UiTextField {
            id: searchBar
            theme: pane.theme
            icon: "\uf002"
            placeholder: "Filter wallpapers…"
            onTextChanged: pane.searchText = text
        }

        // ── Thumbnail grid ────────────────────────────────────────────────
        Item {
            width: parent.width
            // Space left after the toggles card and search bar.
            height: parent.height - togglesCard.height - searchBar.height - 48

            Text {
                visible: pane.folderEmpty
                anchors.centerIn: parent
                text: "No wallpapers found in " + WallpaperService.wallpaperFolder
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
                        radius: 12
                        color: pane.theme.field
                        border.color: cell.isApplied ? pane.theme.primary
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

                            readonly property string thumb: WallpaperService.thumbForWallpaper(cell.modelData)
                            readonly property string orig:  cell.modelData ? "file://" + cell.modelData : ""
                            // Cached thumb — decoding full originals per
                            // cell made the grid slow.
                            source: thumb

                            onStatusChanged: {
                                // Wait while thumbs generate; else fall back
                                // to the original so a cell is never blank.
                                if (status === Image.Error && !WallpaperService.wallpaperThumbBusy)
                                    source = orig
                            }
                            // Retry as generation progresses (clear first
                            // to force reload after an error).
                            Connections {
                                target: WallpaperService
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
                            color: pane.theme.primary
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
