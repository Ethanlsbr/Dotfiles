import QtQuick
import Quickshell
import qs.common.ui

// Bar popup page: month calendar (hover the clock).
Item {
    id: popup

    required property var theme
    implicitHeight: col.implicitHeight + 24

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

    // Check for a new day every minute; `today` only changes then, so the
    // grid isn't rebuilt (42 cells, in every bar's popup) each tick.
    Timer {
        interval: 60000; repeat: true; running: true
        onTriggered: {
            const now = new Date()
            if (now.toDateString() !== popup.today.toDateString()) popup.today = now
        }
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 10

        // ── Header: today's date + month navigation ──────────────
        Item {
            width: parent.width
            height: 50

            Column {
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 2
                Text {
                    text: Qt.formatDate(popup.today, "dddd")
                    color: popup.theme.primary
                    font.family: popup.theme.ff; font.bold: true; font.pixelSize: popup.theme.fs - 3
                }
                Text {
                    text: Qt.formatDate(popup.today, "d MMMM yyyy")
                    color: popup.theme.fg
                    font.family: popup.theme.ff; font.bold: true; font.pixelSize: popup.theme.fs + 3
                }
            }
            Row {
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                spacing: 6
                UiButton {
                    theme: popup.theme
                    visible: popup.viewMonth !== popup.today.getMonth() || popup.viewYear !== popup.today.getFullYear()
                    text: "Today"
                    onClicked: popup.resetToToday()
                }
                UiButton { theme: popup.theme; icon: "\uf053"; onClicked: popup.shiftMonth(-1) }
                UiButton { theme: popup.theme; icon: "\uf054"; onClicked: popup.shiftMonth(1) }
            }
        }

        // ── Month ────────────────────────────────────────────────
        UiCard {
            theme: popup.theme
            height: monthCol.implicitHeight + 20

            Column {
                id: monthCol
                x: 10; y: 10
                width: parent.width - 20
                spacing: 6

                Text {
                    leftPadding: 6
                    text: popup.monthNames[popup.viewMonth] + " " + popup.viewYear
                    color: popup.theme.fg
                    font.family: popup.theme.ff; font.bold: true; font.pixelSize: popup.theme.fs - 1
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onDoubleClicked: popup.resetToToday()
                    }
                }

                // Day-of-week labels
                Row {
                    Repeater {
                        model: ["S", "M", "T", "W", "T", "F", "S"]
                        delegate: Item {
                            required property var modelData
                            width: monthCol.width / 7
                            height: 22
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: popup.theme.txt2
                                font.family: popup.theme.ff; font.bold: true; font.pixelSize: popup.theme.fs - 4
                            }
                        }
                    }
                }

                // Date grid
                Grid {
                    columns: 7
                    rowSpacing: 2
                    Repeater {
                        model: popup.grid
                        delegate: Item {
                            id: cell
                            required property var modelData
                            width: monthCol.width / 7
                            height: 32

                            Rectangle {
                                anchors.centerIn: parent
                                width: 30; height: 30
                                radius: 8
                                color: cell.modelData.isToday ? popup.theme.primary
                                     : (cellHover.hovered && cell.modelData.current
                                        ? Qt.rgba(popup.theme.fg.r, popup.theme.fg.g, popup.theme.fg.b, 0.08) : "transparent")
                                Behavior on color { ColorAnimation { duration: 100 } }
                                HoverHandler { id: cellHover }

                                Text {
                                    anchors.centerIn: parent
                                    text: cell.modelData.day
                                    color: cell.modelData.isToday ? popup.theme.bg
                                         : cell.modelData.current ? popup.theme.fg
                                                                  : Qt.rgba(popup.theme.fg.r, popup.theme.fg.g, popup.theme.fg.b, 0.3)
                                    font.family: popup.theme.ff
                                    font.bold: cell.modelData.isToday
                                    font.pixelSize: popup.theme.fs - 2
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
