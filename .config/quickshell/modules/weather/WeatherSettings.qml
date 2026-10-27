import QtQuick
import qs.common.ui

// Settings pane: current conditions + the wttr.in location.
Item {
    id: pane

    required property var theme

    UiPage {
        anchors.fill: parent
        theme: pane.theme

        // ── Current conditions ────────────────────────────────────────────
        UiCard {
            theme: pane.theme
            height: 124

            Text {
                id: wIcon
                anchors { left: parent.left; leftMargin: 26; verticalCenter: parent.verticalCenter }
                text: WeatherService.weather.ready ? WeatherService.weather.icon : "󰖐"
                color: pane.theme.secondary
                font.family: pane.theme.ff; font.pixelSize: pane.theme.fs * 3 + 4
            }
            Column {
                anchors { left: wIcon.right; leftMargin: 24; verticalCenter: parent.verticalCenter }
                spacing: 4
                Text {
                    text: WeatherService.weather.ready ? (WeatherService.weather.city || "Unknown") : "Loading…"
                    color: pane.theme.fg
                    font.family: pane.theme.ff; font.bold: true
                    font.pixelSize: pane.theme.fs + 6
                }
                Text {
                    visible: WeatherService.weather.ready
                    text: WeatherService.weather.temp + "  ·  " + WeatherService.weather.description
                    color: pane.theme.primary
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs
                }
                Text {
                    text: WeatherService.weatherLocation
                          ? "Location set to “" + WeatherService.weatherLocation + "”"
                          : "Location detected automatically from your IP"
                    color: pane.theme.txt2
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 3
                }
            }
            UiButton {
                anchors { right: parent.right; rightMargin: 20; top: parent.top; topMargin: 16 }
                theme: pane.theme
                icon: ""
                text: "Refresh"
                onClicked: WeatherService.refreshWeather()
            }
        }

        // ── Location ──────────────────────────────────────────────────────
        UiGroup {
            theme: pane.theme
            title: "Location"
            description: "City name, airport code, ZIP or coordinates. Leave empty to detect it from your IP."

            Item {
                width: parent.width
                implicitHeight: locCol.implicitHeight + 32

                Column {
                    id: locCol
                    x: 16; y: 16
                    width: parent.width - 32
                    spacing: 12

                    UiTextField {
                        id: locField
                        theme: pane.theme
                        icon: ""
                        placeholder: "e.g. Paris, NYC, 75001, 48.85,2.35"
                        text: WeatherService.weatherLocation
                        onAccepted: t => WeatherService.setWeatherLocation(t)
                    }
                    Row {
                        spacing: 8
                        UiButton {
                            theme: pane.theme
                            kind: "primary"
                            text: "Save"
                            onClicked: WeatherService.setWeatherLocation(locField.text)
                        }
                        UiButton {
                            theme: pane.theme
                            icon: ""
                            text: "Auto-detect"
                            onClicked: {
                                locField.text = ""
                                WeatherService.setWeatherLocation("")
                            }
                        }
                    }
                }
            }
        }
    }
}
