import QtQuick

// Settings page body: a scrollable column of groups with consistent spacing
// and a slim overlay scrollbar.
Flickable {
    id: page

    required property var theme
    default property alias content: col.data
    property alias spacing: col.spacing

    contentHeight: col.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
        id: col
        width: page.width - 14      // keep clear of the scrollbar
        spacing: 22
    }

    // Overlay scrollbar, only while content overflows.
    Rectangle {
        visible: page.contentHeight > page.height
        x: page.width - 6
        y: page.contentY + page.visibleArea.yPosition * page.height
        width: 4
        height: Math.max(32, page.visibleArea.heightRatio * page.height)
        radius: 2
        color: page.theme.outline
        opacity: page.moving || scrollHover.hovered ? 0.8 : 0.35
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }
    HoverHandler { id: scrollHover }
}
