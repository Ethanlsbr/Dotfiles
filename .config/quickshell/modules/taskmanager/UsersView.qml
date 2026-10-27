import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.common.ui
import qs.modules.account

// Users tab: every account on the machine (Users = root + UID_MIN..UID_MAX,
// System accounts = the rest) in a sidebar; the selected one on the right
// with its live process / CPU / memory totals, account details and all of
// its groups (primary first).
// The window's search field filters by name, full name, UID or group.
// ↑/↓ select · Ctrl+Tab next tab · Ctrl+F search · Esc close.
FocusScope {
    id: view

    required property var theme
    property string searchText: ""

    // Typed while the list has focus → the window's search field.
    signal typed(string text)
    signal searchRequested()

    property int selectedUid: -1

    readonly property var stats: TaskManagerService.userStats
    readonly property int ownUid: TaskManagerService.ownUid

    // Flat sidebar list: section headers + users.
    readonly property var rows: {
        const q = searchText.trim().toLowerCase()
        const match = u => !q || u.name.toLowerCase().includes(q)
                              || u.fullname.toLowerCase().includes(q)
                              || String(u.uid).startsWith(q)
                              || u.groups.some(g => g.name.toLowerCase().includes(q))
        const all = TaskManagerService.users.filter(match)
        const out = []
        const regular = all.filter(u => u.regular)
        const system  = all.filter(u => !u.regular)
        if (regular.length) out.push({ header: true, label: "Users", count: regular.length })
        for (const u of regular) out.push(u)
        if (system.length) out.push({ header: true, label: "System accounts", count: system.length })
        for (const u of system) out.push(u)
        return out
    }
    readonly property var user: rows.find(r => !r.header && r.uid === selectedUid)
                                || rows.find(r => !r.header) || null

    function move(step) {
        const r = rows
        let i = r.findIndex(x => !x.header && user && x.uid === user.uid)
        if (i < 0) i = step > 0 ? -1 : r.length
        let j = i
        do { j += step } while (j >= 0 && j < r.length && r[j].header)
        if (j < 0 || j >= r.length) {
            // Clamp to the first / last user (PageUp / PageDown overshoot).
            j = step > 0 ? r.length - 1 : 0
            while (j >= 0 && j < r.length && r[j].header) j += step > 0 ? -1 : 1
            if (j < 0 || j >= r.length || j === i) return
        }
        selectedUid = r[j].uid
        list.positionViewAtIndex(j, ListView.Contain)
    }

    function isAdmin(u) {
        return u.uid === 0 || u.groups.some(g => g.name === "wheel" || g.name === "sudo" || g.name === "admin")
    }
    function fmtCpu(v) { return v < 0.05 ? "0%" : v.toFixed(1) + "%" }
    function statsFor(u) { return (u && stats[u.uid]) || { count: 0, cpu: 0, mem: 0 } }

    // Start on your own account.
    Connections {
        target: TaskManagerService
        function onUsersChanged() {
            if (!TaskManagerService.users.some(u => u.uid === view.selectedUid))
                view.selectedUid = view.ownUid
        }
    }

    Keys.onPressed: e => {
        const ctrl = e.modifiers & Qt.ControlModifier
        if (ctrl && (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab)) {
            TaskManagerService.nextTab(e.key === Qt.Key_Backtab ? -1 : 1); e.accepted = true
        }
        else if (e.key === Qt.Key_Down)     { view.move(1);   e.accepted = true }
        else if (e.key === Qt.Key_Up)       { view.move(-1);  e.accepted = true }
        else if (e.key === Qt.Key_PageDown) { view.move(10);  e.accepted = true }
        else if (e.key === Qt.Key_PageUp)   { view.move(-10); e.accepted = true }
        else if (ctrl && e.key === Qt.Key_F) { view.searchRequested(); e.accepted = true }
        else if (e.key === Qt.Key_Escape)   { TaskManagerService.close(); e.accepted = true }
        else if (!ctrl && e.text.length === 1 && e.text >= " ") { view.typed(e.text); e.accepted = true }
    }

    // ── Shared pieces ──────────────────────────────────────────────────
    component Caption: Text {
        color: view.theme.txt2
        font.family: view.theme.ff
        font.pixelSize: view.theme.fs - 3
    }

    // Round avatar: your picture when set, else the name's initial.
    component Avatar: Item {
        id: av
        property var  u: null
        readonly property bool own: !!u && u.uid === view.ownUid && AccountService.hasAvatar
        ClippingRectangle {
            anchors.fill: parent
            radius: width / 2
            color: av.u && av.u.regular
                   ? Qt.rgba(view.theme.primary.r, view.theme.primary.g, view.theme.primary.b, 0.18)
                   : view.theme.chip
            Text {
                anchors.centerIn: parent
                visible: avImg.status !== Image.Ready
                text: av.u ? av.u.name.charAt(0).toUpperCase() : ""
                color: av.u && av.u.regular ? view.theme.primary : view.theme.txt2
                font.family: view.theme.ff; font.bold: true
                font.pixelSize: av.height * 0.44
            }
            Image {
                id: avImg
                anchors.fill: parent
                visible: av.own
                source: av.own ? AccountService.avatarUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(av.width * 2, av.height * 2)
            }
        }
    }

    component Badge: Rectangle {
        id: bd
        property string text: ""
        property color  tint: view.theme.primary
        implicitWidth: bdText.implicitWidth + 16
        implicitHeight: 22
        radius: 11
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.16)
        Text {
            id: bdText
            anchors.centerIn: parent
            text: bd.text
            color: bd.tint
            font.family: view.theme.ff; font.bold: true
            font.pixelSize: view.theme.fs - 4
        }
    }

    component Stat: Column {
        property string label: ""
        property string value: ""
        width: Math.max(110, implicitWidth + 10)
        spacing: 2
        Caption { text: parent.label }
        Text {
            text: parent.value
            color: view.theme.fg
            font.family: view.theme.ff
            font.pixelSize: view.theme.fs + 5
        }
    }

    component SectionTitle: Text {
        color: view.theme.primary
        font.family: view.theme.ff; font.bold: true
        font.pixelSize: view.theme.fs - 1
    }

    // ── Sidebar ────────────────────────────────────────────────────────
    Rectangle {
        id: side
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: 290
        color: view.theme.inset

        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 1
            color: view.theme.sep
        }

        Text {
            anchors.centerIn: parent
            visible: list.count === 0
            width: parent.width - 32
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: !TaskManagerService.usersLoaded ? "Loading users…"
                : view.searchText ? "No user matches \"" + view.searchText + "\""
                : "No users"
            color: view.theme.outline
            font.family: view.theme.ff; font.pixelSize: view.theme.fs - 1
        }

        ListView {
            id: list
            anchors { fill: parent; topMargin: 6; bottomMargin: 8 }
            clip: true
            model: view.rows
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: UiScrollBar { theme: view.theme }

            delegate: Item {
                id: card
                required property var modelData
                readonly property var  u: modelData
                readonly property bool current: !u.header && !!view.user && view.user.uid === u.uid
                readonly property var  st: u.header ? null : view.statsFor(u)
                width: ListView.view.width
                height: u.header ? 36 : 56

                // Section header.
                Text {
                    visible: !!card.u.header
                    anchors { left: parent.left; leftMargin: 20; bottom: parent.bottom; bottomMargin: 6 }
                    text: card.u.header ? card.u.label + " (" + card.u.count + ")" : ""
                    color: view.theme.primary
                    font.family: view.theme.ff; font.bold: true
                    font.pixelSize: view.theme.fs - 1
                }

                Rectangle {
                    visible: !card.u.header
                    x: 8
                    width: parent.width - 17
                    height: parent.height
                    radius: 10
                    color: card.current ? Qt.rgba(view.theme.fg.r, view.theme.fg.g, view.theme.fg.b, 0.08)
                         : cardHover.hovered ? Qt.rgba(view.theme.fg.r, view.theme.fg.g, view.theme.fg.b, 0.04)
                         : "transparent"
                    HoverHandler { id: cardHover }

                    Rectangle {
                        visible: card.current
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: 3; height: 22; radius: 2
                        color: view.theme.primary
                    }

                    Avatar {
                        id: cardAvatar
                        u: card.u.header ? null : card.u
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        width: 34; height: 34
                    }
                    // Signed-in dot.
                    Rectangle {
                        visible: !card.u.header && card.u.sessions > 0
                        x: cardAvatar.x + cardAvatar.width - width + 1
                        y: cardAvatar.y + cardAvatar.height - height + 1
                        width: 11; height: 11; radius: 6
                        color: view.theme.green
                        border.color: view.theme.inset
                        border.width: 2
                    }

                    Column {
                        anchors { left: cardAvatar.right; leftMargin: 12; right: procText.left; rightMargin: 8
                                  verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Text {
                            width: parent.width
                            text: card.u.header ? "" : card.u.name + (card.u.uid === view.ownUid ? "  (you)" : "")
                            color: view.theme.fg
                            font.family: view.theme.ff; font.bold: true
                            font.pixelSize: view.theme.fs - 1
                            elide: Text.ElideRight
                        }
                        Caption {
                            width: parent.width
                            text: card.u.header ? ""
                                : (card.u.fullname && card.u.fullname !== card.u.name ? card.u.fullname + " · " : "")
                                  + "UID " + card.u.uid + " · " + card.u.groups.length
                                  + (card.u.groups.length === 1 ? " group" : " groups")
                            elide: Text.ElideRight
                        }
                    }

                    Caption {
                        id: procText
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        visible: !!card.st && card.st.count > 0
                        text: card.st ? card.st.count + (card.st.count === 1 ? " proc" : " procs") : ""
                        color: view.theme.outline
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { view.selectedUid = card.u.uid; view.forceActiveFocus() }
                    }
                }
            }
        }
    }

    // ── Detail ─────────────────────────────────────────────────────────
    Flickable {
        id: detail
        anchors {
            left: side.right;    leftMargin: 26
            right: parent.right; rightMargin: 24
            top: parent.top;     topMargin: 14
            bottom: parent.bottom
        }
        visible: !!view.user
        clip: true
        contentHeight: detailCol.implicitHeight + 18
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: detailCol
            readonly property var u:  view.user
            readonly property var st: view.statsFor(u)
            width: detail.width
            spacing: 22

            // Avatar, name, badges.
            Row {
                spacing: 18
                Avatar {
                    u: detailCol.u
                    width: 72; height: 72
                    anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Text {
                        text: detailCol.u ? detailCol.u.name : ""
                        color: view.theme.fg
                        font.family: view.theme.ff; font.bold: true
                        font.pixelSize: view.theme.fs + 12
                    }
                    Text {
                        visible: text !== ""
                        text: detailCol.u && detailCol.u.fullname !== detailCol.u.name ? detailCol.u.fullname : ""
                        color: view.theme.txt2
                        font.family: view.theme.ff; font.pixelSize: view.theme.fs + 1
                    }
                    Flow {
                        width: detail.width - 90
                        spacing: 6
                        Badge { visible: !!detailCol.u && detailCol.u.uid === view.ownUid; text: "You" }
                        Badge { visible: !!detailCol.u && view.isAdmin(detailCol.u); text: "Administrator"; tint: view.theme.warn }
                        Badge { visible: !!detailCol.u && detailCol.u.sessions > 0; text: "Signed in"; tint: view.theme.green }
                        Badge { visible: !!detailCol.u && !detailCol.u.regular; text: "System account"; tint: view.theme.txt2 }
                        Badge { visible: !!detailCol.u && !detailCol.u.login; text: "No login shell"; tint: view.theme.outline }
                    }
                }
            }

            // Live usage.
            Flow {
                width: parent.width
                spacing: 14
                Stat { label: "Processes"; value: String(detailCol.st.count) }
                Stat { label: "CPU";       value: view.fmtCpu(detailCol.st.cpu) }
                Stat { label: "Memory";    value: PerfService.fmtBytes(detailCol.st.mem) }
                Stat { label: "Sessions";  value: detailCol.u ? String(detailCol.u.sessions) : "0" }
            }

            // Account details.
            Column {
                width: parent.width
                spacing: 8
                SectionTitle { text: "Account" }
                Repeater {
                    model: !detailCol.u ? [] : [
                        ["Username",       detailCol.u.name],
                        ["Full name",      detailCol.u.fullname || "—"],
                        ["User ID",        String(detailCol.u.uid)],
                        ["Primary group",  detailCol.u.groups[0].name + " (" + detailCol.u.gid + ")"],
                        ["Home directory", detailCol.u.home || "—"],
                        ["Shell",          detailCol.u.shell || "—"]
                    ]
                    Row {
                        required property var modelData
                        spacing: 14
                        Caption { width: 130; text: modelData[0] }
                        Text {
                            width: detailCol.width - 144
                            text: modelData[1]
                            color: view.theme.fg
                            font.family: view.theme.ff
                            font.pixelSize: view.theme.fs - 3
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Groups.
            Column {
                width: parent.width
                spacing: 10
                SectionTitle {
                    text: "Groups (" + (detailCol.u ? detailCol.u.groups.length : 0) + ")"
                }
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: detailCol.u ? detailCol.u.groups : []
                        delegate: Rectangle {
                            id: gchip
                            required property var modelData
                            readonly property string q: view.searchText.trim().toLowerCase()
                            readonly property bool hit: q !== "" && modelData.name.toLowerCase().includes(q)
                            readonly property bool accent: modelData.primary || hit
                            implicitWidth: gRow.implicitWidth + 24
                            implicitHeight: 30
                            radius: 15
                            color: accent
                                   ? Qt.rgba(view.theme.primary.r, view.theme.primary.g, view.theme.primary.b, 0.16)
                                   : view.theme.chip
                            border.color: accent ? view.theme.primary : view.theme.sep
                            border.width: 1
                            Row {
                                id: gRow
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: gchip.modelData.name
                                    color: gchip.accent ? view.theme.primary : view.theme.fg
                                    font.family: view.theme.ff; font.bold: gchip.modelData.primary
                                    font.pixelSize: view.theme.fs - 2
                                }
                                Caption {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: gchip.modelData.gid + (gchip.modelData.primary ? " · primary" : "")
                                    color: view.theme.outline
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
