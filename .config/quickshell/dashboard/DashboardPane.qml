import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Widgets

Item {
    id: pane
    required property var shellRoot
    required property var theme

    property var now: new Date()
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: pane.now = new Date()
    }

    readonly property var activePlayer: Mpris.players.values.find(p =>
        p.playbackState === MprisPlaybackState.Playing) ?? Mpris.players.values[0] ?? null

    function artUrlFor(player) {
        if (!player) return ""
        if (player.trackArtUrl && player.trackArtUrl.length > 0) return player.trackArtUrl
        const url = player.metadata ? (player.metadata["xesam:url"] ?? "") : ""
        if (!url) return ""
        let m = url.match(/[?&]v=([\w-]{11})/) || url.match(/youtu\.be\/([\w-]{11})/)
        if (m) return "https://i.ytimg.com/vi/" + m[1] + "/hqdefault.jpg"
        return ""
    }

    readonly property real progress: activePlayer?.length
        ? (activePlayer.position % activePlayer.length) / activePlayer.length : 0
    Timer {
        running: pane.activePlayer?.playbackState === MprisPlaybackState.Playing
        interval: 500; repeat: true
        onTriggered: pane.activePlayer?.positionChanged()
    }

    function fmtTime(s) {
        if (s < 0 || !isFinite(s)) return "0:00"
        const m = Math.floor(s / 60), sec = Math.floor(s % 60).toString().padStart(2, "0")
        return m + ":" + sec
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 10

        // ════════ LEFT column: weather + clock/date ════════
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.preferredWidth: 250
            spacing: 10

            // Weather
            Card {
                Layout.fillWidth: true; Layout.fillHeight: true
                Row {
                    anchors.centerIn: parent
                    spacing: 14
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: pane.shellRoot.weather.ready ? pane.shellRoot.weather.icon : "󰖐"
                        color: pane.theme.secondary
                        font.family: pane.theme.ff; font.pixelSize: pane.theme.fs * 3.2
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: pane.shellRoot.weather.ready ? pane.shellRoot.weather.temp : "—"
                            color: pane.theme.primary
                            font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs + 12
                        }
                        Text {
                            text: pane.shellRoot.weather.ready ? pane.shellRoot.weather.description : "Loading..."
                            color: pane.theme.txt2
                            font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                            elide: Text.ElideRight; width: 130
                        }
                        Text {
                            text: pane.shellRoot.weather.ready ? pane.shellRoot.weather.city : ""
                            color: pane.theme.outline
                            font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
                        }
                    }
                }
            }

            // Clock / date
            Card {
                Layout.fillWidth: true; Layout.fillHeight: true
                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatTime(pane.now, "HH:mm")
                        color: pane.theme.primary
                        font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs * 2.8
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDate(pane.now, "dddd d MMMM")
                        color: pane.theme.txt2
                        font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 1
                        topPadding: 6
                    }
                }
            }
        }

        // ════════ CENTER column: system info + resources/battery ════════
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.preferredWidth: 340
            spacing: 10

            // System info (avatar + distro / WM / uptime)
            Card {
                Layout.fillWidth: true; Layout.fillHeight: true
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 18

                    // Avatar — ~/.config/hypr/user.png if present, else a glyph.
                    ClippingRectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 72; implicitHeight: 72
                        radius: width / 2
                        color: pane.theme.surface2
                        Text {
                            anchors.centerIn: parent
                            text: ""
                            color: pane.theme.outline
                            font.family: pane.theme.ff; font.pixelSize: 38
                            visible: avatarImg.status !== Image.Ready
                        }
                        Image {
                            id: avatarImg
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            source: "file:///home/ethan/.config/hypr/user.png"
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        spacing: 8
                        InfoRow { icon: ""; value: pane.shellRoot.sysDistro || "Linux" }
                        InfoRow { icon: "";     value: pane.shellRoot.sysWM }
                        InfoRow { icon: "";     value: pane.shellRoot.sysUptime || "—" }
                    }
                }
            }

            // Resources + battery side by side
            RowLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: 10

                // Resources (CPU / Mem / Disk)
                Card {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Row {
                        anchors.centerIn: parent
                        spacing: 20
                        ResBar { ic: "";  value: pane.shellRoot.cpuPerc;  col: pane.theme.primary }
                        ResBar { ic: "";  value: pane.shellRoot.memPerc;  col: pane.theme.tertiary }
                        ResBar { ic: ""; value: pane.shellRoot.diskPerc; col: pane.theme.secondary }
                    }
                }

                // Battery / power
                Card {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: {
                                const d = UPower.displayDevice
                                if (!d?.isPresent) return ""
                                const p = Math.round(d.percentage * 100)
                                if (d.state === UPowerDeviceState.Charging
                                 || d.state === UPowerDeviceState.PendingCharge) return "󰂄"
                                return p > 80 ? ""
                                     : p > 60 ? ""
                                     : p > 40 ? ""
                                     : p > 20 ? "" : ""
                            }
                            color: pane.theme.tertiary
                            font.family: pane.theme.ff; font.pixelSize: pane.theme.fs * 2
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: {
                                const d = UPower.displayDevice
                                if (!d?.isPresent) return "AC"
                                return Math.round(d.percentage * 100) + "%"
                            }
                            color: pane.theme.primary
                            font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs + 4
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: {
                                const d = UPower.displayDevice
                                if (!d?.isPresent) return "Desktop"
                                if (d.state === UPowerDeviceState.FullyCharged) return "Full"
                                const t = UPower.onBattery ? d.timeToEmpty : d.timeToFull
                                if (t <= 0) return UPower.onBattery ? "On battery" : "Charging"
                                const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60)
                                return (h > 0 ? h + "h " : "") + m + "m"
                            }
                            color: pane.theme.txt2
                            font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
                        }
                    }
                }
            }
        }

        // ════════ RIGHT column: media (big, with controls) ════════
        Card {
            Layout.fillHeight: true
            Layout.preferredWidth: 280

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                // Album art
                ClippingRectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 4
                    implicitWidth: 190; implicitHeight: 190
                    radius: 16
                    color: pane.theme.surface2
                    Text {
                        anchors.centerIn: parent
                        text: ""
                        color: pane.theme.outline
                        font.family: pane.theme.ff; font.pixelSize: 64
                        visible: art.status !== Image.Ready
                    }
                    Image {
                        id: art
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: pane.artUrlFor(pane.activePlayer)
                        asynchronous: true
                    }
                }

                // Title / artist
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: pane.activePlayer?.trackTitle || "No media"
                    color: pane.theme.primary
                    font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs + 1
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: pane.activePlayer?.trackArtist || "—"
                    color: pane.theme.txt2
                    font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                    elide: Text.ElideRight
                }

                // Progress bar
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 16
                    Layout.topMargin: 2
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 4; radius: 2
                        color: pane.theme.surface2
                        Rectangle {
                            width: parent.width * pane.progress
                            height: parent.height; radius: 2
                            color: pane.theme.primary
                        }
                    }
                    // Draggable handle
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: pane.theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(parent.width - width, parent.width * pane.progress - width / 2))
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: (pane.activePlayer?.canSeek ?? false) && (pane.activePlayer?.positionSupported ?? false)
                        onClicked: e => {
                            const frac = Math.max(0, Math.min(1, e.x / width))
                            if (pane.activePlayer) pane.activePlayer.position = frac * pane.activePlayer.length
                        }
                    }
                }

                // Position / duration
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 14
                    Text {
                        anchors.left: parent.left
                        text: pane.fmtTime(pane.activePlayer?.position ?? 0)
                        color: pane.theme.outline
                        font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
                    }
                    Text {
                        anchors.right: parent.right
                        text: pane.fmtTime(pane.activePlayer?.length ?? 0)
                        color: pane.theme.outline
                        font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
                    }
                }

                Item { Layout.fillHeight: true }   // push controls toward the bottom

                // Transport controls
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 4
                    spacing: 16

                    CtrlBtn {
                        icon: ""
                        enabled: pane.activePlayer?.canGoPrevious ?? false
                        onClicked: pane.activePlayer?.previous()
                    }
                    CtrlBtn {
                        icon: pane.activePlayer?.playbackState === MprisPlaybackState.Playing ? "" : ""
                        big: true
                        enabled: pane.activePlayer?.canTogglePlaying ?? false
                        onClicked: pane.activePlayer?.togglePlaying()
                    }
                    CtrlBtn {
                        icon: ""
                        enabled: pane.activePlayer?.canGoNext ?? false
                        onClicked: pane.activePlayer?.next()
                    }
                }
            }
        }
    }

    // ── Components ───────────────────────────────────────────────────────
    component Card: Rectangle {
        color: pane.theme.surface
        radius: 14
        border.color: pane.theme.sep
        border.width: 1
    }

    component InfoRow: RowLayout {
        property string icon: ""
        property string value: ""
        spacing: 10
        Text {
            text: parent.icon
            color: pane.theme.secondary
            font.family: pane.theme.ff; font.pixelSize: pane.theme.fs + 2
            Layout.preferredWidth: 22
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            Layout.fillWidth: true
            text: parent.value
            color: pane.theme.fg
            font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs
            elide: Text.ElideRight
        }
    }

    component ResBar: Item {
        id: rb
        required property string ic
        required property real   value
        required property color  col
        width: 34; height: 120

        Rectangle {
            id: track
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: icon.top
            anchors.bottomMargin: 6
            width: 12; radius: 6
            color: Qt.darker(pane.theme.surface2, 1.05)

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Math.max(2, track.height * Math.min(1, rb.value))
                radius: 6
                color: rb.col
                Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }
        Text {
            id: icon
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: rb.ic
            color: rb.col
            font.family: pane.theme.ff
            font.pixelSize: pane.theme.fs
        }
    }

    component CtrlBtn: Rectangle {
        id: btn
        signal clicked()
        property string icon: ""
        property bool   big:  false
        property alias  enabled: hitbox.enabled

        implicitWidth:  big ? 50 : 40
        implicitHeight: big ? 50 : 40
        radius: width / 2
        color: hover.hovered ? Qt.lighter(pane.theme.active, 1.5)
                             : (big ? Qt.lighter(pane.theme.active, 1.2) : "transparent")
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
            font.pixelSize: btn.big ? pane.theme.fs + 6 : pane.theme.fs + 2
        }
        MouseArea {
            id: hitbox
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
