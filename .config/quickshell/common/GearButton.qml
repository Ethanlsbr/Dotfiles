import QtQuick

// Settings-wheel button (top-right of the bar popups).
Rectangle {
    id: gear

    required property var theme
    signal clicked()

    width: 32; height: 32
    radius: 8
    // Same soft fill as UiButton's secondary kind.
    color: Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, hover.hovered ? 0.14 : 0.08)
    Behavior on color { ColorAnimation { duration: 120 } }

    HoverHandler { id: hover }

    Text {
        anchors.centerIn: parent
        text: ""
        color: gear.theme.fg
        font.family: gear.theme.ff
        font.pixelSize: gear.theme.fs
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: gear.clicked()
    }
}
