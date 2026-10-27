import QtQuick

// Pill toggle switch. Emits toggled(newValue); the owner updates `checked`.
Rectangle {
    id: sw

    required property var theme
    property bool checked: false
    signal toggled(bool value)

    width: 44; height: 24
    radius: 12
    color: checked ? theme.primary : (theme.light ? "#C8CCD6" : Qt.lighter(theme.surface, 1.6))
    Behavior on color { ColorAnimation { duration: 140 } }

    Rectangle {
        width: 18; height: 18; radius: 9
        y: 3
        x: sw.checked ? sw.width - width - 3 : 3
        color: sw.checked ? sw.theme.bg : "white"
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled(!sw.checked)
    }
}
