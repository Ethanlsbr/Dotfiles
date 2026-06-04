import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

Item {
    id: pane
    required property var shellRoot
    required property var theme

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

                // Tint fill behind based on usage
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * pane.shellRoot.cpuPerc
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
                        visible: pane.shellRoot.cpuTempC > 0
                        spacing: 4
                        Text {
                            anchors.right: parent.right
                            text: Math.round(pane.shellRoot.cpuTempC) + "°C"
                            color: pane.shellRoot.cpuTempC >= 85 ? pane.theme.error
                                 : pane.shellRoot.cpuTempC >= 70 ? pane.theme.warn
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
                        text: Math.round(pane.shellRoot.cpuPerc * 100) + "%"
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
                                value: pane.shellRoot.memPerc
                                accent: pane.theme.tertiary
                                track:  pane.theme.surface2
                                label:  Math.round(pane.shellRoot.memPerc * 100) + "%"
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: (pane.shellRoot.memUsedKib / 1024 / 1024).toFixed(1)
                                  + " / " + (pane.shellRoot.memTotalKib / 1024 / 1024).toFixed(1) + " GiB"
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
                                text: "Storage — " + pane.shellRoot.diskMount
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
                                value: pane.shellRoot.diskPerc
                                accent: pane.theme.secondary
                                track:  pane.theme.surface2
                                label:  Math.round(pane.shellRoot.diskPerc * 100) + "%"
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: pane.fmtBytes(pane.shellRoot.diskUsedB) + " / " + pane.fmtBytes(pane.shellRoot.diskTotalB)
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
                                series: pane.shellRoot.netDownHistory
                                col:    pane.theme.primary
                            }
                            Sparkline {
                                anchors.fill: parent
                                series: pane.shellRoot.netUpHistory
                                col:    pane.theme.secondary
                            }
                        }

                        Row {
                            Layout.fillWidth: true
                            spacing: 12
                            Text {
                                text: "  " + pane.fmtRate(pane.shellRoot.netDownBps)
                                color: pane.theme.primary
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs - 2
                            }
                            Text {
                                text: "  " + pane.fmtRate(pane.shellRoot.netUpBps)
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

            // background fill
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: parent.height * (UPower.displayDevice?.percentage ?? 0)
                color: Qt.alpha(pane.theme.tertiary, 0.18)
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

    // Simple arc gauge using a Canvas
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

    // Simple sparkline using a Canvas
    component Sparkline: Item {
        id: spark
        property var   series: []
        property color col:    pane.theme.primary

        Canvas {
            id: sparkCanvas
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const s = spark.series || []
                if (s.length < 2) return
                let mx = 1024
                for (let i = 0; i < s.length; i++) if (s[i] > mx) mx = s[i]
                ctx.lineWidth = 1.5
                ctx.strokeStyle = spark.col
                ctx.beginPath()
                const dx = width / (s.length - 1)
                for (let i = 0; i < s.length; i++) {
                    const x = i * dx
                    const y = height - (s[i] / mx) * height * 0.95 - 2
                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                }
                ctx.stroke()
                ctx.lineTo(width, height)
                ctx.lineTo(0, height)
                ctx.closePath()
                ctx.fillStyle = Qt.alpha(spark.col, 0.18)
                ctx.fill()
            }
            Connections {
                target: spark
                function onSeriesChanged() { sparkCanvas.requestPaint() }
            }
        }
    }
}
