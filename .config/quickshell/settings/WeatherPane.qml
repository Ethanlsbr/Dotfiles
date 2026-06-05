import QtQuick

Item {
    id: pane

    required property var shellRoot
    required property var theme

    // Local edit buffer — flushed on Save
    property string editLoc: shellRoot.weatherLocation

    Column {
        anchors.fill: parent
        spacing: 16

        // ── Current location card ────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 110
            color: Qt.darker(pane.theme.bg, 1.2)
            radius: 12
            border.color: pane.theme.sep
            border.width: 1

            Row {
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                spacing: 16

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pane.shellRoot.weather.ready ? pane.shellRoot.weather.icon : "󰖐"
                    color: pane.theme.secondary
                    font.family: pane.theme.ff; font.pixelSize: pane.theme.fs * 3
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: pane.shellRoot.weather.ready
                              ? (pane.shellRoot.weather.city || "Unknown")
                              : "Loading…"
                        color: pane.theme.fg
                        font.family: pane.theme.ff; font.bold: true
                        font.pixelSize: pane.theme.fs + 2
                    }
                    Text {
                        text: pane.shellRoot.weatherLocation
                              ? "Custom: " + pane.shellRoot.weatherLocation
                              : "Auto-detected via IP"
                        color: pane.theme.outline
                        font.family: pane.theme.ff
                        font.pixelSize: pane.theme.fs - 2
                    }
                    Text {
                        visible: pane.shellRoot.weather.ready
                        text: pane.shellRoot.weather.temp + "  •  " + pane.shellRoot.weather.description
                        color: pane.theme.primary
                        font.family: pane.theme.ff
                        font.pixelSize: pane.theme.fs - 1
                    }
                }
            }
        }

        // ── Location input ────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 6

            Text {
                text: "Location"
                color: pane.theme.fg
                font.family: pane.theme.ff
                font.bold: true
                font.pixelSize: pane.theme.fs - 1
            }
            Text {
                text: "City name, airport code, ZIP, or coordinates. Leave empty to auto-detect by IP."
                color: pane.theme.outline
                font.family: pane.theme.ff
                font.pixelSize: pane.theme.fs - 3
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Rectangle {
                width: parent.width
                height: 36
                radius: 8
                color: pane.theme.field
                border.color: locInput.activeFocus ? pane.theme.primary : pane.theme.sep
                border.width: 1

                TextInput {
                    id: locInput
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: pane.theme.fg
                    selectionColor: pane.theme.hi(1.4)
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 1
                    text: pane.editLoc
                    onTextChanged: pane.editLoc = text
                    onAccepted: pane.shellRoot.setWeatherLocation(text)

                    // Placeholder when empty
                    Text {
                        anchors { fill: parent; leftMargin: 0 }
                        verticalAlignment: TextInput.AlignVCenter
                        visible: locInput.text.length === 0
                        text: "e.g. Paris, NYC, 75001, 48.85,2.35"
                        color: pane.theme.outline
                        font: locInput.font
                    }
                }
            }
        }

        // ── Buttons ───────────────────────────────────────────────────────
        Row {
            spacing: 8

            Rectangle {
                width: 110; height: 32
                radius: 8
                color: saveHover.hovered ? pane.theme.hi(1.6) : pane.theme.hi(1.3)
                HoverHandler { id: saveHover }
                Text {
                    anchors.centerIn: parent
                    text: "Save"
                    color: pane.theme.fg
                    font.family: pane.theme.ff; font.bold: true
                    font.pixelSize: pane.theme.fs - 1
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pane.shellRoot.setWeatherLocation(pane.editLoc)
                }
            }

            Rectangle {
                width: 110; height: 32
                radius: 8
                color: clearHover.hovered ? pane.theme.surface : Qt.darker(pane.theme.bg, 1.2)
                border.color: pane.theme.sep
                border.width: 1
                HoverHandler { id: clearHover }
                Text {
                    anchors.centerIn: parent
                    text: "Auto-detect"
                    color: pane.theme.fg
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 1
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        pane.editLoc = ""
                        locInput.text = ""
                        pane.shellRoot.setWeatherLocation("")
                    }
                }
            }

            Rectangle {
                width: 110; height: 32
                radius: 8
                color: refreshHover.hovered ? pane.theme.surface : Qt.darker(pane.theme.bg, 1.2)
                border.color: pane.theme.sep
                border.width: 1
                HoverHandler { id: refreshHover }
                Text {
                    anchors.centerIn: parent
                    text: "Refresh"
                    color: pane.theme.fg
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 1
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pane.shellRoot.refreshWeather()
                }
            }
        }
    }
}
