import QtQuick
import QtQuick.Controls

// Thin rounded scrollbar: faint at rest, brighter on hover / drag; hidden
// when the content fits. Attach as `ScrollBar.vertical: UiScrollBar { … }`.
ScrollBar {
    id: bar

    required property var theme

    policy: size < 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
    rightPadding: 2
    width: 8
    background: null
    contentItem: Rectangle {
        implicitWidth: 6
        radius: 3
        color: bar.theme.fg
        opacity: bar.pressed ? 0.45 : bar.hovered ? 0.3 : 0.16
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
}
