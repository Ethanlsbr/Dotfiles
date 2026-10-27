pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.modules.settings

// Audio: default-sink and default-source volume/mute (wpctl, live via
// `pactl subscribe`), sink/source pickers and card profiles.
Singleton {
    id: root

    property int    volPct:      -1
    property bool   volMuted:    false
    property int    micPct:      -1
    property bool   micMuted:    false
    property var    sinkList:         []
    property var    _sinkBuffer:      []
    property var    sourceList:       []
    property var    _sourceBuffer:    []
    property var    cardList:         []   // [{name, desc, profiles:[{key,desc,active,available}]}]
    property var    _cardBuffer:      []

    // Swap in a re-queried list only if it differs — every volume change
    // fires a sink event, and a fresh array would rebuild every row.
    function _replaceIfChanged(prop, buf) {
        if (JSON.stringify(root[prop]) !== JSON.stringify(buf)) root[prop] = buf.slice()
    }

    // Public API for the settings panes.
    function switchSink(name) {
        switchSinkProc.sinkName = name
        switchSinkProc.running  = false
        switchSinkProc.running  = true
    }
    function switchSource(name) {
        switchSourceProc.sourceName = name
        switchSourceProc.running    = false
        switchSourceProc.running    = true
    }
    function refreshSources() {
        sourceQueryProc.running = false
        sourceQueryProc.running = true
    }
    // While dragging: show the value optimistically and block incoming
    // wpctl queries from snapping the UI back.
    property bool _volHold: false
    property int  _volPendingPct: -1

    function setVolumePct(pct) {
        const p = Math.max(0, Math.min(100, Math.round(pct)))
        root.volPct = p
        if (p > 0) root.volMuted = false
        root._volHold = true
        volHoldTimer.restart()
        // Coalesce set-volume so a fast drag fires one call.
        root._volPendingPct = p
        volSetDebounce.restart()
    }
    function adjustVolume(direction) {  // "+" or "-"
        setVolStepProc.target  = direction === "+" ? "2%+" : "2%-"
        setVolStepProc.running = false
        setVolStepProc.running = true
    }
    function toggleMute() {
        root.volMuted = !root.volMuted   // optimistic; query confirms
        root._volHold = true
        volHoldTimer.restart()
        toggleMuteProc.running = false
        toggleMuteProc.running = true
    }
    // Input (default source) volume — same optimistic hold/debounce scheme.
    property bool _micHold: false
    property int  _micPendingPct: -1

    function setMicVolumePct(pct) {
        const p = Math.max(0, Math.min(100, Math.round(pct)))
        root.micPct = p
        if (p > 0) root.micMuted = false
        root._micHold = true
        micHoldTimer.restart()
        root._micPendingPct = p
        micSetDebounce.restart()
    }
    function toggleMicMute() {
        root.micMuted = !root.micMuted
        root._micHold = true
        micHoldTimer.restart()
        toggleMicMuteProc.running = false
        toggleMicMuteProc.running = true
    }
    function refreshMicVolume() {
        micQueryProc.running = false
        micQueryProc.running = true
    }
    function refreshSinks() {
        sinkQueryProc.running = false
        sinkQueryProc.running = true
    }
    // Card profiles (pactl set-card-profile); switching rearranges sinks
    // and sources, so refresh those too.
    function refreshCards() {
        cardQueryProc.running = false
        cardQueryProc.running = true
    }
    function setCardProfile(card, profile) {
        setCardProfileProc.card    = card
        setCardProfileProc.profile = profile
        setCardProfileProc.running = false
        setCardProfileProc.running = true
    }

    // ── Volume (wpctl → pactl subscribe) ──────────────────────────────────
    Process {
        id: volQueryProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: line => {
                var m = line.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
                if (!m) return
                // Don't clobber the optimistic value mid-drag (_volHold).
                if (root._volHold) return
                root.volPct   = Math.round(parseFloat(m[1]) * 100)
                root.volMuted = !!m[2]
            }
        }
    }
    // Coalesces rapid slider updates into one wpctl set-volume.
    Timer {
        id: volSetDebounce
        interval: 40; repeat: false
        onTriggered: {
            if (root._volPendingPct < 0) return
            setVolProc.targetPct = root._volPendingPct
            setVolProc.running   = false
            setVolProc.running   = true
        }
    }
    // Release the hold shortly after the last interaction.
    Timer {
        id: volHoldTimer
        interval: 450; repeat: false
        onTriggered: root._volHold = false
    }

    // setpriv: ends with the shell even if it crashes (no orphan).
    Process {
        id: pactlMonitor
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "--", "pactl", "subscribe"]
        stdout: SplitParser {
            onRead: line => {
                // 'on server' = default-device change; 'on sink/source #N' =
                // per-device change. Stream events ('on sink-input',
                // 'on source-output') fire throughout playback and never
                // change device volume — don't re-query on those.
                const isSink   = / on (sink|server) #/.test(line)
                const isSource = / on (source|server) #/.test(line)
                if (isSink) {
                    volQueryProc.running = false
                    volQueryProc.running = true
                    if (PopupService.sinkPopupOpen || SettingsService.settingsOpen) {
                        sinkQueryProc.running = false
                        sinkQueryProc.running = true
                    }
                }
                if (isSource) {
                    root.refreshMicVolume()
                    if (SettingsService.settingsOpen) {
                        sourceQueryProc.running = false
                        sourceQueryProc.running = true
                    }
                }
            }
        }
        onExited: (code, status) => pactlMonitorRestartTimer.start()
    }
    Timer {
        id: pactlMonitorRestartTimer
        interval: 2000; repeat: false
        onTriggered: pactlMonitor.running = true
    }

    // ── Volume setter (used by settings pane slider) ─────────────────────
    Process {
        id: setVolProc
        property int targetPct: 0
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", (targetPct / 100).toFixed(2)]
        onExited: {
            volQueryProc.running = false
            volQueryProc.running = true
        }
    }

    // ── Input volume (default source) ────────────────────────────────────
    Process {
        id: micQueryProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
        stdout: SplitParser {
            onRead: line => {
                var m = line.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
                if (!m || root._micHold) return
                root.micPct   = Math.round(parseFloat(m[1]) * 100)
                root.micMuted = !!m[2]
            }
        }
    }
    Timer {
        id: micSetDebounce
        interval: 40; repeat: false
        onTriggered: {
            if (root._micPendingPct < 0) return
            setMicProc.targetPct = root._micPendingPct
            setMicProc.running   = false
            setMicProc.running   = true
        }
    }
    Timer {
        id: micHoldTimer
        interval: 450; repeat: false
        onTriggered: root._micHold = false
    }
    Process {
        id: setMicProc
        property int targetPct: 0
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", (targetPct / 100).toFixed(2)]
        onExited: root.refreshMicVolume()
    }
    Process {
        id: toggleMicMuteProc
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]
        onExited: root.refreshMicVolume()
    }

    // ── Switch sink: set default + move all existing sink inputs ─────────
    Process {
        id: switchSinkProc
        property string sinkName: ""
        command: ["sh", "-c",
            "pactl set-default-sink \"" + sinkName + "\" && " +
            "pactl list sink-inputs short | awk '{print $1}' | " +
            "xargs -r -I{} pactl move-sink-input {} \"" + sinkName + "\""]
    }

    // ── Switch source: set default + move all existing source outputs ────
    Process {
        id: switchSourceProc
        property string sourceName: ""
        command: ["sh", "-c",
            "pactl set-default-source \"" + sourceName + "\" && " +
            "pactl list source-outputs short | awk '{print $1}' | " +
            "xargs -r -I{} pactl move-source-output {} \"" + sourceName + "\""]
    }

    // ── Source list (input device picker) ────────────────────────────────
    Process {
        id: sourceQueryProc
        running: false
        command: ["sh", "-c",
            "DEFAULT=$(pactl get-default-source); " +
            "pactl list sources | awk -v def=\"$DEFAULT\" " +
            "'/\\tName:/{name=$2} /\\tDescription:/{desc=substr($0,index($0,$2)); " +
            "if (name !~ /\\.monitor$/) printf \"%s\\t%s\\t%s\\n\",(name==def?\"1\":\"0\"),name,desc}'"]
        onRunningChanged: if (running) root._sourceBuffer = []
        stdout: SplitParser {
            onRead: line => {
                var parts = line.split("\t")
                if (parts.length >= 3)
                    root._sourceBuffer.push({active: parts[0]==="1", name: parts[1], desc: parts[2]})
            }
        }
        onExited: root._replaceIfChanged("sourceList", root._sourceBuffer)
    }

    // ── Sink list (for device picker) ─────────────────────────────────────
    Process {
        id: sinkQueryProc
        running: false
        command: ["sh", "-c",
            "DEFAULT=$(pactl get-default-sink); " +
            "pactl list sinks | awk -v def=\"$DEFAULT\" " +
            "'/\\tName:/{name=$2} /\\tDescription:/{desc=substr($0,index($0,$2)); " +
            "printf \"%s\\t%s\\t%s\\n\",(name==def?\"1\":\"0\"),name,desc}'"]
        onRunningChanged: if (running) root._sinkBuffer = []
        stdout: SplitParser {
            onRead: line => {
                var parts = line.split("\t")
                if (parts.length >= 3)
                    root._sinkBuffer.push({active: parts[0]==="1", name: parts[1], desc: parts[2]})
            }
        }
        onExited: root._replaceIfChanged("sinkList", root._sinkBuffer)
    }

    // ── Card profile list (output-profile picker) ────────────────────────
    // list-cards.sh emits one record per profile; grouped by card here.
    Process {
        id: cardQueryProc
        running: false
        command: [Paths.local(Qt.resolvedUrl("list-cards.sh"))]
        onRunningChanged: if (running) root._cardBuffer = []
        stdout: SplitParser {
            onRead: line => {
                var p = line.split("\t")
                if (p.length < 6) return
                var cardName = p[0], cardDesc = p[1]
                var prof = { key: p[2], desc: p[3], active: p[4] === "1", available: p[5] === "1" }
                // Append to the existing card group or start a new one.
                var buf = root._cardBuffer
                var card = buf.length && buf[buf.length - 1].name === cardName
                           ? buf[buf.length - 1] : null
                if (!card) { card = { name: cardName, desc: cardDesc, profiles: [] }; buf.push(card) }
                card.profiles.push(prof)
            }
        }
        onExited: root._replaceIfChanged("cardList", root._cardBuffer)
    }

    // ── Switch card profile ──────────────────────────────────────────────
    // Array args (no shell) — profile keys with spaces/parens need no quoting.
    Process {
        id: setCardProfileProc
        property string card: ""
        property string profile: ""
        command: ["pactl", "set-card-profile", card, profile]
        onExited: { root.refreshCards(); root.refreshSinks(); root.refreshSources() }
    }

    // ── Volume step (wheel-driven from bar) ───────────────────────────────
    // Capped at 100% like the sliders (-l): a plain step went past it.
    Process {
        id: setVolStepProc
        property string target: "2%+"
        command: ["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", target]
        onExited: refreshVolumeAfterStep()
    }
    function refreshVolumeAfterStep() {
        volQueryProc.running = false
        volQueryProc.running = true
    }

    // ── Mute toggle ───────────────────────────────────────────────────────
    Process {
        id: toggleMuteProc
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        onExited: refreshVolumeAfterStep()
    }

    function launchPavucontrol() { launchPavucontrolProc.running = false; launchPavucontrolProc.running = true }
    Process { id: launchPavucontrolProc; command: ["pavucontrol"] }

    Component.onCompleted: { volQueryProc.running = true; micQueryProc.running = true }
}
