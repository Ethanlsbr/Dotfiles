import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Widgets

Item {
    id: pane
    required property var shellRoot
    required property var theme

    // The player the user explicitly picked from the switcher (if still alive).
    property var selectedPlayer: null

    // Honour the manual selection; otherwise prefer a playing player, then any.
    readonly property var active: {
        const ps = Mpris.players.values
        if (selectedPlayer && ps.indexOf(selectedPlayer) >= 0) return selectedPlayer
        return ps.find(p => p.playbackState === MprisPlaybackState.Playing)
            ?? ps[0] ?? null
    }
    readonly property var players: Mpris.players.values

    // Derive an art URL. Falls back to deriving a YouTube thumbnail from
    // xesam:url for browsers (Firefox/Chrome) that don't set mpris:artUrl.
    function artUrlFor(player) {
        if (!player) return ""
        if (player.trackArtUrl && player.trackArtUrl.length > 0) return player.trackArtUrl
        const url = player.metadata ? (player.metadata["xesam:url"] ?? "") : ""
        if (!url) return ""
        // youtube.com/watch?v=ID  or  youtu.be/ID
        let m = url.match(/[?&]v=([\w-]{11})/) || url.match(/youtu\.be\/([\w-]{11})/)
        if (m) return "https://i.ytimg.com/vi/" + m[1] + "/hqdefault.jpg"
        return ""
    }
    readonly property string artUrl: artUrlFor(active)

    readonly property real progress: active?.length ? (active.position % active.length) / active.length : 0

    // Tick MPRIS position
    Timer {
        running: pane.active?.playbackState === MprisPlaybackState.Playing
        interval: 500; repeat: true
        onTriggered: pane.active?.positionChanged()
    }

    function fmtTime(s) {
        if (s < 0 || !isFinite(s)) return "0:00"
        const m = Math.floor(s / 60), sec = Math.floor(s % 60).toString().padStart(2, "0")
        return m + ":" + sec
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 28

        // ── Cover + cava ring ──────────────────────────────────────────
        Item {
            id: coverWrap
            // Sized to fully contain the radiating cava bars: a peak bar reaches
            // innerR + thickness/2 + maxBarLen + round-cap (~140px from centre),
            // so the box must be large enough or the loud bars get clipped.
            Layout.preferredWidth:  300
            Layout.preferredHeight: 300
            Layout.alignment: Qt.AlignVCenter

            readonly property real coverSize: 160
            readonly property real maxBarLen: 38   // outward reach beyond cover edge

            // Audio-reactive bars radiating from the cover edge (Canvas-based).
            Canvas {
                id: viz
                anchors.fill: parent
                antialiasing: true
                renderTarget: Canvas.FramebufferObject

                readonly property real innerR: coverWrap.coverSize / 2 + 6
                readonly property int  n:      pane.shellRoot.cavaBarCount

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const cx = width / 2, cy = height / 2
                    const sw = Math.max(2, (2 * Math.PI * innerR) / n - 2)  // bar thickness
                    ctx.lineCap   = "round"
                    ctx.lineWidth = sw
                    ctx.strokeStyle = pane.theme.primary
                    const vals = pane.shellRoot.cavaValues || []
                    for (let i = 0; i < n; i++) {
                        const v = Math.max(0.02, vals[i] || 0)
                        const a = i * 2 * Math.PI / n - Math.PI / 2  // start at top
                        const cos = Math.cos(a), sin = Math.sin(a)
                        const r0 = innerR + sw / 2
                        const r1 = r0 + v * coverWrap.maxBarLen
                        ctx.beginPath()
                        ctx.moveTo(cx + r0 * cos, cy + r0 * sin)
                        ctx.lineTo(cx + r1 * cos, cy + r1 * sin)
                        ctx.stroke()
                    }
                }

                Connections {
                    target: pane.shellRoot
                    function onCavaValuesChanged() { viz.requestPaint() }
                }
            }

            // Cover art — actually circular via ClippingRectangle (clips to its rounded shape).
            ClippingRectangle {
                anchors.centerIn: parent
                width:  coverWrap.coverSize
                height: coverWrap.coverSize
                radius: width / 2
                color: pane.theme.surface2

                Text {
                    anchors.centerIn: parent
                    text: ""
                    color: pane.theme.outline
                    font.family: pane.theme.ff; font.pixelSize: 80
                    visible: art.status !== Image.Ready
                }

                Image {
                    id: art
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    source: pane.artUrl
                    asynchronous: true
                }
            }

            // Circular border drawn on top
            Rectangle {
                anchors.centerIn: parent
                width:  coverWrap.coverSize
                height: coverWrap.coverSize
                radius: width / 2
                color: "transparent"
                border.color: pane.theme.primary
                border.width: 2
            }
        }

        // ── Details + controls ─────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 8

            // ── Source switcher (only when >1 player is around) ─────────
            Flow {
                Layout.fillWidth: true
                Layout.bottomMargin: 2
                visible: pane.players.length > 1
                spacing: 6

                Repeater {
                    model: pane.players
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: modelData === pane.active
                        readonly property bool playing: modelData.playbackState === MprisPlaybackState.Playing
                        height: 26
                        width: srcRow.implicitWidth + 20
                        radius: 13
                        color: sel ? pane.theme.hi(1.4) : Qt.darker(pane.theme.bg, 1.15)
                        border.color: sel ? pane.theme.primary : pane.theme.sep
                        border.width: 1

                        Row {
                            id: srcRow
                            anchors.centerIn: parent
                            spacing: 6
                            // Status dot: green while playing, dim otherwise.
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "●"
                                color: playing ? pane.theme.tertiary : pane.theme.outline
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs - 4
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.identity || "Player"
                                color: sel ? pane.theme.fg : pane.theme.txt2
                                font.family: pane.theme.ff
                                font.bold: sel
                                font.pixelSize: pane.theme.fs - 2
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pane.selectedPlayer = modelData
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: pane.active?.trackTitle || "No media"
                color: pane.theme.primary
                font.family: pane.theme.ff
                font.bold: true
                font.pixelSize: pane.theme.fs + 8
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: pane.active?.trackAlbum || ""
                color: pane.theme.outline
                font.family: pane.theme.ff
                font.pixelSize: pane.theme.fs - 1
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: pane.active?.trackArtist || "Play some music for stuff to show up here!"
                color: pane.active ? pane.theme.secondary : pane.theme.outline
                font.family: pane.theme.ff
                font.pixelSize: pane.theme.fs
                elide: Text.ElideRight
            }

            // ── Progress slider ─────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.topMargin: 12
                implicitHeight: 28

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4; radius: 2
                    color: pane.theme.surface2

                    Rectangle {
                        width: parent.width * pane.progress
                        height: parent.height; radius: 2
                        color: pane.theme.primary
                    }
                }
                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: pane.theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(parent.width - width, parent.width * pane.progress - width / 2))
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: (pane.active?.canSeek ?? false) && (pane.active?.positionSupported ?? false)
                    onClicked: e => {
                        const frac = Math.max(0, Math.min(1, e.x / width))
                        if (pane.active) pane.active.position = frac * pane.active.length
                    }
                }
            }

            // ── Position / duration ─────────────────────────────────────
            Item {
                Layout.fillWidth: true
                implicitHeight: 16

                Text {
                    anchors.left: parent.left
                    text: pane.fmtTime(pane.active?.position ?? 0)
                    color: pane.theme.outline
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 2
                }
                Text {
                    anchors.right: parent.right
                    text: pane.fmtTime(pane.active?.length ?? 0)
                    color: pane.theme.outline
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 2
                }
            }

            // ── Transport controls ──────────────────────────────────────
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 18
                spacing: 14

                CtrlBtn {
                    icon: ""
                    enabled: pane.active?.canGoPrevious ?? false
                    onClicked: pane.active?.previous()
                }
                CtrlBtn {
                    icon: pane.active?.playbackState === MprisPlaybackState.Playing ? "" : ""
                    enabled: pane.active?.canTogglePlaying ?? false
                    big: true
                    onClicked: pane.active?.togglePlaying()
                }
                CtrlBtn {
                    icon: ""
                    enabled: pane.active?.canGoNext ?? false
                    onClicked: pane.active?.next()
                }
            }
        }
    }

    component CtrlBtn: Rectangle {
        id: btn
        signal clicked()
        property string icon: ""
        property bool   big:  false
        property alias  enabled: hitbox.enabled

        width:  big ? 56 : 44
        height: big ? 56 : 44
        radius: big ? 28 : 22
        color: hover.hovered
                ? pane.theme.hi(1.5)
                : (big ? pane.theme.hi(1.2) : "transparent")
        opacity: enabled ? 1 : 0.4
        border.color: pane.theme.sep
        border.width: big ? 0 : 1

        Behavior on color { ColorAnimation { duration: 120 } }

        HoverHandler { id: hover }

        Text {
            anchors.centerIn: parent
            text: btn.icon
            color: pane.theme.primary
            font.family: pane.theme.ff
            font.pixelSize: btn.big ? pane.theme.fs + 8 : pane.theme.fs + 4
        }

        MouseArea {
            id: hitbox
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
