pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Applications settings pane: default apps per file/link type (xdg-mime)
// and installed desktop apps with their pacman package (apps.py).
// Uninstalling runs `yay -Rncs` in a kitty window so the removal list,
// sudo password and confirmation stay with yay; a singleton so a pane
// switch doesn't kill that terminal.
Singleton {
    id: root

    // [{ key, label, current, candidates: [desktop id] }]
    property var defaults: []
    // [{ mime, ext, desc, category, current, candidates: [desktop id] }]
    property var types: []
    // [{ id, name, icon, comment, pkg, version, size, shown }]
    property var apps: []
    // desktop id → app entry, for names and icons.
    property var byId: ({})
    function app(id) {
        return byId[id] || { id: id, name: id ? id.replace(/\.desktop$/, "") : "", icon: "" }
    }
    property bool loading: listProc.running
    // Package whose uninstall terminal is open ("" = none).
    property string removing: ""

    function refresh() { listProc.running = true }

    // Optimistic: show the pick now, the re-list after the write confirms it.
    function setDefault(key, desktopId) {
        const label = (defaults.find(d => d.key === key) || {}).label
        defaults = defaults.map(d => d.key === key ? Object.assign({}, d, { current: desktopId }) : d)
        types = types.map(t => t.category === label ? Object.assign({}, t, { current: desktopId }) : t)
        _write(["set", key, desktopId])
    }
    function setType(mime, desktopId) {
        types = types.map(t => t.mime === mime ? Object.assign({}, t, { current: desktopId }) : t)
        _write(["set-type", mime, desktopId])
    }
    // Writes run one after another; picks made meanwhile wait their turn.
    property var _queue: []
    function _write(args) {
        _queue = _queue.concat([args])
        if (!setProc.running) _next()
    }
    function _next() {
        if (!_queue.length) { refresh(); return }
        setProc.command = ["python3", Paths.local(Qt.resolvedUrl("apps.py"))].concat(_queue[0])
        _queue = _queue.slice(1)
        setProc.running = true
    }

    function uninstall(pkg) {
        if (removing !== "" || !pkg) return
        removing = pkg
        removeProc.command = ["kitty", "--class", "qs-uninstall", "--title", "Uninstall " + pkg,
                              "sh", "-c", "yay -Rncs -- \"$1\"; echo; printf 'Press Enter to close… '; read _",
                              "sh", pkg]
        removeProc.running = true
    }

    Process {
        id: listProc
        command: ["python3", Paths.local(Qt.resolvedUrl("apps.py")), "list"]
        property string _buf: ""
        onRunningChanged: if (running) _buf = ""
        stdout: SplitParser { onRead: line => listProc._buf += line }
        onExited: (code, status) => {
            if (code !== 0 || status !== 0) return
            try {
                const j = JSON.parse(listProc._buf)
                const map = {}
                for (const a of j.apps) map[a.id] = a
                root.byId = map
                root.defaults = j.defaults
                root.types = j.types
                root.apps = j.apps
            } catch (e) { console.log("apps parse failed:", e) }
        }
    }
    Process {
        id: setProc
        stderr: SplitParser { onRead: line => console.log("apps:", line) }
        onExited: root._next()
    }
    Process {
        id: removeProc
        onExited: { root.removing = ""; root.refresh() }
    }
}
