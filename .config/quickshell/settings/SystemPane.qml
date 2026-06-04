import QtQuick

Item {
    id: pane

    required property var theme
    required property var shellRoot

    // Static details collected by shell.qml (scripts/system-info.sh).
    readonly property var info: pane.shellRoot.sysInfo || ({})

    function orDash(s) { return (s && ("" + s).length > 0) ? ("" + s) : "—" }

    function fmtKib(kib) {
        if (!kib || kib <= 0) return "—"
        const gib = kib / (1024 * 1024)
        return gib >= 1 ? gib.toFixed(1) + " GiB" : (kib / 1024).toFixed(0) + " MiB"
    }
    function fmtBytes(b) {
        if (!b || b <= 0) return "—"
        if (b < 1024 ** 3) return (b / 1024 ** 2).toFixed(1) + " MiB"
        if (b < 1024 ** 4) return (b / 1024 ** 3).toFixed(1) + " GiB"
        return (b / 1024 ** 4).toFixed(2) + " TiB"
    }

    // ── A single label / value line ──────────────────────────────────────
    component InfoRow: Row {
        required property string label
        required property string value
        width: parent ? parent.width : 0
        height: 30

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 160
            text: parent.label
            color: pane.theme.outline
            font.family: pane.theme.ff
            font.pixelSize: pane.theme.fs - 1
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 160
            text: parent.value
            color: pane.theme.fg
            font.family: pane.theme.ff
            font.bold: true
            font.pixelSize: pane.theme.fs - 1
            elide: Text.ElideRight
        }
    }

    // ── A titled card wrapping a stack of InfoRows ───────────────────────
    component InfoCard: Rectangle {
        id: card
        property string title: ""
        default property alias rows: rowCol.data

        width: parent ? parent.width : 0
        height: cardCol.implicitHeight + 28
        radius: 12
        color: Qt.darker(pane.theme.bg, 1.2)
        border.color: pane.theme.sep
        border.width: 1

        Column {
            id: cardCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 2

            Text {
                text: card.title
                color: pane.theme.fg
                font.family: pane.theme.ff
                font.bold: true
                font.pixelSize: pane.theme.fs + 1
                bottomPadding: 6
            }
            Column { id: rowCol; width: parent.width; spacing: 2 }
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: 16

            InfoCard {
                title: "Operating system"
                InfoRow { label: "OS";             value: pane.orDash(pane.info.os) }
                InfoRow { label: "Kernel";         value: pane.orDash(pane.info.kernel) }
                InfoRow { label: "Architecture";   value: pane.orDash(pane.info.arch) }
                InfoRow { label: "Hostname";       value: pane.orDash(pane.info.host) }
                InfoRow { label: "Window manager"; value: pane.orDash(pane.shellRoot.sysWM) }
                InfoRow { label: "Shell";          value: pane.orDash(pane.info.shell) }
                InfoRow { label: "Uptime";         value: pane.orDash(pane.shellRoot.sysUptime) }
            }

            InfoCard {
                title: "Hardware"
                InfoRow {
                    label: "Model"
                    value: pane.orDash([pane.info.vendor, pane.info.board].filter(Boolean).join(" "))
                }
                InfoRow { label: "CPU";    value: pane.orDash(pane.info.cpu) }
                InfoRow { label: "Cores";  value: pane.orDash(pane.info.cores) }
                InfoRow { label: "GPU";    value: pane.orDash(pane.info.gpu) }
                InfoRow {
                    label: "Dedicated GPU"
                    value: pane.orDash(pane.info.dgpu)
                    // Only shown on systems with a second (dedicated) GPU.
                    visible: pane.orDash(pane.info.dgpu) !== "—"
                }
                InfoRow { label: "Memory"; value: pane.fmtKib(pane.shellRoot.memTotalKib) }
                InfoRow {
                    label: "Disk (" + pane.shellRoot.diskMount + ")"
                    value: pane.fmtBytes(pane.shellRoot.diskTotalB - pane.shellRoot.diskUsedB)
                           + " free of " + pane.fmtBytes(pane.shellRoot.diskTotalB)
                }
            }
        }
    }
}
