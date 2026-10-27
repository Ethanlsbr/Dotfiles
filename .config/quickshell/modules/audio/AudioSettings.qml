import QtQuick
import qs.common.ui

// Settings pane: output/input volume, output/input device pickers and
// card profiles.
Item {
    id: pane

    required property var theme

    // Which card's profile list is expanded ("" = none).
    property string openCard: ""

    function volIcon() {
        if (AudioService.volMuted) return "󰝟"
        const v = AudioService.volPct
        return v < 33 ? "󰕿" : v < 67 ? "󰖀" : "󰕾"
    }
    function sinkIcon(desc) {
        const d = (desc || "").toLowerCase()
        if (d.indexOf("hdmi") >= 0 || d.indexOf("displayport") >= 0) return ""
        if (d.indexOf("headphone") >= 0 || d.indexOf("headset") >= 0 || d.indexOf("bluez") >= 0) return ""
        return ""
    }

    // Selectable device row (output or input), check mark when active.
    component DeviceRow: UiRow {
        id: devRow
        required property var modelData
        signal pick(string name)
        theme: pane.theme
        title: modelData.desc
        clickable: true
        highlighted: modelData.active
        iconColor: modelData.active ? pane.theme.primary : pane.theme.txt2
        onClicked: if (!modelData.active) pick(modelData.name)
        Text {
            visible: devRow.modelData.active
            text: ""
            color: pane.theme.primary
            font.family: pane.theme.ff; font.pixelSize: pane.theme.fs
        }
    }

    // Mute button + labelled slider; the first row of the Output and Input
    // cards, so each level sits with the devices it controls.
    component VolumeRow: Item {
        id: volCard
        property string label
        property string icon
        property int    pct: -1
        property bool   muted: false
        signal moved(real pct)
        signal toggleMute()

        readonly property color tint: muted ? pane.theme.outline : pane.theme.primary
        width: parent ? parent.width : 0
        height: 84

        Rectangle {
            id: muteBtn
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            width: 44; height: 44; radius: 12
            color: Qt.rgba(volCard.tint.r, volCard.tint.g, volCard.tint.b, muteHover.hovered ? 0.25 : 0.15)
            Behavior on color { ColorAnimation { duration: 120 } }
            HoverHandler { id: muteHover }
            Text {
                anchors.centerIn: parent
                text: volCard.icon
                color: volCard.tint
                font.family: pane.theme.ff; font.pixelSize: pane.theme.fs + 7
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: volCard.toggleMute()
            }
        }

        Column {
            anchors { left: muteBtn.right; leftMargin: 16; right: parent.right; rightMargin: 20
                      verticalCenter: parent.verticalCenter }
            spacing: 10

            Row {
                spacing: 10
                Text {
                    text: volCard.label
                    color: pane.theme.fg
                    font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs - 1
                }
                Text {
                    text: volCard.muted ? "Muted" : (volCard.pct < 0 ? "--" : volCard.pct) + "%"
                    color: volCard.tint
                    font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs - 1
                }
            }

            UiSlider {
                width: parent.width
                theme: pane.theme
                tint: volCard.tint
                value: (volCard.pct < 0 ? 0 : volCard.pct) / 100
                onMoved: frac => volCard.moved(frac * 100)
            }
        }
    }

    UiPage {
        anchors.fill: parent
        theme: pane.theme

        // ── Output: volume + devices ──────────────────────────────────────
        UiGroup {
            theme: pane.theme
            title: "Output"
            actions: [
                UiButton {
                    theme: pane.theme
                    icon: ""
                    text: "Pavucontrol"
                    onClicked: AudioService.launchPavucontrol()
                }
            ]
            VolumeRow {
                label: "Volume"
                icon: pane.volIcon()
                pct: AudioService.volPct
                muted: AudioService.volMuted
                onMoved: p => AudioService.setVolumePct(p)
                onToggleMute: AudioService.toggleMute()
            }
            Repeater {
                model: AudioService.sinkList
                delegate: DeviceRow {
                    icon: pane.sinkIcon(modelData.desc)
                    onPick: name => AudioService.switchSink(name)
                }
            }
        }

        // ── Output profile (per card; click to expand the choices) ────────
        UiGroup {
            theme: pane.theme
            visible: AudioService.cardList.length > 0
            title: "Output profile"
            description: "How the sound card exposes its outputs (stereo, HDMI, headset…)."

            Repeater {
                model: AudioService.cardList
                delegate: Column {
                    id: cardDelegate
                    required property var modelData
                    readonly property bool open: pane.openCard === modelData.name
                    readonly property var activeProfile: {
                        const ps = modelData.profiles
                        for (let i = 0; i < ps.length; i++) if (ps[i].active) return ps[i]
                        return null
                    }
                    width: parent.width

                    UiRow {
                        theme: pane.theme
                        icon: ""
                        title: AudioService.cardList.length > 1 ? cardDelegate.modelData.desc : "Profile"
                        subtitle: cardDelegate.activeProfile ? cardDelegate.activeProfile.desc : "—"
                        clickable: true
                        onClicked: pane.openCard = cardDelegate.open ? "" : cardDelegate.modelData.name
                        Text {
                            text: ""
                            rotation: cardDelegate.open ? 180 : 0
                            color: pane.theme.txt2
                            font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                            Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                    }

                    Repeater {
                        model: cardDelegate.open ? cardDelegate.modelData.profiles : []
                        delegate: Item {
                            id: profRow
                            required property var modelData
                            width: parent.width
                            height: 40
                            opacity: modelData.available ? 1 : 0.4

                            Rectangle {
                                anchors { fill: parent; leftMargin: 56; rightMargin: 12; topMargin: 2; bottomMargin: 2 }
                                radius: 8
                                color: profRow.modelData.active
                                       ? Qt.rgba(pane.theme.primary.r, pane.theme.primary.g, pane.theme.primary.b, 0.14)
                                       : (profHover.hovered ? Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.05) : "transparent")
                                HoverHandler { id: profHover; enabled: profRow.modelData.available }
                                Text {
                                    anchors { left: parent.left; leftMargin: 12; right: profCheck.left; rightMargin: 8
                                              verticalCenter: parent.verticalCenter }
                                    text: profRow.modelData.desc
                                    color: pane.theme.fg
                                    font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                                    elide: Text.ElideRight
                                }
                                Text {
                                    id: profCheck
                                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    visible: profRow.modelData.active
                                    text: ""
                                    color: pane.theme.primary
                                    font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: profRow.modelData.available
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!profRow.modelData.active)
                                            AudioService.setCardProfile(cardDelegate.modelData.name, profRow.modelData.key)
                                        pane.openCard = ""
                                    }
                                }
                            }
                        }
                    }
                    Item { width: 1; height: cardDelegate.open ? 8 : 0 }
                }
            }
        }

        // ── Input: volume + devices ───────────────────────────────────────
        UiGroup {
            theme: pane.theme
            title: "Input"
            VolumeRow {
                label: "Volume"
                icon: AudioService.micMuted ? "\udb80\udf6d" : "\udb80\udf6c"
                pct: AudioService.micPct
                muted: AudioService.micMuted
                onMoved: p => AudioService.setMicVolumePct(p)
                onToggleMute: AudioService.toggleMicMute()
            }
            Repeater {
                model: AudioService.sourceList
                delegate: DeviceRow {
                    icon: ""
                    onPick: name => AudioService.switchSource(name)
                }
            }
        }
    }

    // Refresh device lists on mount — otherwise they stay empty until a
    // PipeWire event fires while settings is open.
    Component.onCompleted: {
        AudioService.refreshSinks()
        AudioService.refreshSources()
        AudioService.refreshCards()
        AudioService.refreshMicVolume()
    }
}
