import QtQuick

// Monitor configuration. Scans `hyprctl monitors`, shows a draggable
// arrangement diagram, and edits one monitor at a time (resolution, scale,
// rotation, enable). Positioning is done by dragging in the diagram. Writes
// ~/.config/hypr/modules/monitors.lua + reloads Hyprland.
Item {
    id: pane

    required property var shellRoot
    required property var theme

    ListModel { id: edits; dynamicRoles: true }
    property int    vizTick: 0
    property string selectedOutput: ""
    // The principal monitor is pinned to 0×0 (the layout origin).
    property string primaryOutput: ""

    function setEdit(i, role, val) { edits.setProperty(i, role, val); vizTick++ }

    // Make `output` the principal monitor: re-base every monitor so this one
    // sits at 0×0 (keeping the relative arrangement intact).
    function setPrimary(output) {
        let dx = 0, dy = 0, found = false
        for (let i = 0; i < edits.count; i++) {
            const r = edits.get(i)
            if (r.output === output) { dx = r.x; dy = r.y; found = true; break }
        }
        if (!found) return
        for (let i = 0; i < edits.count; i++) {
            const r = edits.get(i)
            setEdit(i, "x", r.x - dx); setEdit(i, "y", r.y - dy)
        }
        primaryOutput = output
    }

    function modesFor(output) {
        const m = (pane.shellRoot.monitorList || []).find(x => x.name === output)
        return m ? m.modes : []
    }
    function modeW(row) { const m = String(row.mode).match(/^(\d+)x(\d+)/); return m ? parseInt(m[1]) : 1920 }
    function modeH(row) { const m = String(row.mode).match(/^(\d+)x(\d+)/); return m ? parseInt(m[2]) : 1080 }
    function rotated(row) { const t = parseInt(row.transform) || 0; return (t % 2) === 1 }
    // transform value (0..3) → human label.
    function rotLabel(t) {
        return ["Landscape (default)", "Portrait", "Landscape (reversed)", "Portrait (reversed)"][(parseInt(t) || 0) % 4]
    }
    // Effective logical size (rotation swaps W/H, scale shrinks).
    function effW(row) { const s = parseFloat(row.scale) || 1; return Math.round((rotated(row) ? modeH(row) : modeW(row)) / s) }
    function effH(row) { const s = parseFloat(row.scale) || 1; return Math.round((rotated(row) ? modeW(row) : modeH(row)) / s) }

    function hasOutput(o) {
        for (let i = 0; i < edits.count; i++) if (edits.get(i).output === o) return true
        return false
    }

    function rebuild() {
        edits.clear()
        for (const m of (pane.shellRoot.monitorList || [])) {
            edits.append({
                output:    m.name,
                desc:      m.description,
                mode:      m.width + "x" + m.height + "@" + m.refresh,
                x:         m.x,
                y:         m.y,
                scale:     String(m.scale),
                transform: parseInt(m.transform) || 0,
                disabled:  m.disabled,
                modesOpen: false,
                rotOpen:   false
            })
        }
        if (!hasOutput(selectedOutput) && edits.count > 0) selectedOutput = edits.get(0).output
        // Principal = the monitor already at the origin, else re-base the first.
        let prim = ""
        for (let i = 0; i < edits.count; i++) {
            const r = edits.get(i)
            if (r.x === 0 && r.y === 0) { prim = r.output; break }
        }
        if (prim === "" && edits.count > 0) setPrimary(edits.get(0).output)
        else primaryOutput = prim
        vizTick++
    }
    function applyAll() {
        const cfgs = []
        for (let i = 0; i < edits.count; i++) {
            const r = edits.get(i)
            cfgs.push({ output: r.output, mode: r.mode,
                        x: parseInt(r.x) || 0, y: parseInt(r.y) || 0,
                        scale: r.scale || "1", transform: parseInt(r.transform) || 0,
                        disabled: r.disabled })
        }
        pane.shellRoot.applyMonitors(cfgs)
    }

    function bounds() {
        let minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9
        for (let i = 0; i < edits.count; i++) {
            const r = edits.get(i)
            minX = Math.min(minX, r.x); minY = Math.min(minY, r.y)
            maxX = Math.max(maxX, r.x + effW(r)); maxY = Math.max(maxY, r.y + effH(r))
        }
        if (edits.count === 0) return { minX: 0, minY: 0, maxX: 1920, maxY: 1080 }
        return { minX, minY, maxX, maxY }
    }

    // ── Magnetic snapping (see drag handler) ─────────────────────────────
    function _clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
    function _rects(exclude) {
        const a = []
        for (let j = 0; j < edits.count; j++) {
            if (j === exclude) continue
            const r = edits.get(j); if (r.disabled) continue
            a.push({ x: r.x, y: r.y, w: effW(r), h: effH(r) })
        }
        return a
    }
    function _overlap(a, b) { return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y }
    function _touches(a, list) {
        for (const o of list) {
            const xOv = a.x < o.x + o.w && a.x + a.w > o.x
            const yOv = a.y < o.y + o.h && a.y + a.h > o.y
            if (((Math.abs(a.x - (o.x + o.w)) < 1) || (Math.abs((a.x + a.w) - o.x) < 1)) && yOv) return true
            if (((Math.abs(a.y - (o.y + o.h)) < 1) || (Math.abs((a.y + a.h) - o.y) < 1)) && xOv) return true
        }
        return false
    }
    function resolvePosition(idx, rx, ry) {
        const r = edits.get(idx)
        const w = effW(r), h = effH(r)
        const others = _rects(idx)
        if (others.length === 0) return { x: Math.round(rx), y: Math.round(ry) }

        const thr = 140
        let sx = rx, sy = ry, bdx = thr, bdy = thr
        for (const o of others) {
            for (const c of [o.x, o.x + o.w - w, o.x + o.w, o.x - w]) { const d = Math.abs(rx - c); if (d < bdx) { bdx = d; sx = c } }
            for (const c of [o.y, o.y + o.h - h, o.y + o.h, o.y - h]) { const d = Math.abs(ry - c); if (d < bdy) { bdy = d; sy = c } }
        }
        for (let it = 0; it < 12; it++) {
            let moved = false
            for (const o of others) {
                const a = { x: sx, y: sy, w, h }
                if (_overlap(a, o)) {
                    const pR = (o.x + o.w) - sx, pL = (sx + w) - o.x, pD = (o.y + o.h) - sy, pU = (sy + h) - o.y
                    const mn = Math.min(pR, pL, pD, pU)
                    if      (mn === pR) sx = o.x + o.w
                    else if (mn === pL) sx = o.x - w
                    else if (mn === pD) sy = o.y + o.h
                    else                sy = o.y - h
                    moved = true
                }
            }
            if (!moved) break
        }
        if (!_touches({ x: sx, y: sy, w, h }, others)) {
            let best = null, bestD = Infinity
            for (const o of others) {
                const cands = [
                    { x: o.x + o.w, y: _clamp(sy, o.y - h + 1, o.y + o.h - 1) },
                    { x: o.x - w,   y: _clamp(sy, o.y - h + 1, o.y + o.h - 1) },
                    { x: _clamp(sx, o.x - w + 1, o.x + o.w - 1), y: o.y + o.h },
                    { x: _clamp(sx, o.x - w + 1, o.x + o.w - 1), y: o.y - h }
                ]
                for (const c of cands) { const d = (c.x - sx) * (c.x - sx) + (c.y - sy) * (c.y - sy); if (d < bestD) { bestD = d; best = c } }
            }
            if (best) { sx = best.x; sy = best.y }
        }
        return { x: Math.round(sx), y: Math.round(sy) }
    }

    Component.onCompleted: pane.shellRoot.refreshMonitors()
    Connections {
        target: pane.shellRoot
        function onMonitorListChanged() { pane.rebuild() }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: 14

            // ── Header: count + rescan + cancel + apply ──────────────────
            Row {
                width: parent.width
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: edits.count + (edits.count === 1 ? " monitor" : " monitors")
                    color: pane.theme.outline
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 1
                    width: parent.width - rescanBtn.width - cancelBtn.width - applyBtn.width - 24
                }
                MonBtn { id: rescanBtn; label: "Rescan"; onClicked: pane.shellRoot.refreshMonitors() }
                MonBtn { id: cancelBtn; label: "Cancel"; onClicked: pane.rebuild() }
                MonBtn { id: applyBtn;  label: "Apply"; accent: true; onClicked: pane.applyAll() }
            }

            // ── Arrangement diagram (drag to position) ───────────────────
            Rectangle {
                width: parent.width
                height: 200
                radius: 12
                color: Qt.darker(pane.theme.bg, 1.25)
                border.color: pane.theme.sep
                border.width: 1

                Item {
                    id: diagram
                    anchors { fill: parent; margins: 16 }
                    readonly property var b: { pane.vizTick; return pane.bounds() }
                    readonly property real spanX: Math.max(1, b.maxX - b.minX)
                    readonly property real spanY: Math.max(1, b.maxY - b.minY)
                    readonly property real s: Math.min(width / spanX, height / spanY) * 0.9
                    readonly property real ox: (width  - spanX * s) / 2
                    readonly property real oy: (height - spanY * s) / 2

                    Repeater {
                        model: edits
                        delegate: Rectangle {
                            id: box
                            required property var model
                            required property int index
                            readonly property bool sel: model.output === pane.selectedOutput
                            property real dragDX: 0
                            property real dragDY: 0
                            property int  pendX: 0
                            property int  pendY: 0

                            x: diagram.ox + (model.x - diagram.b.minX) * diagram.s + dragDX
                            y: diagram.oy + (model.y - diagram.b.minY) * diagram.s + dragDY
                            width:  Math.max(26, pane.effW(model) * diagram.s)
                            height: Math.max(20, pane.effH(model) * diagram.s)
                            radius: 6
                            color: model.disabled ? Qt.darker(pane.theme.bg, 1.5)
                                  : (sel ? pane.theme.hi(1.5) : pane.theme.surface)
                            border.color: sel ? pane.theme.primary : pane.theme.sep
                            border.width: sel ? 2 : 1
                            z: sel ? 2 : 1

                            Column {
                                anchors.centerIn: parent
                                spacing: 1
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: box.model.output
                                    color: pane.theme.fg
                                    font.family: pane.theme.ff; font.bold: true
                                    font.pixelSize: pane.theme.fs - 3
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: box.height > 36
                                    text: pane.modeW(box.model) + "×" + pane.modeH(box.model)
                                        + (pane.rotated(box.model) ? " ⟳" : "")
                                    color: pane.theme.outline
                                    font.family: pane.theme.ff
                                    font.pixelSize: pane.theme.fs - 5
                                }
                            }

                            // Primary badge (pinned at 0×0, not draggable).
                            Text {
                                visible: box.model.output === pane.primaryOutput
                                anchors { left: parent.left; top: parent.top; margins: 3 }
                                text: "★"
                                color: pane.theme.warn
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs - 3
                            }

                            DragHandler {
                                target: null
                                enabled: box.model.output !== pane.primaryOutput
                                onActiveChanged: {
                                    if (active) pane.selectedOutput = box.model.output
                                    else {
                                        pane.setEdit(box.index, "x", box.pendX)
                                        pane.setEdit(box.index, "y", box.pendY)
                                        box.dragDX = 0; box.dragDY = 0
                                    }
                                }
                                onTranslationChanged: {
                                    const rawX = box.model.x + translation.x / diagram.s
                                    const rawY = box.model.y + translation.y / diagram.s
                                    const res = pane.resolvePosition(box.index, rawX, rawY)
                                    box.pendX = res.x; box.pendY = res.y
                                    box.dragDX = (res.x - box.model.x) * diagram.s
                                    box.dragDY = (res.y - box.model.y) * diagram.s
                                }
                            }
                            TapHandler { onTapped: pane.selectedOutput = box.model.output }
                        }
                    }
                }
            }

            // ── Monitor selector ─────────────────────────────────────────
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: edits
                    delegate: MonBtn {
                        required property var model
                        label: model.output
                        selected: model.output === pane.selectedOutput
                        onClicked: pane.selectedOutput = model.output
                    }
                }
            }

            // ── Editor for the selected monitor ──────────────────────────
            Repeater {
                model: edits
                delegate: Rectangle {
                    id: card
                    required property var model
                    required property int index
                    readonly property bool isSel: model.output === pane.selectedOutput
                    readonly property var monModes: pane.modesFor(model.output)

                    visible: isSel
                    width: col.width
                    height: isSel ? cardCol.implicitHeight + 24 : 0
                    radius: 12
                    color: Qt.darker(pane.theme.bg, 1.2)
                    border.color: pane.theme.sep
                    border.width: 1

                    Column {
                        id: cardCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 14

                        // Name + description + enabled toggle
                        Row {
                            width: parent.width
                            spacing: 10
                            Column {
                                width: parent.width - enToggle.width - 10
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    text: card.model.output
                                    color: pane.theme.fg
                                    font.family: pane.theme.ff; font.bold: true
                                    font.pixelSize: pane.theme.fs + 2
                                }
                                Text {
                                    text: card.model.desc
                                    color: pane.theme.outline
                                    font.family: pane.theme.ff
                                    font.pixelSize: pane.theme.fs - 3
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }
                            Rectangle {
                                id: enToggle
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44; height: 24; radius: 12
                                color: card.model.disabled ? Qt.darker(pane.theme.bg, 1.4) : pane.theme.tertiary
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Rectangle {
                                    width: 18; height: 18; radius: 9; y: 3
                                    x: card.model.disabled ? 3 : parent.width - width - 3
                                    color: "white"
                                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pane.setEdit(card.index, "disabled", !card.model.disabled)
                                }
                            }
                        }

                        // Primary monitor — pins this screen to 0×0.
                        MonBtn {
                            visible: !card.model.disabled
                            label: card.model.output === pane.primaryOutput ? "★ Primary monitor" : "Set as primary monitor"
                            selected: card.model.output === pane.primaryOutput
                            onClicked: pane.setPrimary(card.model.output)
                        }

                        // Show the Quickshell bar on this monitor (applies live).
                        Row {
                            width: parent.width
                            visible: !card.model.disabled
                            spacing: 10
                            readonly property bool barOn: pane.shellRoot.barDisabledMonitors.indexOf(card.model.output) < 0
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - barToggle.width - 10
                                text: "Show bar on this monitor"
                                color: pane.theme.fg
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs
                            }
                            Rectangle {
                                id: barToggle
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44; height: 24; radius: 12
                                color: parent.barOn ? pane.theme.tertiary : Qt.darker(pane.theme.bg, 1.4)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Rectangle {
                                    width: 18; height: 18; radius: 9; y: 3
                                    x: parent.parent.barOn ? parent.width - width - 3 : 3
                                    color: "white"
                                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pane.shellRoot.setBarOnMonitor(card.model.output, !parent.parent.barOn)
                                }
                            }
                        }

                        // Resolution dropdown
                        Column {
                            width: parent.width
                            spacing: 6
                            visible: !card.model.disabled
                            Text { text: "Resolution"; color: pane.theme.txt2; font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2 }
                            Rectangle {
                                width: parent.width
                                height: 34
                                radius: 8
                                color: pane.theme.field
                                border.color: card.model.modesOpen ? pane.theme.primary : pane.theme.sep
                                border.width: 1
                                Text {
                                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: card.model.mode
                                    color: pane.theme.fg; font.family: pane.theme.ff; font.pixelSize: pane.theme.fs
                                }
                                Text {
                                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: card.model.modesOpen ? "▲" : "▼"
                                    color: pane.theme.outline; font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pane.setEdit(card.index, "modesOpen", !card.model.modesOpen)
                                }
                            }
                            Rectangle {
                                width: parent.width
                                visible: card.model.modesOpen
                                height: Math.min(170, modesCol.implicitHeight + 8)
                                radius: 8
                                color: Qt.darker(pane.theme.bg, 1.35)
                                border.color: pane.theme.sep
                                border.width: 1
                                clip: true
                                Flickable {
                                    anchors.fill: parent; anchors.margins: 4
                                    contentHeight: modesCol.height
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    Column {
                                        id: modesCol
                                        width: parent.width
                                        Text {
                                            visible: card.monModes.length === 0
                                            text: "  (no modes reported)"
                                            color: pane.theme.outline; font.family: pane.theme.ff
                                            font.pixelSize: pane.theme.fs - 1
                                            height: 26; verticalAlignment: Text.AlignVCenter
                                        }
                                        Repeater {
                                            model: card.monModes
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: modesCol.width
                                                height: 28; radius: 6
                                                color: modelData === card.model.mode
                                                       ? pane.theme.hi(1.3)
                                                       : (mHover.hovered ? pane.theme.surface : "transparent")
                                                HoverHandler { id: mHover }
                                                Text {
                                                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                                    text: modelData
                                                    color: pane.theme.fg; font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 1
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: { pane.setEdit(card.index, "mode", modelData); pane.setEdit(card.index, "modesOpen", false) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Scale stepper (0.25 increments, 0.5–3.0)
                        Column {
                            width: parent.width
                            spacing: 6
                            visible: !card.model.disabled
                            Text { text: "Scale"; color: pane.theme.txt2; font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2 }
                            Stepper {
                                text: (parseFloat(card.model.scale) || 1).toFixed(2).replace(/\.?0+$/, "") + "×"
                                onDec: {
                                    const s = Math.max(0.5, Math.round(((parseFloat(card.model.scale) || 1) - 0.25) * 100) / 100)
                                    pane.setEdit(card.index, "scale", String(s))
                                }
                                onInc: {
                                    const s = Math.min(3, Math.round(((parseFloat(card.model.scale) || 1) + 0.25) * 100) / 100)
                                    pane.setEdit(card.index, "scale", String(s))
                                }
                            }
                        }

                        // Rotation dropdown
                        Column {
                            width: parent.width
                            spacing: 6
                            visible: !card.model.disabled
                            readonly property var rotOpts: [
                                { t: 0, l: "Normal" }, { t: 1, l: "90°" }, { t: 2, l: "180°" }, { t: 3, l: "270°" }
                            ]
                            Text { text: "Rotation"; color: pane.theme.txt2; font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2 }
                            Rectangle {
                                width: parent.width
                                height: 34
                                radius: 8
                                color: pane.theme.field
                                border.color: card.model.rotOpen ? pane.theme.primary : pane.theme.sep
                                border.width: 1
                                Text {
                                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: pane.rotLabel(card.model.transform)
                                    color: pane.theme.fg; font.family: pane.theme.ff; font.pixelSize: pane.theme.fs
                                }
                                Text {
                                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: card.model.rotOpen ? "▲" : "▼"
                                    color: pane.theme.outline; font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pane.setEdit(card.index, "rotOpen", !card.model.rotOpen)
                                }
                            }
                            Rectangle {
                                width: parent.width
                                visible: card.model.rotOpen
                                height: rotCol.implicitHeight + 8
                                radius: 8
                                color: Qt.darker(pane.theme.bg, 1.35)
                                border.color: pane.theme.sep
                                border.width: 1
                                Column {
                                    id: rotCol
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
                                    Repeater {
                                        model: [ { t: 0, l: "Landscape (default)" },
                                                 { t: 2, l: "Landscape (reversed)" },
                                                 { t: 1, l: "Portrait" },
                                                 { t: 3, l: "Portrait (reversed)" } ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: rotCol.width
                                            height: 28; radius: 6
                                            color: (parseInt(card.model.transform) || 0) === modelData.t
                                                   ? pane.theme.hi(1.3)
                                                   : (rHover.hovered ? pane.theme.surface : "transparent")
                                            HoverHandler { id: rHover }
                                            Text {
                                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                                text: modelData.l
                                                color: pane.theme.fg; font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 1
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { pane.setEdit(card.index, "transform", modelData.t); pane.setEdit(card.index, "rotOpen", false) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: edits.count === 0
                text: "No monitors detected."
                color: pane.theme.outline; font.family: pane.theme.ff; font.pixelSize: pane.theme.fs
            }
            Text {
                width: parent.width
                text: "Applying writes ~/.config/hypr/modules/monitors.lua and reloads Hyprland."
                color: pane.theme.outline; font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
                wrapMode: Text.WordWrap; topPadding: 4
            }
        }
    }

    // ── Components ───────────────────────────────────────────────────────
    component MonBtn: Rectangle {
        property string label: ""
        property bool   accent: false
        property bool   selected: false
        signal clicked()
        width: lbl.implicitWidth + 26; height: 30
        radius: 8
        color: selected ? pane.theme.hi(1.5)
             : accent   ? (bHover.hovered ? pane.theme.hi(1.6) : pane.theme.hi(1.3))
             :            (bHover.hovered ? pane.theme.surface : Qt.darker(pane.theme.bg, 1.2))
        border.color: selected ? pane.theme.primary : pane.theme.sep
        border.width: selected ? 2 : 1
        HoverHandler { id: bHover }
        Text {
            id: lbl
            anchors.centerIn: parent
            text: parent.label
            color: pane.theme.fg
            font.family: pane.theme.ff
            font.bold: true
            font.pixelSize: pane.theme.fs - 1
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }

    // − [ value ] +  stepper
    component Stepper: Row {
        property string text: ""
        signal dec()
        signal inc()
        spacing: 10

        MonBtn { label: "−"; onClicked: parent.dec() }
        Rectangle {
            width: 110; height: 30; radius: 8
            color: pane.theme.field
            border.color: pane.theme.sep
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: parent.parent.text
                color: pane.theme.fg
                font.family: pane.theme.ff
                font.bold: true
                font.pixelSize: pane.theme.fs
            }
        }
        MonBtn { label: "+"; onClicked: parent.inc() }
    }
}
