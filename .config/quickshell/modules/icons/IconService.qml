pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// System icon theme (mirrors GNOME's icon-theme gsetting). Qt icon lookup
// is stuck on hicolor under wayland — resolve name → path from the GTK
// theme (+ Inherits) via icon-resolver.py and watch gsettings.
Singleton {
    id: root

    property string systemIconTheme: "hicolor"
    property var    iconMap:         ({})
    property var    _iconMapBuffer:  ({})

    function iconFor(name) {
        if (!name) return ""
        if (name.startsWith("/")) {
            // .desktop icon paths may point at removed themes; prefer the
            // active theme by basename, else use the literal path.
            const base = name.split("/").pop().replace(/\.[^.]+$/, "")
            const p = iconMap[base]
            if (p) return "file://" + p
            return "file://" + name
        }
        const p = iconMap[name]
        return p ? "file://" + p : ""
    }
    function rescanIcons() {
        iconScanProc.running = false
        iconScanProc.running = true
    }

    // Glyph fallback for names without a usable themed image (e.g. battery
    // icons are dark symbolic only). Used by toasts + control center.
    function glyphForIcon(name) {
        const n = (name || "").toLowerCase()
        if (n.indexOf("battery") !== -1)
            return n.indexOf("charg") !== -1 ? String.fromCodePoint(0xf0084)   // charging
                                             : String.fromCodePoint(0xf0079)   // battery
        return ""
    }

    // Initial read + scan + live monitor.
    Process {
        id: iconThemeQueryProc
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"]
        stdout: SplitParser {
            onRead: line => {
                // gsettings returns quoted: 'Tela'
                const m = line.match(/'([^']+)'/) || line.match(/"([^"]+)"/)
                const t = (m ? m[1] : line.trim()) || "hicolor"
                if (t !== root.systemIconTheme) root.systemIconTheme = t
            }
        }
        onExited: root.rescanIcons()
    }

    Process {
        id: iconScanProc
        command: ["python3", Paths.local(Qt.resolvedUrl("icon-resolver.py")), root.systemIconTheme]
        onRunningChanged: if (running) root._iconMapBuffer = {}
        stdout: SplitParser {
            onRead: line => {
                const i = line.indexOf("\t")
                if (i > 0) root._iconMapBuffer[line.substring(0, i)]
                         = line.substring(i + 1)
            }
        }
        onExited: root.iconMap = root._iconMapBuffer
    }

    // setpriv: ends with the shell even if it crashes (no orphan).
    Process {
        id: iconThemeMonitorProc
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "--",
                  "gsettings", "monitor", "org.gnome.desktop.interface", "icon-theme"]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/'([^']+)'/)
                if (m && m[1] !== root.systemIconTheme) {
                    root.systemIconTheme = m[1]
                    root.rescanIcons()
                }
            }
        }
        onExited: iconThemeMonitorRestartTimer.start()
    }
    Timer {
        id: iconThemeMonitorRestartTimer
        interval: 3000; repeat: false
        onTriggered: iconThemeMonitorProc.running = true
    }
}
