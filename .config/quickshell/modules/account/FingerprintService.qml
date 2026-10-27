pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import qs.common

// Fingerprints (fprintd): enrolled list, enroll / delete / test via the
// fprintd-* tools. Enroll and delete need polkit auth (auth_self_keep), so a
// polkit agent is registered only while one of them runs and answers
// fprintd requests from the Profile pane; anything else is refused.
Singleton {
    id: root

    // fprintd package installed (and its tools on PATH). Every fingerprint
    // element — Profile section, lockscreen icon and messages — shows only
    // then. Re-checked after each pacman transaction (pacman.log watch).
    property bool installed: false
    // A check is running; the lockscreen hides fingerprint UI until it's done.
    readonly property bool refreshing: listProc.running
    property bool hasDevice: false
    property string deviceName: ""
    property var enrolled: []          // ["right-index-finger", …]
    property int numStages: 0

    readonly property var fingers: [
        "right-index-finger", "right-middle-finger", "right-thumb", "right-ring-finger", "right-little-finger",
        "left-index-finger", "left-middle-finger", "left-thumb", "left-ring-finger", "left-little-finger"
    ]
    function fingerLabel(f) {
        const s = String(f).replace(/-finger$/, "").replace(/-/g, " ")
        return s.charAt(0).toUpperCase() + s.slice(1) + (/thumb$/.test(f) ? "" : " finger")
    }

    function refresh() { listProc.running = true }

    Process {
        id: listProc
        command: ["sh", "-c", "{ pacman -Q fprintd >/dev/null 2>&1 || pacman -Qqo /usr/lib/security/pam_fprintd.so >/dev/null 2>&1; } "
                            + "&& command -v fprintd-list >/dev/null || { echo NOT_INSTALLED; exit 0; }; "
                            + "fprintd-list \"$USER\" 2>&1; "
                            + "busctl get-property net.reactivated.Fprint /net/reactivated/Fprint/Device/0 "
                            + "net.reactivated.Fprint.Device num-enroll-stages 2>/dev/null | sed 's/^i /STAGES /'"]
        property var _lines: []
        onRunningChanged: if (running) _lines = []
        stdout: SplitParser { onRead: line => listProc._lines.push(line) }
        onExited: (code, status) => {
            if (code !== 0 || status !== 0) return
            const lines = listProc._lines
            root.installed = !lines.includes("NOT_INSTALLED")
            if (!root.installed) {
                root.hasDevice = false; root.deviceName = ""; root.numStages = 0; root.enrolled = []
                return
            }
            root.hasDevice = root.installed && lines.some(l => /^Using device /.test(l))
            const prints = []
            for (const l of lines) {
                let m = l.match(/^\s*-\s*#\d+:\s*(\S+)/)
                if (m) prints.push(m[1])
                m = l.match(/^Fingerprints for user \S+ on (.+?)(?: \((?:press|swipe)\))?:?\s*$/)
                    || l.match(/no fingers enrolled for (.+?)\.?\s*$/)
                if (m) root.deviceName = m[1]
                m = l.match(/^STAGES (\d+)/)
                if (m) root.numStages = parseInt(m[1])
            }
            root.enrolled = prints
        }
    }

    // ── Enroll ───────────────────────────────────────────────────────────
    // state: "" | "enrolling" | "done" | "failed"
    property string enrollState: ""
    property string enrollFinger: ""
    property int    enrollStage: 0
    property string enrollHint: ""

    function enroll(finger) {
        if (busy) return
        enrollFinger = finger
        enrollStage = 0
        enrollHint = ""
        enrollState = "enrolling"
        _withAgent(() => { enrollProc.running = true })
    }
    function cancelEnroll() {
        enrollProc.running = false
        if (agentLoader.item?.flow) agentLoader.item.flow.cancelAuthenticationRequest()
        enrollState = ""
        _pending = null
    }
    function dismissEnroll() { if (enrollState !== "enrolling") enrollState = "" }

    readonly property var _enrollMessages: ({
        "enroll-retry-scan":          "Didn't catch that. Touch the sensor again.",
        "enroll-swipe-too-short":     "Too short. Try again.",
        "enroll-finger-not-centered": "Center your finger on the sensor.",
        "enroll-remove-and-retry":    "Lift your finger and touch again.",
        "enroll-failed":              "Enrollment failed.",
        "enroll-data-full":           "The sensor's storage is full.",
        "enroll-duplicate":           "This finger is already enrolled.",
        "enroll-disconnected":        "The fingerprint reader was disconnected.",
        "enroll-unknown-error":       "Something went wrong with the reader."
    })
    Process {
        id: enrollProc
        command: ["fprintd-enroll", "-f", root.enrollFinger]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/Enroll result:\s*(\S+)/)
                if (!m) return
                const r = m[1]
                if (r === "enroll-stage-passed") {
                    root.enrollStage++
                    root.enrollHint = "Lift and touch again, moving your finger slightly."
                } else if (r === "enroll-completed") {
                    root.enrollStage = root.numStages
                    root.enrollState = "done"
                    root.enrollHint = ""
                } else if (/failed|data-full|duplicate|disconnected|unknown-error/.test(r)) {
                    root.enrollState = "failed"
                    root.enrollHint = root._enrollMessages[r] || r
                } else {
                    root.enrollHint = root._enrollMessages[r] || r
                }
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (root.enrollState !== "enrolling") return
                root.enrollState = "failed"
                root.enrollHint = /PermissionDenied|Not Authorized/i.test(line) ? "Authorization was refused."
                                : /AlreadyInUse|busy/i.test(line) ? "The reader is busy (is the screen locked elsewhere?)."
                                : line.replace(/^.*Error[.:]\s*/, "")
            }
        }
        onExited: {
            if (root.enrollState === "enrolling") {
                root.enrollState = "failed"
                if (!root.enrollHint) root.enrollHint = "Enrollment stopped."
            }
            root.refresh()
        }
    }

    // ── Delete ───────────────────────────────────────────────────────────
    property bool deleting: false
    property string deleteError: ""
    function remove(finger) {
        if (busy) return
        deleting = true
        deleteError = ""
        deleteProc.finger = finger
        _withAgent(() => { deleteProc.running = true })
    }
    Process {
        id: deleteProc
        property string finger: ""
        command: ["sh", "-c", "fprintd-delete \"$USER\" -f \"$FINGER\" 2>&1"]
        environment: ({ FINGER: finger })
        stdout: SplitParser {
            onRead: line => {
                if (/PermissionDenied|Not Authorized/i.test(line)) root.deleteError = "Authorization was refused."
                else if (/failed|error/i.test(line)) root.deleteError = line
            }
        }
        onExited: { root.deleting = false; root.refresh() }
    }

    // ── Test (verify) ────────────────────────────────────────────────────
    // verifyState: "" | "scanning" | "match" | "nomatch" | "error"
    property string verifyState: ""
    function verify() {
        if (busy || !enrolled.length) return
        verifyState = "scanning"
        verifyProc.running = true
    }
    Process {
        id: verifyProc
        command: ["fprintd-verify"]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/Verify result:\s*(\S+)/)
                if (!m) return
                if (m[1] === "verify-match") root.verifyState = "match"
                else if (m[1] === "verify-no-match") root.verifyState = "nomatch"
            }
        }
        onExited: if (root.verifyState === "scanning") root.verifyState = "error"
    }
    Timer {
        interval: 4000
        running: root.verifyState === "match" || root.verifyState === "nomatch" || root.verifyState === "error"
        onTriggered: root.verifyState = ""
    }

    readonly property bool busy: enrollState === "enrolling" || deleting || verifyState === "scanning"

    // ── Scoped polkit agent ──────────────────────────────────────────────
    property var _pending: null
    // Runs `fn` once the agent is registered (or after 1.5 s if another
    // agent already owns the session and ours can't register).
    function _withAgent(fn) {
        _pending = fn
        if (agentLoader.item?.isRegistered) _runPending()
        else agentFallback.restart()
    }
    function _runPending() {
        agentFallback.stop()
        const fn = _pending
        _pending = null
        if (fn) fn()
    }
    Timer { id: agentFallback; interval: 1500; onTriggered: root._runPending() }

    LazyLoader {
        id: agentLoader
        active: root.enrollState === "enrolling" || root.deleting
        PolkitAgent {
            onIsRegisteredChanged: if (isRegistered && root._pending) root._runPending()
            onAuthenticationRequestStarted: {
                if (!flow.actionId.startsWith("net.reactivated.fprint")) flow.cancelAuthenticationRequest()
            }
        }
    }
    readonly property var authFlow: agentLoader.item?.flow ?? null
    readonly property bool authRequired: !!authFlow && authFlow.isResponseRequired
                                         && authFlow.actionId.startsWith("net.reactivated.fprint")
    readonly property string authError: authFlow && authFlow.supplementaryIsError ? authFlow.supplementaryMessage : ""
    function submitAuth(password) { if (authFlow) authFlow.submit(password) }

    // Package installs / removals append to pacman.log; re-check once the
    // transaction settles.
    FileView {
        path: "/var/log/pacman.log"
        preload: false
        watchChanges: true
        onFileChanged: pacmanSettle.restart()
    }
    Timer {
        id: pacmanSettle
        interval: 1500
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
