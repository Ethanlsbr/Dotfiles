import QtQuick
import Quickshell

PanelWindow {
    id: overlay

    required property var shellRoot
    required property var theme

    readonly property bool _open: shellRoot.clockPopupOpen

    visible: _open || exitAnim.running

    on_OpenChanged: {

        if (_open) { exitAnim.stop(); enterAnim.restart() }

        else       { enterAnim.stop(); exitAnim.restart() }

    }

    anchors { top: true; right: true }
    margins.right: 10
    margins.top:   6      // sit just below the bar (bar exclusiveZone is 34)
    exclusiveZone: 0
    color: "transparent"

    implicitWidth:  280
    implicitHeight: card.implicitHeight + 20

    // ── Calendar state ────────────────────────────────────────────────
    property var today: new Date()
    property int viewYear:  today.getFullYear()
    property int viewMonth: today.getMonth()      // 0..11

    // Build a 6×7 grid of date cells for the current view.
    readonly property var grid: {
        const cells = []
        const first = new Date(viewYear, viewMonth, 1)
        const startDow = first.getDay()                                // 0=Sun
        const daysInMonth = new Date(viewYear, viewMonth + 1, 0).getDate()
        const daysInPrev  = new Date(viewYear, viewMonth, 0).getDate()
        for (let i = startDow - 1; i >= 0; i--)
            cells.push({ day: daysInPrev - i, current: false, isToday: false })
        for (let d = 1; d <= daysInMonth; d++) {
            const isToday = (today.getFullYear() === viewYear
                          && today.getMonth()    === viewMonth
                          && today.getDate()     === d)
            cells.push({ day: d, current: true, isToday })
        }
        let nx = 1
        while (cells.length < 42) cells.push({ day: nx++, current: false, isToday: false })
        return cells
    }

    readonly property var monthNames: [
        "January","February","March","April","May","June",
        "July","August","September","October","November","December"
    ]

    function shiftMonth(d) {
        let m = viewMonth + d, y = viewYear
        if (m < 0)  { m += 12; y-- }
        if (m > 11) { m -= 12; y++ }
        viewMonth = m
        viewYear  = y
    }
    function resetToToday() {
        today = new Date()
        viewYear  = today.getFullYear()
        viewMonth = today.getMonth()
    }

    // Refresh "today" once a minute so a long-open overlay stays accurate.
    Timer {
        interval: 60000; repeat: true; running: true
        onTriggered: overlay.today = new Date()
    }

    // Slide-from-edge enter animation, shared style across every popup.
    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: card;      property: "opacity"; from: 0; to: 1; duration: 360; easing.type: Easing.OutCubic }
        NumberAnimation { target: card;      property: "scale"; from: 0.96; to: 1; duration: 360; easing.type: Easing.OutCubic }
    }
    // Reverse of enterAnim — plays before the panel is hidden so it slides
    // back out instead of snapping away. `visible` stays true while running.
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: card;      property: "opacity"; to: 0;   duration: 280; easing.type: Easing.InCubic }
        NumberAnimation { target: card;      property: "scale"; to: 0.96; duration: 280; easing.type: Easing.InCubic }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        color: overlay.theme.bg
        radius: overlay.theme.pr
        border.color: overlay.theme.sep
        border.width: 1
        implicitHeight: col.implicitHeight + 20
        opacity: 0
        scale: 0.96
        transformOrigin: Item.Top

        HoverHandler {
            onHoveredChanged: hovered ? overlay.shellRoot.stopHideTimer("clock")
                                      : overlay.shellRoot.startHideTimer("clock")
        }

        Column {
            id: col
            anchors { fill: parent; margins: 10 }
            spacing: 8

            // ── Header: < Month YYYY > + today reset ───────────────────
            Row {
                width: col.width
                spacing: 0

                NavBtn { icon: "‹"; onActivated: overlay.shiftMonth(-1) }

                Item {
                    width:  col.width - 28 - 28 - 28
                    height: 28
                    Text {
                        anchors.centerIn: parent
                        text: overlay.monthNames[overlay.viewMonth] + " " + overlay.viewYear
                        color: overlay.theme.fg
                        font.family: overlay.theme.ff
                        font.bold: true
                        font.pixelSize: overlay.theme.fs
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onDoubleClicked: overlay.resetToToday()
                    }
                }

                NavBtn { icon: "›"; onActivated: overlay.shiftMonth(1) }
                NavBtn { icon: "·"; onActivated: overlay.resetToToday() }
            }

            // ── Day-of-week labels ────────────────────────────────────
            Row {
                spacing: 0
                Repeater {
                    model: ["S","M","T","W","T","F","S"]
                    delegate: Item {
                        required property var modelData
                        width: col.width / 7
                        height: 20
                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: overlay.theme.outline
                            font.family: overlay.theme.ff
                            font.pixelSize: overlay.theme.fs - 3
                            font.bold: true
                        }
                    }
                }
            }

            // ── Date grid ─────────────────────────────────────────────
            Grid {
                columns: 7
                rows: 6
                rowSpacing: 2
                columnSpacing: 0

                Repeater {
                    model: overlay.grid
                    delegate: Item {
                        required property var modelData
                        width:  col.width / 7
                        height: 28

                        Rectangle {
                            anchors.centerIn: parent
                            width:  24; height: 24
                            radius: 12
                            color:   parent.modelData.isToday ? overlay.theme.primary
                                   : (cellHover.hovered && parent.modelData.current
                                        ? overlay.theme.hi(1.4) : "transparent")
                            HoverHandler { id: cellHover }

                            Text {
                                anchors.centerIn: parent
                                text: parent.parent.modelData.day
                                color: parent.parent.modelData.isToday ? overlay.theme.bg
                                     : parent.parent.modelData.current  ? overlay.theme.fg
                                                                        : overlay.theme.outline
                                font.family: overlay.theme.ff
                                font.pixelSize: overlay.theme.fs - 2
                                font.bold: parent.parent.modelData.isToday
                            }
                        }
                    }
                }
            }
        }
    }

    component NavBtn: Rectangle {
        id: btn
        property string icon: ""
        signal activated()

        width: 28; height: 28
        radius: 14
        color: navHover.hovered ? overlay.theme.hi(1.4) : "transparent"
        HoverHandler { id: navHover }

        Text {
            anchors.centerIn: parent
            text: btn.icon
            color: overlay.theme.fg
            font.family: overlay.theme.ff
            font.bold: true
            font.pixelSize: overlay.theme.fs + 2
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
        }
    }
}
