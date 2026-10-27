pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Now-playing text for the bar + playback controls (playerctl → spotify).
Singleton {
    id: root

    property string mediaText: ""

    function playerToggle()     { playerctlToggleProc.running  = false; playerctlToggleProc.running  = true }
    function playerNext()       { playerctlNextProc.running    = false; playerctlNextProc.running    = true }
    function playerPrev()       { playerctlPrevProc.running    = false; playerctlPrevProc.running    = true }

    // playerctl runs directly, not under sh: a reload only kills the direct
    // child, so a wrapped follower was orphaned each time; setpriv also ends
    // it if the shell dies.
    Process {
        id: mediaProc
        command: ["setpriv", "--pdeathsig", "TERM", "--",
                  "playerctl", "-p", "spotify", "metadata", "--follow",
                  "--format", "{{status}}|||{{artist}} - {{title}}"]
        stdout: SplitParser {
            onRead: line => {
                var sep    = line.indexOf("|||")
                if (sep < 0) { root.mediaText = ""; return }
                var status = line.substring(0, sep).trim()
                var track  = line.substring(sep + 3).trim()
                root.mediaText = (status === "Playing" || status === "Paused") ? track : ""
            }
        }
        // Follower gone = nothing playing until it restarts.
        onExited: (code, status) => { root.mediaText = ""; mediaRestartTimer.start() }
    }
    Timer {
        id: mediaRestartTimer
        interval: 3000; repeat: false
        onTriggered: mediaProc.running = true
    }

    Process { id: playerctlToggleProc; command: ["playerctl", "-p", "spotify", "play-pause"] }
    Process { id: playerctlNextProc;   command: ["playerctl", "-p", "spotify", "next"] }
    Process { id: playerctlPrevProc;   command: ["playerctl", "-p", "spotify", "previous"] }

    Component.onCompleted: mediaProc.running = true
}
