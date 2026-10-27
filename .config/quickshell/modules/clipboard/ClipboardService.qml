pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Clipboard history (cliphist). Entries {id, preview} from `cliphist list`;
// copying restores the original bytes via `cliphist decode <id> | wl-copy`.
Singleton {
    id: root

    property bool clipboardOpen:    false
    property var  clipboardList:    []
    property var  _clipboardBuffer: []

    function openClipboard() {
        FocusService.captureThenOpen(() => { root.clipboardOpen = true; root.refreshClipboard() })
    }
    function closeClipboard() { clipboardOpen = false }
    onClipboardOpenChanged: if (!clipboardOpen) FocusService.refocusLastWindow()

    function refreshClipboard() {
        clipboardListProc.running = false
        clipboardListProc.running = true
    }
    function copyClipboardEntry(id) {
        copyClipboardProc.target = id
        copyClipboardProc.running = false
        copyClipboardProc.running = true
    }
    function deleteClipboardEntry(id) {
        deleteClipboardProc.target = id
        deleteClipboardProc.running = false
        deleteClipboardProc.running = true
    }

    // External control: `qs ipc call clipboard toggle|open|close`
    IpcHandler {
        target: "clipboard"
        function toggle() {
            if (root.clipboardOpen) root.clipboardOpen = false
            else                    root.openClipboard()
        }
        function open()   { root.openClipboard()  }
        function close()  { root.closeClipboard() }
    }

    Process {
        id: clipboardListProc
        command: ["cliphist", "list"]
        onRunningChanged: if (running) root._clipboardBuffer = []
        stdout: SplitParser {
            onRead: line => {
                const t = line.indexOf("\t")
                if (t <= 0) return
                root._clipboardBuffer.push({
                    id:      line.substring(0, t),
                    preview: line.substring(t + 1)
                })
            }
        }
        onExited: root.clipboardList = root._clipboardBuffer.slice()
    }
    Process {
        id: copyClipboardProc
        property string target: ""
        environment: ({ ID: target })
        command: ["sh", "-c", "cliphist decode \"$ID\" | wl-copy"]
    }
    Process {
        id: deleteClipboardProc
        property string target: ""
        environment: ({ ID: target })
        // cliphist delete takes "id<TAB>preview" on stdin; pipe only the
        // matching line.
        command: ["sh", "-c",
                  "cliphist list | awk -v id=\"$ID\" 'index($0,id\"\\t\")==1' | cliphist delete"]
        onExited: root.refreshClipboard()
    }
}
