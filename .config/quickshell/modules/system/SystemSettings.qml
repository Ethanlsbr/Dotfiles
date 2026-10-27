import QtQuick
import qs.common.ui

// Settings pane: device + OS details (Windows "About"-style spec sheet).
Item {
    id: pane

    required property var theme

    // Static details from system-info.sh.
    readonly property var info: SystemService.sysInfo || ({})

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

    UiPage {
        anchors.fill: parent
        theme: pane.theme

        // ── Device ────────────────────────────────────────────────────────
        UiCard {
            theme: pane.theme
            height: 112

            Rectangle {
                id: devTile
                anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                width: 60; height: 60; radius: 16
                color: Qt.rgba(pane.theme.primary.r, pane.theme.primary.g, pane.theme.primary.b, 0.15)
                Text {
                    anchors.centerIn: parent
                    text: ""
                    color: pane.theme.primary
                    font.family: pane.theme.ff; font.pixelSize: pane.theme.fs + 14
                }
            }
            Column {
                anchors { left: devTile.right; leftMargin: 20; right: parent.right; rightMargin: 22
                          verticalCenter: parent.verticalCenter }
                spacing: 4
                Text {
                    width: parent.width
                    text: pane.orDash(pane.info.host)
                    color: pane.theme.fg
                    font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs + 6
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: [pane.info.vendor, pane.info.board].filter(Boolean).join(" ") || "—"
                    color: pane.theme.txt2
                    font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 1
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: pane.orDash(pane.info.os) + "  ·  up " + (SystemService.sysUptime || "").replace(/^up\s+/, "")
                    color: pane.theme.primary
                    font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                    elide: Text.ElideRight
                }
            }
        }

        // ── Device specifications ─────────────────────────────────────────
        UiGroup {
            theme: pane.theme
            title: "Device specifications"

            UiInfoRow { theme: pane.theme; label: "Processor"; value: pane.orDash(pane.info.cpu) }
            UiInfoRow { theme: pane.theme; label: "Cores";     value: pane.orDash(pane.info.cores) }
            UiInfoRow { theme: pane.theme; label: "Graphics";  value: pane.orDash(pane.info.gpu) }
            UiInfoRow {
                theme: pane.theme
                label: "Dedicated graphics"
                value: pane.orDash(pane.info.dgpu)
                // Only on systems with a second (dedicated) GPU.
                visible: pane.orDash(pane.info.dgpu) !== "—"
            }
            UiInfoRow { theme: pane.theme; label: "Memory"; value: pane.fmtKib(SystemService.memTotalKib) }
            UiInfoRow {
                theme: pane.theme
                label: "Storage (" + SystemService.diskMount + ")"
                value: pane.fmtBytes(SystemService.diskTotalB - SystemService.diskUsedB)
                       + " free of " + pane.fmtBytes(SystemService.diskTotalB)
            }
        }

        // ── Operating system ──────────────────────────────────────────────
        UiGroup {
            theme: pane.theme
            title: "Operating system"

            UiInfoRow { theme: pane.theme; label: "Distribution";   value: pane.orDash(pane.info.os) }
            UiInfoRow { theme: pane.theme; label: "Kernel";         value: pane.orDash(pane.info.kernel) }
            UiInfoRow { theme: pane.theme; label: "Architecture";   value: pane.orDash(pane.info.arch) }
            UiInfoRow { theme: pane.theme; label: "Window manager"; value: pane.orDash(SystemService.sysWM) }
            UiInfoRow { theme: pane.theme; label: "Shell";          value: pane.orDash(pane.info.shell) }
            UiInfoRow {
                theme: pane.theme
                label: "Uptime"
                value: pane.orDash((SystemService.sysUptime || "").replace(/^up\s+/, ""))
            }
        }
    }
}
