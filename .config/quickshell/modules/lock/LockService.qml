pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import qs.common
import qs.modules.account

// Windows-style lockscreen state: session lock, password buffer shared by
// every monitor's surface, PAM checks: pam/password.conf (pam_unix with
// pam_faillock) and, when fingers are enrolled, pam/fprint.conf
// (pam_fprintd) in parallel.
// Failed passwords count toward the system faillock policy
// (/etc/security/faillock.conf, shared with hyprlock/sudo/login); the prompt
// shows the attempts left and, once locked out, a countdown with input off.
// A marker in $XDG_RUNTIME_DIR re-locks if the shell restarts while locked.
// `qs ipc call lock lock`
Singleton {
    id: root

    property bool locked: false
    // Curtain (clock) vs. sign-in prompt (avatar + password field).
    property bool prompt: false
    property string buffer: ""
    property bool busy: false
    property string error: ""
    // Bumped on each failed attempt (drives the field shake).
    property int failTick: 0
    // Fade-out running before the lock is released.
    property bool unlocking: false

    function lock() {
        if (locked) return
        refreshWallpapers()
        FingerprintService.refresh()
        refreshFaillock()
        buffer = ""; error = ""; prompt = false; busy = false; unlocking = false
        fpFailRounds = 0
        locked = true
        Quickshell.execDetached(["touch", lockMarker])
    }

    function showPrompt() { if (!prompt) { prompt = true; error = lockedOut ? lockoutText() : "" } }
    function hidePrompt() { if (!busy) { prompt = false; buffer = ""; error = "" } }
    function type(text) { if (!busy && !lockedOut) { buffer += text; error = "" } }
    function backspace(all) { if (!busy) buffer = all ? "" : buffer.slice(0, -1) }

    function submit() {
        if (busy || buffer === "" || pam.active || lockedOut) return
        busy = true
        error = ""
        pamNote = ""
        if (!pam.start()) {
            busy = false
            error = "Couldn't start authentication"
        }
    }

    PamContext {
        id: pam
        configDirectory: Paths.local(Qt.resolvedUrl("pam"))
        config: "password.conf"
        onPamMessage: {
            if (responseRequired) respond(root.buffer)
            // e.g. faillock's "The account is locked due to 5 failed logins."
            else if (message) root.pamNote = message.trim()
        }
        onCompleted: result => {
            root.busy = false
            root.buffer = ""
            if (!root.locked || root.unlocking) return
            if (result === PamResult.Success) {
                root._unlock()
            } else {
                root.failTick++
                root.error = root.pamNote || "The password is incorrect."
                // The tally decides what comes next (attempts left / lockout).
                root.refreshFaillock()
            }
        }
        onError: err => {
            root.busy = false
            root.buffer = ""
            root.error = "Authentication error (" + PamError.toString(err) + ")"
        }
    }
    // Last informational PAM message of the current attempt.
    property string pamNote: ""

    function _unlock() {
        root.unlocking = true
        if (fpPam.active) fpPam.abort()
        Quickshell.execDetached(["rm", "-f", lockMarker])
        unlockTimer.restart()
    }

    // ── Failed-attempt policy (pam_faillock) ─────────────────────────────
    // Policy from /etc/security/faillock.conf (pam_faillock's built-in
    // defaults when unset); failures from `faillock --user`, which reads
    // the user's own tally.
    property int failDeny: 3
    property int failInterval: 900      // s: failures older than this don't count
    property int failUnlockTime: 600    // s: lockout length (0 = until an admin resets)
    property int failures: 0            // counted failures right now
    property real lockoutUntil: 0       // ms epoch; 0 = not locked out
    readonly property bool lockedOut: lockoutUntil > now.getTime()
    readonly property int attemptsLeft: Math.max(0, failDeny - failures)

    function lockoutText() {
        if (failUnlockTime === 0) return "Too many failed attempts. This account is locked until an administrator unlocks it."
        const s = Math.max(0, Math.ceil((lockoutUntil - now.getTime()) / 1000))
        return "Too many failed attempts. Try again in " + Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") + "."
    }
    function refreshFaillock() {
        faillockConf.running = false; faillockConf.running = true
    }
    // Live countdown while locked out; clears itself when the time is up.
    onNowChanged: {
        if (lockoutUntil <= 0) return
        if (lockedOut) { if (prompt) error = lockoutText() }
        else { lockoutUntil = 0; error = ""; refreshFaillock() }
    }
    function _applyTally(stamps) {
        const t = now.getTime()
        const recent = stamps.filter(x => t - x < failInterval * 1000)
        failures = recent.length
        if (failures >= failDeny) {
            const last = Math.max.apply(null, recent)
            lockoutUntil = failUnlockTime === 0 ? Number.MAX_SAFE_INTEGER : last + failUnlockTime * 1000
        } else {
            lockoutUntil = 0
        }
        if (!locked || unlocking || busy) return
        if (lockedOut) {
            error = lockoutText()
            buffer = ""
        } else if (failures > 0 && error !== "") {
            const left = attemptsLeft
            error = (pamNote || "The password is incorrect.") + " " + left
                  + (left === 1 ? " attempt" : " attempts") + " left before the account is locked"
                  + (failUnlockTime > 0 ? " for " + Math.round(failUnlockTime / 60) + " min." : ".")
        }
    }
    Process {
        id: faillockConf
        command: ["sh", "-c", "grep -E '^[[:space:]]*(deny|fail_interval|unlock_time)[[:space:]]*=' /etc/security/faillock.conf"]
        property var _acc: ({})
        onRunningChanged: if (running) _acc = {}
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/^\s*(\w+)\s*=\s*(\S+)/)
                if (m) faillockConf._acc[m[1]] = m[2]
            }
        }
        onExited: {
            // Missing keys keep pam_faillock's defaults; "never" = no auto-unlock.
            const a = faillockConf._acc
            root.failDeny = a.deny !== undefined ? parseInt(a.deny) : 3
            root.failInterval = a.fail_interval !== undefined ? parseInt(a.fail_interval) : 900
            root.failUnlockTime = a.unlock_time === "never" ? 0
                                : a.unlock_time !== undefined ? parseInt(a.unlock_time) : 600
            faillockTally.running = false; faillockTally.running = true
        }
    }
    Process {
        id: faillockTally
        command: ["faillock", "--user", Quickshell.env("USER")]
        property var _stamps: []
        onRunningChanged: if (running) _stamps = []
        // "2026-10-24 20:03:45 SVC   password.conf      V" (V = counted)
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)\s.*\sV\s*$/)
                if (m) faillockTally._stamps.push(new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime())
            }
        }
        onExited: (code, status) => { if (code === 0 && status === 0) root._applyTally(faillockTally._stamps) }
    }

    // ── Crash safety ─────────────────────────────────────────────────────
    // Hyprland keeps the screen locked if this shell dies while locked
    // (misc.allow_session_lock_restore lets a new instance take over); the
    // marker makes the restarted shell put the lockscreen straight back.
    readonly property string lockMarker: Quickshell.env("XDG_RUNTIME_DIR") + "/quickshell-locked"
    Process {
        id: markerCheck
        command: ["test", "-e", root.lockMarker]
        onExited: code => { if (code === 0) root.lock() }
    }
    // Lets the fade-out play, then releases the session lock.
    Timer {
        id: unlockTimer
        interval: 320
        onTriggered: {
            root.locked = false
            root.unlocking = false
            root.prompt = false
            root.buffer = ""
        }
    }
    // ── Fingerprint (runs the whole time the screen is locked) ──────────
    // Off while FingerprintService re-checks (on every lock), so nothing
    // fingerprint-related shows from stale state, e.g. after fprintd was removed.
    readonly property bool fingerprintReady: FingerprintService.installed && !FingerprintService.refreshing
                                             && FingerprintService.hasDevice
                                             && FingerprintService.enrolled.length > 0
    // Two rounds of failed scans (max-tries=3 each) and the reader stops
    // until the next lock; a faillock lockout pauses it too.
    property int fpFailRounds: 0
    readonly property bool fpBlocked: fpFailRounds >= 2
    readonly property bool fpWanted: locked && !unlocking && fingerprintReady && !fpBlocked && !lockedOut
    property string fpMessage: ""
    property bool   fpError: false
    onFpWantedChanged: {
        if (fpWanted) fpRestart.restart()
        else {
            fpRestart.stop(); if (fpPam.active) fpPam.abort()
            fpMessage = fpBlocked && locked ? "Too many fingerprint attempts. Use your password." : ""
            fpError = fpBlocked
        }
    }
    PamContext {
        id: fpPam
        configDirectory: Paths.local(Qt.resolvedUrl("pam"))
        config: "fprint.conf"
        onPamMessage: {
            if (messageIsError) {
                root.fpError = true
                root.fpMessage = "Fingerprint not recognized. Try again."
                root.showPrompt()       // surface the message, like Windows Hello
            } else if (/finger/i.test(message)) {
                root.fpError = false
                root.fpMessage = "Touch the fingerprint sensor to unlock"
            }
        }
        onCompleted: result => {
            if (!root.locked || root.unlocking) return
            if (result === PamResult.Success) { root._unlock(); return }
            if (result === PamResult.MaxTries) root.fpFailRounds++
            // Timed out / out of tries: listen again; back off on reader errors.
            fpRestart.interval = result === PamResult.Error ? 5000 : 1200
            if (root.fpWanted) fpRestart.restart()
        }
        onError: err => { fpRestart.interval = 5000; if (root.fpWanted) fpRestart.restart() }
    }
    // Short pause between attempts (also lets the device settle after resume).
    Timer {
        id: fpRestart
        interval: 1200
        onTriggered: if (root.fpWanted && !fpPam.active) fpPam.start()
    }

    // Back to the clock after 30 s without input on the prompt.
    Timer {
        id: idleTimer
        interval: 30000
        running: root.locked && root.prompt && !root.busy
        onTriggered: root.hidePrompt()
    }
    function poke() { if (idleTimer.running) idleTimer.restart() }

    // ── Clock ────────────────────────────────────────────────────────────
    property date now: new Date()
    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: root.locked
        onTriggered: root.now = new Date()
    }

    // ── Per-output wallpaper (awww query) ────────────────────────────────
    property var wallpapers: ({})
    function wallpaperFor(output) {
        return wallpapers[output] || Object.values(wallpapers)[0] || ""
    }
    function refreshWallpapers() {
        wallpaperProc.running = false
        wallpaperProc.running = true
    }
    Process {
        id: wallpaperProc
        command: ["awww", "query"]
        property var _acc: ({})
        onRunningChanged: if (running) _acc = {}
        // ": eDP-1: 1920x1200, scale: 1, currently displaying: image: /path"
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/^[:\s]*([^:\s]+):.*image:\s*(.+)$/)
                if (m) wallpaperProc._acc[m[1]] = m[2].trim()
            }
        }
        onExited: (code, status) => {
            if (code === 0 && status === 0 && Object.keys(_acc).length) root.wallpapers = _acc
        }
    }

    IpcHandler {
        target: "lock"
        function lock() { root.lock() }
        function isLocked(): bool { return root.locked }
    }

    Component.onCompleted: {
        refreshWallpapers()
        refreshFaillock()
        markerCheck.running = true
    }
}
