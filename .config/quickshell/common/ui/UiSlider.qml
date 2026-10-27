import QtQuick

// Horizontal slider: `value` 0..1 (owner-driven); drags emit moved(frac).
Item {
    id: slider

    required property var theme
    property real  value: 0
    property color tint: theme.primary
    signal moved(real frac)

    implicitHeight: 20
    readonly property real frac: Math.max(0, Math.min(1, value))

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 6; radius: 3
        color: Qt.rgba(slider.theme.fg.r, slider.theme.fg.g, slider.theme.fg.b, 0.1)
        Rectangle {
            width: parent.width * slider.frac
            height: parent.height; radius: parent.radius
            color: slider.tint
        }
    }
    Rectangle {
        width: 18; height: 18; radius: 9
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(parent.width - width, parent.width * slider.frac - width / 2))
        color: slider.tint
        border.color: slider.theme.light ? slider.theme.paper : slider.theme.surface
        border.width: 3
    }
    MouseArea {
        anchors.fill: parent
        anchors.topMargin: -4; anchors.bottomMargin: -4
        cursorShape: Qt.PointingHandCursor
        onPressed: slider.moved(Math.max(0, Math.min(1, mouseX / width)))
        onPositionChanged: if (pressed) slider.moved(Math.max(0, Math.min(1, mouseX / width)))
    }
}
