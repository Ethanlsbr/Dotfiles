import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.UPower
import qs.common
import qs.modules.audio
import qs.modules.battery
import qs.modules.bluetooth
import qs.modules.dashboard
import qs.modules.launcher
import qs.modules.media
import qs.modules.network
import qs.modules.notifications
import qs.modules.settings

PanelWindow {
    id: bar

    required property var theme
    // Unscaled tokens for the hover popup panel (it lays out at 100%).
    required property var popupTheme
    // Connector name from the Variants delegate — using screen.name here
    // would loop the `visible` binding.
    property string monitorName: ""

    // Bar-only font — popups and the rest of the shell keep theme.ff.
    readonly property string ff: "JetBrainsMono Nerd Font Propo"

    // This bar's Hyprland monitor — scopes the workspace module.
    readonly property var hyprMonitor:
        Hyprland.monitors.values.find(m => m.name === bar.monitorName) ?? null

    // Clicking a status module opens its settings page (and drops the hover
    // popup so it doesn't sit over the window).
    function openSettings(pane) {
        PopupService.showPopup("")
        SettingsService.openSettings(pane)
    }

    // Hit area for a right-pill module that also covers the gap above the
    // pill, up to the screen edge — throwing the cursor to the top still
    // hovers / clicks the module. Also claims the popup for this monitor.
    component TopHit: Item {
        y: -(rightPill.y + rightLayout.y + parent.y)
        width: parent.width
        height: parent.height - y
        HoverHandler { onHoveredChanged: if (hovered) PopupService.popupScreen = bar.screen }
    }

    // False for the first moments after launch, while workspaces and
    // battery data arrive: those land in place instead of playing their
    // grow-in animations, so the bar looks finished as soon as it shows.
    property bool settled: false
    Timer { interval: 1500; running: true; onTriggered: bar.settled = true }

    // Hidden by `qs ipc call bar toggle` or the per-monitor settings toggle.
    visible: BarService.barVisible && BarService.barEnabledOn(bar.monitorName)

    anchors { top: true; left: true; right: true }
    // The hover popup panel lives in this window (so it tracks the pill in
    // the same frame). The surface keeps one fixed height — resizing it on
    // popup open/close made the whole bar flicker for a frame. Everything
    // but the bar strip + the visible panel is transparent and input-masked.
    implicitHeight: Math.ceil(Math.min((bar.screen?.height ?? 1080) - 20,
                                       bar.theme.sc(40) + 900 * bar.theme.scale))
    mask: Region {
        item: barArea
        Region { item: popupPanel.maskItem }
        Region { item: toastPanel.maskItem }
    }
    // Keyboard only while the popup's Wi-Fi password prompt is up.
    WlrLayershell.keyboardFocus: popupPanel.wantsKeyboard ? WlrKeyboardFocus.OnDemand
                                                          : WlrKeyboardFocus.None
    // Pills end ~35px (at 100%), so reserve less than full height — tiled
    // windows sit closer without clipping.
    exclusiveZone: bar.visible ? bar.theme.sc(34) : 0
    color: "transparent"

    // The bar strip itself (fixed height; the window may be taller while a
    // popup is open).
    Item {
        id: barArea
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: bar.theme.sc(40)

        // ── Dashboard hover trigger ───────────────────────────────────
        // Centered 240px zone; the geometric HoverHandler fires even under
        // the media pill's MouseArea.
        Item {
            id: dashTrigger
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: bar.theme.sc(240)

            HoverHandler {
                onHoveredChanged: DashboardService.hoverDashboard(hovered)
            }
        }

        // ── LEFT: Power + Workspaces ───────────────────────────────────
        Row {
            anchors {
                left: parent.left
                leftMargin: 10
                top: parent.top
                topMargin: bar.theme.sc(5)
            }
            spacing: 10

            Rectangle {
                id: archBtn
                visible: BarService.isShown("launcher")
                height: bar.theme.ph; width: bar.theme.sc(50)
                radius: bar.theme.pr
                color: archHover.hovered
                       ? bar.theme.hi(1.3)
                       : bar.theme.bg
                Text {
                    anchors.centerIn: parent
                    text: "  "
                    color: bar.theme.fg
                    font.family: bar.ff; font.bold: true; font.pixelSize: bar.theme.fs
                }
                HoverHandler { id: archHover }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: LauncherService.toggleLauncher()
                }
            }

            // 1:1 copy of the waybar #workspaces module: 35px module,
            // 27px buttons (margins 5/1 + 4/3), same colours and hover.
            Rectangle {
                visible: BarService.isShown("workspaces")
                height: bar.theme.ph
                width:  wsRow.implicitWidth + bar.theme.sc(8)   // module-level horizontal padding
                radius: bar.theme.pr
                color:  bar.theme.bg

                Row {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: bar.theme.sc(4)              // tighter than the literal 6px to match waybar's rendered gap

                    Repeater {
                        // Only this monitor's workspaces, in id order.
                        // ScriptModel diffs the list, so existing buttons
                        // survive workspace creation/removal and can animate
                        // (a plain array would recreate every delegate).
                        model: ScriptModel {
                            values: Hyprland.workspaces.values
                                .filter(w => w.monitor && w.monitor.name === bar.monitorName)
                                .sort((a, b) => a.id - b.id)
                        }
                        delegate: Rectangle {
                            id: wsBtn
                            required property var modelData
                            readonly property bool isActive:
                                bar.hyprMonitor?.activeWorkspace?.id === modelData.id
                            // New workspaces grow in from zero width.
                            property bool born: false
                            Component.onCompleted: Qt.callLater(() => wsBtn.born = true)

                            height: bar.theme.sc(22)
                            radius: bar.theme.pr          // waybar border-radius: 15px (at 100%)
                            color:  bar.theme.active      // every button
                            clip: true
                            opacity: (born ? 1 : 0) * (wsHover.hovered ? 0.7 : 1.0)
                            Behavior on opacity { enabled: bar.settled; NumberAnimation { duration: 300 } }
                            Behavior on width   { enabled: bar.settled; NumberAnimation { duration: 300 } }

                            // Inactive buttons hug content; active gets
                            // waybar's min-width: 40px.
                            width: !born ? 0
                                 : isActive
                                ? Math.max(bar.theme.sc(40), wsLabel.implicitWidth + bar.theme.sc(40))
                                : Math.max(bar.theme.sc(28), wsLabel.implicitWidth + bar.theme.sc(14))

                            Text {
                                id: wsLabel
                                anchors.centerIn: parent
                                text: modelData.id
                                color: wsHover.hovered ? (bar.theme.light ? bar.theme.primary : "#1a110f") : bar.theme.fg
                                font.family: bar.ff
                                font.bold: true
                                font.pixelSize: bar.theme.fs   // 14px — matches the rest of the bar
                            }
                            HoverHandler { id: wsHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                // Hyprland 0.55+ Lua config wraps the legacy
                                // "workspace N" dispatch — use the Lua one.
                                onClicked: Hyprland.dispatch("hl.dsp.focus({workspace=" + modelData.id + "})")
                            }
                        }
                    }
                }
            }
        }

        // ── CENTER: Spotify ────────────────────────────────────────────
        Rectangle {
            visible: BarService.isShown("media") && MediaService.mediaText !== ""
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top; topMargin: bar.theme.sc(5)
            }
            height: bar.theme.ph
            width:  mediaRow.implicitWidth + bar.theme.sc(20)
            radius: bar.theme.pr; color: bar.theme.bg

            Row {
                id: mediaRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""; color: bar.theme.green
                    font.family: bar.ff; font.pixelSize: bar.theme.fs + 1
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: MediaService.mediaText; color: bar.theme.fg
                    font.family: bar.ff; font.bold: true; font.pixelSize: bar.theme.fs
                    elide: Text.ElideRight; maximumLineCount: 1
                    width: Math.min(implicitWidth, bar.theme.sc(320))
                }
            }

            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) MediaService.playerToggle()
                    else                                MediaService.playerNext()
                }
                onWheel: wheel => {
                    if (wheel.angleDelta.y > 0) MediaService.playerNext()
                    else                        MediaService.playerPrev()
                }
            }
        }

        // ── RIGHT: Status pill ─────────────────────────────────────────
        Rectangle {
            id: rightPill
            // Gone entirely when every right-side element is switched off.
            visible: ["bluetooth", "volume", "battery", "network", "clock", "notifs"]
                     .some(k => BarService.isShown(k))
            anchors {
                right: parent.right; rightMargin: 10
                top: parent.top;     topMargin: bar.theme.sc(5)
            }
            height: bar.theme.ph
            width:  rightLayout.implicitWidth
            radius: bar.theme.pr; color: bar.theme.bg

            // The hover popup panel (and the notification toasts) grow out
            // of this pill: claim it for this monitor, and square the bottom
            // corners as they open. The 4th power keeps them round until the
            // panel is nearly full width, reaching 0 exactly when it spans
            // the pill.
            readonly property real popupProgress:
                (PopupService.popupScreen ?? Quickshell.screens[0]) === bar.screen
                    ? Math.max(PopupService.rightPopupProgress, NotificationService.toastProgress) : 0
            readonly property real bottomRadius: bar.theme.pr * (1 - Math.pow(popupProgress, 4))
            bottomLeftRadius:  bottomRadius
            bottomRightRadius: bottomRadius

            HoverHandler {
                onHoveredChanged: if (hovered) {
                    PopupService.popupScreen = bar.screen
                }
            }

            RowLayout {
                id: rightLayout
                anchors.verticalCenter: parent.verticalCenter
                x: 0; height: bar.theme.ph; spacing: 0

                // Pill end padding (modules add 10px each side), so the
                // ends stay even whichever modules are shown.
                Item { implicitWidth: bar.theme.sc(5) }

                // ── Bluetooth (native Quickshell.Bluetooth) ──
                Text {
                    visible: BarService.isShown("bluetooth")
                    Layout.alignment: Qt.AlignVCenter
                    text: {
                        const adapter = Bluetooth.defaultAdapter
                        const conn = adapter?.enabled
                            ? Bluetooth.devices.values.filter(d => d.connected)
                            : []
                        return (conn.length > 0 ? conn.length + " " : "") + ""
                    }
                    color: Bluetooth.defaultAdapter?.enabled ? bar.theme.fg : bar.theme.outline
                    font.family: bar.ff; font.bold: true; font.pixelSize: bar.theme.fs
                    leftPadding: bar.theme.sc(10); rightPadding: bar.theme.sc(10)

                    // Hit area reaching up to the screen edge.
                    TopHit {
                        HoverHandler {
                            onHoveredChanged: PopupService.hoverModule("bluetooth", hovered)
                        }

                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: bar.openSettings("bluetooth")
                        }
                    }
                }

                // ── Volume (wpctl) ──
                Text {
                    visible: BarService.isShown("volume")
                    Layout.alignment: Qt.AlignVCenter
                    text: {
                        if (AudioService.volPct < 0)  return "--%"
                        if (AudioService.volMuted)    return "󰝟"
                        var vol = AudioService.volPct
                        var ic  = vol < 33 ? "󰕿" : vol < 67 ? "󰖀" : "󰕾"
                        return vol + "% " + ic
                    }
                    color: bar.theme.fg
                    font.family: bar.ff; font.bold: true; font.pixelSize: bar.theme.fs
                    leftPadding: bar.theme.sc(10); rightPadding: bar.theme.sc(10)

                    // Hit area reaching up to the screen edge.
                    TopHit {
                        HoverHandler {
                            onHoveredChanged: {
                                PopupService.hoverModule("sink", hovered)
                                if (hovered) AudioService.refreshSinks()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: bar.openSettings("audio")
                            onWheel: wheel => AudioService.adjustVolume(wheel.angleDelta.y > 0 ? "+" : "-")
                        }
                    }
                }

                // ── Battery (UPower.displayDevice) ──
                Item {
                    id: batt
                    visible: BarService.isShown("battery") && (UPower.displayDevice?.isPresent ?? false)
                    Layout.fillHeight: true
                    implicitWidth:  battRow.implicitWidth + bar.theme.sc(20)
                    implicitHeight: battRow.implicitHeight

                    // Spans the full pill height and centres children against
                    // it with floor(), so the drawn icon sits on whole pixels
                    // at the pill's true centre instead of rounding 1px low.
                    Row {
                        id: battRow
                        x: Math.round((batt.width - width) / 2)
                        height: batt.height
                        spacing: bar.theme.sc(6)

                        Text {
                            visible: BatteryService.batteryPercentEnabled
                            y: Math.round((battRow.height - height) / 2)
                            text: Math.round(battIcon.pct * 100) + "%"
                            color: bar.theme.fg
                            font.family: bar.ff; font.bold: true; font.pixelSize: bar.theme.fs
                        }

                        BatteryIcon {
                            id: battIcon
                            y: Math.floor((battRow.height - height) / 2)
                            theme: bar.theme
                            size: bar.theme.sc(11)
                        }
                    }

                    // Hit area reaching up to the screen edge.
                    TopHit {
                        HoverHandler {
                            onHoveredChanged: PopupService.hoverModule("battery", hovered)
                        }

                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: bar.openSettings("battery")
                        }
                    }
                }

                // ── Network (reactive nmcli monitor) ──
                Text {
                    visible: BarService.isShown("network")
                    Layout.alignment: Qt.AlignVCenter
                    text: NetworkService.netIcon; color: bar.theme.fg
                    font.family: bar.ff; font.bold: true; font.pixelSize: bar.theme.fs
                    leftPadding: bar.theme.sc(10); rightPadding: bar.theme.sc(10)

                    // Hit area reaching up to the screen edge.
                    TopHit {
                        HoverHandler {
                            onHoveredChanged: {
                                PopupService.hoverModule("wifi", hovered)
                                if (hovered) NetworkService.refreshWifi()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: bar.openSettings("wifi")
                        }
                    }
                }

                // ── Clock ──
                // SystemClock ticks on the minute (it only shows HH:mm).
                Text {
                    visible: BarService.isShown("clock")
                    Layout.alignment: Qt.AlignVCenter
                    SystemClock { id: clock; precision: SystemClock.Minutes }
                    text: Qt.formatDate(clock.date, "ddd dd MMM") + " " + Qt.formatTime(clock.date, "HH:mm")
                    color: bar.theme.fg
                    font.family: bar.ff; font.bold: true; font.pixelSize: bar.theme.fs
                    leftPadding: bar.theme.sc(10); rightPadding: bar.theme.sc(10)

                    // Hit area reaching up to the screen edge.
                    TopHit {
                        HoverHandler {
                            onHoveredChanged: PopupService.hoverModule("clock", hovered)
                        }
                    }
                }

                // ── Notifications (native) — pinned to far right ──
                // Hover opens; left-click pins open; middle-click clears all.
                Text {
                    visible: BarService.isShown("notifs") && NotificationService.notifIcon !== ""
                    Layout.alignment: Qt.AlignVCenter
                    text: NotificationService.notifIcon; color: bar.theme.fg
                    font.family: bar.ff; font.bold: true; font.pixelSize: bar.theme.fs
                    leftPadding: bar.theme.sc(10); rightPadding: bar.theme.sc(10)

                    // Hit area reaching up to the screen edge.
                    TopHit {
                        HoverHandler {
                            onHoveredChanged: PopupService.hoverModule("notif", hovered)
                        }

                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.LeftButton)        NotificationService.toggleNotifPanel()
                                else if (mouse.button === Qt.MiddleButton) NotificationService.clearAllNotifs()
                            }
                        }
                    }
                }

                Item { implicitWidth: bar.theme.sc(5) }
            }

        }
    }

    // Notification toasts hanging from the right pill (below the hover
    // popups, which take the pill over while open).
    BarToastPanel {
        id: toastPanel
        anchors.fill: parent
        theme: bar.popupTheme
        pill: rightPill
        uiScale: bar.theme.scale
        hostActive: bar.visible
                    && (PopupService.popupScreen ?? Quickshell.screens[0]) === bar.screen
    }

    // Hover popups for the right pill (only on the bar they belong to).
    BarPopupPanel {
        id: popupPanel
        anchors.fill: parent
        theme: bar.popupTheme
        pill: rightPill
        uiScale: bar.theme.scale
        hostActive: (PopupService.popupScreen ?? Quickshell.screens[0]) === bar.screen
    }
}
