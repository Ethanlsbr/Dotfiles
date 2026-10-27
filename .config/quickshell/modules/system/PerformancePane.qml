import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

Item {
    id: pane
    required property var theme
    // Dashboard open on this tab (set by DashboardOverlay). Readouts and
    // graphs only animate then — samples keep arriving while closed, and
    // their 2 s glides ran back to back, keeping animations ticking forever.
    property bool live: true

    function fmtBytes(b) {
        if (b < 1024)        return b.toFixed(0) + " B"
        if (b < 1024 ** 2)   return (b / 1024).toFixed(1) + " KiB"
        if (b < 1024 ** 3)   return (b / 1024 ** 2).toFixed(1) + " MiB"
        if (b < 1024 ** 4)   return (b / 1024 ** 3).toFixed(1) + " GiB"
        return (b / 1024 ** 4).toFixed(1) + " TiB"
    }
    function fmtRate(b) {
        if (b < 1024)        return b.toFixed(0) + " B/s"
        if (b < 1024 ** 2)   return (b / 1024).toFixed(1) + " KB/s"
        return (b / 1024 ** 2).toFixed(1) + " MB/s"
    }

    // Network readouts: average of the last three samples (6 s), gliding
    // over one sample period; the text only refreshes twice a second so the
    // digits don't churn.
    function recentAvg(h) {
        const t = h.slice(-3)
        return t.length ? t.reduce((a, b) => a + b, 0) / t.length : 0
    }
    property real netDown: recentAvg(SystemService.netDownHistory)
    property real netUp:   recentAvg(SystemService.netUpHistory)
    Behavior on netDown { enabled: pane.live; NumberAnimation { duration: 2000; easing.type: Easing.InOutSine } }
    Behavior on netUp   { enabled: pane.live; NumberAnimation { duration: 2000; easing.type: Easing.InOutSine } }
    property string netDownText: fmtRate(0)
    property string netUpText:   fmtRate(0)
    Timer {
        interval: 500; repeat: true; triggeredOnStart: true
        running: pane.live
        onTriggered: {
            pane.netDownText = pane.fmtRate(pane.netDown)
            pane.netUpText   = pane.fmtRate(pane.netUp)
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 10

        // ── Main column: CPU hero, then Memory + Storage + Network ────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // ── CPU hero ──
            Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 140

                // Usage-tinted fill.
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * SystemService.cpuPerc
                    color: Qt.alpha(pane.theme.primary, 0.18)
                    radius: parent.radius
                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 16

                    Text {
                        text: ""
                        color: pane.theme.primary
                        font.family: pane.theme.ff; font.pixelSize: pane.theme.fs + 12
                    }
                    Column {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            text: "CPU"
                            color: pane.theme.fg
                            font.family: pane.theme.ff
                            font.bold: true
                            font.pixelSize: pane.theme.fs + 4
                        }
                        Text {
                            text: "Usage"
                            color: pane.theme.outline
                            font.family: pane.theme.ff
                            font.pixelSize: pane.theme.fs - 2
                        }
                    }
                    // Temperature — colour warms as it climbs.
                    Column {
                        visible: SystemService.cpuTempC > 0
                        spacing: 4
                        Text {
                            anchors.right: parent.right
                            text: Math.round(SystemService.cpuTempC) + "°C"
                            color: SystemService.cpuTempC >= 85 ? pane.theme.error
                                 : SystemService.cpuTempC >= 70 ? pane.theme.warn
                                                                 : pane.theme.tertiary
                            font.family: pane.theme.ff
                            font.bold: true
                            font.pixelSize: pane.theme.fs + 8
                        }
                        Text {
                            anchors.right: parent.right
                            text: "Temp"
                            color: pane.theme.outline
                            font.family: pane.theme.ff
                            font.pixelSize: pane.theme.fs - 2
                        }
                    }
                    Text {
                        text: Math.round(SystemService.cpuPerc * 100) + "%"
                        color: pane.theme.primary
                        font.family: pane.theme.ff
                        font.bold: true
                        font.pixelSize: pane.theme.fs + 20
                    }
                }
            }

            // ── Memory + Storage + Network row ──
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // Memory gauge
                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 220

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 6

                        RowLayout {
                            Text {
                                text: ""
                                color: pane.theme.tertiary
                                font.family: pane.theme.ff; font.pixelSize: pane.theme.fs + 4
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Memory"
                                color: pane.theme.fg
                                font.family: pane.theme.ff
                                font.bold: true
                                font.pixelSize: pane.theme.fs
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ArcGauge {
                                anchors.centerIn: parent
                                width: Math.min(parent.width, parent.height) - 10
                                height: width
                                value: SystemService.memPerc
                                accent: pane.theme.tertiary
                                track:  pane.theme.surface2
                                label:  Math.round(SystemService.memPerc * 100) + "%"
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: (SystemService.memUsedKib / 1024 / 1024).toFixed(1)
                                  + " / " + (SystemService.memTotalKib / 1024 / 1024).toFixed(1) + " GiB"
                            color: pane.theme.outline
                            font.family: pane.theme.ff
                            font.pixelSize: pane.theme.fs - 3
                        }
                    }
                }

                // Storage gauge
                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 220

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 6

                        RowLayout {
                            Text {
                                text: ""
                                color: pane.theme.secondary
                                font.family: pane.theme.ff; font.pixelSize: pane.theme.fs + 4
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Storage — " + SystemService.diskMount
                                color: pane.theme.fg
                                font.family: pane.theme.ff
                                font.bold: true
                                font.pixelSize: pane.theme.fs
                                elide: Text.ElideRight
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ArcGauge {
                                anchors.centerIn: parent
                                width: Math.min(parent.width, parent.height) - 10
                                height: width
                                value: SystemService.diskPerc
                                accent: pane.theme.secondary
                                track:  pane.theme.surface2
                                label:  Math.round(SystemService.diskPerc * 100) + "%"
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: pane.fmtBytes(SystemService.diskUsedB) + " / " + pane.fmtBytes(SystemService.diskTotalB)
                            color: pane.theme.outline
                            font.family: pane.theme.ff
                            font.pixelSize: pane.theme.fs - 3
                        }
                    }
                }

                // Network card (with sparkline)
                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 220

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 6

                        RowLayout {
                            Text {
                                text: ""
                                color: pane.theme.primary
                                font.family: pane.theme.ff; font.pixelSize: pane.theme.fs + 4
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Network"
                                color: pane.theme.fg
                                font.family: pane.theme.ff
                                font.bold: true
                                font.pixelSize: pane.theme.fs
                            }
                        }

                        // Sparkline area
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Sparkline {
                                anchors.fill: parent
                                series: SystemService.netDownHistory
                                col:    pane.theme.primary
                            }
                            Sparkline {
                                anchors.fill: parent
                                series: SystemService.netUpHistory
                                col:    pane.theme.secondary
                            }
                        }

                        Row {
                            Layout.fillWidth: true
                            spacing: 12
                            Text {
                                text: "  " + pane.netDownText
                                color: pane.theme.primary
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs - 2
                            }
                            Text {
                                text: "  " + pane.netUpText
                                color: pane.theme.secondary
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs - 2
                            }
                        }
                    }
                }
            }
        }

        // ── Battery tank (right column, if laptop) ────────────────────
        Card {
            visible: UPower.displayDevice?.isLaptopBattery ?? false
            Layout.preferredWidth: 110
            Layout.fillHeight: true
            clip: true

            // Background fill.
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: parent.height * (UPower.displayDevice?.percentage ?? 0)
                color: Qt.alpha(pane.theme.tertiary, 0.18)
                radius: parent.radius
                Behavior on height { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 4

                Text {
                    text: "󰁹"
                    color: pane.theme.tertiary
                    font.family: pane.theme.ff; font.pixelSize: pane.theme.fs + 6
                }
                Text {
                    text: "Battery"
                    color: pane.theme.fg
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 1
                }
                Item { Layout.fillHeight: true }
                Text {
                    Layout.alignment: Qt.AlignRight
                    text: Math.round((UPower.displayDevice?.percentage ?? 0) * 100) + "%"
                    color: pane.theme.tertiary
                    font.family: pane.theme.ff
                    font.bold: true
                    font.pixelSize: pane.theme.fs + 8
                }
                Text {
                    Layout.alignment: Qt.AlignRight
                    text: {
                        const d = UPower.displayDevice
                        if (!d) return ""
                        if (d.state === UPowerDeviceState.FullyCharged) return "Full"
                        if (d.state === UPowerDeviceState.Charging) return "Charging"
                        const s = d.timeToEmpty
                        if (s <= 0) return "..."
                        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60)
                        return (h > 0 ? h + "h " : "") + m + "m"
                    }
                    color: pane.theme.outline
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 3
                }
            }
        }
    }

    component Card: Rectangle {
        color: pane.theme.surface
        radius: 14
        border.color: pane.theme.sep
        border.width: 1
        clip: true
    }

    // Canvas arc gauge.
    component ArcGauge: Item {
        id: gauge
        property real  value: 0
        property color accent: pane.theme.primary
        property color track:  pane.theme.surface2
        property string label: ""

        Canvas {
            id: canvas
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const cx = width / 2, cy = height / 2
                const r  = Math.min(width, height) / 2 - 8
                const start = 0.75 * Math.PI
                const sweep = 1.5  * Math.PI
                ctx.lineWidth = 10
                ctx.lineCap   = "round"
                ctx.strokeStyle = gauge.track
                ctx.beginPath()
                ctx.arc(cx, cy, r, start, start + sweep)
                ctx.stroke()
                ctx.strokeStyle = gauge.accent
                ctx.beginPath()
                ctx.arc(cx, cy, r, start, start + sweep * gauge.value)
                ctx.stroke()
            }
            Connections {
                target: gauge
                function onValueChanged()  { canvas.requestPaint() }
                function onAccentChanged() { canvas.requestPaint() }
                function onTrackChanged()  { canvas.requestPaint() }
            }
        }

        Text {
            anchors.centerIn: parent
            text: gauge.label
            color: gauge.accent
            font.family: pane.theme.ff
            font.bold: true
            font.pixelSize: pane.theme.fs + 6
        }
    }

    // Canvas sparkline that scrolls continuously: each new sample enters
    // from the right edge over one sample period (`interval`) rather than
    // the whole line stepping left at once, and the vertical scale eases.
    // Samples keep arriving while the dashboard is closed; it only animates
    // while shown (pane.live) and redraws in full on open.
    component Sparkline: Item {
        id: spark
        property var   series: []
        property color col:    pane.theme.primary
        property int   capacity: 30     // SystemService keeps the last 30 samples
        property int   interval: 2000   // SystemService network sampler
        readonly property bool live: pane.live

        property real phase: 1
        property real peak: 1024
        Behavior on peak {
            enabled: spark.live
            NumberAnimation { duration: 800; easing.type: Easing.OutCubic }
        }
        NumberAnimation on phase { id: scroll; from: 0; to: 1; duration: spark.interval; running: false }

        function update() {
            const s = series || []
            let mx = 1024
            for (let i = 0; i < s.length; i++) if (s[i] > mx) mx = s[i]
            peak = mx
            if (live) scroll.restart()
            else { scroll.stop(); phase = 1 }
            sparkCanvas.requestPaint()
        }
        onSeriesChanged: update()
        onLiveChanged:   update()
        Component.onCompleted: update()
        onPhaseChanged: sparkCanvas.requestPaint()
        onPeakChanged:  sparkCanvas.requestPaint()

        Canvas {
            id: sparkCanvas
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const s = spark.series || []
                if (s.length < 2) return
                // Fixed spacing; the newest point sits one step past the right
                // edge at phase 0 and reaches it at phase 1.
                const dx = width / (spark.capacity - 2)
                const pts = []
                for (let i = 0; i < s.length; i++) {
                    const age = s.length - 1 - i
                    pts.push({ x: width + (1 - spark.phase) * dx - age * dx,
                               y: height - (s[i] / spark.peak) * height * 0.95 - 2 })
                }
                ctx.lineWidth = 1.5
                ctx.lineJoin = "round"
                ctx.strokeStyle = spark.col
                ctx.beginPath()
                ctx.moveTo(pts[0].x, pts[0].y)
                // Curve through the midpoints so the line has no corners.
                for (let i = 1; i < pts.length - 1; i++)
                    ctx.quadraticCurveTo(pts[i].x, pts[i].y,
                                         (pts[i].x + pts[i + 1].x) / 2, (pts[i].y + pts[i + 1].y) / 2)
                ctx.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y)
                ctx.stroke()
                ctx.lineTo(pts[pts.length - 1].x, height)
                ctx.lineTo(pts[0].x, height)
                ctx.closePath()
                ctx.fillStyle = Qt.alpha(spark.col, 0.18)
                ctx.fill()
            }
        }
    }
}
