import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Services.UPower

PanelWindow {
    id: bar

    required property var shellRoot
    required property var theme
    // The monitor connector name (set by the Variants delegate). Used instead
    // of `screen.name` so the `visible` binding doesn't loop with `screen`.
    property string monitorName: ""

    // The Hyprland monitor matching this bar — used to scope the workspace
    // module to this screen only (and to know its active workspace).
    readonly property var hyprMonitor:
        Hyprland.monitors.values.find(m => m.name === bar.monitorName) ?? null

    // Expose for overlay alignment — published to shellRoot (all bars share
    // the same pill width since the content is identical).
    readonly property real rightPillWidth: rightPill.width
    onRightPillWidthChanged: bar.shellRoot.rightPillWidth = rightPillWidth
    Component.onCompleted: bar.shellRoot.rightPillWidth = rightPillWidth

    // Shown unless globally hidden (`qs ipc call bar toggle`) or disabled for
    // this specific monitor in the settings Monitor pane.
    visible: bar.shellRoot.barVisible && bar.shellRoot.barEnabledOn(bar.monitorName)

    anchors { top: true; left: true; right: true }
    implicitHeight: 40
    // Reserve less than the full height: the pills only reach ~35px, so the
    // bottom few px are dead space. Trimming the exclusive zone pulls tiled
    // windows up closer to the bar without clipping anything.
    exclusiveZone: bar.visible ? 34 : 0
    color: "transparent"

    Item {
        anchors.fill: parent

        // ── Dashboard hover trigger ───────────────────────────────────
        // Centered 240×full-bar zone. HoverHandler is geometric and fires
        // even when the media pill's MouseArea sits on top of it.
        Item {
            id: dashTrigger
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 240

            HoverHandler {
                onHoveredChanged: hovered ? bar.shellRoot.openDashboard()
                                          : bar.shellRoot.startDashboardHide()
            }
        }

        // ── LEFT: Power + Workspaces ───────────────────────────────────
        Row {
            anchors {
                left: parent.left
                leftMargin: 10
                top: parent.top
                topMargin: 5
            }
            spacing: 10

            Rectangle {
                id: archBtn
                height: bar.theme.ph; width:50
                radius: bar.theme.pr
                color: archHover.hovered
                       ? bar.theme.hi(1.3)
                       : bar.theme.bg
                Text {
                    anchors.centerIn: parent
                    text: "  "
                    color: bar.theme.fg
                    font.family: bar.theme.ff; font.bold: true; font.pixelSize: bar.theme.fs
                }
                HoverHandler { id: archHover }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.shellRoot.toggleLauncher()
                }
            }

            // Mirrors the waybar #workspaces module 1:1 — same colours,
            // radii, padding and hover behaviour. Bar is 40px tall and
            // waybar gives #workspaces `margin: 5px 1px 0 1px`, so the
            // module is 35px tall; with button `margin: 4 3`, buttons
            // are 27px tall. We reproduce those exact sizes here even
            // though it makes this pill a touch chunkier than the others.
            Rectangle {
                height: bar.theme.ph
                width:  wsRow.implicitWidth + 8         // module-level horizontal padding
                radius: 15
                color:  bar.theme.bg

                Row {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: 4                            // tighter than the literal 6px to match waybar's rendered gap

                    Repeater {
                        // Only this monitor's workspaces, in id order.
                        model: Hyprland.workspaces.values
                            .filter(w => w.monitor && w.monitor.name === bar.monitorName)
                            .sort((a, b) => a.id - b.id)
                        delegate: Rectangle {
                            id: wsBtn
                            required property var modelData
                            readonly property bool isActive:
                                bar.hyprMonitor?.activeWorkspace?.id === modelData.id

                            height: 22
                            radius: 15                    // waybar border-radius: 15px
                            color:  bar.theme.active      // every button: #38375B
                            opacity: wsHover.hovered ? 0.7 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            Behavior on width   { NumberAnimation { duration: 300 } }

                            // Inactive buttons hug their content with comfortable
                            // side padding; active gets `min-width: 40px` exactly
                            // like the waybar CSS rule.
                            width: isActive
                                ? Math.max(40, wsLabel.implicitWidth + 40)
                                : Math.max(28, wsLabel.implicitWidth + 14)

                            Text {
                                id: wsLabel
                                anchors.centerIn: parent
                                text: modelData.id
                                color: wsHover.hovered ? "#1a110f" : bar.theme.fg
                                font.family: bar.theme.ff
                                font.bold: true
                                font.pixelSize: bar.theme.fs   // 14px — matches the rest of the bar
                            }
                            HoverHandler { id: wsHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                // Hyprland 0.55+ with Lua config: the legacy
                                // "workspace N" dispatch is now wrapped through
                                // Lua, so we call the new focus dispatcher.
                                onClicked: Hyprland.dispatch("hl.dsp.focus({workspace=" + modelData.id + "})")
                            }
                        }
                    }
                }
            }
        }

        // ── CENTER: Spotify ────────────────────────────────────────────
        Rectangle {
            visible: bar.shellRoot.mediaText !== ""
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top; topMargin: 5
            }
            height: bar.theme.ph
            width:  mediaRow.implicitWidth + 20
            radius: bar.theme.pr; color: bar.theme.bg

            Row {
                id: mediaRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""; color: bar.theme.green
                    font.family: bar.theme.ff; font.pixelSize: 15
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: bar.shellRoot.mediaText; color: bar.theme.fg
                    font.family: bar.theme.ff; font.bold: true; font.pixelSize: bar.theme.fs
                    elide: Text.ElideRight; maximumLineCount: 1
                    width: Math.min(implicitWidth, 320)
                }
            }

            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) bar.shellRoot.playerToggle()
                    else                                bar.shellRoot.playerNext()
                }
                onWheel: wheel => {
                    if (wheel.angleDelta.y > 0) bar.shellRoot.playerNext()
                    else                        bar.shellRoot.playerPrev()
                }
            }
        }

        // ── RIGHT: Status pill ─────────────────────────────────────────
        Rectangle {
            id: rightPill
            anchors {
                right: parent.right; rightMargin: 10
                top: parent.top;     topMargin: 5
            }
            height: bar.theme.ph
            width:  rightLayout.implicitWidth
            radius: bar.theme.pr; color: bar.theme.bg

            RowLayout {
                id: rightLayout
                anchors.verticalCenter: parent.verticalCenter
                x: 0; height: bar.theme.ph; spacing: 0

                // ── Bluetooth (native Quickshell.Bluetooth) ──
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: {
                        const adapter = Bluetooth.defaultAdapter
                        const conn = adapter?.enabled
                            ? Bluetooth.devices.values.filter(d => d.connected)
                            : []
                        return (conn.length > 0 ? conn.length + " " : "") + ""
                    }
                    color: Bluetooth.defaultAdapter?.enabled ? bar.theme.fg : bar.theme.outline
                    font.family: bar.theme.ff; font.bold: true; font.pixelSize: bar.theme.fs
                    leftPadding: 15; rightPadding: 10

                    HoverHandler {
                        onHoveredChanged: {
                            if (hovered) bar.shellRoot.showPopup("bluetooth")
                            else         bar.shellRoot.startHideTimer("bluetooth")
                        }
                    }

                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: bar.shellRoot.launchBlueman()
                    }
                }

                // ── Volume (wpctl) ──
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: {
                        if (bar.shellRoot.volPct < 0)  return "  --%  "
                        if (bar.shellRoot.volMuted)    return "  󰝟  "
                        var vol = bar.shellRoot.volPct
                        var ic  = vol < 33 ? "󰕿" : vol < 67 ? "󰖀" : "󰕾"
                        return "  " + vol + "% " + ic + "  "
                    }
                    color: bar.theme.fg
                    font.family: bar.theme.ff; font.bold: true; font.pixelSize: bar.theme.fs
                    leftPadding: 0; rightPadding: 0

                    HoverHandler {
                        onHoveredChanged: {
                            if (hovered) {
                                bar.shellRoot.showPopup("sink")
                                bar.shellRoot.refreshSinks()
                            } else {
                                bar.shellRoot.startHideTimer("sink")
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: bar.shellRoot.launchPavucontrol()
                        onWheel: wheel => bar.shellRoot.adjustVolume(wheel.angleDelta.y > 0 ? "+" : "-")
                    }
                }

                // ── Battery (UPower.displayDevice) ──
                Text {
                    visible: UPower.displayDevice?.isPresent ?? false
                    Layout.alignment: Qt.AlignVCenter
                    text: {
                        var dev = UPower.displayDevice
                        if (!dev?.isPresent) return ""
                        var pct   = Math.round(dev.percentage * 100)
                        var icons = ["", "", "", "", ""]
                        var charging = [
                            UPowerDeviceState.Charging,
                            UPowerDeviceState.FullyCharged,
                            UPowerDeviceState.PendingCharge
                        ].includes(dev.state)
                        var ic = charging ? "" : icons[Math.min(4, Math.floor(pct / 21))]
                        return pct + "% " + ic
                    }
                    color: {
                        var dev = UPower.displayDevice
                        if (!dev?.isPresent) return bar.theme.fg
                        var pct = dev.percentage * 100
                        return pct < 15 ? bar.theme.error
                             : pct < 30 ? bar.theme.warn
                             : bar.theme.fg
                    }
                    font.family: bar.theme.ff; font.bold: true; font.pixelSize: bar.theme.fs
                    leftPadding: 10; rightPadding: 10

                    HoverHandler {
                        onHoveredChanged: {
                            if (hovered) bar.shellRoot.showPopup("battery")
                            else         bar.shellRoot.startHideTimer("battery")
                        }
                    }
                }

                // ── Network (reactive nmcli monitor) ──
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: bar.shellRoot.netIcon; color: bar.theme.fg
                    font.family: bar.theme.ff; font.bold: true; font.pixelSize: bar.theme.fs
                    leftPadding: 10; rightPadding: 10

                    HoverHandler {
                        onHoveredChanged: {
                            if (hovered) {
                                bar.shellRoot.showPopup("wifi")
                                bar.shellRoot.refreshWifi()
                            } else {
                                bar.shellRoot.startHideTimer("wifi")
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: bar.shellRoot.launchNmtui()
                    }
                }

                // ── Clock ──
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    property var now: new Date()
                    text: Qt.formatDate(now, "ddd dd MMM") + " " + Qt.formatTime(now, "HH:mm")
                    color: bar.theme.fg
                    font.family: bar.theme.ff; font.bold: true; font.pixelSize: bar.theme.fs
                    leftPadding: 10; rightPadding: 10

                    HoverHandler {
                        onHoveredChanged: {
                            if (hovered) bar.shellRoot.showPopup("clock")
                            else         bar.shellRoot.startHideTimer("clock")
                        }
                    }

                    Timer {
                        interval: 1000; running: true; repeat: true
                        onTriggered: parent.now = new Date()
                    }
                }

                // ── Notifications (native) — pinned to far right ──
                // Hover opens the notification center; left-click toggles it
                // (pinned open), middle-click clears all.
                Text {
                    visible: bar.shellRoot.notifIcon !== ""
                    Layout.alignment: Qt.AlignVCenter
                    text: bar.shellRoot.notifIcon; color: bar.theme.fg
                    font.family: bar.theme.ff; font.bold: true; font.pixelSize: bar.theme.fs
                    leftPadding: 10; rightPadding: 15

                    HoverHandler {
                        onHoveredChanged: {
                            if (hovered) bar.shellRoot.showPopup("notif")
                            else         bar.shellRoot.startHideTimer("notif")
                        }
                    }

                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton)        bar.shellRoot.toggleNotifPanel()
                            else if (mouse.button === Qt.MiddleButton) bar.shellRoot.clearAllNotifs()
                        }
                    }
                }
            }

        }
    }
}
