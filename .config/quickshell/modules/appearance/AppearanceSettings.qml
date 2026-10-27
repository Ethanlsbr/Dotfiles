import QtQuick
import Quickshell
import qs.common.ui
import qs.modules.dashboard

// Settings pane: opens on a chooser between colour theme, per-monitor shell
// size, bar elements and the bar dashboard.
Item {
    id: pane

    required property var theme

    readonly property var sizeOptions: [0.5, 0.75, 1.0, 1.25, 1.5]

    // "" = chooser, "theme", "size", "bar" or "dashboard".
    property string view: ""
    onViewChanged: page.contentY = 0
    // Back arrow beside the settings window title (SettingsWindow).
    readonly property bool canGoBack: view !== ""
    function goBack() { view = "" }


    readonly property var barSides: ["Left", "Center", "Right"]
    function barSummary() {
        const shown = AppearanceService.barModules.filter(m => AppearanceService.barModuleShown(m.key)).length
        const off = Quickshell.screens.filter(s => !AppearanceService.barEnabledOn(s.name)).length
        return shown + " of " + AppearanceService.barModules.length + " elements shown"
             + (off ? "  ·  hidden on " + off + (off === 1 ? " monitor" : " monitors") : "")
    }

    UiPage {
        id: page
        anchors.fill: parent
        theme: pane.theme

        // ── Chooser ───────────────────────────────────────────────────────
        UiGroup {
            visible: pane.view === ""
            theme: pane.theme
            title: "Customise"

            UiRow {
                theme: pane.theme
                icon: ""
                title: "Theme"
                subtitle: (AppearanceService.themePalettes.find(t => t.id === AppearanceService.themeName) || {}).name || ""
                clickable: true
                onClicked: pane.view = "theme"
                UiChevron { theme: pane.theme }
            }
            UiRow {
                theme: pane.theme
                icon: ""
                title: "Shell size"
                subtitle: Quickshell.screens.map(sc => sc.name + " "
                              + Math.round(AppearanceService.scaleFor(sc.name) * 100) + "%").join("  ·  ")
                clickable: true
                onClicked: pane.view = "size"
                UiChevron { theme: pane.theme }
            }
            UiRow {
                theme: pane.theme
                icon: ""
                title: "Bar"
                subtitle: pane.barSummary()
                clickable: true
                onClicked: pane.view = "bar"
                UiChevron { theme: pane.theme }
            }
            UiRow {
                theme: pane.theme
                icon: ""
                title: "Dashboard"
                subtitle: !DashboardService.dashboardEnabled ? "Off"
                        : DashboardService.tabs.filter(t => DashboardService.isTabEnabled(t.idx))
                                               .map(t => t.label).join(", ")
                clickable: true
                onClicked: pane.view = "dashboard"
                UiChevron { theme: pane.theme }
            }
        }

        // ── Theme ─────────────────────────────────────────────────────────
        UiGroup {
            visible: pane.view === "theme"
            theme: pane.theme
            title: "Theme"
            description: "Recolours the whole shell. Also available from the launcher (> Theme)."

            Item {
                width: parent.width
                implicitHeight: themeFlow.implicitHeight + 32

                Flow {
                    id: themeFlow
                    x: 16; y: 16
                    width: parent.width - 32
                    spacing: 12

                    Repeater {
                        model: AppearanceService.themePalettes
                        delegate: Rectangle {
                            id: opt
                            required property var modelData
                            readonly property bool applied: modelData.id === AppearanceService.themeName
                            // Fill the row evenly: as many ~170px cards as fit.
                            readonly property int perRow: Math.max(1, Math.floor((themeFlow.width + 12) / 182))
                            width: (themeFlow.width - (perRow - 1) * 12) / perRow
                            height: width * 0.62 + 34
                            radius: 12
                            color: optHover.hovered
                                   ? Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.06)
                                   : "transparent"
                            border.color: applied ? pane.theme.primary
                                        : Qt.rgba(pane.theme.sep.r, pane.theme.sep.g, pane.theme.sep.b, 0.9)
                            border.width: applied ? 2 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            HoverHandler { id: optHover }

                            // Palette mockup (same design as the launcher picker).
                            Rectangle {
                                id: mock
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                height: opt.width * 0.62 - 6
                                radius: 8
                                color: opt.modelData.bg
                                border.color: Qt.rgba(0, 0, 0, 0.15)
                                border.width: 1

                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 7 }
                                    height: 14; radius: 5
                                    color: opt.modelData.surface
                                    Row {
                                        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                        spacing: 4
                                        Rectangle { width: 7; height: 7; radius: 3.5; color: opt.modelData.primary }
                                        Rectangle { width: 7; height: 7; radius: 3.5; color: opt.modelData.secondary }
                                        Rectangle { width: 7; height: 7; radius: 3.5; color: opt.modelData.tertiary }
                                    }
                                }
                                Column {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
                                    spacing: 5
                                    Rectangle { width: parent.width * 0.7; height: 6; radius: 3; color: opt.modelData.fg; opacity: 0.9 }
                                    Rectangle { width: parent.width * 0.45; height: 6; radius: 3; color: opt.modelData.fg; opacity: 0.45 }
                                }
                            }

                            Row {
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 9 }
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: opt.applied
                                    text: ""
                                    color: pane.theme.primary
                                    font.family: pane.theme.ff
                                    font.pixelSize: pane.theme.fs - 2
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: opt.modelData.name
                                    color: opt.applied ? pane.theme.primary : pane.theme.fg
                                    font.family: pane.theme.ff
                                    font.bold: true
                                    font.pixelSize: pane.theme.fs - 2
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: AppearanceService.setTheme(opt.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // ── Shell size ────────────────────────────────────────────────────
        UiGroup {
            visible: pane.view === "size"
            theme: pane.theme
            title: "Shell size"
            description: "Scales the bar, menus, popups and overlays on each monitor. New monitors default to 100%."

            Repeater {
                model: Quickshell.screens
                delegate: UiRow {
                    id: monRow
                    required property var modelData
                    readonly property real current: AppearanceService.scaleFor(modelData.name)
                    theme: pane.theme
                    icon: ""
                    title: modelData.name
                    subtitle: modelData.model || ""

                    // Segmented size picker.
                    Rectangle {
                        width: seg.implicitWidth + 6
                        height: 32
                        radius: 9
                        color: Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.06)

                        Row {
                            id: seg
                            anchors.centerIn: parent
                            spacing: 2
                            Repeater {
                                model: pane.sizeOptions
                                delegate: Rectangle {
                                    id: segBtn
                                    required property real modelData
                                    readonly property bool selected: Math.abs(monRow.current - modelData) < 0.001
                                    width: 52; height: 26
                                    radius: 7
                                    color: selected ? pane.theme.primary
                                         : (segHover.hovered ? Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.08)
                                                             : "transparent")
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    HoverHandler { id: segHover }
                                    Text {
                                        anchors.centerIn: parent
                                        text: Math.round(segBtn.modelData * 100) + "%"
                                        color: segBtn.selected ? pane.theme.bg : pane.theme.fg
                                        font.family: pane.theme.ff; font.bold: segBtn.selected
                                        font.pixelSize: pane.theme.fs - 3
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: AppearanceService.setMonitorScale(monRow.modelData.name, segBtn.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Bar: monitors ─────────────────────────────────────────────────
        UiGroup {
            visible: pane.view === "bar"
            theme: pane.theme
            title: "Show the bar on"

            Repeater {
                model: Quickshell.screens
                delegate: UiRow {
                    id: barMon
                    required property var modelData
                    theme: pane.theme
                    icon: ""
                    title: modelData.name
                    subtitle: modelData.model || ""
                    UiSwitch {
                        theme: pane.theme
                        checked: AppearanceService.barEnabledOn(barMon.modelData.name)
                        onToggled: value => AppearanceService.setBarOnMonitor(barMon.modelData.name, value)
                    }
                }
            }
        }

        // ── Bar: elements, by position ────────────────────────────────────
        Repeater {
            model: pane.view === "bar" ? pane.barSides : []
            delegate: UiGroup {
                id: side
                required property string modelData
                theme: pane.theme
                title: modelData === "Left" ? "Left side" : modelData === "Center" ? "Centre" : "Right side"
                description: modelData === "Right" ? "The status pill; hidden entirely when all of these are off" : ""

                Repeater {
                    model: AppearanceService.barModules.filter(m => m.side === side.modelData)
                    delegate: Column {
                        id: mod
                        required property var modelData
                        required property int index
                        readonly property bool on: AppearanceService.barModuleShown(modelData.key)
                        width: parent.width

                        UiRow {
                            theme: pane.theme
                            showDivider: mod.index > 0
                            icon: mod.modelData.icon
                            iconColor: mod.on ? pane.theme.primary : pane.theme.txt2
                            title: mod.modelData.label
                            subtitle: mod.modelData.description
                            UiSwitch {
                                theme: pane.theme
                                checked: mod.on
                                onToggled: value => AppearanceService.setBarModuleShown(mod.modelData.key, value)
                            }
                        }
                    }
                }
            }
        }

        // ── Dashboard ─────────────────────────────────────────────────────
        UiGroup {
            visible: pane.view === "dashboard"
            theme: pane.theme
            title: "Dashboard"
            description: "Opens when hovering the centre of the bar. Pick which tabs it shows; at least one stays on."
            actions: UiSwitch {
                theme: pane.theme
                checked: DashboardService.dashboardEnabled
                onToggled: value => DashboardService.setDashboardEnabled(value)
            }

            Repeater {
                model: DashboardService.tabs
                delegate: UiRow {
                    id: tabRow
                    required property var modelData
                    readonly property bool on: DashboardService.isTabEnabled(modelData.idx)
                    // The last shown tab can't be switched off.
                    readonly property bool locked: on && DashboardService.visibleTabs.length <= 1
                    theme: pane.theme
                    icon: modelData.icon
                    title: modelData.label
                    subtitle: modelData.description
                    enabled: DashboardService.dashboardEnabled
                    opacity: enabled ? 1 : 0.45
                    Behavior on opacity { NumberAnimation { duration: 140 } }

                    UiSwitch {
                        theme: pane.theme
                        checked: tabRow.on
                        opacity: tabRow.locked ? 0.5 : 1
                        onToggled: value => DashboardService.setTabEnabled(tabRow.modelData.idx, value)
                    }
                }
            }
        }
    }
}
