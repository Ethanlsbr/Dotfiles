import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Bluetooth

// Control center — anchored top-right, revealed on hover of the bar's bell
// icon. Holds quick toggles (Wi-Fi / Bluetooth / Do Not Disturb), brightness
// and volume sliders, and the live notification list.
PanelWindow {
    id: overlay

    required property var shellRoot
    required property var theme

    readonly property var items: shellRoot.notifServer
        ? shellRoot.notifServer.trackedNotifications.values
        : []

    // Open when the popup flag is set (hover/click). Unlike the old behaviour
    // it shows even with zero notifications, since it now hosts controls.
    readonly property bool _open: shellRoot.notifPopupOpen
    visible: _open || exitAnim.running

    anchors { top: true; right: true }
    margins.right: 10
    margins.top:   6
    exclusiveZone: 0
    color: "transparent"

    implicitWidth:  360
    implicitHeight: card.implicitHeight

    on_OpenChanged: _open ? enterAnim.restart() : exitAnim.restart()

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: card; property: "opacity"; from: 0; to: 1;   duration: 360; easing.type: Easing.OutCubic }
        NumberAnimation { target: card;      property: "scale"; from: 0.96; to: 1; duration: 360; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: card; property: "opacity"; to: 0;   duration: 280; easing.type: Easing.InCubic }
        NumberAnimation { target: card;      property: "scale"; to: 0.96; duration: 280; easing.type: Easing.InCubic }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        color: overlay.theme.bg
        radius: overlay.theme.pr
        border.color: overlay.theme.sep
        border.width: 1
        opacity: 0
        implicitHeight: col.implicitHeight + 24
        scale: 0.96
        transformOrigin: Item.Top

        HoverHandler {
            onHoveredChanged: hovered ? overlay.shellRoot.stopHideTimer("notif")
                                      : overlay.shellRoot.startHideTimer("notif")
        }

        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 12

            // ── Quick toggles row ────────────────────────────────────
            Row {
                width: parent.width
                spacing: 10

                QuickToggle {
                    label: "Wi-Fi"
                    icon:  overlay.shellRoot.wifiEnabled ? "" : "󰖪"
                    on:    overlay.shellRoot.wifiEnabled
                    onClicked: overlay.shellRoot.toggleWifi(!overlay.shellRoot.wifiEnabled)
                }
                QuickToggle {
                    label: "Bluetooth"
                    icon:  (Bluetooth.defaultAdapter?.enabled ?? false) ? "" : "󰂲"
                    on:    Bluetooth.defaultAdapter?.enabled ?? false
                    onClicked: {
                        const a = Bluetooth.defaultAdapter
                        if (a) a.enabled = !a.enabled
                    }
                }
                QuickToggle {
                    label: overlay.shellRoot.dndEnabled ? "DND on" : "DND off"
                    icon:  overlay.shellRoot.dndEnabled ? "󰂛" : "󰂚"
                    on:    overlay.shellRoot.dndEnabled
                    onClicked: overlay.shellRoot.toggleDnd()
                }
            }

            // ── Brightness slider ────────────────────────────────────
            CcSlider {
                width: parent.width
                icon:  "󰃟"
                value: overlay.shellRoot.brightnessPct < 0 ? 0 : overlay.shellRoot.brightnessPct
                onMoved: pct => overlay.shellRoot.setBrightnessPct(pct)
            }

            // ── Volume slider ────────────────────────────────────────
            CcSlider {
                width: parent.width
                icon:  overlay.shellRoot.volMuted ? "󰝟"
                       : (overlay.shellRoot.volPct < 33 ? "󰕿"
                          : overlay.shellRoot.volPct < 67 ? "󰖀" : "󰕾")
                value: overlay.shellRoot.volMuted ? 0
                       : (overlay.shellRoot.volPct < 0 ? 0 : overlay.shellRoot.volPct)
                onMoved:     pct => overlay.shellRoot.setVolumePct(pct)
                onIconClick: overlay.shellRoot.toggleMute()
            }

            // ── Divider ──────────────────────────────────────────────
            Rectangle {
                width: parent.width; height: 1
                color: overlay.theme.sep; opacity: 0.5
            }

            // ── Notifications header ─────────────────────────────────
            // Row stays at a fixed height so the panel is the same size with
            // or without notifications; only its contents toggle.
            Row {
                width: parent.width
                height: 22

                Text {
                    visible: overlay.items.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: overlay.items.length + " notification" + (overlay.items.length === 1 ? "" : "s")
                    color: overlay.theme.outline
                    font.family: overlay.theme.ff
                    font.bold: true
                    font.pixelSize: overlay.theme.fs - 2
                    width: parent.width - clearBtn.width
                }
                Rectangle {
                    id: clearBtn
                    visible: overlay.items.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 80; height: 22
                    radius: 7
                    color: clearHover.hovered ? overlay.theme.error : Qt.darker(overlay.theme.bg, 1.1)
                    border.color: overlay.theme.sep
                    border.width: 1
                    HoverHandler { id: clearHover }
                    Text {
                        anchors.centerIn: parent
                        text: "Clear all"
                        color: overlay.theme.fg
                        font.family: overlay.theme.ff
                        font.pixelSize: overlay.theme.fs - 3
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: overlay.shellRoot.clearAllNotifs()
                    }
                }
            }

            // ── Notification cards (fixed-height area + scrollbar) ────
            // Always reserves its full height so an empty panel matches a
            // full one; the empty-state message sits centred inside it.
            Item {
                id: notifArea
                width: col.width
                readonly property int maxH: 300
                height: maxH

                Text {
                    visible: overlay.items.length === 0
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: overlay.shellRoot.dndEnabled ? "Do Not Disturb is on" : "No notifications"
                    color: overlay.theme.outline
                    font.family: overlay.theme.ff
                    font.pixelSize: overlay.theme.fs - 1
                }

                Flickable {
                    id: notifFlick
                    anchors.fill: parent
                    anchors.rightMargin: 10   // room for the scrollbar
                    clip: true
                    contentHeight: notifCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: notifCol
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: overlay.items

                            delegate: Rectangle {
                                required property var modelData
                                width: notifCol.width
                                implicitHeight: Math.max(58, body.y + body.implicitHeight + 10)
                                radius: 12
                                color: Qt.darker(overlay.theme.bg, 1.15)
                                border.color: modelData.urgency === 2 ? overlay.theme.error : overlay.theme.sep
                                border.width: 1

                                Item {
                                    id: nIcon
                                    anchors { left: parent.left; top: parent.top; margins: 10 }
                                    implicitWidth: 30; implicitHeight: 30
                                    width: 30; height: 30

                                    // notify-send's -i <x> → image="image://icon/<x>"
                                    // (path or name). Provider loads paths; names
                                    // need our resolver (Qt stuck on hicolor).
                                    readonly property string rawImage: modelData.image || ""
                                    readonly property string iconName: rawImage.startsWith("image://icon/")
                                            ? rawImage.substring(13)
                                            : (modelData.appIcon || "")
                                    readonly property bool nameIsPath: iconName.startsWith("/") || iconName.startsWith("file:")
                                    readonly property string resolved: {
                                        if (!rawImage.startsWith("image://icon/"))
                                            return rawImage
                                        return nameIsPath ? rawImage
                                                          : overlay.shellRoot.iconFor(iconName)
                                    }
                                    readonly property string glyph: overlay.shellRoot.glyphForIcon(iconName)

                                    Text {
                                        anchors.centerIn: parent
                                        visible: nIcon.glyph !== ""
                                        text: nIcon.glyph
                                        color: overlay.theme.fg
                                        font.family: overlay.theme.ff
                                        font.pixelSize: 24
                                    }
                                    IconImage {
                                        anchors.fill: parent
                                        asynchronous: true
                                        visible: nIcon.glyph === "" && nIcon.resolved !== ""
                                        source: nIcon.resolved
                                    }
                                    IconImage {
                                        anchors.fill: parent
                                        asynchronous: true
                                        visible: nIcon.glyph === "" && nIcon.resolved === ""
                                        source: overlay.shellRoot.iconFor("dialog-information")
                                    }
                                }

                                Text {
                                    id: appName
                                    anchors { left: nIcon.right; leftMargin: 10; top: parent.top; topMargin: 9
                                              right: closeN.left; rightMargin: 6 }
                                    text: modelData.appName || "Notification"
                                    color: overlay.theme.outline
                                    font.family: overlay.theme.ff
                                    font.pixelSize: overlay.theme.fs - 3
                                    elide: Text.ElideRight
                                }
                                Text {
                                    id: summary
                                    anchors { left: nIcon.right; leftMargin: 10; top: appName.bottom; topMargin: 1
                                              right: closeN.left; rightMargin: 6 }
                                    text: modelData.summary || ""
                                    color: overlay.theme.fg
                                    font.family: overlay.theme.ff
                                    font.bold: true
                                    font.pixelSize: overlay.theme.fs - 1
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                }
                                Text {
                                    id: body
                                    anchors { left: nIcon.right; leftMargin: 10
                                              top: summary.visible ? summary.bottom : appName.bottom; topMargin: 2
                                              right: parent.right; rightMargin: 10 }
                                    text: modelData.body || ""
                                    color: overlay.theme.txt2
                                    font.family: overlay.theme.ff
                                    font.pixelSize: overlay.theme.fs - 2
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                }

                                Rectangle {
                                    id: closeN
                                    anchors { right: parent.right; top: parent.top; margins: 8 }
                                    width: 20; height: 20; radius: 10
                                    color: closeNHover.hovered ? overlay.theme.error : "transparent"
                                    HoverHandler { id: closeNHover }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: overlay.theme.fg
                                        font.family: overlay.theme.ff
                                        font.pixelSize: overlay.theme.fs - 3
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: overlay.shellRoot.dismissNotif(modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // Scrollbar (right edge) — visible only when content overflows.
                Rectangle {
                    id: sbTrack
                    readonly property bool active: notifFlick.contentHeight > notifFlick.height
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 6
                    radius: 3
                    color: "transparent"
                    visible: active

                    Rectangle {
                        id: sbThumb
                        width: parent.width
                        radius: parent.radius
                        color: overlay.theme.hi(1.6)
                        height: Math.max(28, sbTrack.height * notifFlick.visibleArea.heightRatio)
                        y: notifFlick.visibleArea.yPosition * sbTrack.height

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            drag.target: sbThumb
                            drag.axis: Drag.YAxis
                            drag.minimumY: 0
                            drag.maximumY: sbTrack.height - sbThumb.height
                            onPositionChanged: if (drag.active) {
                                notifFlick.contentY = (sbThumb.y / (sbTrack.height - sbThumb.height))
                                    * (notifFlick.contentHeight - notifFlick.height)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Reusable quick-toggle pill ───────────────────────────────────────
    component QuickToggle: Rectangle {
        id: qt
        property string label: ""
        property string icon:  ""
        property bool   on:    false
        signal clicked()

        width: (col.width - 20) / 3
        height: 58
        radius: 12
        color: qt.on ? overlay.theme.hi(1.5)
                     : Qt.darker(overlay.theme.bg, 1.15)
        border.color: qt.on ? overlay.theme.primary : overlay.theme.sep
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }

        Column {
            anchors.centerIn: parent
            spacing: 3
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qt.icon
                color: qt.on ? overlay.theme.primary : overlay.theme.fg
                font.family: overlay.theme.ff
                font.pixelSize: overlay.theme.fs + 4
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qt.label
                color: qt.on ? overlay.theme.primary : overlay.theme.txt2
                font.family: overlay.theme.ff
                font.pixelSize: overlay.theme.fs - 4
                font.bold: qt.on
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: qt.clicked()
        }
    }

    // ── Reusable control-center slider (icon + track + %) ────────────────
    component CcSlider: Item {
        id: sl
        property string icon: ""
        property int    value: 0          // 0..100
        signal moved(int pct)
        signal iconClick()

        height: 30

        Text {
            id: slIcon
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 26
            horizontalAlignment: Text.AlignHCenter
            text: sl.icon
            color: overlay.theme.fg
            font.family: overlay.theme.ff
            font.pixelSize: overlay.theme.fs + 2
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sl.iconClick()
            }
        }

        Rectangle {
            id: slTrack
            anchors { left: slIcon.right; leftMargin: 10
                      right: slPct.left;  rightMargin: 10
                      verticalCenter: parent.verticalCenter }
            height: 8
            radius: 4
            color: overlay.theme.field

            Rectangle {
                id: slFill
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.max(0, Math.min(1, sl.value / 100))
                color: overlay.theme.tertiary
            }
            Rectangle {
                width: 16; height: 16; radius: 8
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(parent.width - width, slFill.width - width / 2))
                color: overlay.theme.tertiary
                border.color: overlay.theme.bg
                border.width: 2
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed:         sl.moved(mouseX / width * 100)
                onPositionChanged: if (pressed) sl.moved(mouseX / width * 100)
            }
        }

        Text {
            id: slPct
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 38
            horizontalAlignment: Text.AlignRight
            text: sl.value + "%"
            color: overlay.theme.fg
            font.family: overlay.theme.ff
            font.pixelSize: overlay.theme.fs - 2
        }
    }
}
