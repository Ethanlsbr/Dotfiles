import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.common
import qs.common.ui
import qs.modules.settings

// Bar popup page: charge %, time remaining + power mode (hover the battery).
Item {
    id: popup

    required property var theme
    implicitHeight: col.implicitHeight + 24

    function formatSeconds(s) {
        const hr  = Math.floor(s / 3600)
        const min = Math.floor(s / 60) % 60
        let comps = []
        if (hr  > 0) comps.push(hr  + " h")
        if (min > 0) comps.push(min + " min")
        return comps.join(" ") || "< 1 min"
    }
    // UPower reports 0 while it's still estimating ("Calculating…" alone,
    // not "Calculating… remaining").
    readonly property string timeText: {
        const dev = UPower.displayDevice
        if (!dev?.isPresent) return ""
        if (UPower.onBattery)
            return dev.timeToEmpty > 0 ? formatSeconds(dev.timeToEmpty) + " remaining" : "Calculating…"
        const t = dev.timeToFull
        return t <= 0 ? "Fully charged" : formatSeconds(t) + " until charged"
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 10

        // ── Header: icon, percentage, time remaining ─────────────
        Item {
            width: parent.width
            height: 50

            Rectangle {
                id: tile
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                width: 30; height: 30; radius: 8
                color: Qt.rgba(popup.theme.primary.r, popup.theme.primary.g, popup.theme.primary.b, 0.15)
                BatteryIcon {
                    anchors.centerIn: parent
                    theme: popup.theme
                    size: 11
                }
            }
            Column {
                anchors { left: tile.right; leftMargin: 10; right: gear.left; rightMargin: 10
                          verticalCenter: parent.verticalCenter }
                spacing: 3
                Row {
                    spacing: 8
                    Text {
                        anchors.baseline: stateText.baseline
                        text: Math.round((UPower.displayDevice?.percentage ?? 0) * 100) + "%"
                        color: popup.theme.fg
                        font.family: popup.theme.ff; font.bold: true; font.pixelSize: popup.theme.fs + 2
                    }
                    Text {
                        id: stateText
                        text: UPower.onBattery ? "On battery" : "Plugged in"
                        color: popup.theme.txt2
                        font.family: popup.theme.ff; font.pixelSize: popup.theme.fs - 3
                    }
                }
                Text {
                    width: parent.width
                    text: popup.timeText
                    color: popup.theme.txt2
                    font.family: popup.theme.ff; font.pixelSize: popup.theme.fs - 3
                    elide: Text.ElideRight
                }
            }
            GearButton {
                id: gear
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                theme: popup.theme
                onClicked: {
                    PopupService.batteryPopupOpen = false
                    SettingsService.openSettings("battery")
                }
            }
        }

        // ── Power mode ───────────────────────────────────────────
        UiCard {
            theme: popup.theme
            height: modeRow.height + 12

            Row {
                id: modeRow
                anchors.centerIn: parent
                width: parent.width - 12
                height: 38
                spacing: 4

                component ModeBtn: Rectangle {
                    id: mb
                    required property string label
                    required property string icon
                    required property int    prof
                    property color tint: popup.theme.primary
                    readonly property bool current: PowerProfiles.profile === prof

                    width: (modeRow.width - 8) / 3
                    height: modeRow.height
                    radius: 8
                    color: current ? Qt.rgba(tint.r, tint.g, tint.b, 0.18)
                         : (mbHover.hovered ? Qt.rgba(popup.theme.fg.r, popup.theme.fg.g, popup.theme.fg.b, 0.05) : "transparent")
                    border.color: current ? Qt.rgba(tint.r, tint.g, tint.b, 0.6) : "transparent"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: mbHover }

                    // Icon only (label names the mode in code).
                    Text {
                        anchors.centerIn: parent
                        text: mb.icon
                        color: mb.current ? mb.tint : popup.theme.txt2
                        font.family: popup.theme.ff; font.pixelSize: popup.theme.fs + 2
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PowerProfiles.profile = mb.prof
                    }
                }

                ModeBtn { label: "Saver";       icon: "󰌪"; prof: PowerProfile.PowerSaver;  tint: popup.theme.tertiary }
                ModeBtn { label: "Balanced";    icon: "";       prof: PowerProfile.Balanced }
                ModeBtn { label: "Performance"; icon: "";       prof: PowerProfile.Performance; tint: popup.theme.warn }
            }
        }
    }
}
