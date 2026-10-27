import QtQuick
import Quickshell.Services.UPower
import qs.common.ui

// Settings pane: battery status, bar options and power mode.
Item {
    id: pane

    required property var theme

    function formatSeconds(s) {
        const day = Math.floor(s / 86400)
        const hr  = Math.floor(s / 3600) % 24
        const min = Math.floor(s / 60) % 60
        let comps = []
        if (day > 0) comps.push(day + " d")
        if (hr  > 0) comps.push(hr  + " h")
        if (min > 0) comps.push(min + " min")
        return comps.join(" ") || "< 1 min"
    }

    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev?.isPresent ?? false
    readonly property real pct: Math.max(0, Math.min(1, dev?.percentage ?? 0))
    // UPower reports 0 while it's still estimating.
    readonly property string timeText: {
        if (!present) return ""
        if (UPower.onBattery)
            return dev.timeToEmpty > 0 ? formatSeconds(dev.timeToEmpty) + " remaining" : "Calculating…"
        const t = dev.timeToFull
        return t <= 0 ? "Fully charged" : formatSeconds(t) + " until charged"
    }

    UiPage {
        anchors.fill: parent
        theme: pane.theme

        // ── Status ────────────────────────────────────────────────────────
        UiCard {
            theme: pane.theme
            height: 124

            BatteryIcon {
                id: bigIcon
                anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                theme: pane.theme
                size: 30
            }
            Column {
                anchors {
                    left: bigIcon.right; leftMargin: 22; right: parent.right; rightMargin: 24
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                Row {
                    spacing: 12
                    Text {
                        anchors.baseline: stateText.baseline
                        text: pane.present ? Math.round(pane.pct * 100) + "%" : "No battery"
                        color: pane.theme.fg
                        font.family: pane.theme.ff; font.bold: true
                        font.pixelSize: pane.theme.fs + 14
                    }
                    Text {
                        id: stateText
                        visible: pane.present
                        text: UPower.onBattery ? "On battery" : "Plugged in"
                        color: pane.theme.txt2
                        font.family: pane.theme.ff
                        font.pixelSize: pane.theme.fs - 1
                    }
                }
                Rectangle {
                    visible: pane.present
                    width: parent.width
                    height: 6; radius: 3
                    color: Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.1)
                    Rectangle {
                        width: parent.width * pane.pct
                        height: parent.height; radius: parent.radius
                        color: bigIcon.fillColor
                    }
                }
                Text {
                    text: pane.timeText
                    color: pane.theme.txt2
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 2
                }
            }
        }

        // ── Bar ───────────────────────────────────────────────────────────
        UiGroup {
            theme: pane.theme
            title: "Status bar"

            UiRow {
                theme: pane.theme
                icon: ""
                title: "Show battery percentage"
                subtitle: "Display the charge percentage next to the battery icon in the bar"
                UiSwitch {
                    theme: pane.theme
                    checked: BatteryService.batteryPercentEnabled
                    onToggled: value => BatteryService.setBatteryPercent(value)
                }
            }
        }

        // ── Power mode ────────────────────────────────────────────────────
        UiGroup {
            theme: pane.theme
            title: "Power mode"
            description: "Trade battery life against performance."

            component ModeRow: UiRow {
                id: modeRow
                required property int prof
                theme: pane.theme
                clickable: true
                highlighted: PowerProfiles.profile === prof
                onClicked: PowerProfiles.profile = prof
                Text {
                    visible: modeRow.highlighted
                    text: ""
                    color: pane.theme.primary
                    font.family: pane.theme.ff; font.pixelSize: pane.theme.fs
                }
            }

            ModeRow {
                prof: PowerProfile.PowerSaver
                icon: "󰌪"
                iconColor: pane.theme.tertiary
                title: "Power saver"
                subtitle: "Lower performance for longer battery life"
            }
            ModeRow {
                prof: PowerProfile.Balanced
                icon: ""
                title: "Balanced"
                subtitle: "Performance when you need it, efficiency when you don't"
            }
            ModeRow {
                prof: PowerProfile.Performance
                icon: ""
                iconColor: pane.theme.warn
                title: "Performance"
                subtitle: "Maximum performance, uses more power"
            }
            UiRow {
                visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
                theme: pane.theme
                icon: ""
                iconColor: pane.theme.error
                title: "Performance degraded"
                subtitle: PerformanceDegradationReason.toString(PowerProfiles.degradationReason)
            }
        }
    }
}
