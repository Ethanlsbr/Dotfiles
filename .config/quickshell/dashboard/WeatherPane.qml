import QtQuick
import QtQuick.Layouts

Item {
    id: pane
    required property var shellRoot
    required property var theme

    readonly property var w: shellRoot.weather

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 10

        // ── Header: city + date + sunrise/sunset ──
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin:  10
            Layout.rightMargin: 10
            spacing: 12

            Column {
                spacing: 2
                Text {
                    text: pane.w.ready ? (pane.w.city || "Unknown") : "Loading..."
                    color: pane.theme.fg
                    font.family: pane.theme.ff
                    font.bold: true
                    font.pixelSize: pane.theme.fs + 8
                }
                Text {
                    text: new Date().toLocaleDateString(Qt.locale(), "dddd, MMMM d")
                    color: pane.theme.outline
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 2
                }
            }

            Item { Layout.fillWidth: true }

            Row {
                spacing: 18

                SunStat { ic: ""; lbl: "Sunrise"; v: pane.w.sunrise; col: pane.theme.warn }
                SunStat { ic: "";  lbl: "Sunset";  v: pane.w.sunset;  col: pane.theme.secondary }
            }
        }

        // ── Hero: big icon + temp + description ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 130
            radius: 16
            color: pane.theme.surface
            border.color: pane.theme.sep
            border.width: 1

            RowLayout {
                anchors.centerIn: parent
                spacing: 22

                Text {
                    text: pane.w.ready ? pane.w.icon : "󰖐"
                    color: pane.theme.secondary
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs * 5
                }
                Column {
                    spacing: -4
                    Text {
                        text: pane.w.ready ? pane.w.temp : "—"
                        color: pane.theme.primary
                        font.family: pane.theme.ff
                        font.bold: true
                        font.pixelSize: pane.theme.fs * 3
                    }
                    Text {
                        text: pane.w.ready ? pane.w.description : ""
                        color: pane.theme.txt2
                        font.family: pane.theme.ff
                        font.pixelSize: pane.theme.fs
                    }
                }
            }
        }

        // ── Detail cards ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            DetailCard { ic: ""; lbl: "Humidity";   v: pane.w.ready ? pane.w.humidity + "%"     : "—"; col: pane.theme.secondary }
            DetailCard { ic: ""; lbl: "Feels Like"; v: pane.w.ready ? pane.w.feelsLike          : "—"; col: pane.theme.primary }
            DetailCard { ic: ""; lbl: "Wind";       v: pane.w.ready ? pane.w.windKph + " km/h" : "—"; col: pane.theme.tertiary }
        }

        // ── Forecast ──
        Text {
            Layout.leftMargin: 10
            Layout.topMargin: 4
            visible: pane.w.ready && pane.w.forecast.length > 0
            text: "Forecast"
            color: pane.theme.fg
            font.family: pane.theme.ff
            font.bold: true
            font.pixelSize: pane.theme.fs
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: pane.w.ready ? pane.w.forecast : []
                delegate: Rectangle {
                    required property int index
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: 110
                    radius: 12
                    color: pane.theme.surface
                    border.color: pane.theme.sep
                    border.width: 1

                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: index === 0
                                  ? "Today"
                                  : new Date(modelData.date).toLocaleDateString(Qt.locale(), "ddd")
                            color: pane.theme.primary
                            font.family: pane.theme.ff
                            font.bold: true
                            font.pixelSize: pane.theme.fs
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.icon
                            color: pane.theme.secondary
                            font.family: pane.theme.ff
                            font.pixelSize: pane.theme.fs + 14
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.maxTempC + "° / " + modelData.minTempC + "°"
                            color: pane.theme.tertiary
                            font.family: pane.theme.ff
                            font.pixelSize: pane.theme.fs - 2
                            font.bold: true
                        }
                    }
                }
            }
        }
    }

    component SunStat: Row {
        id: ss
        property string ic
        property string lbl
        property string v
        property color  col
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ss.ic
            color: ss.col
            font.family: pane.theme.ff
            font.pixelSize: pane.theme.fs + 6
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
                text: ss.lbl
                color: pane.theme.outline
                font.family: pane.theme.ff
                font.pixelSize: pane.theme.fs - 3
            }
            Text {
                text: ss.v || "—"
                color: pane.theme.fg
                font.family: pane.theme.ff
                font.pixelSize: pane.theme.fs - 1
                font.bold: true
            }
        }
    }

    component DetailCard: Rectangle {
        id: dc
        property string ic
        property string lbl
        property string v
        property color  col

        Layout.fillWidth: true
        Layout.preferredHeight: 64
        radius: 10
        color: pane.theme.surface
        border.color: pane.theme.sep
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: 12
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: dc.ic
                color: dc.col
                font.family: pane.theme.ff
                font.pixelSize: pane.theme.fs + 4
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    text: dc.lbl
                    color: pane.theme.outline
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 3
                }
                Text {
                    text: dc.v
                    color: pane.theme.fg
                    font.family: pane.theme.ff
                    font.bold: true
                    font.pixelSize: pane.theme.fs - 1
                }
            }
        }
    }
}
