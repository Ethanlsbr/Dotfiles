import QtQuick

// Trailing "opens a sub-page" arrow for a clickable UiRow.
Text {
    required property var theme

    anchors.verticalCenter: parent.verticalCenter
    text: ""
    color: theme.txt2
    font.family: theme.ff; font.pixelSize: theme.fs - 2
}
