import QtQuick
import qs.common.ui
import qs.modules.bar

// Monitor configuration: hyprctl scan, draggable arrangement diagram,
// per-monitor resolution / scale / rotation / enable editing. Writes
// ~/.config/hypr/modules/monitors.lua and reloads Hyprland.
Item {
    id: pane

    required property var theme

    ListModel { id: edits; dynamicRoles: true }
    property int    vizTick: 0
    property string selectedOutput: ""
    // The principal monitor is pinned to 0×0 (the layout origin).
    property string primaryOutput: ""

    function setEdit(i, role, val) { edits.setProperty(i, role, val); vizTick++ }

    // Re-base every monitor so `output` sits at 0×0 (arrangement kept).
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
        const m = (MonitorService.monitorList || []).find(x => x.name === output)
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
        for (const m of (MonitorService.monitorList || [])) {
            edits.append({
                output:    m.name,
                desc:      m.description,
                // Same "%.2f" refresh as hyprctl's mode list, so the current
                // mode matches its entry (60 → "60.00").
                mode:      m.width + "x" + m.height + "@" + m.refresh.toFixed(2),
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
        savedConfig = JSON.stringify(configs())
    }
    function configs() {
        const cfgs = []
        for (let i = 0; i < edits.count; i++) {
            const r = edits.get(i)
            cfgs.push({ output: r.output, mode: r.mode,
                        x: parseInt(r.x) || 0, y: parseInt(r.y) || 0,
                        scale: r.scale || "1", transform: parseInt(r.transform) || 0,
                        disabled: r.disabled })
        }
        return cfgs
    }
    function applyAll() { MonitorService.applyMonitors(configs()) }

    // Snapshot of the scanned config; Apply/Revert are greyed out until edits differ.
    property string savedConfig: "[]"
    readonly property bool dirty: { vizTick; return JSON.stringify(configs()) !== savedConfig }

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

    Component.onCompleted: MonitorService.refreshMonitors()
    Connections {
        target: MonitorService
        function onMonitorListChanged() { pane.rebuild() }
    }

    UiPage {
        anchors { top: parent.top; left: parent.left; right: parent.right
                  bottom: footer.top; bottomMargin: 12 }
        theme: pane.theme

        // ── Arrangement ───────────────────────────────────────────────────
        UiGroup {
            theme: pane.theme
            title: "Arrangement"
            description: edits.count > 1
                         ? "Drag displays to arrange them. The primary display (★) stays at the origin."
                         : (edits.count === 1 ? "1 display connected" : "No displays detected")
            actions: [
                UiButton { theme: pane.theme; icon: ""; onClicked: MonitorService.refreshMonitors() }
            ]

            Item {
                width: parent.width
                implicitHeight: 230

                Item {
                    id: diagram
                    anchors { fill: parent; margins: 22 }
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
                            radius: 8
                            color: model.disabled ? Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.04)
                                 : sel ? Qt.rgba(pane.theme.primary.r, pane.theme.primary.g, pane.theme.primary.b, 0.25)
                                 : Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.1)
                            border.color: sel ? pane.theme.primary : Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.25)
                            border.width: sel ? 2 : 1
                            z: sel ? 2 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: box.model.output
                                    color: box.sel ? pane.theme.primary : pane.theme.fg
                                    font.family: pane.theme.ff; font.bold: true
                                    font.pixelSize: pane.theme.fs - 2
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: box.height > 40
                                    text: pane.modeW(box.model) + "×" + pane.modeH(box.model)
                                        + (pane.rotated(box.model) ? " ⟳" : "")
                                    color: pane.theme.txt2
                                    font.family: pane.theme.ff
                                    font.pixelSize: pane.theme.fs - 4
                                }
                            }

                            // Primary badge (pinned at 0×0, not draggable).
                            Text {
                                visible: box.model.output === pane.primaryOutput
                                anchors { left: parent.left; top: parent.top; margins: 5 }
                                text: "★"
                                color: pane.theme.warn
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs - 2
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
        }

        // ── Display chips (only useful with several displays) ─────────────
        Flow {
            visible: edits.count > 1
            width: parent.width
            spacing: 8
            Repeater {
                model: edits
                delegate: UiButton {
                    required property var model
                    theme: pane.theme
                    kind: model.output === pane.selectedOutput ? "primary" : "secondary"
                    icon: ""
                    text: model.output
                    onClicked: pane.selectedOutput = model.output
                }
            }
        }

        // ── Editor for the selected display ───────────────────────────────
        Repeater {
            model: edits
            delegate: UiGroup {
                id: card
                required property var model
                required property int index
                readonly property bool isSel: model.output === pane.selectedOutput
                readonly property var monModes: pane.modesFor(model.output)
                readonly property bool isPrimary: model.output === pane.primaryOutput
                readonly property bool barOn: BarService.barDisabledMonitors.indexOf(model.output) < 0

                visible: isSel
                theme: pane.theme
                title: model.output
                description: model.desc

                UiRow {
                    theme: pane.theme
                    icon: ""
                    title: "Use this display"
                    subtitle: card.model.disabled ? "Disabled — turned off when you apply" : "Enabled"
                    UiSwitch {
                        theme: pane.theme
                        checked: !card.model.disabled
                        onToggled: value => pane.setEdit(card.index, "disabled", !value)
                    }
                }
                UiRow {
                    visible: !card.model.disabled
                    theme: pane.theme
                    icon: ""
                    iconColor: pane.theme.warn
                    title: "Primary display"
                    subtitle: card.isPrimary ? "This display is at the layout origin (0×0)"
                                             : "Pin this display to the layout origin"
                    UiButton {
                        visible: !card.isPrimary
                        theme: pane.theme
                        text: "Make primary"
                        onClicked: pane.setPrimary(card.model.output)
                    }
                    Text {
                        visible: card.isPrimary
                        text: "  Primary"
                        color: pane.theme.primary
                        font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs - 2
                    }
                }
                // Applies live (no Apply needed).
                UiRow {
                    visible: !card.model.disabled
                    theme: pane.theme
                    icon: ""
                    title: "Show the bar"
                    subtitle: "Applies immediately"
                    UiSwitch {
                        theme: pane.theme
                        checked: card.barOn
                        onToggled: value => BarService.setBarOnMonitor(card.model.output, value)
                    }
                }

                // Resolution (expands to the reported modes).
                UiRow {
                    visible: !card.model.disabled
                    theme: pane.theme
                    icon: ""
                    title: "Resolution"
                    subtitle: card.model.mode + " Hz"
                    clickable: true
                    onClicked: {
                        pane.setEdit(card.index, "modesOpen", !card.model.modesOpen)
                        pane.setEdit(card.index, "rotOpen", false)
                    }
                    Text {
                        text: ""
                        rotation: card.model.modesOpen ? 180 : 0
                        color: pane.theme.txt2
                        font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                        Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                }
                Item {
                    visible: !card.model.disabled && card.model.modesOpen
                    width: parent.width
                    implicitHeight: Math.min(220, modesCol.implicitHeight) + 10
                    Flickable {
                        anchors { fill: parent; leftMargin: 56; rightMargin: 12; bottomMargin: 10 }
                        contentHeight: modesCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: modesCol
                            width: parent.width
                            Text {
                                visible: card.monModes.length === 0
                                height: 34
                                verticalAlignment: Text.AlignVCenter
                                text: "No modes reported"
                                color: pane.theme.txt2
                                font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                            }
                            Repeater {
                                model: card.monModes
                                delegate: OptionRow {
                                    required property var modelData
                                    label: modelData + " Hz"
                                    selected: modelData === card.model.mode
                                    onPicked: {
                                        pane.setEdit(card.index, "mode", modelData)
                                        pane.setEdit(card.index, "modesOpen", false)
                                    }
                                }
                            }
                        }
                    }
                }

                // Scale stepper (0.25 increments, 0.5–3.0).
                UiRow {
                    visible: !card.model.disabled
                    theme: pane.theme
                    icon: ""
                    title: "Scale"
                    subtitle: "Hyprland output scale (not the shell size)"
                    UiButton {
                        theme: pane.theme
                        text: "−"
                        onClicked: {
                            const s = Math.max(0.5, Math.round(((parseFloat(card.model.scale) || 1) - 0.25) * 100) / 100)
                            pane.setEdit(card.index, "scale", String(s))
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 56
                        horizontalAlignment: Text.AlignHCenter
                        text: (parseFloat(card.model.scale) || 1).toFixed(2).replace(/\.?0+$/, "") + "×"
                        color: pane.theme.fg
                        font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs - 1
                    }
                    UiButton {
                        theme: pane.theme
                        text: "+"
                        onClicked: {
                            const s = Math.min(3, Math.round(((parseFloat(card.model.scale) || 1) + 0.25) * 100) / 100)
                            pane.setEdit(card.index, "scale", String(s))
                        }
                    }
                }

                // Orientation (expands to the four transforms).
                UiRow {
                    visible: !card.model.disabled
                    theme: pane.theme
                    icon: ""
                    title: "Orientation"
                    subtitle: pane.rotLabel(card.model.transform)
                    clickable: true
                    onClicked: {
                        pane.setEdit(card.index, "rotOpen", !card.model.rotOpen)
                        pane.setEdit(card.index, "modesOpen", false)
                    }
                    Text {
                        text: ""
                        rotation: card.model.rotOpen ? 180 : 0
                        color: pane.theme.txt2
                        font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                        Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                }
                Column {
                    visible: !card.model.disabled && card.model.rotOpen
                    x: 56
                    width: parent.width - 68
                    bottomPadding: 10
                    Repeater {
                        model: [ { t: 0, l: "Landscape (default)" },
                                 { t: 2, l: "Landscape (reversed)" },
                                 { t: 1, l: "Portrait" },
                                 { t: 3, l: "Portrait (reversed)" } ]
                        delegate: OptionRow {
                            required property var modelData
                            label: modelData.l
                            selected: (parseInt(card.model.transform) || 0) === modelData.t
                            onPicked: {
                                pane.setEdit(card.index, "transform", modelData.t)
                                pane.setEdit(card.index, "rotOpen", false)
                            }
                        }
                    }
                }
            }
        }

        Text {
            width: parent.width
            leftPadding: 4
            text: "Apply writes ~/.config/hypr/modules/monitors.lua and reloads Hyprland."
            color: pane.theme.txt2
            font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
            wrapMode: Text.WordWrap
        }
    }

    // Pinned below the scroll area so Apply/Revert stay reachable.
    Row {
        id: footer
        anchors { right: parent.right; rightMargin: 14; bottom: parent.bottom }
        spacing: 8
        UiButton { theme: pane.theme; enabled: pane.dirty; text: "Revert"; onClicked: pane.rebuild() }
        UiButton {
            theme: pane.theme
            enabled: pane.dirty
            kind: pane.dirty ? "primary" : "secondary"
            icon: ""
            text: "Apply"
            onClicked: pane.applyAll()
        }
    }

    // One choice in an expanded option list, check mark when selected.
    component OptionRow: Rectangle {
        id: opt
        property string label: ""
        property bool   selected: false
        signal picked()
        width: parent ? parent.width : 0
        height: 34
        radius: 8
        color: selected ? Qt.rgba(pane.theme.primary.r, pane.theme.primary.g, pane.theme.primary.b, 0.14)
             : (optHover.hovered ? Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.05) : "transparent")
        HoverHandler { id: optHover }
        Text {
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            text: opt.label
            color: pane.theme.fg
            font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
        }
        Text {
            visible: opt.selected
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: ""
            color: pane.theme.primary
            font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: opt.picked()
        }
    }
}
