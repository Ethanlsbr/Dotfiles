import QtQuick
import Quickshell
import "../dashboard"

PanelWindow {
    id: overlay

    required property var shellRoot
    required property var theme

    readonly property bool _open: shellRoot.dashboardOpen
    visible: _open || exitAnim.running
    on_OpenChanged: {
        if (_open) { exitAnim.stop(); enterAnim.restart() }
        else       { enterAnim.stop(); exitAnim.restart() }
    }

    anchors { top: true }
    margins.top: -30            // sit just below the bar
    exclusiveZone: 0
    color: "transparent"

    implicitWidth:  920
    implicitHeight: 540

    // The dashboard is horizontally centred and anchored to the top edge,
    // so the Spotify (media) pill in the bar's centre sits directly above
    // its top-centre. Scaling from origin (card.width/2, 0) on both axes
    // makes the panel look like it's expanding outward from the pill.
    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: card;      property: "opacity"; from: 0;    to: 1; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: cardScale; property: "xScale";  from: 0.05; to: 1; duration: 380; easing.type: Easing.OutCubic }
        NumberAnimation { target: cardScale; property: "yScale";  from: 0.05; to: 1; duration: 380; easing.type: Easing.OutCubic }
    }
    // Reverse: shrink the panel back into the Spotify pill and fade out.
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: card;      property: "opacity"; to: 0;    duration: 220; easing.type: Easing.InCubic }
        NumberAnimation { target: cardScale; property: "xScale";  to: 0.05; duration: 300; easing.type: Easing.InCubic }
        NumberAnimation { target: cardScale; property: "yScale";  to: 0.05; duration: 300; easing.type: Easing.InCubic }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.leftMargin:   8
        anchors.rightMargin:  8
        anchors.bottomMargin: 8
        anchors.topMargin:    0      // hug the bar's bottom — no air gap
        color: overlay.theme.bg
        radius: 18
        border.color: overlay.theme.sep
        border.width: 1
        opacity: 0
        transform: Scale {
            id: cardScale
            origin.x: card.width / 2     // align with Spotify pill (bar centre)
            origin.y: 0                  // grow downward from the bar
            xScale: 0.05
            yScale: 0.05
        }

        HoverHandler {
            onHoveredChanged: hovered ? overlay.shellRoot.stopDashboardHide()
                                      : overlay.shellRoot.startDashboardHide()
        }

        Column {
            anchors { fill: parent; margins: 14 }
            spacing: 12

            // ── Tab bar ────────────────────────────────────────────────
            Row {
                id: tabsRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4

                component Tab: Rectangle {
                    id: tab
                    required property int    idx
                    required property string label
                    required property string icon
                    readonly property bool current: overlay.shellRoot.dashboardTab === tab.idx

                    width: 130
                    height: 48
                    radius: 10
                    color: tab.current
                            ? overlay.theme.hi(1.5)
                            : (tabHover.hovered ? Qt.lighter(overlay.theme.surface, 1.2)
                                                : "transparent")

                    HoverHandler { id: tabHover }
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tab.icon
                            color: tab.current ? overlay.theme.primary : overlay.theme.txt2
                            font.family: overlay.theme.ff
                            font.pixelSize: overlay.theme.fs + 4
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tab.label
                            color: tab.current ? overlay.theme.primary : overlay.theme.txt2
                            font.family: overlay.theme.ff
                            font.pixelSize: overlay.theme.fs - 3
                            font.bold: tab.current
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: overlay.shellRoot.dashboardTab = tab.idx
                    }
                }

                Tab { idx: 0; label: "Dashboard";   icon: "󰕮" }
                Tab { idx: 1; label: "Media";       icon: "󰝚" }
                Tab { idx: 2; label: "Performance"; icon: "󰓅" }
                Tab { idx: 3; label: "Weather";     icon: "" }
            }

            // ── Underline indicator ────────────────────────────────────
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: tabsRow.width
                height: 2
                Rectangle {
                    width: 40; height: 2; radius: 1
                    color: overlay.theme.primary
                    x: (overlay.shellRoot.dashboardTab * (130 + 4)) + (130 - 40) / 2
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: overlay.theme.sep
                opacity: 0.5
            }

            // ── Tab content ────────────────────────────────────────────
            Loader {
                width: parent.width
                height: parent.height - tabsRow.height - 38
                sourceComponent: switch (overlay.shellRoot.dashboardTab) {
                    case 0: return dashCmp
                    case 1: return mediaCmp
                    case 2: return perfCmp
                    case 3: return weatherCmp
                }
            }

            Component { id: dashCmp;    DashboardPane   { shellRoot: overlay.shellRoot; theme: overlay.theme } }
            Component { id: mediaCmp;   MediaPane       { shellRoot: overlay.shellRoot; theme: overlay.theme } }
            Component { id: perfCmp;    PerformancePane { shellRoot: overlay.shellRoot; theme: overlay.theme } }
            Component { id: weatherCmp; WeatherPane     { shellRoot: overlay.shellRoot; theme: overlay.theme } }
        }
    }
}
