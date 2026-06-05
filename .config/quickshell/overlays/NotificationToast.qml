import QtQuick
import Quickshell
import Quickshell.Widgets

// Transient notification toasts — stacked top-right, independent of the
// control-center panel. Each toast auto-dismisses after a few seconds
// (critical-urgency ones persist until clicked).
PanelWindow {
    id: overlay

    required property var shellRoot
    required property var theme

    visible: shellRoot.toastCount > 0

    anchors { top: true; right: true }
    margins.right: 10
    margins.top:   6
    exclusiveZone: 0
    color: "transparent"

    implicitWidth:  360
    implicitHeight: Math.max(1, stack.implicitHeight)

    Column {
        id: stack
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 8

        Repeater {
            model: shellRoot.toasts

            delegate: Rectangle {
                id: toast
                required property var notif
                required property string gid
                readonly property var modelData: notif
                width: stack.width

                // Volume / brightness notifications carry the level as a "NN%"
                // in their summary — parse it to draw a progress slider.
                readonly property int level: {
                    const g = overlay.shellRoot.notifGroup(modelData)
                    if (g !== "audio" && g !== "brightness") return -1
                    const m = (modelData.summary || "").match(/(\d+)\s*%/)
                    return m ? Math.max(0, Math.min(100, parseInt(m[1]))) : -1
                }

                // A synchronous notification (volume/brightness/media) reuses
                // this same delegate via ListModel.set(), which updates `notif`
                // in place without replaying the slide-in. Restart the
                // auto-dismiss countdown each time the content changes.
                onNotifChanged: if (notif && notif.urgency !== 2) dismissTimer.restart()
                implicitHeight: Math.max(58, textCol.implicitHeight + 20)
                radius: 12
                color: overlay.theme.bg
                border.color: modelData.urgency === 2 ? overlay.theme.error : overlay.theme.sep
                border.width: 1

                // Slide-in from the right.
                transform: Translate { id: slide; x: 0 }
                opacity: 0
                Component.onCompleted: appear.start()
                ParallelAnimation {
                    id: appear
                    NumberAnimation { target: toast; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { target: slide; property: "x"; from: 40; to: 0;      duration: 260; easing.type: Easing.OutCubic }
                }

                // Auto-dismiss (skip for critical urgency).
                Timer {
                    id: dismissTimer
                    interval: 5000; repeat: false
                    running: toast.modelData.urgency !== 2
                    onTriggered: overlay.shellRoot.removeToast(toast.modelData)
                }

                HoverHandler { id: toastHover }

                Item {
                    id: tIcon
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 12 }
                    implicitWidth: 30; implicitHeight: 30
                    width: 30; height: 30

                    // notify-send's -i <x> arrives as image="image://icon/<x>"
                    // (appIcon empty), where <x> is either a file path or a
                    // themed-icon name. The image://icon provider loads paths
                    // fine but fails on names (Qt is stuck on hicolor), so we
                    // resolve names ourselves (or fall back to a glyph).
                    readonly property string rawImage: toast.modelData.image || ""
                    readonly property string iconName: rawImage.startsWith("image://icon/")
                            ? rawImage.substring(13)
                            : (toast.modelData.appIcon || "")
                    readonly property bool nameIsPath: iconName.startsWith("/") || iconName.startsWith("file:")
                    readonly property string resolved: {
                        if (!rawImage.startsWith("image://icon/"))
                            return rawImage                                 // real image / url / data
                        return nameIsPath ? rawImage                        // path → provider loads it
                                          : overlay.shellRoot.iconFor(iconName)  // name → custom resolver
                    }
                    readonly property string glyph: overlay.shellRoot.glyphForIcon(iconName)

                    // Glyph takes precedence: for names we recognise (battery)
                    // the theme only has dark/symbolic icons, so prefer the glyph.
                    Text {
                        anchors.centerIn: parent
                        visible: tIcon.glyph !== ""
                        text: tIcon.glyph
                        color: overlay.theme.fg
                        font.family: overlay.theme.ff
                        font.pixelSize: 24
                    }
                    IconImage {
                        anchors.fill: parent
                        asynchronous: true
                        visible: tIcon.glyph === "" && tIcon.resolved !== ""
                        source: tIcon.resolved
                    }
                    // Generic last resort (themed info icon).
                    IconImage {
                        anchors.fill: parent
                        asynchronous: true
                        visible: tIcon.glyph === "" && tIcon.resolved === ""
                        source: overlay.shellRoot.iconFor("dialog-information")
                    }
                }

                Column {
                    id: textCol
                    anchors { left: tIcon.right; leftMargin: 10; right: closeT.left; rightMargin: 6
                              verticalCenter: parent.verticalCenter }
                    spacing: 1

                    Text {
                        id: appName
                        width: parent.width
                        text: toast.modelData.appName || "Notification"
                        color: overlay.theme.outline
                        font.family: overlay.theme.ff
                        font.pixelSize: overlay.theme.fs - 3
                        elide: Text.ElideRight
                    }
                    Text {
                        id: summary
                        width: parent.width
                        text: toast.modelData.summary || ""
                        color: overlay.theme.fg
                        font.family: overlay.theme.ff
                        font.bold: true
                        font.pixelSize: overlay.theme.fs - 1
                        elide: Text.ElideRight
                        visible: text.length > 0
                    }
                    Text {
                        id: body
                        width: parent.width
                        text: toast.modelData.body || ""
                        color: overlay.theme.txt2
                        font.family: overlay.theme.ff
                        font.pixelSize: overlay.theme.fs - 2
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        visible: text.length > 0
                    }

                    // Volume / brightness level slider.
                    Item {
                        width: parent.width
                        height: toast.level >= 0 ? 12 : 0
                        visible: toast.level >= 0
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                            height: 5; radius: 3
                            color: Qt.darker(overlay.theme.bg, 1.4)
                            Rectangle {
                                height: parent.height; radius: parent.radius
                                width: parent.width * (toast.level / 100)
                                color: overlay.theme.primary
                                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }

                Rectangle {
                    id: closeT
                    anchors { right: parent.right; top: parent.top; margins: 8 }
                    width: 20; height: 20; radius: 10
                    color: closeHover.hovered ? overlay.theme.error : "transparent"
                    opacity: toastHover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    HoverHandler { id: closeHover }
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
                        onClicked: overlay.shellRoot.removeToast(toast.modelData)
                    }
                }

                // Click the toast body to dismiss it from the toast stack
                // (it stays in the control-center list).
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    z: -1
                    onClicked: overlay.shellRoot.removeToast(toast.modelData)
                }
            }
        }
    }
}
