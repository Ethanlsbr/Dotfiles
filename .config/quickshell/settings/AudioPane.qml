import QtQuick

Item {
    id: pane

    required property var shellRoot
    required property var theme

    Column {
        anchors.fill: parent
        spacing: 16

        // ── Output devices ────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Output devices"
                color: pane.theme.fg
                font.family: pane.theme.ff
                font.bold: true
                font.pixelSize: pane.theme.fs + 1
                width: parent.width - pavuBtn.width - 8
            }

            // Launch pavucontrol
            Rectangle {
                id: pavuBtn
                anchors.verticalCenter: parent.verticalCenter
                width: 180; height: 28
                radius: 8
                color: pavuHover.hovered
                       ? Qt.lighter(pane.theme.active, 1.4)
                       : Qt.darker(pane.theme.bg, 1.2)
                border.color: pane.theme.sep
                border.width: 1

                HoverHandler { id: pavuHover }

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰕾"
                        color: pane.theme.fg
                        font.family: pane.theme.ff
                        font.pixelSize: pane.theme.fs - 1
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Open in pavucontrol"
                        color: pane.theme.fg
                        font.family: pane.theme.ff
                        font.pixelSize: pane.theme.fs - 1
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pane.shellRoot.launchPavucontrol()
                }
            }
        }

        Rectangle {
            width: parent.width
            height: outCol.implicitHeight + 12
            color: Qt.darker(pane.theme.bg, 1.2)
            radius: 12
            border.color: pane.theme.sep
            border.width: 1

            Column {
                id: outCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 2

                Repeater {
                    model: pane.shellRoot.sinkList
                    delegate: Rectangle {
                        required property var modelData
                        width:  outCol.width
                        height: 34
                        radius: 8
                        color: sinkHover.hovered
                                ? Qt.lighter(pane.theme.active, 1.2)
                                : (modelData.active ? Qt.lighter(pane.theme.active, 1.4) : "transparent")

                        HoverHandler { id: sinkHover }

                        Row {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.active ? "●" : "○"
                                color: modelData.active ? "#A6E3A1" : pane.theme.fg
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.desc
                                color: pane.theme.fg
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs
                                elide: Text.ElideRight
                                width: outCol.width - 60
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pane.shellRoot.switchSink(modelData.name)
                        }
                    }
                }
            }
        }

        // ── Volume slider ─────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 12

            // Mute toggle / level icon
            Text {
                id: volIcon
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                horizontalAlignment: Text.AlignHCenter
                text: {
                    if (pane.shellRoot.volMuted)   return "󰝟"
                    const v = pane.shellRoot.volPct
                    if (v < 0)  return "󰕿"
                    return v < 33 ? "󰕿" : v < 67 ? "󰖀" : "󰕾"
                }
                color: pane.shellRoot.volMuted ? pane.theme.outline : pane.theme.fg
                font.family: pane.theme.ff
                font.pixelSize: pane.theme.fs + 2

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pane.shellRoot.toggleMute()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pane.shellRoot.volMuted
                      ? "Muted"
                      : (pane.shellRoot.volPct < 0 ? "--" : pane.shellRoot.volPct) + "%"
                color: pane.theme.fg
                font.family: pane.theme.ff
                font.bold: true
                font.pixelSize: pane.theme.fs
                width: 70
            }

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: pane.width - 24 - 70 - 24
                height: 8
                radius: 4
                color: pane.theme.field

                Rectangle {
                    id: volFill
                    height: parent.height
                    radius: parent.radius
                    width: parent.width * Math.max(0, Math.min(1, (pane.shellRoot.volPct < 0 ? 0 : pane.shellRoot.volPct) / 100))
                    color: pane.shellRoot.volMuted ? "#6c7086" : "#A6E3A1"
                }

                // Draggable handle dot at the fill edge.
                Rectangle {
                    width: 16; height: 16; radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(parent.width - width, volFill.width - width / 2))
                    color: pane.shellRoot.volMuted ? "#6c7086" : "#A6E3A1"
                    border.color: pane.theme.bg
                    border.width: 2
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: pane.shellRoot.setVolumePct(mouseX / width * 100)
                    onPositionChanged: if (pressed) pane.shellRoot.setVolumePct(mouseX / width * 100)
                }
            }
        }

        // ── Input devices ─────────────────────────────────────────────────
        Text {
            text: "Input devices"
            color: pane.theme.fg
            font.family: pane.theme.ff
            font.bold: true
            font.pixelSize: pane.theme.fs + 1
        }

        Rectangle {
            width: parent.width
            height: inCol.implicitHeight + 12
            color: Qt.darker(pane.theme.bg, 1.2)
            radius: 12
            border.color: pane.theme.sep
            border.width: 1

            Column {
                id: inCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 2

                Repeater {
                    model: pane.shellRoot.sourceList
                    delegate: Rectangle {
                        required property var modelData
                        width:  inCol.width
                        height: 34
                        radius: 8
                        color: srcHover.hovered
                                ? Qt.lighter(pane.theme.active, 1.2)
                                : (modelData.active ? Qt.lighter(pane.theme.active, 1.4) : "transparent")

                        HoverHandler { id: srcHover }

                        Row {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.active ? "●" : "○"
                                color: modelData.active ? "#A6E3A1" : pane.theme.fg
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.desc
                                color: pane.theme.fg
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs
                                elide: Text.ElideRight
                                width: inCol.width - 60
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pane.shellRoot.switchSource(modelData.name)
                        }
                    }
                }
            }
        }
    }

    // Refresh both device lists whenever this pane mounts (otherwise the
    // output list stays empty until a PipeWire event happens to fire while
    // settings is open).
    Component.onCompleted: {
        pane.shellRoot.refreshSinks()
        pane.shellRoot.refreshSources()
    }
}
