import QtQuick
import Quickshell

// Real movable desktop window (FloatingWindow = xdg-toplevel) hosting
// the nav rail + active pane. Driven imperatively by the shell via
// .show()/.hide(); a signal reports user-driven closes back upstream.
FloatingWindow {
    id: window

    required property var shellRoot
    required property var theme

    property string activePane: "audio"

    signal closeRequested()

    title: "Quickshell settings"
    color: theme.bg

    minimumSize: Qt.size(640, 460)
    implicitWidth:  760
    implicitHeight: 520

    visible: false

    function show() { visible = true }
    function hide() { visible = false }

    // WM close → tell the shell, don't just vanish (keeps state in sync)
    onVisibleChanged: if (!visible) window.closeRequested()

    Item {
        id: content
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: window.closeRequested()

        // ── Nav rail ──────────────────────────────────────────────────────
        Rectangle {
            id: navRail
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 170
            color: Qt.darker(window.theme.bg, 1.25)

            Column {
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 16 }
                spacing: 4

                Repeater {
                    model: [
                        { id: "wifi",      icon: "", label: "Wi-Fi"     },
                        { id: "bluetooth", icon: "", label: "Bluetooth" },
                        { id: "monitor",   icon: "", label: "Monitors"  },
                        { id: "audio",     icon: "", label: "Audio"     },
                        { id: "battery",   icon: "󰁹", label: "Battery"   },
                        { id: "weather",   icon: "", label: "Weather"   },
                        { id: "wallpaper", icon: "", label: "Wallpaper" },
                        { id: "system",    icon: "", label: "System"    }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: navRail.width - 16
                        x: 8
                        height: 40
                        radius: 10
                        color: window.activePane === modelData.id
                               ? window.theme.active
                               : (navHover.hovered ? window.theme.surface : "transparent")

                        HoverHandler { id: navHover }

                        Row {
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            spacing: 12

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.icon
                                color: window.theme.fg
                                font.family: window.theme.ff
                                font.pixelSize: window.theme.fs + 2
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: window.theme.fg
                                font.family: window.theme.ff
                                font.pixelSize: window.theme.fs
                                font.bold: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.activePane = modelData.id
                        }
                    }
                }
            }
        }

        // ── Pane title ────────────────────────────────────────────────────
        Text {
            anchors { left: navRail.right; leftMargin: 24; top: parent.top; topMargin: 22 }
            text: window.activePane === "wifi"      ? "Wi-Fi"
                : window.activePane === "bluetooth" ? "Bluetooth"
                : window.activePane === "audio"     ? "Audio settings"
                : window.activePane === "weather"   ? "Weather"
                : window.activePane === "wallpaper" ? "Wallpaper"
                : window.activePane === "monitor"   ? "Monitors"
                : window.activePane === "system"    ? "System info"
                : "Battery & power"
            color: window.theme.fg
            font.family: window.theme.ff
            font.bold: true
            font.pixelSize: window.theme.fs + 4
        }

        // ── In-app close button ──────────────────────────────────────────
        Rectangle {
            id: closeBtn
            anchors { right: parent.right; top: parent.top; margins: 14 }
            width: 30; height: 30
            radius: 15
            color: closeHover.hovered ? window.theme.error : Qt.darker(window.theme.bg, 1.2)
            border.color: window.theme.sep
            border.width: 1

            HoverHandler { id: closeHover }

            Text {
                anchors.centerIn: parent
                text: "✕"
                color: window.theme.fg
                font.family: window.theme.ff
                font.bold: true
                font.pixelSize: window.theme.fs
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: window.closeRequested()
            }
        }

        // ── Active pane content ──────────────────────────────────────────
        Loader {
            anchors {
                left: navRail.right;  leftMargin: 24
                right: parent.right;  rightMargin: 24
                top: parent.top;      topMargin: 64
                bottom: parent.bottom; bottomMargin: 20
            }
            sourceComponent: window.activePane === "wifi"      ? wifiComp
                           : window.activePane === "bluetooth" ? bluetoothComp
                           : window.activePane === "audio"     ? audioComp
                           : window.activePane === "weather"   ? weatherComp
                           : window.activePane === "wallpaper" ? wallpaperComp
                           : window.activePane === "monitor"   ? monitorComp
                           : window.activePane === "system"    ? systemComp
                           : batteryComp
        }

        Component { id: wifiComp;      WifiPane      { shellRoot: window.shellRoot; theme: window.theme } }
        Component { id: audioComp;     AudioPane     { shellRoot: window.shellRoot; theme: window.theme } }
        Component { id: bluetoothComp; BluetoothPane { shellRoot: window.shellRoot; theme: window.theme } }
        Component { id: batteryComp;   BatteryPane   { theme: window.theme } }
        Component { id: weatherComp;   WeatherPane   { shellRoot: window.shellRoot; theme: window.theme } }
        Component { id: wallpaperComp; WallpaperPane { shellRoot: window.shellRoot; theme: window.theme } }
        Component { id: monitorComp;   MonitorPane   { shellRoot: window.shellRoot; theme: window.theme } }
        Component { id: systemComp;    SystemPane    { shellRoot: window.shellRoot; theme: window.theme } }
    }
}
