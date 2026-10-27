import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.modules.appearance
import qs.modules.icons
import qs.modules.system

// Windows-style task manager (FloatingWindow). Apps / Background / System
// sections with sortable Name, PID, User, CPU and Memory columns (usage
// cells heat-tinted). Select a row, then End task (SIGTERM) / Force kill
// (SIGKILL), or right-click for the full menu.
// Performance tab: Windows-style live graphs (PerformanceView).
// Users tab: every account and its groups (UsersView).
// Keys: ↑/↓ select · ←/→ collapse/expand · Enter switch to app · Del end
// task · Shift+Del force kill · Ctrl+F search · Ctrl+Tab next tab ·
// Esc close.
// Shown/hidden imperatively from TaskManagerService.taskManagerOpen, like
// the settings window (the WM close button writes `visible`).
FloatingWindow {
    id: win

    required property var theme
    // Shell-size scale of this window's monitor (unset monitors = 100%).
    readonly property real uiScale: AppearanceService.scaleFor(screen?.name ?? "")

    title: "Task Manager"
    color: theme.bg

    minimumSize: Qt.size(720 * uiScale, 420 * uiScale)
    implicitWidth:  1000 * uiScale
    implicitHeight: 680 * uiScale

    visible: false

    onVisibleChanged: if (!visible) TaskManagerService.close()

    Connections {
        target: TaskManagerService
        function onTaskManagerOpenChanged() {
            if (TaskManagerService.taskManagerOpen) {
                win.searchText = ""
                search.text = ""
                win.selectedKey = ""
                win.menuOpen = false
                win.visible = true
                focusDelay.restart()
                win.focusTab()
            } else {
                win.visible = false
            }
        }
    }

    // Opened from the launcher / a keybind, the keyboard often stays on the
    // old app — focus by title once mapped.
    Timer {
        id: focusDelay
        interval: 140; repeat: false
        onTriggered: {
            focusProc.running = false; focusProc.running = true
            win.focusTab()
        }
    }
    Process {
        id: focusProc
        command: ["hyprctl", "dispatch", "hl.dsp.focus({window = \"title:Task Manager\"})"]
    }

    readonly property string tab: TaskManagerService.tab
    readonly property bool onPerf:  tab === "performance"
    readonly property bool onUsers: tab === "users"
    readonly property bool onProcs: !onPerf && !onUsers
    function focusTab() {
        if (onPerf)       perf.forceActiveFocus()
        else if (onUsers) users.forceActiveFocus()
        else              table.forceActiveFocus()
    }
    // The search field is shared by Processes and Users; each starts empty.
    onTabChanged: { menuOpen = false; search.text = ""; focusTab() }

    // ── Table state ────────────────────────────────────────────────────
    property string searchText:  ""
    property string sortKey:     "name"     // name | pid | user | cpu | mem
    property bool   sortDesc:    false
    property string selectedKey: ""         // "app:<pid>" | "p:<pid>"
    property var    expanded:    ({})       // app key → true

    readonly property int colPid:  80
    readonly property int colUser: 110
    readonly property int colCpu:  90
    readonly property int colMem:  120

    function sortBy(k) {
        if (sortKey === k) sortDesc = !sortDesc
        else { sortKey = k; sortDesc = (k === "cpu" || k === "mem") }
    }
    function _cmp(a, b) {
        let r
        if (sortKey === "name" || sortKey === "user")
            r = a[sortKey].localeCompare(b[sortKey], undefined, { sensitivity: "base" })
        else
            r = a[sortKey] - b[sortKey]
        if (r === 0) r = a.pid - b.pid
        return sortDesc ? -r : r
    }
    function setExpanded(key, on) {
        const e = Object.assign({}, expanded)
        if (on) e[key] = true
        else    delete e[key]
        expanded = e
    }

    // Desktop entry for a window class → display name + icon.
    function _entry(cls) {
        return cls ? DesktopEntries.heuristicLookup(cls) : null
    }

    function _procRow(p, depth, address) {
        return { kind: "proc", key: "p:" + p.pid, pid: p.pid, name: p.name,
                 sub: p.cmd, icon: p.name, cpu: p.cpu, mem: p.mem, user: p.user,
                 count: 0, depth: depth, expanded: false, address: address || "" }
    }
    function _header(id, label, n) {
        return { kind: "header", key: "h:" + id, pid: 0, name: label, sub: "",
                 icon: "", cpu: 0, mem: 0, user: "", count: n, depth: 0,
                 expanded: false, address: "" }
    }

    // Flat row list fed to the ListView (headers, apps, their processes).
    readonly property var rows: {
        const g = TaskManagerService.groups
        const q = searchText.trim().toLowerCase()
        const match = p => !q || p.name.toLowerCase().includes(q)
                              || String(p.pid).startsWith(q)
                              || p.cmd.toLowerCase().includes(q)
        const out = []

        const apps = []
        for (const a of g.apps) {
            const e = _entry(a.cls)
            const name = (e && e.name) || a.cls || a.members[0].name
            const nameHit = !q || name.toLowerCase().includes(q)
                               || a.title.toLowerCase().includes(q)
            const hits = a.members.filter(match)
            if (!nameHit && !hits.length) continue
            apps.push({ kind: "app", key: a.key, pid: a.pid, name: name,
                        sub: a.title, icon: (e && e.icon) || a.cls.toLowerCase(),
                        cpu: a.cpu, mem: a.mem, user: a.members[0].user,
                        count: a.members.length, depth: 0, address: a.address,
                        expanded: !!expanded[a.key] || (!nameHit && hits.length > 0),
                        _members: nameHit ? a.members : hits })
        }
        apps.sort(_cmp)
        if (apps.length) out.push(_header("apps", "Apps", apps.length))
        for (const a of apps) {
            const members = a._members
            delete a._members
            out.push(a)
            if (a.expanded)
                for (const p of members.slice().sort(_cmp))
                    out.push(_procRow(p, 1, a.address))
        }

        const bg = g.background.filter(match).sort(_cmp)
        if (bg.length) out.push(_header("bg", "Background processes", bg.length))
        for (const p of bg) out.push(_procRow(p, 0))

        const sys = g.system.filter(match).sort(_cmp)
        if (sys.length) out.push(_header("sys", "System processes", sys.length))
        for (const p of sys) out.push(_procRow(p, 0))
        return out
    }
    readonly property int selectedIndex: rows.findIndex(r => r.key === selectedKey)
    readonly property var selectedRow: selectedIndex >= 0 ? rows[selectedIndex] : null

    // Sync into a ListModel in place so refreshes keep scroll + delegates.
    onRowsChanged: {
        const r = rows
        for (let i = 0; i < r.length; i++) {
            if (i < rowModel.count) rowModel.set(i, r[i])
            else                    rowModel.append(r[i])
        }
        if (rowModel.count > r.length) rowModel.remove(r.length, rowModel.count - r.length)
    }
    ListModel { id: rowModel }

    function moveSelection(step) {
        const r = rows
        if (!r.length) return
        let i = selectedIndex
        if (i < 0) i = step > 0 ? -1 : r.length
        do { i += step } while (i >= 0 && i < r.length && r[i].kind === "header")
        if (i < 0 || i >= r.length) return
        selectedKey = r[i].key
        list.positionViewAtIndex(i, ListView.Contain)
    }

    function endSelected(force) {
        const r = selectedRow
        if (!r) return
        if (force) TaskManagerService.forceKill(r.pid)
        else       TaskManagerService.endTask(r.pid)
    }

    // ── Formatting ─────────────────────────────────────────────────────
    function fmtCpu(v)  { return v < 0.05 ? "0%" : v.toFixed(1) + "%" }
    function fmtMem(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(2) + " GB"
        return (b / 1048576).toFixed(1) + " MB"
    }
    // Windows-style heat tint: stronger warn fill as usage grows.
    function heat(frac) {
        const f = Math.max(0, Math.min(1, frac))
        return Qt.rgba(theme.warn.r, theme.warn.g, theme.warn.b, 0.04 + 0.36 * f)
    }

    // ── Context menu ───────────────────────────────────────────────────
    property bool menuOpen: false
    property real menuX: 0
    property real menuY: 0
    property var  menuItems: []

    function openMenu(row, x, y) {
        selectedKey = row.key
        const pid = row.pid
        const items = []
        if (row.kind === "app") {
            const addr = row.address
            items.push({ label: "Switch to", icon: "", run: () => { TaskManagerService.focusWindow(addr) } })
            items.push({ label: row.expanded ? "Collapse" : "Expand",
                         icon: row.expanded ? "" : "",
                         run: () => win.setExpanded(row.key, !row.expanded) })
            items.push({ sep: true })
        }
        items.push({ label: "End task",         icon: "", run: () => TaskManagerService.endTask(pid) })
        items.push({ label: "Force kill",       icon: "", danger: true, run: () => TaskManagerService.forceKill(pid) })
        items.push({ label: "End process tree", icon: "", danger: true, run: () => TaskManagerService.endTree(pid) })
        items.push({ sep: true })
        items.push({ label: "Copy PID", icon: "", run: () => Quickshell.execDetached(["wl-copy", "--", String(pid)]) })
        if (row.kind === "proc") {
            const cmd = row.sub
            items.push({ label: "Copy command line", icon: "", run: () => Quickshell.execDetached(["wl-copy", "--", cmd]) })
        }
        menuItems = items
        menuX = x
        menuY = y
        menuOpen = true
    }

    Item {
        id: content
        // 100% layout rendered at uiScale; the window dims above match.
        x: 0; y: 0
        width:  parent.width  / win.uiScale
        height: parent.height / win.uiScale
        scale: win.uiScale
        transformOrigin: Item.TopLeft

        // ── Title bar ──────────────────────────────────────────────────
        Item {
            id: titleBar
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 68

            Row {
                id: titleRow
                anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                spacing: 12
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    color: win.theme.primary
                    font.family: win.theme.ff; font.pixelSize: win.theme.fs + 8
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Task Manager"
                    color: win.theme.fg
                    font.family: win.theme.ff; font.bold: true
                    font.pixelSize: win.theme.fs + 8
                }
            }

            // Tabs (segmented control).
            Rectangle {
                id: tabs
                anchors { left: titleRow.right; leftMargin: 28; verticalCenter: parent.verticalCenter }
                width: tabRow.implicitWidth + 8
                height: 36
                radius: 10
                color: win.theme.inset

                Row {
                    id: tabRow
                    anchors.centerIn: parent
                    spacing: 4
                    Repeater {
                        model: [
                            { id: "processes",   icon: "", label: "Processes"   },
                            { id: "performance", icon: "", label: "Performance" },
                            { id: "users",       icon: "", label: "Users"       }
                        ]
                        delegate: Rectangle {
                            id: tabBtn
                            required property var modelData
                            readonly property bool current: TaskManagerService.tab === modelData.id
                            width: tabContent.implicitWidth + 26
                            height: 28
                            radius: 7
                            color: current ? win.theme.active
                                 : tabHover.hovered ? Qt.rgba(win.theme.fg.r, win.theme.fg.g, win.theme.fg.b, 0.05)
                                 : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            HoverHandler { id: tabHover }
                            Row {
                                id: tabContent
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tabBtn.modelData.icon
                                    color: tabBtn.current ? win.theme.primary : win.theme.txt2
                                    font.family: win.theme.ff; font.pixelSize: win.theme.fs - 1
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tabBtn.modelData.label
                                    color: tabBtn.current ? win.theme.fg : win.theme.txt2
                                    font.family: win.theme.ff; font.bold: tabBtn.current
                                    font.pixelSize: win.theme.fs - 1
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: TaskManagerService.tab = tabBtn.modelData.id
                            }
                        }
                    }
                }
            }

            UiTextField {
                id: search
                theme: win.theme
                visible: !win.onPerf
                anchors { right: closeBtn.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: Math.min(300, closeBtn.x - tabs.x - tabs.width - 40)
                icon: ""
                placeholder: win.onUsers ? "Search user, UID or group…" : "Search name, PID or command…"
                onTextChanged: win.searchText = text

                Component.onCompleted: textInput.Keys.pressed.connect(e => {
                    const move = step => win.onUsers ? users.move(step) : win.moveSelection(step)
                    if (e.key === Qt.Key_Down)      { move(1);  e.accepted = true }
                    else if (e.key === Qt.Key_Up)   { move(-1); e.accepted = true }
                    else if (e.key === Qt.Key_Escape) {
                        if (search.text) search.text = ""
                        else             win.focusTab()
                        e.accepted = true
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        if (!win.onUsers && win.selectedIndex < 0) win.moveSelection(1)
                        win.focusTab(); e.accepted = true
                    }
                })
            }

            Rectangle {
                id: closeBtn
                anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                width: 30; height: 30
                radius: 15
                color: closeHover.hovered ? win.theme.error : win.theme.chip
                border.color: win.theme.sep
                border.width: 1
                HoverHandler { id: closeHover }
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: win.theme.fg
                    font.family: win.theme.ff; font.bold: true
                    font.pixelSize: win.theme.fs
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: TaskManagerService.close()
                }
            }
        }

        // ── Table ──────────────────────────────────────────────────────
        FocusScope {
            id: table
            anchors {
                left: parent.left;   leftMargin: 16
                right: parent.right; rightMargin: 16
                top: titleBar.bottom
                bottom: footer.top
            }
            visible: win.onProcs
            focus: true

            Keys.onPressed: e => {
                const ctrl  = e.modifiers & Qt.ControlModifier
                const shift = e.modifiers & Qt.ShiftModifier
                const r = win.selectedRow
                if (win.menuOpen && e.key === Qt.Key_Escape) { win.menuOpen = false; e.accepted = true; return }
                if (ctrl && (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab)) {
                    TaskManagerService.nextTab(e.key === Qt.Key_Backtab ? -1 : 1); e.accepted = true
                }
                else if (e.key === Qt.Key_Down) { win.moveSelection(1);  e.accepted = true }
                else if (e.key === Qt.Key_Up)   { win.moveSelection(-1); e.accepted = true }
                else if (e.key === Qt.Key_PageDown) { win.moveSelection(10);  e.accepted = true }
                else if (e.key === Qt.Key_PageUp)   { win.moveSelection(-10); e.accepted = true }
                else if (e.key === Qt.Key_Right) {
                    if (r && r.kind === "app") win.setExpanded(r.key, true)
                    e.accepted = true
                } else if (e.key === Qt.Key_Left) {
                    if (r && r.kind === "app") win.setExpanded(r.key, false)
                    else if (r && r.depth > 0)   // jump to the owning app
                        for (let i = win.selectedIndex; i >= 0; i--)
                            if (win.rows[i].kind === "app") { win.selectedKey = win.rows[i].key; break }
                    e.accepted = true
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    if (r && r.address) TaskManagerService.focusWindow(r.address)
                    e.accepted = true
                } else if (e.key === Qt.Key_Delete) {
                    win.endSelected(shift); e.accepted = true
                } else if (ctrl && e.key === Qt.Key_F) {
                    search.textInput.forceActiveFocus(); e.accepted = true
                } else if (e.key === Qt.Key_Escape) {
                    TaskManagerService.close(); e.accepted = true
                } else if (!ctrl && e.text.length === 1 && e.text >= " ") {
                    // Type-to-search.
                    search.text += e.text
                    search.textInput.forceActiveFocus()
                    e.accepted = true
                }
            }

            // Column headers (sortable; CPU / Memory show machine totals).
            Item {
                id: colHeader
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 50

                component HeaderCell: Item {
                    id: hc
                    property string key: ""
                    property string label: ""
                    property string total: ""
                    property bool   alignRight: true
                    readonly property bool active: win.sortKey === key
                    height: parent.height
                    Column {
                        anchors {
                            left: hc.alignRight ? undefined : parent.left
                            right: hc.alignRight ? parent.right : undefined
                            leftMargin: 12; rightMargin: 12
                            bottom: parent.bottom; bottomMargin: 8
                        }
                        spacing: 1
                        Text {
                            visible: hc.total !== ""
                            anchors.right: hc.alignRight ? parent.right : undefined
                            text: hc.total
                            color: win.theme.fg
                            font.family: win.theme.ff; font.bold: true
                            font.pixelSize: win.theme.fs + 2
                        }
                        Row {
                            anchors.right: hc.alignRight ? parent.right : undefined
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: hc.active
                                text: win.sortDesc ? "" : ""
                                color: win.theme.primary
                                font.family: win.theme.ff; font.pixelSize: win.theme.fs - 3
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: hc.label
                                color: hc.active ? win.theme.fg : win.theme.txt2
                                font.family: win.theme.ff
                                font.bold: hc.active
                                font.pixelSize: win.theme.fs - 2
                            }
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: Qt.rgba(win.theme.fg.r, win.theme.fg.g, win.theme.fg.b, 0.05)
                        visible: hcHover.hovered
                    }
                    HoverHandler { id: hcHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.sortBy(hc.key)
                    }
                }

                HeaderCell {
                    anchors.left: parent.left
                    width: parent.width - win.colPid - win.colUser - win.colCpu - win.colMem
                    key: "name"; label: "Name"; alignRight: false
                    total: TaskManagerService.procs.length
                           ? TaskManagerService.procs.length + " processes" : ""
                }
                HeaderCell {
                    x: parent.width - win.colPid - win.colUser - win.colCpu - win.colMem
                    width: win.colPid
                    key: "pid"; label: "PID"
                }
                HeaderCell {
                    x: parent.width - win.colUser - win.colCpu - win.colMem
                    width: win.colUser
                    key: "user"; label: "User"; alignRight: false
                }
                HeaderCell {
                    x: parent.width - win.colCpu - win.colMem
                    width: win.colCpu
                    key: "cpu"; label: "CPU"
                    total: Math.round(SystemService.cpuPerc * 100) + "%"
                }
                HeaderCell {
                    x: parent.width - win.colMem
                    width: win.colMem
                    key: "mem"; label: "Memory"
                    total: Math.round(SystemService.memPerc * 100) + "%"
                }

                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1
                    color: win.theme.sep
                }
            }

            Text {
                anchors.centerIn: list
                visible: rowModel.count === 0
                text: !TaskManagerService.loaded ? "Loading processes…"
                    : win.searchText ? "No process matches \"" + win.searchText + "\""
                    : "No processes"
                color: win.theme.outline
                font.family: win.theme.ff; font.pixelSize: win.theme.fs
            }

            ListView {
                id: list
                anchors {
                    left: parent.left; right: parent.right
                    top: colHeader.bottom; topMargin: 4
                    bottom: parent.bottom
                }
                clip: true
                model: rowModel
                spacing: 1
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 400

                // In the table's right margin, so the columns stay aligned.
                ScrollBar.vertical: UiScrollBar {
                    theme: win.theme
                    parent: table
                    anchors { left: list.right; leftMargin: 4; top: list.top; bottom: list.bottom }
                }

                delegate: Rectangle {
                    id: row
                    required property int    index
                    required property string kind
                    required property string key
                    required property int    pid
                    required property string name
                    required property string sub
                    required property string icon
                    required property real   cpu
                    required property real   mem
                    required property string user
                    required property int    count
                    required property int    depth
                    required property bool   expanded
                    required property string address

                    readonly property bool isHeader: kind === "header"
                    readonly property bool isApp:    kind === "app"
                    readonly property bool selected: key === win.selectedKey
                    readonly property real cellsX:   width - win.colPid - win.colUser - win.colCpu - win.colMem

                    width: ListView.view.width
                    height: isHeader ? 38 : 34
                    radius: 8
                    color: isHeader ? "transparent"
                         : selected ? win.theme.active
                         : rowHover.hovered ? Qt.rgba(win.theme.fg.r, win.theme.fg.g, win.theme.fg.b, 0.05)
                         : "transparent"

                    HoverHandler { id: rowHover; enabled: !row.isHeader }

                    // Selection accent pill.
                    Rectangle {
                        visible: row.selected
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: 3; height: 16; radius: 2
                        color: win.theme.primary
                    }

                    // Section header.
                    Text {
                        visible: row.isHeader
                        anchors { left: parent.left; leftMargin: 12; bottom: parent.bottom; bottomMargin: 6 }
                        text: row.name + " (" + row.count + ")"
                        color: win.theme.primary
                        font.family: win.theme.ff; font.bold: true
                        font.pixelSize: win.theme.fs - 1
                    }

                    // Name cell: chevron (apps), icon, name, muted detail.
                    Item {
                        visible: !row.isHeader
                        x: 8 + row.depth * 26
                        width: row.cellsX - x - 8
                        height: parent.height

                        Text {
                            id: chevron
                            visible: row.isApp
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            horizontalAlignment: Text.AlignHCenter
                            text: row.expanded ? "" : ""
                            color: win.theme.txt2
                            font.family: win.theme.ff; font.pixelSize: win.theme.fs - 4
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.setExpanded(row.key, !row.expanded)
                            }
                        }

                        Item {
                            id: iconBox
                            x: row.isApp ? 24 : 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20
                            readonly property string src: IconService.iconFor(row.icon)
                            IconImage {
                                anchors.fill: parent
                                visible: iconBox.src !== ""
                                source: iconBox.src
                                asynchronous: true
                                implicitSize: 20
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: iconBox.src === ""
                                text: ""
                                color: win.theme.outline
                                font.family: win.theme.ff; font.pixelSize: win.theme.fs - 1
                            }
                        }

                        Text {
                            id: nameText
                            anchors { left: iconBox.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            width: Math.min(implicitWidth, parent.width - x - 4)
                            text: row.isApp && row.count > 1 ? row.name + " (" + row.count + ")" : row.name
                            color: win.theme.fg
                            font.family: win.theme.ff
                            font.bold: row.isApp
                            font.pixelSize: win.theme.fs - 1
                            elide: Text.ElideRight
                        }
                        Text {
                            anchors { left: nameText.right; leftMargin: 10; right: parent.right
                                      verticalCenter: parent.verticalCenter }
                            text: row.sub
                            color: win.theme.outline
                            font.family: win.theme.ff
                            font.pixelSize: win.theme.fs - 3
                            elide: Text.ElideRight
                        }
                    }

                    // PID / User / CPU / Memory cells.
                    Text {
                        visible: !row.isHeader
                        x: row.cellsX
                        width: win.colPid - 12
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: row.pid
                        color: win.theme.txt2
                        font.family: win.theme.ff; font.pixelSize: win.theme.fs - 2
                    }
                    Text {
                        visible: !row.isHeader
                        x: row.cellsX + win.colPid + 12
                        width: win.colUser - 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.user
                        color: win.theme.txt2
                        font.family: win.theme.ff; font.pixelSize: win.theme.fs - 2
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        visible: !row.isHeader
                        x: row.cellsX + win.colPid + win.colUser
                        width: win.colCpu - 2; height: parent.height - 4
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 4
                        color: win.heat(row.cpu / 25)
                        Text {
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            text: win.fmtCpu(row.cpu)
                            color: win.theme.fg
                            font.family: win.theme.ff; font.pixelSize: win.theme.fs - 2
                        }
                    }
                    Rectangle {
                        visible: !row.isHeader
                        x: row.cellsX + win.colPid + win.colUser + win.colCpu
                        width: win.colMem - 2; height: parent.height - 4
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 4
                        color: win.heat(TaskManagerService.memTotal > 0
                                        ? row.mem / TaskManagerService.memTotal * 10 : 0)
                        Text {
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            text: win.fmtMem(row.mem)
                            color: win.theme.fg
                            font.family: win.theme.ff; font.pixelSize: win.theme.fs - 2
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.leftMargin: row.isApp ? 8 + 22 : 0   // leave the chevron clickable
                        enabled: !row.isHeader
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            table.forceActiveFocus()
                            win.selectedKey = row.key
                            if (mouse.button === Qt.RightButton) {
                                const p = mapToItem(content, mouse.x, mouse.y)
                                win.openMenu(win.rows[row.index], p.x, p.y)
                            }
                        }
                        onDoubleClicked: mouse => {
                            if (mouse.button !== Qt.LeftButton) return
                            if (row.isApp) TaskManagerService.focusWindow(row.address)
                        }
                    }
                }
            }
        }

        // ── Performance tab ────────────────────────────────────────────
        PerformanceView {
            id: perf
            theme: win.theme
            anchors { left: parent.left; right: parent.right; top: titleBar.bottom; bottom: parent.bottom }
            visible: win.onPerf
        }

        // ── Users tab ──────────────────────────────────────────────────
        UsersView {
            id: users
            theme: win.theme
            anchors { left: parent.left; right: parent.right; top: titleBar.bottom; bottom: parent.bottom }
            visible: win.onUsers
            searchText: win.searchText
            onTyped: t => { search.text += t; search.textInput.forceActiveFocus() }
            onSearchRequested: search.textInput.forceActiveFocus()
        }

        // ── Footer: status + actions ───────────────────────────────────
        Rectangle {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            visible: win.onProcs
            height: 60
            color: win.theme.inset

            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 1
                color: win.theme.sep
            }

            Text {
                anchors { left: parent.left; leftMargin: 24; right: actions.left; rightMargin: 16
                          verticalCenter: parent.verticalCenter }
                readonly property var g: TaskManagerService.groups
                text: TaskManagerService.lastError
                      ? "  " + TaskManagerService.lastError
                      : g.apps.length + " apps · " + g.background.length + " background · "
                        + g.system.length + " system   ·   Memory "
                        + win.fmtMem(SystemService.memUsedKib * 1024) + " / "
                        + win.fmtMem(SystemService.memTotalKib * 1024)
                color: TaskManagerService.lastError ? win.theme.error : win.theme.txt2
                font.family: win.theme.ff; font.pixelSize: win.theme.fs - 2
                elide: Text.ElideRight
            }

            Row {
                id: actions
                anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                spacing: 10
                UiButton {
                    theme: win.theme
                    visible: !!win.selectedRow && win.selectedRow.address !== ""
                    text: "Switch to"
                    icon: ""
                    onClicked: TaskManagerService.focusWindow(win.selectedRow.address)
                }
                UiButton {
                    theme: win.theme
                    enabled: !!win.selectedRow
                    kind: "danger"
                    text: "Force kill"
                    icon: ""
                    onClicked: win.endSelected(true)
                }
                UiButton {
                    theme: win.theme
                    enabled: !!win.selectedRow
                    kind: "primary"
                    text: "End task"
                    icon: ""
                    onClicked: win.endSelected(false)
                }
            }
        }

        // ── Context menu ───────────────────────────────────────────────
        MouseArea {
            anchors.fill: parent
            visible: win.menuOpen
            acceptedButtons: Qt.AllButtons
            onPressed: win.menuOpen = false
        }
        Rectangle {
            id: menu
            visible: win.menuOpen
            width: 220
            height: menuCol.implicitHeight + 12
            x: Math.min(win.menuX, content.width - width - 8)
            y: Math.min(win.menuY, content.height - height - 8)
            radius: 10
            color: win.theme.surface
            border.color: win.theme.sep
            border.width: 1

            Column {
                id: menuCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 2
                Repeater {
                    model: win.menuItems
                    delegate: Item {
                        id: mi
                        required property var modelData
                        width: menuCol.width
                        height: modelData.sep ? 9 : 32
                        Rectangle {
                            visible: !!mi.modelData.sep
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                      leftMargin: 6; rightMargin: 6 }
                            height: 1
                            color: win.theme.sep
                        }
                        Rectangle {
                            visible: !mi.modelData.sep
                            anchors.fill: parent
                            radius: 7
                            color: miHover.hovered
                                   ? Qt.rgba(win.theme.fg.r, win.theme.fg.g, win.theme.fg.b, 0.08)
                                   : "transparent"
                            HoverHandler { id: miHover }
                            Row {
                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                spacing: 10
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    text: mi.modelData.icon || ""
                                    color: mi.modelData.danger ? win.theme.error : win.theme.txt2
                                    font.family: win.theme.ff; font.pixelSize: win.theme.fs - 2
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: mi.modelData.label || ""
                                    color: mi.modelData.danger ? win.theme.error : win.theme.fg
                                    font.family: win.theme.ff; font.pixelSize: win.theme.fs - 1
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    win.menuOpen = false
                                    mi.modelData.run()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
