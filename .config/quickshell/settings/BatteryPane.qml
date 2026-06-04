import QtQuick
import Quickshell.Services.UPower

Item {
    id: pane

    required property var theme

    function formatSeconds(s) {
        if (s <= 0) return "Calculating…"
        const day = Math.floor(s / 86400)
        const hr  = Math.floor(s / 3600) % 24
        const min = Math.floor(s / 60) % 60
        let comps = []
        if (day > 0) comps.push(day + " d")
        if (hr  > 0) comps.push(hr  + " h")
        if (min > 0) comps.push(min + " min")
        return comps.join(" ") || "Calculating…"
    }

    function profileLabel(p) {
        if (p === PowerProfile.PowerSaver)   return "Power saver"
        if (p === PowerProfile.Performance)  return "Performance"
        return "Balanced"
    }

    Column {
        anchors.fill: parent
        spacing: 16

        // ── Battery info card ────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 110
            color: Qt.darker(pane.theme.bg, 1.2)
            radius: 12
            border.color: pane.theme.sep
            border.width: 1

            Column {
                anchors { fill: parent; margins: 16 }
                spacing: 8

                Text {
                    text: {
                        const dev = UPower.displayDevice
                        if (!dev?.isPresent) return "No battery detected"
                        const pct = Math.round(dev.percentage * 100)
                        return pct + "% — " + (UPower.onBattery ? "on battery" : "plugged in")
                    }
                    color: pane.theme.fg
                    font.family: pane.theme.ff
                    font.bold: true
                    font.pixelSize: pane.theme.fs + 2
                }

                // Charge bar
                Rectangle {
                    width: parent.width
                    height: 10
                    radius: 5
                    color: Qt.darker(pane.theme.bg, 1.4)
                    visible: UPower.displayDevice?.isPresent ?? false

                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        width:  parent.width * Math.max(0, Math.min(1, (UPower.displayDevice?.percentage ?? 0)))
                        color: {
                            const p = (UPower.displayDevice?.percentage ?? 0) * 100
                            return p < 15 ? "#F38BA8" : p < 30 ? "#FAB387" : "#A6E3A1"
                        }
                    }
                }

                Text {
                    text: {
                        const dev = UPower.displayDevice
                        if (!dev?.isPresent) return ""
                        if (UPower.onBattery) {
                            return pane.formatSeconds(dev.timeToEmpty) + " remaining"
                        } else {
                            const t = dev.timeToFull
                            return t <= 0 ? "Fully charged" : pane.formatSeconds(t) + " until charged"
                        }
                    }
                    color: pane.theme.fg
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs
                }
            }
        }

        // ── Power profile ─────────────────────────────────────────────────
        Text {
            text: "Power profile"
            color: pane.theme.fg
            font.family: pane.theme.ff
            font.bold: true
            font.pixelSize: pane.theme.fs + 1
        }

        Row {
            width: parent.width
            spacing: 8

            component ProfileBtn: Rectangle {
                required property string label
                required property string icon
                required property int    prof

                width:  (pane.width - 16) / 3
                height: 70
                radius: 12
                color:  PowerProfiles.profile === prof
                        ? Qt.lighter(pane.theme.active, 1.6)
                        : (hov.hovered ? Qt.lighter(pane.theme.bg, 1.25) : Qt.darker(pane.theme.bg, 1.2))
                border.color: PowerProfiles.profile === prof ? "#A6E3A1" : pane.theme.sep
                border.width: PowerProfiles.profile === prof ? 2 : 1

                HoverHandler { id: hov }

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: parent.parent.icon
                        color: pane.theme.fg
                        font.family: pane.theme.ff
                        font.pixelSize: pane.theme.fs + 6
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: parent.parent.label
                        color: pane.theme.fg
                        font.family: pane.theme.ff
                        font.bold: true
                        font.pixelSize: pane.theme.fs - 1
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: PowerProfiles.profile = parent.prof
                }
            }

            ProfileBtn { label: "Power saver"; icon: "󰌪"; prof: PowerProfile.PowerSaver  }
            ProfileBtn { label: "Balanced";    icon: "";  prof: PowerProfile.Balanced    }
            ProfileBtn { label: "Performance"; icon: "";  prof: PowerProfile.Performance }
        }

        // ── Performance-degradation warning ──────────────────────────────
        Rectangle {
            visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
            width: parent.width
            height: 50
            radius: 10
            color: "#80F38BA8"
            border.color: "#F38BA8"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "⚠  Performance degraded: " + PerformanceDegradationReason.toString(PowerProfiles.degradationReason)
                color: pane.theme.fg
                font.family: pane.theme.ff
                font.bold: true
                font.pixelSize: pane.theme.fs
            }
        }
    }
}
