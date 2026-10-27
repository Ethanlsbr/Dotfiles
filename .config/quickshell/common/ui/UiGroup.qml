import QtQuick

// A titled section: header text above a card that stacks UiRows (dividers
// are drawn by the rows themselves).
Column {
    id: group

    required property var theme
    property string title: ""
    property string description: ""
    default property alias rows: cardCol.data
    // Extra header content (e.g. buttons), right-aligned beside the title.
    property alias actions: actionRow.data

    width: parent ? parent.width : 0
    spacing: 10

    Item {
        visible: group.title !== "" || actionRow.children.length > 0
        width: parent.width
        height: Math.max(headCol.implicitHeight, actionRow.implicitHeight)

        Column {
            id: headCol
            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
            width: parent.width - actionRow.width - 16
            spacing: 2
            Text {
                text: group.title
                color: group.theme.fg
                font.family: group.theme.ff; font.bold: true
                font.pixelSize: group.theme.fs + 1
            }
            Text {
                visible: group.description !== ""
                width: parent.width
                text: group.description
                color: group.theme.txt2
                font.family: group.theme.ff
                font.pixelSize: group.theme.fs - 3
                wrapMode: Text.WordWrap
            }
        }
        Row {
            id: actionRow
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8
        }
    }

    UiCard {
        theme: group.theme
        visible: cardCol.children.length > 0
        height: cardCol.implicitHeight
        Column { id: cardCol; width: parent.width }
    }
}
