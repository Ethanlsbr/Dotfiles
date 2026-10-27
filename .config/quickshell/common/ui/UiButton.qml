import QtQuick

// Button with an optional icon. kind: "primary" (filled accent),
// "secondary" (soft fill), "danger" (soft error tint).
Rectangle {
    id: btn

    required property var theme
    property string text: ""
    property string icon: ""
    property string kind: "secondary"
    signal clicked()

    readonly property color _fg: kind === "primary" ? theme.bg
                               : kind === "danger"  ? theme.error
                               : theme.fg
    readonly property color _bg: kind === "primary" ? theme.primary
                               : kind === "danger"  ? Qt.rgba(theme.error.r, theme.error.g, theme.error.b, 0.14)
                               : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.08)

    implicitWidth: content.implicitWidth + (text !== "" ? 28 : 18)
    implicitHeight: 32
    width: implicitWidth
    height: implicitHeight
    radius: 8
    opacity: enabled ? 1 : 0.45
    color: hover.hovered && enabled
           ? (kind === "primary" ? Qt.lighter(_bg, 1.12) : Qt.rgba(_bg.r, _bg.g, _bg.b, _bg.a * 1.8))
           : _bg
    Behavior on color { ColorAnimation { duration: 120 } }

    HoverHandler { id: hover }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 7
        Text {
            visible: btn.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.icon
            color: btn._fg
            font.family: btn.theme.ff; font.pixelSize: btn.theme.fs - 1
        }
        Text {
            visible: btn.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.text
            color: btn._fg
            font.family: btn.theme.ff; font.bold: true; font.pixelSize: btn.theme.fs - 2
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: btn.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
