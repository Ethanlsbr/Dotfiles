import QtQuick

// One setting inside a UiGroup card: tinted icon tile, title + subtitle,
// trailing controls on the right. Draws a divider above itself unless it is
// the first row. `clickable` adds hover + a chevron-free click target.
Item {
    id: row

    required property var theme
    property string icon: ""
    property color  iconColor: theme.primary
    property string title: ""
    property string subtitle: ""
    property bool   clickable: false
    property bool   highlighted: false
    // Tighter metrics for the narrow bar popups.
    property bool   compact: false
    // Divider above the row; override when the row isn't a direct child of
    // the card's column (e.g. wrapped with extra content in a delegate).
    property bool   showDivider: !Positioner.isFirstItem
    default property alias trailing: trail.data
    signal clicked()

    width: parent ? parent.width : 0
    implicitHeight: compact ? Math.max(subtitle !== "" ? 50 : 42, textCol.implicitHeight + 16)
                            : Math.max(subtitle !== "" ? 64 : 54, textCol.implicitHeight + 24)

    Rectangle {
        anchors { fill: parent; margins: 4 }
        radius: 9
        color: row.highlighted
               ? Qt.rgba(row.theme.primary.r, row.theme.primary.g, row.theme.primary.b, 0.14)
               : (row.clickable && hover.hovered
                  ? Qt.rgba(row.theme.fg.r, row.theme.fg.g, row.theme.fg.b, 0.05) : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Rectangle {
        visible: row.showDivider
        anchors { top: parent.top; left: parent.left; right: parent.right
                  leftMargin: row.compact ? 12 : 16; rightMargin: row.compact ? 12 : 16 }
        height: 1
        color: row.theme.sep
        opacity: 0.6
    }

    HoverHandler { id: hover }
    MouseArea {
        anchors.fill: parent
        enabled: row.clickable
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }

    Rectangle {
        id: tile
        visible: row.icon !== ""
        anchors { left: parent.left; leftMargin: row.compact ? 10 : 16; verticalCenter: parent.verticalCenter }
        width: row.compact ? 30 : 36; height: width
        radius: row.compact ? 8 : 10
        color: Qt.rgba(row.iconColor.r, row.iconColor.g, row.iconColor.b, 0.15)
        Text {
            anchors.centerIn: parent
            text: row.icon
            color: row.iconColor
            font.family: row.theme.ff; font.pixelSize: row.compact ? row.theme.fs : row.theme.fs + 3
        }
    }

    Column {
        id: textCol
        anchors {
            left: tile.visible ? tile.right : parent.left
            leftMargin: tile.visible ? (row.compact ? 10 : 14) : (row.compact ? 12 : 18)
            right: trail.left; rightMargin: row.compact ? 10 : 14
            verticalCenter: parent.verticalCenter
        }
        spacing: 3
        Text {
            width: parent.width
            text: row.title
            color: row.theme.fg
            font.family: row.theme.ff; font.bold: true
            font.pixelSize: row.theme.fs - 1
            elide: Text.ElideRight
        }
        Text {
            visible: row.subtitle !== ""
            width: parent.width
            text: row.subtitle
            color: row.theme.txt2
            font.family: row.theme.ff
            font.pixelSize: row.theme.fs - 3
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    Row {
        id: trail
        anchors { right: parent.right; rightMargin: row.compact ? 10 : 16; verticalCenter: parent.verticalCenter }
        spacing: 8
    }
}
