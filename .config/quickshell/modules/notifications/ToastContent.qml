import QtQuick
import Quickshell.Widgets
import qs.modules.icons

// Body of a notification toast: icon, app name, summary, body, optional
// volume/brightness level bar, hover ✕. Shared by the bar-attached toasts
// (BarToastPanel) and the floating fallback (NotificationToast).
// `info` is a plain snapshot ({appName, summary, body, image, appIcon,
// urgency}) so the content survives the notification being destroyed
// mid exit animation.
Item {
    id: tc

    required property var theme
    property var info: ({})
    signal closeClicked()

    implicitHeight: Math.max(58, textCol.implicitHeight + 20)

    // Volume/brightness toasts carry "NN%" in the summary → slider.
    readonly property int level: {
        const g = NotificationService.notifGroup(info)
        if (g !== "audio" && g !== "brightness") return -1
        const m = (info.summary || "").match(/(\d+)\s*%/)
        return m ? Math.max(0, Math.min(100, parseInt(m[1]))) : -1
    }

    HoverHandler { id: hover }

    Item {
        id: tIcon
        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 12 }
        width: 30; height: 30

        // -i <x> arrives as image://icon/<x>: paths load via the provider,
        // themed names need our resolver (Qt is stuck on hicolor) or a
        // glyph fallback.
        readonly property string rawImage: tc.info.image || ""
        readonly property string iconName: rawImage.startsWith("image://icon/")
                ? rawImage.substring(13)
                : (tc.info.appIcon || "")
        readonly property bool nameIsPath: iconName.startsWith("/") || iconName.startsWith("file:")
        readonly property string resolved: {
            if (!rawImage.startsWith("image://icon/"))
                return rawImage                                 // real image / url / data
            return nameIsPath ? rawImage                        // path → provider loads it
                              : IconService.iconFor(iconName)  // name → custom resolver
        }
        // Critical → warning sign, whatever icon the sender passed.
        readonly property bool critical: tc.info.urgency === 2
        readonly property string glyph: critical ? "" : IconService.glyphForIcon(iconName)

        // Prefer the glyph — themed battery icons are dark/symbolic.
        Text {
            anchors.centerIn: parent
            visible: tIcon.glyph !== ""
            text: tIcon.glyph
            color: tIcon.critical ? tc.theme.error : tc.theme.fg
            font.family: tc.theme.ff
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
            source: IconService.iconFor("dialog-information")
        }
    }

    Column {
        id: textCol
        anchors { left: tIcon.right; leftMargin: 10; right: closeT.left; rightMargin: 6
                  verticalCenter: parent.verticalCenter }
        spacing: 1

        Text {
            width: parent.width
            text: tc.info.appName || "Notification"
            color: tc.theme.outline
            font.family: tc.theme.ff
            font.pixelSize: tc.theme.fs - 3
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: tc.info.summary || ""
            color: tc.theme.fg
            font.family: tc.theme.ff
            font.bold: true
            font.pixelSize: tc.theme.fs - 1
            elide: Text.ElideRight
            visible: text.length > 0
        }
        Text {
            width: parent.width
            text: tc.info.body || ""
            color: tc.theme.txt2
            font.family: tc.theme.ff
            font.pixelSize: tc.theme.fs - 2
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            visible: text.length > 0
        }

        // Volume / brightness level slider.
        Item {
            width: parent.width
            height: tc.level >= 0 ? 12 : 0
            visible: tc.level >= 0
            Rectangle {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                height: 5; radius: 3
                color: tc.theme.light ? tc.theme.surface2 : Qt.darker(tc.theme.bg, 1.4)
                Rectangle {
                    height: parent.height; radius: parent.radius
                    width: parent.width * (tc.level / 100)
                    color: tc.theme.primary
                    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }
            }
        }
    }

    Rectangle {
        id: closeT
        anchors { right: parent.right; top: parent.top; margins: 8 }
        width: 20; height: 20; radius: 10
        color: closeHover.hovered ? tc.theme.error : "transparent"
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        HoverHandler { id: closeHover }
        Text {
            anchors.centerIn: parent
            text: "✕"
            color: tc.theme.fg
            font.family: tc.theme.ff
            font.pixelSize: tc.theme.fs - 3
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tc.closeClicked()
        }
    }

    // Click anywhere: dismiss the toast (stays in the notification list).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        z: -1
        onClicked: tc.closeClicked()
    }
}
