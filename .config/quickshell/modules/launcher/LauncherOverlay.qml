import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.modules.appearance
import qs.modules.clipboard
import qs.modules.icons
import qs.modules.keybinds
import qs.modules.settings
import qs.modules.taskmanager
import qs.modules.wallpaper
import qs.common

// Spotlight-style launcher: fat centred search bar; results appear only
// once the user types.
PanelWindow {
    id: overlay

    required property var theme
    // Shell-size scale of this window's monitor (unset monitors = 100%).
    readonly property real uiScale: AppearanceService.scaleFor(screen?.name ?? "")

    readonly property bool _open: LauncherService.launcherOpen
    // Unmapped once the close animation ends: a kept-alive fullscreen layer
    // holds the Wayland keyboard grab and starves the refocused window
    // (FocusService refocuses after the animation).
    visible: pop.shown
    // Stay mapped through the close animation, but input-transparent and
    // without the keyboard (focus handoff happens once it unmaps).
    mask: _open ? null : noInput
    Region { id: noInput }
    // Keyboard only while truly open; dropped at exit-anim start so focus
    // returns immediately.
    WlrLayershell.keyboardFocus: _open ? WlrKeyboardFocus.OnDemand
                                       : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }
    exclusiveZone: 0
    color: "transparent"

    // Launcher-only font override.
    readonly property string ff: "CaskaydiaCove Nerd Font Propo"

    // ── Layout tuning ────────────────────────────────────────────────
    readonly property int  panelWidth:    640
    readonly property int  topOffset:     140
    readonly property int  searchHeight:  64
    readonly property int  rowHeight:     54
    readonly property int  maxVisibleRows: 7

    property string searchText:    ""
    property int    selectedIndex: 0

    // ">>" = calculator; single ">" = shell-command mode.
    readonly property bool calcMode:    /^\s*>>/.test(searchText)
    readonly property bool commandMode: /^\s*>/.test(searchText) && !calcMode

    // ── Calculator ───────────────────────────────────────────────────────
    readonly property string calcExpr: calcMode ? searchText.replace(/^\s*>>/, "").trim() : ""
    readonly property var calcResult:  calcMode ? overlay._calc(calcExpr) : null
    function _calc(expr) {
        if (!expr) return null
        let e = expr
            .replace(/\^/g, "**")
            .replace(/\blog2\b/gi,  "Math.log2")
            .replace(/\blog10\b/gi, "Math.log10")
            .replace(/\bln\b/gi,    "Math.log")
            .replace(/\blog\b/gi,   "Math.log10")
            .replace(/\b(sqrt|cbrt|abs|sin|cos|tan|asin|acos|atan|exp|floor|ceil|round|sign|min|max|pow)\b/gi, "Math.$1")
            .replace(/\bpi\b/gi,  "(Math.PI)")
            .replace(/\btau\b/gi, "(2*Math.PI)")
            .replace(/\be\b/gi,   "(Math.E)")
        // Reject anything but safe math after stripping Math.* helpers.
        const stripped = e.replace(/Math\.\w+/g, "")
        if (/[^0-9+\-*/%.,()eE\s]/.test(stripped)) return null
        try {
            const r = Function('"use strict"; return (' + e + ')')()
            if (typeof r === "number" && isFinite(r)) return r
        } catch (err) {}
        return null
    }
    function _fmtCalc(r) {
        if (r === null || r === undefined) return ""
        return String(Math.round(r * 1e10) / 1e10)
    }
    function _copyCalc() {
        if (calcResult !== null) Quickshell.execDetached(["wl-copy", "--", overlay._fmtCalc(calcResult)])
        close()
    }

    // Shell commands — each entry: { name, desc, icon, run() }
    readonly property var shellCommands: [
        {
            name: "Settings",
            desc: "Open Quickshell settings",
            icon: "preferences-system",
            run: () => { SettingsService.openSettings("wifi") }
        },
        {
            name: "Task Manager",
            desc: "See running apps and processes, end or kill them",
            icon: "utilities-system-monitor",
            run: () => { TaskManagerService.open() }
        },
        {
            name: "Wallpaper",
            desc: "Browse and apply wallpapers from " + WallpaperService.wallpaperFolder,
            icon: "preferences-desktop-wallpaper",
            run: () => { WallpaperService.openWallpaperPicker() }
        },
        {
            name: "Clipboard",
            desc: "Browse and re-copy from clipboard history (cliphist)",
            icon: "edit-paste",
            run: () => { ClipboardService.openClipboard() }
        },
        {
            name: "Keybinds",
            desc: "Show the keyboard shortcuts cheat-sheet",
            icon: "preferences-desktop-keyboard-shortcuts",
            run: () => { KeybindsService.openKeybinds() }
        },
        {
            name: "Theme",
            desc: "Switch the shell colour theme",
            icon: "preferences-desktop-theme",
            run: () => { AppearanceService.openTheme() }
        },
        {
            name: "GPU Launch",
            desc: "Launch an app on the dedicated GPU (DRI_PRIME=1)",
            icon: "preferences-desktop-display",
            run: () => { LauncherService.openGpuLauncher() }
        }
    ]

    // Empty query shows nothing (Spotlight behaviour).
    readonly property var filtered: {
        const raw = searchText.trim()
        if (!raw) return []
        if (calcMode) return []                 // calculator has its own view
        if (commandMode) {
            const q = raw.replace(/^>\s*/, "").toLowerCase()
            const list = shellCommands
            if (!q) return list
            return list.filter(c =>
                (c.name + " " + (c.desc || "")).toLowerCase().includes(q))
        }
        if (!DesktopEntries?.applications?.values) return []
        const q = raw.toLowerCase()
        const apps = [...DesktopEntries.applications.values]
            .filter(e => e && !e.noDisplay)
        // Score: prefix on name beats substring on name beats anything else.
        const scored = []
        for (const e of apps) {
            const name = (e.name || "").toLowerCase()
            const kw   = Array.isArray(e.keywords) ? e.keywords.join(" ") : ""
            const hay  = [e.genericName, e.comment, kw]
                            .filter(Boolean).join(" ").toLowerCase()
            let score = 0
            if (name === q)            score = 100
            else if (name.startsWith(q)) score = 80
            else if (name.includes(q)) score = 60
            else if (hay.includes(q))  score = 30
            if (score > 0) scored.push({ entry: e, score, name })
        }
        scored.sort((a, b) => (b.score - a.score) || a.name.localeCompare(b.name))
        return scored.map(s => s.entry)
    }

    readonly property bool hasResults: filtered.length > 0
    readonly property bool showResults: searchText.trim().length > 0

    // Back to the first row without the highlight gliding up to it.
    property bool _snapHighlight: false
    function resetSelection() {
        _snapHighlight = true
        selectedIndex  = 0
        listView.positionViewAtBeginning()
        Qt.callLater(() => _snapHighlight = false)
    }

    function close() {
        LauncherService.launcherOpen = false
        searchText    = ""
        resetSelection()
    }

    function launchSelected() {
        if (calcMode) { _copyCalc(); return }   // Enter copies the result
        const e = filtered[selectedIndex]
        if (!e) return
        try {
            if (typeof e.run === "function") {
                e.run()                                            // shell command
            } else if (LauncherService.launcherGpuMode && e.command && e.command.length) {
                // Launch on the dGPU; sh -c '… "$@"' keeps args intact.
                Quickshell.execDetached(["sh", "-c", "DRI_PRIME=1 exec \"$@\"", "gpu"].concat(e.command))
            } else if (typeof e.execute === "function") {
                e.execute()                                        // .desktop entry (default GPU)
            }
        } catch(err) { console.log("launch failed:", err) }
        close()
    }

    onFilteredChanged: resetSelection()
    on_OpenChanged: {
        if (_open) {
            searchInput.text = ""           // clears the TextInput itself
            searchText       = ""
            resetSelection()
            Qt.callLater(() => searchInput.forceActiveFocus())
        }
    }

    // ── Backdrop: clicking anywhere outside closes ───────────────────
    MouseArea {
        anchors.fill: parent
        onClicked: overlay.close()
    }

    // ── Floating panel (search bar + collapsible results) ────────────
    Column {
        id: floater
        anchors.horizontalCenter: parent.horizontalCenter
        y: overlay.topOffset
        width: overlay.panelWidth
        // uiScale transform from the top edge; composes with the pop.
        scale: overlay.uiScale
        transformOrigin: Item.Top
        spacing: 8
        opacity: 0
        // Shared open motion, growing down from the top centre.
        transform: PopAnim { id: pop; item: floater; open: overlay._open; origin.x: floater.width / 2; origin.y: 0 }

        // ── Search bar ───────────────────────────────────────────────
        Rectangle {
            id: searchBar
            width: parent.width
            height: overlay.searchHeight
            radius: 14
            color: overlay.theme.bg
            border.color: searchInput.activeFocus
                          ? overlay.theme.primary
                          : overlay.theme.sep
            border.width: 1

            // Swallow clicks — don't trigger backdrop close.
            MouseArea { anchors.fill: parent; onClicked: {} }

            Text {
                anchors { left: parent.left; leftMargin: 22
                          verticalCenter: parent.verticalCenter }
                text: ""
                color: overlay.theme.outline
                font.family: overlay.ff
                font.pixelSize: 22
            }

            // GPU-mode badge — apps launched from here run with DRI_PRIME=1.
            Rectangle {
                id: gpuBadge
                visible: LauncherService.launcherGpuMode
                anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                width: gpuLabel.implicitWidth + 22; height: 28
                radius: 8
                color: Qt.alpha(overlay.theme.primary, 0.18)
                border.color: overlay.theme.primary
                border.width: 1
                Text {
                    id: gpuLabel
                    anchors.centerIn: parent
                    text: "GPU"
                    color: overlay.theme.primary
                    font.family: overlay.ff
                    font.bold: true
                    font.pixelSize: overlay.theme.fs - 1
                }
            }

            TextInput {
                id: searchInput
                anchors { left: parent.left;  leftMargin: 60
                          right: parent.right
                          rightMargin: LauncherService.launcherGpuMode ? gpuBadge.width + 28 : 20
                          verticalCenter: parent.verticalCenter }
                color:             overlay.theme.fg
                selectionColor:    overlay.theme.primary
                selectedTextColor: overlay.theme.bg
                font.family:       overlay.ff
                font.pixelSize:    18
                activeFocusOnPress: true
                clip: true
                onTextChanged: overlay.searchText = text

                Text {
                    visible: searchInput.text.length === 0
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: LauncherService.launcherGpuMode
                          ? "Search apps to run on the GPU (DRI_PRIME=1)"
                          : "> to launch shell application"
                    color: overlay.theme.outline
                    opacity: 0.55
                    font: searchInput.font
                }

                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Escape) {
                        overlay.close()
                        e.accepted = true
                    } else if (e.key === Qt.Key_Down) {
                        // Wraps: Down on the last result goes to the first.
                        if (overlay.hasResults) {
                            const n = overlay.filtered.length
                            overlay.selectedIndex = (overlay.selectedIndex + 1) % n
                        }
                        e.accepted = true
                    } else if (e.key === Qt.Key_Up) {
                        // Wraps: Up on the first result goes to the last.
                        if (overlay.hasResults) {
                            const n = overlay.filtered.length
                            overlay.selectedIndex = (overlay.selectedIndex - 1 + n) % n
                        }
                        e.accepted = true
                    } else if (e.key === Qt.Key_Return
                            || e.key === Qt.Key_Enter) {
                        overlay.launchSelected()
                        e.accepted = true
                    }
                }
            }
        }

        // ── Results panel — only present once the user has typed ─────
        Rectangle {
            id: resultsCard
            visible: overlay.showResults
            width: parent.width
            radius: 14
            color: overlay.theme.bg
            border.color: overlay.theme.sep
            border.width: 1

            readonly property int contentHeight: overlay.hasResults
                ? Math.min(overlay.filtered.length, overlay.maxVisibleRows)
                  * (overlay.rowHeight + listView.spacing)
                : 56
            height: overlay.calcMode ? 92 : contentHeight + 12

            // Swallow clicks — don't trigger backdrop close.
            MouseArea { anchors.fill: parent; onClicked: {} }

            // ── Calculator result ───────────────────────────────────────
            Item {
                visible: overlay.calcMode
                anchors { fill: parent; margins: 14 }

                // "= 42" big, with the parsed expression underneath.
                Text {
                    id: calcResultText
                    anchors { left: parent.left; right: copyHint.left; rightMargin: 10
                              verticalCenter: parent.verticalCenter }
                    text: overlay.calcExpr.length === 0
                          ? "…"
                          : (overlay.calcResult === null ? "—" : "= " + overlay._fmtCalc(overlay.calcResult))
                    color: overlay.calcResult === null && overlay.calcExpr.length > 0
                           ? overlay.theme.outline : overlay.theme.primary
                    font.family: overlay.ff
                    font.bold: true
                    font.pixelSize: 30
                    elide: Text.ElideRight
                }
                Text {
                    anchors { left: parent.left; bottom: parent.bottom; bottomMargin: -2 }
                    text: overlay.calcExpr.length === 0 ? "type an expression — e.g. 12*(3+4), sqrt(2), sin(pi/4)"
                        : (overlay.calcResult === null ? "invalid expression" : overlay.calcExpr)
                    color: overlay.theme.outline
                    font.family: overlay.ff
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width - 80
                }
                // Enter-to-copy hint.
                Rectangle {
                    id: copyHint
                    visible: overlay.calcResult !== null
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: copyLbl.implicitWidth + 18; height: 26
                    radius: 7
                    color: overlay.theme.chip
                    border.color: overlay.theme.sep
                    border.width: 1
                    Text {
                        id: copyLbl
                        anchors.centerIn: parent
                        text: "⏎ copy"
                        color: overlay.theme.txt2
                        font.family: overlay.ff
                        font.pixelSize: 12
                    }
                }
            }

            // Empty-state message
            Text {
                visible: !overlay.hasResults && !overlay.calcMode
                anchors.centerIn: parent
                text: "No matching apps"
                color: overlay.theme.outline
                font.family: overlay.ff
                font.pixelSize: 15
            }

            ListView {
                id: listView
                visible: overlay.hasResults && !overlay.calcMode
                anchors { fill: parent; margins: 6 }
                clip: true
                model: overlay.filtered
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 240

                // One shared highlight that glides to the selected row (and
                // scrolls the view along) instead of rows recolouring in place.
                currentIndex: overlay.selectedIndex
                highlightFollowsCurrentItem: true
                highlightMoveDuration: overlay._snapHighlight ? 0 : 160
                highlightMoveVelocity: -1
                highlightResizeDuration: 0
                highlight: Rectangle {
                    radius: 10
                    color: overlay.theme.active
                }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width:  ListView.view.width
                    height: overlay.rowHeight
                    radius: 10
                    color: index !== overlay.selectedIndex && rowHover.hovered
                           ? overlay.theme.surface
                           : "transparent"

                    HoverHandler {
                        id: rowHover
                        onHoveredChanged: if (hovered) overlay.selectedIndex = row.index
                    }

                    Row {
                        anchors { left: parent.left;   leftMargin: 12
                                  right: parent.right; rightMargin: 12
                                  verticalCenter: parent.verticalCenter }
                        spacing: 14

                        IconImage {
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 36
                            asynchronous: true
                            source: IconService.iconFor(
                                        row.modelData?.icon
                                     || "application-x-executable")
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 50
                            spacing: 2
                            Text {
                                text: row.modelData?.name ?? ""
                                color: overlay.theme.fg
                                font.family: overlay.ff
                                font.bold: true
                                font.pixelSize: 15
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                visible: text.length > 0
                                text: row.modelData?.genericName
                                   || row.modelData?.comment
                                   || row.modelData?.desc
                                   || ""
                                color: overlay.theme.outline
                                font.family: overlay.ff
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            overlay.selectedIndex = row.index
                            overlay.launchSelected()
                        }
                    }
                }
            }
        }
    }
}
