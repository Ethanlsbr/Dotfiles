import QtQuick
import Quickshell

// Output device picker — anchored top-right under the bar's exclusive zone.
PanelWindow {
    id: overlay

    required property var  shellRoot
    required property var  theme
    required property real anchorWidth

    readonly property bool _open: shellRoot.sinkPopupOpen && shellRoot.sinkList.length > 0

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

    implicitWidth:  Math.max(anchorWidth, 240)
    implicitHeight: col.implicitHeight + 16

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

        HoverHandler {
            onHoveredChanged: hovered ? overlay.shellRoot.stopHideTimer("sink")
                                      : overlay.shellRoot.startHideTimer("sink")
        }

        Column {
            id: col
            anchors { fill: parent; margins: 8 }
            spacing: 2

            Repeater {
                model: overlay.shellRoot.sinkList
                delegate: Rectangle {
                    required property var modelData
                    width: col.width
                    height: 28
                    radius: 7
                    color: modelData.active ? Qt.lighter(overlay.theme.active, 1.4) : "transparent"

                    Text {
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left;  leftMargin:  10
                            right: parent.right; rightMargin: 10
                        }
                        text:  modelData.desc
                        color: overlay.theme.fg
                        font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 1
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: overlay.shellRoot.switchSink(modelData.name)
                    }
                }
            }

            // ── Volume slider ──────────────────────────────────────────
            Item { width: 1; height: 4 }   // small spacer

            Row {
                width: col.width
                height: 26
                spacing: 8

                // Mute toggle / level icon
                Text {
                    id: volIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    horizontalAlignment: Text.AlignHCenter
                    text: {
                        if (overlay.shellRoot.volMuted)   return "󰝟"
                        const v = overlay.shellRoot.volPct
                        if (v < 0)  return "󰕿"
                        return v < 33 ? "󰕿" : v < 67 ? "󰖀" : "󰕾"
                    }
                    color: overlay.shellRoot.volMuted ? overlay.theme.outline : overlay.theme.fg
                    font.family: overlay.theme.ff
                    font.pixelSize: overlay.theme.fs

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: overlay.shellRoot.toggleMute()
                    }
                }

                Rectangle {
                    id: volTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: col.width - volIcon.width - volLabel.width - 16
                    height: 8
                    radius: 4
                    color: overlay.theme.field

                    Rectangle {
                        id: volFill
                        height: parent.height
                        radius: parent.radius
                        width: parent.width * Math.max(0, Math.min(1,
                                (overlay.shellRoot.volPct < 0 ? 0 : overlay.shellRoot.volPct) / 100))
                        color: overlay.shellRoot.volMuted ? "#6c7086" : "#A6E3A1"
                    }

                    // Draggable handle dot at the fill edge.
                    Rectangle {
                        width: 14; height: 14; radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(parent.width - width, volFill.width - width / 2))
                        color: overlay.shellRoot.volMuted ? "#6c7086" : "#A6E3A1"
                        border.color: overlay.theme.bg
                        border.width: 2
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed:         overlay.shellRoot.setVolumePct(mouseX / width * 100)
                        onPositionChanged: if (pressed) overlay.shellRoot.setVolumePct(mouseX / width * 100)
                    }
                }

                Text {
                    id: volLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38
                    horizontalAlignment: Text.AlignRight
                    text: (overlay.shellRoot.volPct < 0 ? "--" : overlay.shellRoot.volPct) + "%"
                    color: overlay.theme.fg
                    font.family: overlay.theme.ff
                    font.pixelSize: overlay.theme.fs - 2
                }
            }

            Item { width: 1; height: 4 }   // small spacer

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
                        overlay.shellRoot.sinkPopupOpen = false
                        overlay.shellRoot.openSettings("audio")
                    }
                }
            }
        }
    }
}
