import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Bluetooth
import qs.common.ui
import qs.modules.audio
import qs.modules.brightness
import qs.modules.icons
import qs.modules.network

// Bar popup page: control center (hover the bell) — quick toggles,
// brightness / volume sliders, live notification list.
Item {
    id: popup

    required property var theme
    implicitHeight: col.implicitHeight + 24

    readonly property var items: NotificationService.notifServer
        ? NotificationService.notifServer.trackedNotifications.values
        : []

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 12

        // ── Quick toggles row ────────────────────────────────────
        Row {
            width: parent.width
            spacing: 8

            QuickToggle {
                label: "Wi-Fi"
                icon:  NetworkService.wifiEnabled ? "\uf1eb" : "\udb81\uddaa"
                on:    NetworkService.wifiEnabled
                onClicked: NetworkService.toggleWifi(!NetworkService.wifiEnabled)
            }
            QuickToggle {
                label: "Bluetooth"
                icon:  (Bluetooth.defaultAdapter?.enabled ?? false) ? "\uf294" : "\udb80\udcb2"
                on:    Bluetooth.defaultAdapter?.enabled ?? false
                onClicked: {
                    const a = Bluetooth.defaultAdapter
                    if (a) a.enabled = !a.enabled
                }
            }
            QuickToggle {
                label: "Do not disturb"
                icon:  NotificationService.dndEnabled ? "\uf1f6" : "\uf0f3"
                on:    NotificationService.dndEnabled
                onClicked: NotificationService.toggleDnd()
            }
        }

        // ── Brightness + volume ──────────────────────────────────
        UiCard {
            theme: popup.theme
            height: sliderCol.implicitHeight + 16
            Column {
                id: sliderCol
                x: 10; y: 8
                width: parent.width - 24
                CcSlider {
                    width: parent.width
                    icon:  "\udb80\udcdf"
                    value: BrightnessService.brightnessPct < 0 ? 0 : BrightnessService.brightnessPct
                    onMoved:   pct => BrightnessService.setBrightnessPct(pct)
                    onStepped: dir => BrightnessService.adjustBrightness(dir > 0 ? "+" : "-")
                }
                CcSlider {
                    width: parent.width
                    muted: AudioService.volMuted
                    icon:  AudioService.volMuted ? "\udb81\udf5f"
                           : (AudioService.volPct < 33 ? "\udb81\udd7f"
                              : AudioService.volPct < 67 ? "\udb81\udd80" : "\udb81\udd7e")
                    value: AudioService.volMuted ? 0
                           : (AudioService.volPct < 0 ? 0 : AudioService.volPct)
                    onMoved:     pct => AudioService.setVolumePct(pct)
                    onIconClick: AudioService.toggleMute()
                }
            }
        }

        // ── Notifications header ─────────────────────────────────
        // Fixed height so the panel size doesn't change with content.
        Item {
            width: parent.width
            height: 32

            Text {
                anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                text: "Notifications" + (popup.items.length > 0 ? "  ·  " + popup.items.length : "")
                color: popup.theme.fg
                font.family: popup.theme.ff; font.bold: true; font.pixelSize: popup.theme.fs - 1
            }
            UiButton {
                visible: popup.items.length > 0
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                theme: popup.theme
                icon: "\uf1f8"
                text: "Clear all"
                onClicked: NotificationService.clearAllNotifs()
            }
        }

        // ── Notification cards (fixed-height area + scrollbar) ────
        // Full height always reserved; empty-state message centres in it.
        Item {
            id: notifArea
            width: col.width
            readonly property int maxH: 300
            height: maxH

            Text {
                visible: popup.items.length === 0
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: NotificationService.dndEnabled ? "Do not disturb is on" : "You're all caught up"
                color: popup.theme.txt2
                font.family: popup.theme.ff
                font.pixelSize: popup.theme.fs - 1
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
                        model: popup.items

                        delegate: Rectangle {
                            required property var modelData
                            width: notifCol.width
                            implicitHeight: Math.max(58, body.y + body.implicitHeight + 10)
                            radius: 12
                            color: popup.theme.light ? popup.theme.paper : popup.theme.surface
                            border.color: modelData.urgency === 2 ? popup.theme.error
                                        : Qt.rgba(popup.theme.sep.r, popup.theme.sep.g, popup.theme.sep.b, 0.7)
                            border.width: 1

                            Item {
                                id: nIcon
                                anchors { left: parent.left; top: parent.top; margins: 10 }
                                implicitWidth: 30; implicitHeight: 30
                                width: 30; height: 30

                                // image://icon/<x> may be a path (provider
                                // loads it) or a name (needs our resolver).
                                readonly property string rawImage: modelData.image || ""
                                readonly property string iconName: rawImage.startsWith("image://icon/")
                                        ? rawImage.substring(13)
                                        : (modelData.appIcon || "")
                                readonly property bool nameIsPath: iconName.startsWith("/") || iconName.startsWith("file:")
                                readonly property string resolved: {
                                    if (!rawImage.startsWith("image://icon/"))
                                        return rawImage
                                    return nameIsPath ? rawImage
                                                      : IconService.iconFor(iconName)
                                }
                                // Critical → warning sign, whatever icon the sender passed.
                                readonly property bool critical: modelData.urgency === 2
                                readonly property string glyph: critical ? "" : IconService.glyphForIcon(iconName)

                                Text {
                                    anchors.centerIn: parent
                                    visible: nIcon.glyph !== ""
                                    text: nIcon.glyph
                                    color: nIcon.critical ? popup.theme.error : popup.theme.fg
                                    font.family: popup.theme.ff
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
                                    source: IconService.iconFor("dialog-information")
                                }
                            }

                            Text {
                                id: appName
                                anchors { left: nIcon.right; leftMargin: 10; top: parent.top; topMargin: 9
                                          right: closeN.left; rightMargin: 6 }
                                text: modelData.appName || "Notification"
                                color: popup.theme.outline
                                font.family: popup.theme.ff
                                font.pixelSize: popup.theme.fs - 3
                                elide: Text.ElideRight
                            }
                            Text {
                                id: summary
                                anchors { left: nIcon.right; leftMargin: 10; top: appName.bottom; topMargin: 1
                                          right: closeN.left; rightMargin: 6 }
                                text: modelData.summary || ""
                                color: popup.theme.fg
                                font.family: popup.theme.ff
                                font.bold: true
                                font.pixelSize: popup.theme.fs - 1
                                elide: Text.ElideRight
                                visible: text.length > 0
                            }
                            Text {
                                id: body
                                anchors { left: nIcon.right; leftMargin: 10
                                          top: summary.visible ? summary.bottom : appName.bottom; topMargin: 2
                                          right: parent.right; rightMargin: 10 }
                                text: modelData.body || ""
                                color: popup.theme.txt2
                                font.family: popup.theme.ff
                                font.pixelSize: popup.theme.fs - 2
                                wrapMode: Text.WordWrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                visible: text.length > 0
                            }

                            Rectangle {
                                id: closeN
                                anchors { right: parent.right; top: parent.top; margins: 8 }
                                width: 22; height: 22; radius: 6
                                color: closeNHover.hovered
                                       ? Qt.rgba(popup.theme.error.r, popup.theme.error.g, popup.theme.error.b, 0.18)
                                       : "transparent"
                                HoverHandler { id: closeNHover }
                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: closeNHover.hovered ? popup.theme.error : popup.theme.txt2
                                    font.family: popup.theme.ff
                                    font.pixelSize: popup.theme.fs - 3
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: NotificationService.dismissNotif(modelData)
                                }
                            }
                        }
                    }
                }
            }

            // Scrollbar — visible only on overflow.
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
                    color: popup.theme.outline
                    opacity: 0.6
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
    

    // ── Reusable quick-toggle pill ───────────────────────────────────────
    component QuickToggle: Rectangle {
        id: qt
        property string label: ""
        property string icon:  ""
        property bool   on:    false
        signal clicked()

        width: (col.width - 16) / 3
        height: 64
        radius: 10
        // Windows 11 quick-settings tile: accent-filled when on.
        color: qt.on ? (qtHover.hovered ? Qt.lighter(popup.theme.primary, 1.1) : popup.theme.primary)
                     : Qt.rgba(popup.theme.fg.r, popup.theme.fg.g, popup.theme.fg.b, qtHover.hovered ? 0.12 : 0.07)
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: qtHover }

        Column {
            anchors.centerIn: parent
            spacing: 5
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qt.icon
                color: qt.on ? popup.theme.bg : popup.theme.fg
                font.family: popup.theme.ff
                font.pixelSize: popup.theme.fs + 2
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qt.label
                color: qt.on ? popup.theme.bg : popup.theme.txt2
                font.family: popup.theme.ff
                font.pixelSize: popup.theme.fs - 4
                font.bold: true
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
        property bool   muted: false
        signal moved(int pct)
        signal iconClick()
        signal stepped(int dir)           // +1 (scroll up) / -1 (scroll down)

        height: 44
        readonly property color tint: sl.muted ? popup.theme.outline : popup.theme.primary

        Rectangle {
            id: slIcon
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 30; height: 30; radius: 8
            color: Qt.rgba(sl.tint.r, sl.tint.g, sl.tint.b, iconHover.hovered ? 0.25 : 0.15)
            HoverHandler { id: iconHover }
            Text {
                anchors.centerIn: parent
                text: sl.icon
                color: sl.tint
                font.family: popup.theme.ff
                font.pixelSize: popup.theme.fs
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sl.iconClick()
            }
        }
        UiSlider {
            anchors { left: slIcon.right; leftMargin: 12
                      right: slPct.left;  rightMargin: 10
                      verticalCenter: parent.verticalCenter }
            theme: popup.theme
            value: sl.value / 100
            tint: sl.tint
            onMoved: frac => sl.moved(frac * 100)
            WheelHandler { onWheel: event => sl.stepped(event.angleDelta.y > 0 ? 1 : -1) }
        }
        Text {
            id: slPct
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 38
            horizontalAlignment: Text.AlignRight
            text: sl.value + "%"
            color: popup.theme.fg
            font.family: popup.theme.ff; font.bold: true
            font.pixelSize: popup.theme.fs - 2
        }
    }
}
