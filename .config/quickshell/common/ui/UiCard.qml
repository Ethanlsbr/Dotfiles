import QtQuick

// Rounded card surface; content goes inside (padding is up to the content).
Rectangle {
    required property var theme

    width: parent ? parent.width : 0
    radius: 12
    color: theme.light ? theme.paper : theme.surface
    border.color: Qt.rgba(theme.sep.r, theme.sep.g, theme.sep.b, 0.7)
    border.width: 1
}
