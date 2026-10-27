import QtQuick
import Quickshell
import Quickshell.Io

// One persisted setting in state/<name>. Read once on creation (`loaded`
// gets the file's lines, [] if missing); save(text) overwrites it.
Scope {
    id: file

    required property string name
    readonly property string path: Paths.state(name)

    signal loaded(var lines)

    function save(text) {
        saveProc.data = text
        saveProc.running = false
        saveProc.running = true
    }

    Process {
        id: loadProc
        running: true
        command: ["sh", "-c", "cat \"$FILE\" 2>/dev/null || true"]
        environment: ({ FILE: file.path })
        property var _buf: []
        onRunningChanged: if (running) _buf = []
        stdout: SplitParser { onRead: line => loadProc._buf.push(line) }
        onExited: file.loaded(loadProc._buf.slice())
    }
    Process {
        id: saveProc
        property string data: ""
        environment: ({ DATA: data, FILE: file.path })
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$FILE\")\" && printf '%s' \"$DATA\" > \"$FILE\""]
    }
}
