import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.modules.account
import qs.modules.appearance
import qs.modules.apps
import qs.modules.audio
import qs.modules.battery
import qs.modules.bluetooth
import qs.modules.monitors
import qs.modules.network
import qs.modules.system
import qs.modules.wallpaper
import qs.modules.weather

// Movable settings window (FloatingWindow) hosting the nav rail + panes.
// Shown/hidden imperatively from SettingsService.settingsOpen: the WM close
// button writes `visible`, which would break a binding and block reopens.
FloatingWindow {
    id: window

    required property var theme
    // Shell-size scale of this window's monitor (unset monitors = 100%).
    readonly property real uiScale: AppearanceService.scaleFor(screen?.name ?? "")

    // Driven by SettingsService (nav clicks write the service, never this
    // property, so `qs ipc call settings open <pane>` keeps working).
    readonly property string activePane: SettingsService.settingsPane

    signal closeRequested()

    title: "Quickshell settings"
    color: theme.bg

    minimumSize: Qt.size(706 * uiScale, 540 * uiScale)
    implicitWidth:  826 * uiScale
    implicitHeight: 580 * uiScale

    visible: false

    function show() { visible = true }
    function hide() { visible = false }

    // WM close → tell the shell, don't just vanish (keeps state in sync)
    onVisibleChanged: if (!visible) window.closeRequested()
    onCloseRequested: SettingsService.settingsOpen = false

    Connections {
        target: SettingsService
        function onSettingsOpenChanged() {
            if (SettingsService.settingsOpen) { window.show(); focusDelay.restart() }
            else                                window.hide()
        }
    }

    // Opened from the launcher (its layer closes the same frame), so the
    // keyboard often stays on the old app — focus by title once mapped.
    Timer {
        id: focusDelay
        interval: 140; repeat: false
        onTriggered: { focusProc.running = false; focusProc.running = true }
    }
    Process {
        id: focusProc
        command: ["hyprctl", "dispatch", "hl.dsp.focus({window = \"title:Quickshell settings\"})"]
    }

    Item {
        id: content
        // 100% layout rendered at uiScale; the window dims above match.
        x: 0; y: 0
        width:  parent.width  / window.uiScale
        height: parent.height / window.uiScale
        scale: window.uiScale
        transformOrigin: Item.TopLeft
        focus: true
        Keys.onEscapePressed: window.closeRequested()

        // ── Nav rail ──────────────────────────────────────────────────────
        Rectangle {
            id: navRail
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 236
            color: window.theme.inset

            // Entry for the active pane; the highlight below slides to it.
            property Item currentNav: null

            // Selection highlight + accent pill, shared by every entry so
            // changing pane slides it (Windows 11 style). Jumps while the
            // window is hidden, so opening on a pane doesn't animate.
            Rectangle {
                id: navHighlight
                visible: navRail.currentNav !== null
                x: 8
                width: navRail.width - 16
                y: navCol.y + (navRail.currentNav ? navRail.currentNav.y : 0)
                height: navRail.currentNav ? navRail.currentNav.height : 40
                radius: navRail.currentNav ? navRail.currentNav.radius : 10
                color: Qt.rgba(window.theme.fg.r, window.theme.fg.g, window.theme.fg.b, 0.08)
                Behavior on y      { enabled: window.visible; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: window.visible; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: 3; height: 18; radius: 2
                    color: window.theme.primary
                }
            }

            Column {
                id: navCol
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 16 }
                spacing: 4

                // ── Account header (like Windows 11 Settings) ────────────
                // Avatar + name; opens the Profile pane.
                Rectangle {
                    id: account
                    x: 8
                    width: navRail.width - 16
                    height: 76
                    radius: 12
                    readonly property bool current: window.activePane === "profile"
                    onCurrentChanged: if (current) navRail.currentNav = account
                    Component.onCompleted: if (current) navRail.currentNav = account
                    color: !current && accountHover.hovered
                           ? Qt.rgba(window.theme.fg.r, window.theme.fg.g, window.theme.fg.b, 0.04)
                           : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    HoverHandler { id: accountHover }

                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 12

                        ClippingRectangle {
                            id: avatar
                            anchors.verticalCenter: parent.verticalCenter
                            width: 56; height: 56
                            radius: width / 2
                            color: window.theme.surface2

                            Text {
                                anchors.centerIn: parent
                                text: "\uf007"
                                color: window.theme.outline
                                font.family: window.theme.ff; font.pixelSize: 30
                                visible: avatarImg.status !== Image.Ready
                            }
                            Image {
                                id: avatarImg
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                source: AccountService.avatarUrl
                                cache: false
                                asynchronous: true
                                sourceSize: Qt.size(112, 112)
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: account.width - avatar.width - 12 - 20
                            spacing: 2
                            Text {
                                width: parent.width
                                text: AccountService.displayName
                                color: window.theme.fg
                                font.family: window.theme.ff; font.bold: true
                                font.pixelSize: window.theme.fs + 1
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: SettingsService.settingsPane = "profile"
                    }
                }

                Rectangle {
                    x: 16
                    width: navRail.width - 32
                    height: 1
                    color: window.theme.sep
                    opacity: 0.6
                }
                Item { width: 1; height: 4 }

                Repeater {
                    model: [
                        { id: "wifi",      icon: "", label: "Wi-Fi"     },
                        { id: "bluetooth", icon: "", label: "Bluetooth" },
                        { id: "monitor",   icon: "", label: "Monitors"  },
                        { id: "audio",     icon: "", label: "Sound"     },
                        { id: "apps",      icon: "󰀻", label: "Applications" },
                        { id: "battery",   icon: "󰁹", label: "Battery"   },
                        { id: "weather",   icon: "", label: "Weather"   },
                        { id: "wallpaper", icon: "", label: "Wallpaper" },
                        { id: "appearance", icon: "󰍜", label: "Appearance" },
                        { id: "system",    icon: "", label: "About"     }
                    ]
                    delegate: Rectangle {
                        id: navItem
                        required property var modelData
                        readonly property bool current: window.activePane === modelData.id
                        width: navRail.width - 16
                        x: 8
                        height: 40
                        radius: 10
                        onCurrentChanged: if (current) navRail.currentNav = navItem
                        Component.onCompleted: if (current) navRail.currentNav = navItem
                        color: !current && navHover.hovered
                               ? Qt.rgba(window.theme.fg.r, window.theme.fg.g, window.theme.fg.b, 0.04)
                               : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        HoverHandler { id: navHover }

                        Row {
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            spacing: 12

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.icon
                                color: navItem.current ? window.theme.primary : window.theme.fg
                                Behavior on color { ColorAnimation { duration: 200 } }
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
                            onClicked: SettingsService.settingsPane = modelData.id
                        }
                    }
                }
            }
        }

        // ── Pane title ────────────────────────────────────────────────────
        // Panes with sub-pages expose `canGoBack` + `goBack()`; the arrow
        // beside the title returns to the pane's main page.
        Row {
            anchors { left: navRail.right; leftMargin: 28; top: parent.top; topMargin: 20 }
            spacing: 12

            Rectangle {
                id: backBtn
                visible: !!paneLoader.item && paneLoader.item.canGoBack === true
                anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 32
                radius: 16
                color: backHover.hovered ? window.theme.surface2 : window.theme.chip
                border.color: window.theme.sep
                border.width: 1

                HoverHandler { id: backHover }

                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -1
                    text: ""
                    color: window.theme.fg
                    font.family: window.theme.ff
                    font.pixelSize: window.theme.fs - 1
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: paneLoader.item.goBack()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: window.activePane === "profile"   ? "Your profile"
                    : window.activePane === "wifi"      ? "Wi-Fi"
                    : window.activePane === "bluetooth" ? "Bluetooth"
                    : window.activePane === "audio"     ? "Sound"
                    : window.activePane === "weather"   ? "Weather"
                    : window.activePane === "wallpaper" ? "Wallpaper"
                    : window.activePane === "appearance" ? "Appearance"
                    : window.activePane === "monitor"   ? "Monitors"
                    : window.activePane === "apps"      ? "Applications"
                    : window.activePane === "system"    ? "About"
                    : "Battery & power"
                color: window.theme.fg
                font.family: window.theme.ff
                font.bold: true
                font.pixelSize: window.theme.fs + 12
            }
        }

        // ── In-app close button ──────────────────────────────────────────
        Rectangle {
            id: closeBtn
            anchors { right: parent.right; top: parent.top; margins: 14 }
            width: 30; height: 30
            radius: 15
            color: closeHover.hovered ? window.theme.error : window.theme.chip
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
        // Loaded only while the window is shown: a hidden pane kept its
        // bindings, lists and scans live in the background.
        Loader {
            id: paneLoader
            active: window.visible
            anchors {
                left: navRail.right;  leftMargin: 28
                right: parent.right;  rightMargin: 22
                top: parent.top;      topMargin: 70
                bottom: parent.bottom; bottomMargin: 20
            }
            sourceComponent: window.activePane === "profile"   ? profileComp
                           : window.activePane === "wifi"      ? wifiComp
                           : window.activePane === "bluetooth" ? bluetoothComp
                           : window.activePane === "audio"     ? audioComp
                           : window.activePane === "weather"   ? weatherComp
                           : window.activePane === "wallpaper" ? wallpaperComp
                           : window.activePane === "appearance" ? appearanceComp
                           : window.activePane === "monitor"   ? monitorComp
                           : window.activePane === "apps"      ? appsComp
                           : window.activePane === "system"    ? systemComp
                           : batteryComp
        }

        Component { id: profileComp;   AccountSettings   { theme: window.theme } }
        Component { id: wifiComp;      WifiSettings      { theme: window.theme } }
        Component { id: audioComp;     AudioSettings     { theme: window.theme } }
        Component { id: bluetoothComp; BluetoothSettings { theme: window.theme } }
        Component { id: batteryComp;   BatterySettings   { theme: window.theme } }
        Component { id: weatherComp;   WeatherSettings   { theme: window.theme } }
        Component { id: wallpaperComp; WallpaperSettings { theme: window.theme } }
        Component { id: appearanceComp; AppearanceSettings { theme: window.theme } }
        Component { id: monitorComp;   MonitorSettings   { theme: window.theme } }
        Component { id: appsComp;      AppSettings       { theme: window.theme } }
        Component { id: systemComp;    SystemSettings    { theme: window.theme } }
    }
}
