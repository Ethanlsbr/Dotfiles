import QtQuick
import Quickshell
import qs.common
import qs.common.ui
import qs.modules.settings

// Bar popup page: volume + output-device picker (hover the volume module).
Item {
    id: popup

    required property var theme
    implicitHeight: col.implicitHeight + 24

    function volIcon() {
        if (AudioService.volMuted) return "󰝟"
        const v = AudioService.volPct
        return v < 33 ? "󰕿" : v < 67 ? "󰖀" : "󰕾"
    }
    // Device names share the sound card's name ("Raptor Lake-P/U/H cAVS
    // HDMI …", "… Speaker"); drop that common prefix so rows stay distinct
    // in the narrow popup.
    readonly property string commonPrefix: {
        const ds = (AudioService.sinkList || []).map(x => x.desc || "")
        if (ds.length < 2) return ""
        let p = ds[0]
        for (const d of ds) while (p && d.indexOf(p) !== 0) p = p.slice(0, -1)
        const cut = p.lastIndexOf(" ")
        return cut > 0 ? p.slice(0, cut + 1) : ""
    }
    function shortName(desc) {
        const d = desc || ""
        const t = commonPrefix && d.indexOf(commonPrefix) === 0 ? d.slice(commonPrefix.length) : d
        return t.trim() || d
    }

    function sinkIcon(desc) {
        const d = (desc || "").toLowerCase()
        if (d.indexOf("hdmi") >= 0 || d.indexOf("displayport") >= 0) return ""
        if (d.indexOf("headphone") >= 0 || d.indexOf("headset") >= 0 || d.indexOf("bluez") >= 0) return ""
        return ""
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 10

        // ── Header ───────────────────────────────────────────────
        UiRow {
            theme: popup.theme
            compact: true
            showDivider: false
            icon: popup.volIcon()
            iconColor: AudioService.volMuted ? popup.theme.outline : popup.theme.primary
            title: "Sound"
            subtitle: AudioService.volMuted ? "Muted"
                    : (AudioService.volPct < 0 ? "--" : AudioService.volPct) + "% volume"
            GearButton {
                theme: popup.theme
                onClicked: {
                    PopupService.sinkPopupOpen = false
                    SettingsService.openSettings("audio")
                }
            }
        }

        // ── Volume ───────────────────────────────────────────────
        UiCard {
            theme: popup.theme
            height: 52

            // Mute toggle.
            Rectangle {
                id: muteBtn
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                width: 32; height: 32; radius: 8
                readonly property color tint: AudioService.volMuted ? popup.theme.outline : popup.theme.primary
                color: Qt.rgba(tint.r, tint.g, tint.b, muteHover.hovered ? 0.25 : 0.15)
                HoverHandler { id: muteHover }
                Text {
                    anchors.centerIn: parent
                    text: popup.volIcon()
                    color: muteBtn.tint
                    font.family: popup.theme.ff; font.pixelSize: popup.theme.fs
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: AudioService.toggleMute()
                }
            }
            UiSlider {
                anchors { left: muteBtn.right; leftMargin: 12; right: volLabel.left; rightMargin: 10
                          verticalCenter: parent.verticalCenter }
                theme: popup.theme
                value: (AudioService.volPct < 0 ? 0 : AudioService.volPct) / 100
                tint: AudioService.volMuted ? popup.theme.outline : popup.theme.primary
                onMoved: frac => AudioService.setVolumePct(frac * 100)
            }
            Text {
                id: volLabel
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: 36
                horizontalAlignment: Text.AlignRight
                text: (AudioService.volPct < 0 ? "--" : AudioService.volPct) + "%"
                color: popup.theme.fg
                font.family: popup.theme.ff; font.bold: true; font.pixelSize: popup.theme.fs - 2
            }
        }

        // ── Output devices ───────────────────────────────────────
        UiCard {
            theme: popup.theme
            height: outCol.implicitHeight
            Column {
                id: outCol
                width: parent.width
                Repeater {
                    model: AudioService.sinkList
                    delegate: UiRow {
                        id: sinkRow
                        required property var modelData
                        theme: popup.theme
                        compact: true
                        clickable: true
                        highlighted: modelData.active
                        icon: popup.sinkIcon(modelData.desc)
                        iconColor: modelData.active ? popup.theme.primary : popup.theme.txt2
                        title: popup.shortName(modelData.desc)
                        onClicked: if (!modelData.active) AudioService.switchSink(modelData.name)
                        Text {
                            visible: sinkRow.modelData.active
                            text: ""
                            color: popup.theme.primary
                            font.family: popup.theme.ff; font.pixelSize: popup.theme.fs - 1
                        }
                    }
                }
            }
        }
    }
}
