import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.modules.cava

// Click-through desktop decorations on the wlr "bottom" layer, one surface
// per monitor: cava strip (bottom) + Rainmeter-style clock (top-centre).
// Each is gated by a persisted Wallpaper-pane toggle; the empty input mask
// keeps every event falling through to the desktop.
Scope {
    id: scope

    required property var theme

    // Shared 1 s tick for the clock.
    property var now: new Date()
    Timer {
        interval: 1000; repeat: true
        running: WallpaperService.wpClockEnabled
        triggeredOnStart: true
        onTriggered: scope.now = new Date()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            // Above the wallpaper, beneath ordinary windows.
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell:wallpaper-widgets"

            anchors { left: true; right: true; top: true; bottom: true }
            exclusiveZone: 0
            color: "transparent"

            // Only map the surface when at least one widget is enabled.
            visible: WallpaperService.wpCavaEnabled || WallpaperService.wpClockEnabled

            // Empty input region = fully click-through.
            mask: Region {}

            // ── Cava visualiser strip (bottom) ──────────────────────────────
            Row {
                id: cava
                visible: WallpaperService.wpCavaEnabled
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    bottomMargin: 6
                    leftMargin: 12
                    rightMargin: 12
                }
                height: Math.round(parent.height * 0.08)

                readonly property int count: CavaService.cavaBarCount
                // Bars fill the full width with a small fixed gap between them.
                spacing: 4
                readonly property real barW:
                    Math.max(2, (width - (count - 1) * spacing) / count)

                Repeater {
                    model: cava.count
                    Rectangle {
                        required property int index
                        width: cava.barW
                        anchors.bottom: parent.bottom
                        radius: 3
                        // 0..1 magnitude → baseline nub when silent, full
                        // strip height at peak.
                        readonly property real v: (CavaService.cavaValues[index] || 0)
                        height: Math.max(3, v * cava.height)
                        opacity: 0.55 + 0.45 * v
                        // Same accent as the dashboard cava ring.
                        color: scope.theme.primary
                        Behavior on height {
                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }

            // ── Clock / date (top-centre, Rainmeter-style) ──────────────────
            Column {
                id: clock
                visible: WallpaperService.wpClockEnabled
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: Math.round(parent.height * 0.07)
                }
                spacing: 2

                // White + drop shadow: legible over any wallpaper; themed fg
                // reads muddy on photos.
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.85)
                    shadowBlur: 1.0
                    shadowVerticalOffset: 2
                    shadowHorizontalOffset: 0
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(scope.now, "HH:mm")
                    color: "white"
                    font.family: scope.theme.ff
                    font.bold: true
                    font.pixelSize: Math.round(win.height * 0.085)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(scope.now, "dddd d MMMM")
                    color: "white"
                    opacity: 0.9
                    font.family: scope.theme.ff
                    font.pixelSize: Math.round(win.height * 0.022)
                }
            }
        }
    }
}
