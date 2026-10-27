pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Keybinds cheat-sheet: parse-keybinds.py over Hyprland's keybinds.lua →
// keybindsList ({section, keys, desc}).
Singleton {
    id: root

    property bool keybindsOpen:    false
    property var  keybindsList:    []
    property var  _keybindsBuffer: []

    function openKeybinds()  { keybindsOpen = true; refreshKeybinds() }
    function closeKeybinds() { keybindsOpen = false }
    function refreshKeybinds() {
        keybindsProc.running = false
        keybindsProc.running = true
    }

    IpcHandler {
        target: "keybinds"
        function toggle() { root.keybindsOpen = !root.keybindsOpen
                            if (root.keybindsOpen) root.refreshKeybinds() }
        function open()   { root.openKeybinds()  }
        function close()  { root.closeKeybinds() }
    }

    Process {
        id: keybindsProc
        command: ["python3",
                  Paths.local(Qt.resolvedUrl("parse-keybinds.py"))]
        onRunningChanged: if (running) root._keybindsBuffer = []
        stdout: SplitParser {
            onRead: line => {
                const p = line.split("\t")
                if (p.length >= 3)
                    root._keybindsBuffer.push({ section: p[0], keys: p[1], desc: p[2] })
            }
        }
        onExited: root.keybindsList = root._keybindsBuffer.slice()
    }
}
