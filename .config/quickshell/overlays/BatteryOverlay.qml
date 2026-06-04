import QtQuick
import Quickshell
import Quickshell.Services.UPower

PanelWindow {
    id: overlay

    required property var  shellRoot
    required property var  theme
    required property real anchorWidth

    readonly property bool _open: shellRoot.batteryPopupOpen && (UPower.displayDevice?.isPresent ?? false)

    visible: _open || exitAnim.running

    on_OpenChanged: {

        if (_open) { exitAnim.stop(); enterAnim.restart() }

        else       { enterAnim.stop(); exitAnim.restart() }

    }

    anchors { top: true; right: true }
    margins.right: 10
    margins.top:   6      // sit just below the bar (bar exclusiveZone is 34)
    exclusiveZone: 0
    color: "transparent"

    implicitWidth:  Math.max(anchorWidth, 290)
    implicitHeight: col.implicitHeight + 20

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: card;      property: "opacity"; from: 0; to: 1; duration: 360; easing.type: Easing.OutCubic }
        NumberAnimation { target: card;      property: "scale"; from: 0.96; to: 1; duration: 360; easing.type: Easing.OutCubic }
    }
    // Reverse of enterAnim — plays before the panel is hidden so it slides
    // back out instead of snapping away. `visible` stays true while running.
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: card;      property: "opacity"; to: 0;   duration: 280; easing.type: Easing.InCubic }
        NumberAnimation { target: card;      property: "scale"; to: 0.96; duration: 280; easing.type: Easing.InCubic }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        color: overlay.theme.bg
        radius: overlay.theme.pr
        opacity: 0
        scale: 0.96
        transformOrigin: Item.Top

        // HoverHandler tracks geometry — survives the nested-MouseArea race
        // that would otherwise close the popup when child rows take focus.
        HoverHandler {
            onHoveredChanged: hovered ? overlay.shellRoot.stopHideTimer("battery")
                                      : overlay.shellRoot.startHideTimer("battery")
        }

        Column {
            id: col
            anchors { fill: parent; margins: 12 }
            spacing: 8

            // ── Time remaining / until charged ──
            Text {
                function formatSeconds(s) {
                    if (s <= 0) return "Calculating..."
                    const hr  = Math.floor(s / 3600)
                    const min = Math.floor(s / 60) % 60
                    let comps = []
                    if (hr  > 0) comps.push(hr  + " h")
                    if (min > 0) comps.push(min + " min")
                    return comps.join(" ") || "Calculating..."
                }
                text: {
                    const dev = UPower.displayDevice
                    if (!dev?.isPresent) return ""
                    if (UPower.onBattery) {
                        return formatSeconds(dev.timeToEmpty) + " remaining"
                    } else {
                        const t = dev.timeToFull
                        return t <= 0 ? "Fully charged" : formatSeconds(t) + " until charged"
                    }
                }
                color: overlay.theme.fg
                font.family: overlay.theme.ff; font.bold: true; font.pixelSize: overlay.theme.fs
            }

            // ── Power profile selector ──
            Row {
                spacing: 4

                component ProfileBtn: Rectangle {
                    id: pbtn
                    required property string label
                    required property string icon
                    required property int     prof
                    readonly property bool   current: PowerProfiles.profile === prof

                    width:  (col.width - 8) / 3
                    height: 26
                    radius: 8
                    color:  current ? Qt.lighter(overlay.theme.active, 1.6) : "transparent"
                    border.color: overlay.theme.sep
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text:  pbtn.icon
                        color: pbtn.current ? overlay.theme.primary : overlay.theme.fg
                        font.family: overlay.theme.ff
                        font.pixelSize: overlay.theme.fs + 2
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PowerProfiles.profile = pbtn.prof
                    }
                }

                ProfileBtn { label: "Saver";       icon: ""; prof: PowerProfile.PowerSaver   }
                ProfileBtn { label: "Balanced";    icon: ""; prof: PowerProfile.Balanced     }
                ProfileBtn { label: "Performance"; icon: ""; prof: PowerProfile.Performance  }
            }

            // ── Open settings pill ────────────────────────────────────
            Rectangle {
                width: col.width
                height: 32
                radius: 9
                color: settingsBtnHover.hovered
                        ? Qt.lighter(overlay.theme.active, 1.6)
                        : Qt.lighter(overlay.theme.active, 1.3)

                HoverHandler { id: settingsBtnHover }

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: ""; color: overlay.theme.fg; font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs }
                    Text { text: "Open settings"; color: overlay.theme.fg; font.family: overlay.theme.ff; font.bold: true; font.pixelSize: overlay.theme.fs - 1 }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        overlay.shellRoot.batteryPopupOpen = false
                        overlay.shellRoot.openSettings("battery")
                    }
                }
            }
        }
    }
}
