pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Task manager (Windows-style). While open, procmon.py streams a /proc
// snapshot every 2 s; processes are grouped like Windows: Apps (Hyprland
// windows + their child processes), Background (yours), System (other
// users). End task = SIGTERM, Force kill = SIGKILL.
// Users tab: every account (procmon.py users) with its groups, plus live
// per-user process / CPU / memory totals from the snapshot.
// External control: `qs ipc call taskmanager toggle|open|close`, or
// `qs ipc call taskmanager openTab processes|performance|users`.
Singleton {
    id: root

    property bool taskManagerOpen: false
    // Active tab: "processes" | "performance" | "users".
    property string tab: "processes"
    readonly property var tabs: ["processes", "performance", "users"]
    function nextTab(step) {
        const i = tabs.indexOf(tab)
        tab = tabs[(i + step + tabs.length) % tabs.length]
    }

    // Latest snapshot (see procmon.py).
    property var  procs:    []
    property var  clients:  []
    property int  ownUid:   -1
    property real memTotal: 0
    property bool loaded:   false

    // Accounts (see procmon.py users), reloaded each time the Users tab opens.
    property var  users:       []
    property bool usersLoaded: false
    function refreshUsers() { usersProc.running = false; usersProc.running = true }
    onTabChanged: if (taskManagerOpen && tab === "users") refreshUsers()

    // uid → {count, cpu, mem} over the latest snapshot.
    readonly property var userStats: {
        const out = {}
        for (const p of procs) {
            const s = out[p.uid] || (out[p.uid] = { count: 0, cpu: 0, mem: 0 })
            s.count++
            s.cpu += p.cpu
            s.mem += p.mem
        }
        return out
    }

    // Last kill failure, shown in the window footer ("" when none).
    property string lastError: ""

    // ── Grouping ────────────────────────────────────────────────────────
    // apps:       [{key, pid, cls, title, address, windows, members, cpu, mem}]
    //   members = the window's process + its descendants (stopping at other
    //   window-owning processes, which are apps of their own).
    // background: own processes outside every app tree; system: the rest.
    readonly property var groups: {
        const byPid = {}, kids = {}
        for (const p of procs) {
            byPid[p.pid] = p
            if (!kids[p.ppid]) kids[p.ppid] = []
            kids[p.ppid].push(p)
        }
        const appByPid = {}
        const apps = []
        for (const c of clients) {
            if (!byPid[c.pid]) continue
            if (appByPid[c.pid]) { appByPid[c.pid].windows++; continue }
            const a = { key: "app:" + c.pid, pid: c.pid, cls: c.cls, title: c.title,
                        address: c.address, windows: 1, members: [], cpu: 0, mem: 0 }
            appByPid[c.pid] = a
            apps.push(a)
        }
        const owned = {}
        for (const a of apps) {
            const stack = [byPid[a.pid]]
            while (stack.length) {
                const p = stack.pop()
                owned[p.pid] = true
                a.members.push(p)
                a.cpu += p.cpu
                a.mem += p.mem
                for (const k of (kids[p.pid] || []))
                    if (!appByPid[k.pid]) stack.push(k)
            }
        }
        const background = [], system = []
        for (const p of procs) {
            if (owned[p.pid]) continue
            if (p.uid === ownUid) background.push(p)
            else                  system.push(p)
        }
        return { apps, background, system }
    }

    readonly property real totalCpu: procs.reduce((s, p) => s + p.cpu, 0)
    readonly property real totalMem: procs.reduce((s, p) => s + p.mem, 0)

    // All descendants of pid (for "End process tree"), deepest first.
    function descendants(pid) {
        const kids = {}
        for (const p of procs) (kids[p.ppid] = kids[p.ppid] || []).push(p.pid)
        const out = [], stack = [pid]
        while (stack.length) {
            const cur = stack.pop()
            for (const k of (kids[cur] || [])) { out.push(k); stack.push(k) }
        }
        return out.reverse()
    }

    function open()   { taskManagerOpen = true }
    function show(t)  { if (tabs.includes(t)) tab = t; taskManagerOpen = true }
    function close()  { taskManagerOpen = false }
    function toggle() { taskManagerOpen = !taskManagerOpen }
    onTaskManagerOpenChanged: {
        lastError = ""
        if (!taskManagerOpen) { procs = []; clients = []; loaded = false }
        else if (tab === "users") refreshUsers()
    }

    // sig: "TERM" | "KILL"
    function sendSignal(pids, sig) {
        if (!pids || !pids.length) return
        lastError = ""
        killProc.sig  = sig
        killProc.pids = pids.map(String)
        killProc.running = false
        killProc.running = true
    }
    function endTask(pid)   { sendSignal([pid], "TERM") }
    function forceKill(pid) { sendSignal([pid], "KILL") }
    function endTree(pid)   { sendSignal(descendants(pid).concat([pid]), "KILL") }

    function focusWindow(address) {
        if (!address) return
        Quickshell.execDetached(["hyprctl", "dispatch",
                                 "hl.dsp.focus({window = \"address:" + address + "\"})"])
    }

    IpcHandler {
        target: "taskmanager"
        function toggle() { root.toggle() }
        function open()   { root.open()   }
        function openTab(tab: string) { root.show(tab) }
        function close()  { root.close()  }
    }

    Process {
        id: watchProc
        running: root.taskManagerOpen
        command: ["python3", Paths.local(Qt.resolvedUrl("procmon.py")), "watch", "2"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line)
                    root.ownUid   = d.uid
                    root.memTotal = d.mem_total
                    root.clients  = d.clients
                    root.procs    = d.procs
                    root.loaded   = true
                } catch (e) { console.log("[taskmanager] bad snapshot:", e) }
            }
        }
        // Crashed while open → restart.
        onExited: if (root.taskManagerOpen) watchRestart.restart()
    }
    Timer {
        id: watchRestart
        interval: 1000; repeat: false
        onTriggered: if (root.taskManagerOpen) watchProc.running = true
    }

    Process {
        id: usersProc
        command: ["python3", Paths.local(Qt.resolvedUrl("procmon.py")), "users"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.users = JSON.parse(line).users
                    root.usersLoaded = true
                } catch (e) { console.log("[taskmanager] bad users list:", e) }
            }
        }
    }

    Process {
        id: killProc
        property string sig:  "TERM"
        property var    pids: []
        property var    _errs: []
        command: ["python3", Paths.local(Qt.resolvedUrl("procmon.py")), "kill", sig].concat(pids)
        onRunningChanged: if (running) _errs = []
        stdout: SplitParser {
            onRead: line => {
                const t = line.split("\t")
                if (t.length >= 2) killProc._errs.push("PID " + t[0] + ": " + t[1])
            }
        }
        onExited: {
            if (killProc._errs.length)
                root.lastError = killProc._errs.length === 1
                    ? "Couldn't end " + killProc._errs[0]
                    : "Couldn't end " + killProc._errs.length + " processes (" + killProc._errs[0] + ", …)"
        }
    }
}
