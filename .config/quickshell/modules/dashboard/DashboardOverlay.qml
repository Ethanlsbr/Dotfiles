import QtQuick
import Quickshell
import qs.modules.appearance
import qs.modules.media
import qs.modules.system
import qs.modules.weather
import qs.common

PanelWindow {
    id: overlay

    required property var theme
    // Shell-size scale of this window's monitor (unset monitors = 100%).
    readonly property real uiScale: AppearanceService.scaleFor(screen?.name ?? "")

    readonly property bool _open: DashboardService.dashboardOpen
    // Position of the current tab among the shown ones (hidden tabs and
    // panes are skipped by the Row layouts).
    readonly property int _slot: Math.max(0, DashboardService.visibleTabs.indexOf(DashboardService.dashboardTab))
    visible: pop.shown

    anchors { top: true }
    margins.top: Math.round(-30 * uiScale)   // sit just below the bar (offset scales with it)
    exclusiveZone: 0
    color: "transparent"

    implicitWidth:  920 * uiScale
    implicitHeight: 540 * uiScale

    Rectangle {
        id: card
        // 100% layout rendered at uiScale via the item `scale`; the pop grows
        // it out of the bar's media pill (top centre).
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0                         // hug the bar's bottom — no air gap
        width:  parent.width  / overlay.uiScale - 16
        height: parent.height / overlay.uiScale - 8
        color: overlay.theme.bg
        radius: 18
        border.color: overlay.theme.sep
        border.width: 1
        opacity: 0
        scale: overlay.uiScale
        transformOrigin: Item.Top
        transform: PopAnim { id: pop; item: card; open: overlay._open; origin.x: card.width / 2; origin.y: 0 }

        HoverHandler {
            onHoveredChanged: hovered ? DashboardService.stopDashboardHide()
                                      : DashboardService.startDashboardHide()
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
                    visible: DashboardService.isTabEnabled(tab.idx)
                    readonly property bool current: DashboardService.dashboardTab === tab.idx

                    width: 130
                    height: 48
                    radius: 10
                    color: tab.current
                            ? overlay.theme.hi(1.5)
                            : (tabHover.hovered ? overlay.theme.lift(overlay.theme.surface, 1.2)
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
                        onClicked: DashboardService.dashboardTab = tab.idx
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
                    x: (overlay._slot * (130 + 4)) + (130 - 40) / 2
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
            // Panes side by side in tab order; changing tab slides the strip
            // (same motion as the bar popups). Only animated while shown, so
            // opening straight onto a tab doesn't play a slide.
            Item {
                id: tabView
                width: parent.width
                height: parent.height - tabsRow.height - 38
                clip: true

                // Animate the tab position, not the strip's x, so size
                // changes (e.g. while the window maps/unmaps) never slide.
                property real pos: overlay._slot
                Behavior on pos {
                    enabled: overlay.visible
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                // `live`: open on that pane's tab — panes only tick and
                // animate then.
                Row {
                    x: -tabView.pos * tabView.width

                    DashboardPane   { visible: DashboardService.isTabEnabled(0); live: overlay._open && DashboardService.dashboardTab === 0; theme: overlay.theme; width: tabView.width; height: tabView.height }
                    MediaPane       { visible: DashboardService.isTabEnabled(1); live: overlay._open && DashboardService.dashboardTab === 1; theme: overlay.theme; width: tabView.width; height: tabView.height }
                    PerformancePane { visible: DashboardService.isTabEnabled(2); live: overlay._open && DashboardService.dashboardTab === 2; theme: overlay.theme; width: tabView.width; height: tabView.height }
                    WeatherPane     { visible: DashboardService.isTabEnabled(3); live: overlay._open && DashboardService.dashboardTab === 3; theme: overlay.theme; width: tabView.width; height: tabView.height }
                }
            }
        }
    }
}
