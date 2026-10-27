import QtQuick

// Label / value line inside a UiGroup card (spec-sheet style). Draws a
// divider above itself unless it is the first row.
Item {
    id: row

    required property var theme
    property string label: ""
    property string value: ""

    width: parent ? parent.width : 0
    implicitHeight: 46

    Rectangle {
        visible: !row.Positioner.isFirstItem
        anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
        height: 1
        color: row.theme.sep
        opacity: 0.6
    }
    Text {
        id: lbl
        anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
        text: row.label
        color: row.theme.txt2
        font.family: row.theme.ff
        font.pixelSize: row.theme.fs - 2
    }
    Text {
        anchors { left: lbl.right; leftMargin: 24; right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
        horizontalAlignment: Text.AlignRight
        text: row.value
        color: row.theme.fg
        font.family: row.theme.ff; font.bold: true
        font.pixelSize: row.theme.fs - 2
        elide: Text.ElideLeft
    }
}
