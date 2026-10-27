import QtQuick
import QtQuick.Layouts
import qs.modules.system

// Performance tab (Windows-style): resource list with live sparklines on
// the left (CPU, Memory, Disks, Network adapters, GPUs); the selected one
// on the right with its 60 s graph(s), live stats and hardware details.
// ↑/↓ switch resource · Ctrl+Tab next tab.
FocusScope {
    id: view

    required property var theme

    property string selectedId: "cpu"
    property bool   logical:    false      // CPU: one graph per logical processor

    readonly property var hw: PerfService.hw
    readonly property var s:  PerfService.sample
    readonly property var res: PerfService.resources.find(r => r.id === selectedId)
                               || PerfService.resources[0] || null

    function colorFor(kind) {
        return kind === "mem"  ? theme.secondary
             : kind === "disk" ? theme.tertiary
             : kind === "net"  ? theme.warn
             : theme.primary
    }
    function move(step) {
        const list = PerfService.resources
        if (!list.length) return
        const i = Math.max(0, list.findIndex(r => r.id === (res ? res.id : "")))
        selectedId = list[Math.max(0, Math.min(list.length - 1, i + step))].id
    }

    // Sidebar summary lines for a resource.
    function lines(r) {
        const P = PerfService
        if (!s || !r) return ["", ""]
        if (r.kind === "cpu")
            return [P.fmtPct(s.cpu.usage) + "  " + P.fmtGHz(s.cpu.mhz),
                    SystemService.cpuTempC > 0 ? Math.round(SystemService.cpuTempC) + "°C" : ""]
        if (r.kind === "mem")
            return [(s.mem.used / 1024 ** 3).toFixed(1) + "/" + (s.mem.total / 1024 ** 3).toFixed(1)
                    + " GB (" + P.fmtPct(s.mem.used / s.mem.total) + ")", ""]
        if (r.kind === "disk") {
            const d = s.disks[r.key]
            return [r.disk.ssd ? "SSD" : "HDD", d ? P.fmtPct(d.active) : ""]
        }
        if (r.kind === "net") {
            const n = s.net[r.key]
            const ssid = n && n.wifi && P.wifi ? P.wifi.ssid : r.key
            return [ssid, n ? "S: " + P.fmtBits(n.tx) + "  R: " + P.fmtBits(n.rx) : ""]
        }
        if (r.kind === "gpu") {
            const g = s.gpus[r.key]
            if (!g) return [r.gpu.name, ""]
            if (g.suspended || g.idle) return [r.gpu.name, P.gpuState(g)]
            return [r.gpu.name, P.fmtPct(g.util) + (g.temp !== null ? " (" + P.fmtTemp(g.temp) + ")" : "")]
        }
        return ["", ""]
    }

    Keys.onPressed: e => {
        const ctrl = e.modifiers & Qt.ControlModifier
        if (ctrl && (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab)) {
            TaskManagerService.nextTab(e.key === Qt.Key_Backtab ? -1 : 1); e.accepted = true
        }
        else if (e.key === Qt.Key_Down) { view.move(1);  e.accepted = true }
        else if (e.key === Qt.Key_Up) { view.move(-1); e.accepted = true }
        else if (e.key === Qt.Key_Escape) { TaskManagerService.close(); e.accepted = true }
    }

    // ── Shared pieces ──────────────────────────────────────────────────
    component Caption: Text {
        color: view.theme.txt2
        font.family: view.theme.ff
        font.pixelSize: view.theme.fs - 3
    }

    // Graph with Windows' captions: title / scale on top, time span below.
    component GraphBox: ColumnLayout {
        id: gb
        property string caption: ""
        property string topRight: ""
        property var    topFormat: null      // scaleMax → label (auto-scaled graphs)
        property bool   footer: true
        property var    values: []
        property var    values2: []
        property color  color: view.theme.primary
        property real   maxValue: 1
        property real   minScale: 1
        spacing: 4
        RowLayout {
            Layout.fillWidth: true
            Caption { Layout.fillWidth: true; text: gb.caption; elide: Text.ElideRight }
            Caption { text: gb.topFormat ? gb.topFormat(pg.scaleMax) : gb.topRight }
        }
        PerfGraph {
            id: pg
            Layout.fillWidth: true
            Layout.fillHeight: true
            theme: view.theme
            values: gb.values
            values2: gb.values2
            color: gb.color
            maxValue: gb.maxValue
            minScale: gb.minScale
            capacity: PerfService.capacity
        }
        RowLayout {
            visible: gb.footer
            Layout.fillWidth: true
            Caption { Layout.fillWidth: true; text: PerfService.capacity + " seconds" }
            Caption { text: "0" }
        }
    }

    // Big live value with its label (optional solid/dashed legend swatch).
    component Stat: Column {
        id: st
        width: implicitWidth + 10
        property string label: ""
        property string value: ""
        property string legend: ""           // "" | "solid" | "dashed"
        property color  legendColor: view.theme.primary
        spacing: 2
        Row {
            spacing: 6
            Row {
                visible: st.legend !== ""
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater {
                    model: st.legend === "dashed" ? 3 : 1
                    Rectangle { width: st.legend === "dashed" ? 4 : 16; height: 2; color: st.legendColor }
                }
            }
            Caption { text: st.label }
        }
        Text {
            text: st.value
            color: view.theme.fg
            font.family: view.theme.ff
            font.pixelSize: view.theme.fs + 5
        }
    }

    // Static key / value details.
    component InfoTable: Column {
        id: it
        property var rows: []                // [[key, value], …]
        spacing: 5
        Repeater {
            model: it.rows
            Row {
                required property var modelData
                spacing: 14
                Caption { width: 130; text: modelData[0] }
                Text {
                    width: it.width - 144
                    text: modelData[1]
                    color: view.theme.fg
                    font.family: view.theme.ff
                    font.pixelSize: view.theme.fs - 3
                    elide: Text.ElideRight
                }
            }
        }
    }

    component Chip: Rectangle {
        id: chip
        property string text: ""
        property bool   active: false
        signal clicked()
        implicitWidth: chipText.implicitWidth + 18
        implicitHeight: 22
        radius: 11
        color: active ? Qt.rgba(view.theme.primary.r, view.theme.primary.g, view.theme.primary.b, 0.2)
             : chipHover.hovered ? Qt.rgba(view.theme.fg.r, view.theme.fg.g, view.theme.fg.b, 0.06)
             : "transparent"
        border.color: active ? view.theme.primary : view.theme.sep
        border.width: 1
        HoverHandler { id: chipHover }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.text
            color: chip.active ? view.theme.primary : view.theme.txt2
            font.family: view.theme.ff
            font.pixelSize: view.theme.fs - 4
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    // Title + device name, graph area, then live stats beside details.
    component Detail: ColumnLayout {
        id: det
        property string title: ""
        property string subtitle: ""
        property var    info: []
        default property alias graphArea: graphSlot.data
        property alias stats: statsFlow.data
        spacing: 14

        Item {
            Layout.fillWidth: true
            implicitHeight: titleText.implicitHeight
            Text {
                id: titleText
                text: det.title
                color: view.theme.fg
                font.family: view.theme.ff; font.bold: true
                font.pixelSize: view.theme.fs + 12
            }
            Text {
                anchors { right: parent.right; baseline: titleText.baseline }
                width: Math.min(implicitWidth, parent.width - titleText.width - 24)
                horizontalAlignment: Text.AlignRight
                text: det.subtitle
                color: view.theme.txt2
                font.family: view.theme.ff
                font.pixelSize: view.theme.fs + 1
                elide: Text.ElideRight
            }
        }
        Item {
            id: graphSlot
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 24
            Flow {
                id: statsFlow
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 14
            }
            InfoTable {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 320
                rows: det.info
            }
        }
    }

    // ── Sidebar ────────────────────────────────────────────────────────
    Rectangle {
        id: side
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: 270
        color: view.theme.inset

        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 1
            color: view.theme.sep
        }

        Flickable {
            anchors { fill: parent; topMargin: 8; bottomMargin: 8 }
            contentHeight: sideCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: sideCol
                width: parent.width
                spacing: 2

                Repeater {
                    model: PerfService.resources
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        readonly property bool current: view.res && view.res.id === modelData.id
                        readonly property color accent: view.colorFor(modelData.kind)
                        readonly property var   l: view.lines(modelData)
                        x: 8
                        width: side.width - 17
                        height: 70
                        radius: 10
                        color: current ? Qt.rgba(view.theme.fg.r, view.theme.fg.g, view.theme.fg.b, 0.08)
                             : cardHover.hovered ? Qt.rgba(view.theme.fg.r, view.theme.fg.g, view.theme.fg.b, 0.04)
                             : "transparent"
                        HoverHandler { id: cardHover }

                        Rectangle {
                            visible: card.current
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: 3; height: 22; radius: 2
                            color: view.theme.primary
                        }

                        PerfGraph {
                            id: spark
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            width: 70; height: 46
                            theme: view.theme
                            grid: false
                            lineWidth: 1
                            color: card.accent
                            capacity: PerfService.capacity
                            readonly property string k: card.modelData.kind
                            values: k === "cpu"  ? PerfService.series("cpu")
                                  : k === "mem"  ? PerfService.series("mem")
                                  : k === "disk" ? PerfService.series("disk:" + card.modelData.key + ":active")
                                  : k === "net"  ? PerfService.series("net:" + card.modelData.key + ":rx")
                                  : PerfService.series("gpu:" + card.modelData.key + ":util")
                            values2: k === "net" ? PerfService.series("net:" + card.modelData.key + ":tx") : []
                            maxValue: k === "mem" ? (view.s ? view.s.mem.total : 1)
                                    : k === "net" ? 0 : 1
                            minScale: 12500
                        }

                        Column {
                            anchors { left: spark.right; leftMargin: 12; right: parent.right; rightMargin: 8
                                      verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Text {
                                width: parent.width
                                text: card.modelData.title
                                color: view.theme.fg
                                font.family: view.theme.ff; font.bold: true
                                font.pixelSize: view.theme.fs
                                elide: Text.ElideRight
                            }
                            Caption { width: parent.width; text: card.l[0]; elide: Text.ElideRight; visible: text !== "" }
                            Caption { width: parent.width; text: card.l[1]; elide: Text.ElideRight; visible: text !== "" }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { view.selectedId = card.modelData.id; view.forceActiveFocus() }
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: detailArea
        visible: !view.res
        text: "Collecting performance data…"
        color: view.theme.outline
        font.family: view.theme.ff; font.pixelSize: view.theme.fs
    }

    // ── Detail ─────────────────────────────────────────────────────────
    Loader {
        id: detailArea
        anchors {
            left: side.right;    leftMargin: 26
            right: parent.right; rightMargin: 24
            top: parent.top;     topMargin: 14
            bottom: parent.bottom; bottomMargin: 18
        }
        active: !!view.res && !!view.s
        sourceComponent: !view.res ? null
                       : view.res.kind === "cpu"  ? cpuDetail
                       : view.res.kind === "mem"  ? memDetail
                       : view.res.kind === "disk" ? diskDetail
                       : view.res.kind === "net"  ? netDetail
                       : gpuDetail
    }

    // CPU ───────────────────────────────────────────────────────────────
    Component {
        id: cpuDetail
        Detail {
            readonly property var c: view.hw.cpu
            readonly property var cpu: view.s.cpu
            readonly property color accent: view.colorFor("cpu")
            title: "CPU"
            subtitle: c.model
            info: [
                ["Base speed",         c.base_mhz ? PerfService.fmtGHz(c.base_mhz) : "—"],
                ["Max speed",          c.max_mhz ? PerfService.fmtGHz(c.max_mhz) : "—"],
                ["Sockets",            String(c.sockets)],
                ["Cores",              String(c.cores)],
                ["Logical processors", String(c.logical)],
                ["Virtualization",     c.virt],
                ["L1 cache",           PerfService.fmtBytes(c.l1)],
                ["L2 cache",           PerfService.fmtBytes(c.l2)],
                ["L3 cache",           PerfService.fmtBytes(c.l3)]
            ]

            ColumnLayout {
                anchors.fill: parent
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Caption {
                        Layout.fillWidth: true
                        text: view.logical ? "% Utilization per logical processor" : "% Utilization over 60 seconds"
                    }
                    Chip { text: "Overall";            active: !view.logical; onClicked: view.logical = false }
                    Chip { text: "Logical processors"; active: view.logical;  onClicked: view.logical = true }
                    Item { width: 8; height: 1 }
                    Caption { text: "100%" }
                }
                PerfGraph {
                    visible: !view.logical
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    theme: view.theme
                    color: accent
                    values: PerfService.series("cpu")
                    capacity: PerfService.capacity
                }
                GridLayout {
                    visible: view.logical
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: Math.ceil(Math.sqrt(cpu.cores.length))
                    rowSpacing: 4
                    columnSpacing: 4
                    Repeater {
                        model: cpu.cores.length
                        PerfGraph {
                            required property int index
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 1     // equal cells
                            Layout.preferredHeight: 1
                            theme: view.theme
                            color: accent
                            grid: false
                            lineWidth: 1
                            values: PerfService.series("core:" + index)
                            capacity: PerfService.capacity
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Caption { Layout.fillWidth: true; text: PerfService.capacity + " seconds" }
                    Caption { text: "0" }
                }
            }

            stats: [
                Stat { label: "Utilization"; value: PerfService.fmtPct(cpu.usage) },
                Stat { label: "Speed";       value: PerfService.fmtGHz(cpu.mhz) },
                Stat { label: "Processes";   value: String(cpu.procs) },
                Stat { label: "Threads";     value: String(cpu.threads) },
                Stat { label: "Up time";     value: PerfService.fmtUptime(cpu.uptime) },
                Stat { label: "Temperature"; visible: SystemService.cpuTempC > 0
                       value: Math.round(SystemService.cpuTempC) + "°C" }
            ]
        }
    }

    // Memory ────────────────────────────────────────────────────────────
    Component {
        id: memDetail
        Detail {
            readonly property var m: view.s.mem
            readonly property color accent: view.colorFor("mem")
            readonly property real cachedB: Math.max(0, m.avail - m.free)
            title: "Memory"
            subtitle: PerfService.fmtBytes(m.total)
            info: [
                ["Total",           PerfService.fmtBytes(m.total)],
                ["Free",            PerfService.fmtBytes(m.free)],
                ["Dirty/writeback", PerfService.fmtBytes(m.dirty)],
                ["Swap size",       m.swap_total ? PerfService.fmtBytes(m.swap_total) : "No swap"]
            ]

            ColumnLayout {
                anchors.fill: parent
                spacing: 10
                GraphBox {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    caption: "Memory usage"
                    topRight: PerfService.fmtBytes(m.total)
                    color: accent
                    maxValue: m.total
                    values: PerfService.series("mem")
                }
                Caption { text: "Memory composition" }
                // In use | Cached (reclaimable) | Free.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    color: "transparent"
                    border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.6)
                    border.width: 1
                    Row {
                        anchors { fill: parent; margins: 1 }
                        Rectangle {
                            width: parent.width * m.used / m.total; height: parent.height
                            color: Qt.rgba(accent.r, accent.g, accent.b, 0.45)
                        }
                        Rectangle { width: 1; height: parent.height; color: Qt.rgba(accent.r, accent.g, accent.b, 0.6) }
                        Rectangle {
                            width: parent.width * cachedB / m.total; height: parent.height
                            color: Qt.rgba(accent.r, accent.g, accent.b, 0.18)
                        }
                    }
                }
            }

            stats: [
                Stat { label: "In use";    value: PerfService.fmtBytes(m.used) },
                Stat { label: "Available"; value: PerfService.fmtBytes(m.avail) },
                Stat { label: "Cached";    value: PerfService.fmtBytes(m.cached) },
                Stat { label: "Committed"; value: PerfService.fmtBytes(m.committed) },
                Stat { label: "Swap used"; visible: m.swap_total > 0
                       value: PerfService.fmtBytes(m.swap_used) + " / " + PerfService.fmtBytes(m.swap_total) }
            ]
        }
    }

    // Disk ──────────────────────────────────────────────────────────────
    Component {
        id: diskDetail
        Detail {
            readonly property var r: view.res
            readonly property var d: view.s.disks[r.key] || ({ active: 0, read: 0, write: 0, resp: 0, mounts: [] })
            readonly property color accent: view.colorFor("disk")
            title: r.title
            subtitle: r.disk.model
            info: [
                ["Capacity", PerfService.fmtBytes(r.disk.size)],
                ["Type",     r.disk.ssd ? "SSD" : "HDD"],
                ["Device",   "/dev/" + r.key],
                ["Mounted",  d.mounts.length ? d.mounts.join(", ") : "Not mounted"],
                ["Removable", r.disk.removable ? "Yes" : "No"]
            ]

            ColumnLayout {
                anchors.fill: parent
                spacing: 12
                GraphBox {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.verticalStretchFactor: 2
                    caption: "Active time"
                    topRight: "100%"
                    color: accent
                    values: PerfService.series("disk:" + r.key + ":active")
                }
                GraphBox {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.verticalStretchFactor: 1
                    caption: "Disk transfer rate"
                    topFormat: v => PerfService.fmtRate(v)
                    color: accent
                    maxValue: 0
                    minScale: 102400
                    values: PerfService.series("disk:" + r.key + ":read")
                    values2: PerfService.series("disk:" + r.key + ":write")
                }
            }

            stats: [
                Stat { label: "Active time";           value: PerfService.fmtPct(d.active) },
                Stat { label: "Average response time"; value: d.resp.toFixed(1) + " ms" },
                Stat { label: "Read speed";  value: PerfService.fmtRate(d.read);  legend: "solid";  legendColor: accent },
                Stat { label: "Write speed"; value: PerfService.fmtRate(d.write); legend: "dashed"; legendColor: accent }
            ]
        }
    }

    // Network ───────────────────────────────────────────────────────────
    Component {
        id: netDetail
        Detail {
            readonly property var r: view.res
            readonly property var n: view.s.net[r.key] || ({ rx: 0, tx: 0, wifi: false, ipv4: "", ipv6: "" })
            readonly property var w: n.wifi ? PerfService.wifi : null
            readonly property color accent: view.colorFor("net")
            title: r.title
            subtitle: w ? w.ssid : r.key
            info: [
                ["Adapter name",    r.key],
                ["Connection type", n.wifi ? "802.11 (Wi-Fi)" : "Ethernet"]
            ].concat(w ? [["SSID", w.ssid], ["Signal strength", w.strength + "%"]] : [])
             .concat([["IPv4 address", n.ipv4 || "—"], ["IPv6 address", n.ipv6 || "—"]])

            GraphBox {
                anchors.fill: parent
                caption: "Throughput"
                topFormat: v => PerfService.fmtBits(v)
                color: accent
                maxValue: 0
                minScale: 12500
                values: PerfService.series("net:" + r.key + ":rx")
                values2: PerfService.series("net:" + r.key + ":tx")
            }

            stats: [
                Stat { label: "Send";    value: PerfService.fmtBits(n.tx); legend: "dashed"; legendColor: accent },
                Stat { label: "Receive"; value: PerfService.fmtBits(n.rx); legend: "solid";  legendColor: accent }
            ]
        }
    }

    // GPU ───────────────────────────────────────────────────────────────
    Component {
        id: gpuDetail
        Detail {
            readonly property var r: view.res
            readonly property var g: view.s.gpus[r.key]
                || ({ util: 0, engines: {}, mhz: 0, max_mhz: 0, suspended: false, idle: false,
                      mem_local: 0, mem_local_total: 0, mem_system: 0, temp: null, power: null })
            readonly property color accent: view.colorFor("gpu")
            readonly property var engines: {
                const known = PerfService.engineOrder.filter(e => g.engines[e] !== undefined)
                return known.concat(Object.keys(g.engines).filter(e => known.indexOf(e) < 0).sort())
            }
            readonly property real memTotal: g.mem_local_total || r.gpu.mem_total || 0
            readonly property int  maxMhz: g.max_mhz || r.gpu.max_mhz || 0
            readonly property bool off: g.suspended || g.idle
            title: r.title
            subtitle: r.gpu.name
            info: [
                ["Driver",        r.gpu.driver],
                ["Type",          r.gpu.integrated ? "Integrated" : "Dedicated"],
                ["PCI slot",      r.key],
                ["Max frequency", maxMhz ? maxMhz + " MHz" : "—"]
            ].concat(memTotal > 0 ? [["Dedicated memory", PerfService.fmtBytes(memTotal)]] : [])

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                // One graph per engine (or overall utilization if the driver
                // reports none).
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.verticalStretchFactor: 3
                    GridLayout {
                        anchors.fill: parent
                        visible: engines.length > 0
                        columns: engines.length > 4 ? 3 : 2
                        rowSpacing: 10
                        columnSpacing: 12
                        Repeater {
                            model: engines
                            GraphBox {
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: 1     // equal cells
                                Layout.preferredHeight: 1
                                caption: PerfService.engineNames[modelData] || modelData
                                topRight: PerfService.fmtPct(g.engines[modelData] || 0)
                                footer: false
                                color: accent
                                values: PerfService.series("gpu:" + r.key + ":eng:" + modelData)
                            }
                        }
                    }
                    GraphBox {
                        anchors.fill: parent
                        visible: engines.length === 0
                        caption: "Utilization"
                        topRight: "100%"
                        color: accent
                        values: PerfService.series("gpu:" + r.key + ":util")
                    }
                }

                // Dedicated memory (AMD / NVIDIA report its size).
                GraphBox {
                    visible: memTotal > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.verticalStretchFactor: 1
                    caption: "Dedicated GPU memory usage"
                    topRight: PerfService.fmtBytes(memTotal)
                    footer: false
                    color: accent
                    maxValue: memTotal
                    values: PerfService.series("gpu:" + r.key + ":mem")
                }
            }

            stats: [
                Stat { label: "Utilization"; value: off ? "—" : PerfService.fmtPct(g.util) },
                Stat { label: "Frequency";   value: off || !g.mhz ? "—" : g.mhz + " MHz" },
                Stat { label: "Temperature"; visible: g.temp !== null && g.temp !== undefined
                       value: PerfService.fmtTemp(g.temp || 0) },
                Stat { label: "Power";       visible: g.power !== null && g.power !== undefined
                       value: (g.power || 0).toFixed(1) + " W" },
                Stat { label: "Dedicated GPU memory"; visible: !r.gpu.integrated
                       value: PerfService.fmtBytes(g.mem_local)
                              + (memTotal > 0 ? " / " + PerfService.fmtBytes(memTotal) : "") },
                Stat { label: "Shared GPU memory"; value: PerfService.fmtBytes(g.mem_system) },
                Stat { label: "State"; value: PerfService.gpuState(g) }
            ]
        }
    }
}
