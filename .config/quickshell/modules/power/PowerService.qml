pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Power menu (shutdown / reboot / suspend / lock). Standalone — not in the
// launcher. `qs ipc call power toggle|open|close`
Singleton {
    id: root

    property bool powerOpen: false
    function openPower()  { powerOpen = true }
    function closePower() { powerOpen = false }
    function powerAction(which) {
        if      (which === "shutdown")  Quickshell.execDetached(["systemctl", "poweroff"])
        else if (which === "reboot")    Quickshell.execDetached(["systemctl", "reboot"])
        else if (which === "suspend")   Quickshell.execDetached(["systemctl", "suspend"])
        // Quickshell lockscreen.
        else if (which === "lock")      Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/lock.sh"])
        root.powerOpen = false
    }
    IpcHandler {
        target: "power"
        function toggle() { root.powerOpen = !root.powerOpen }
        function open()   { root.openPower()  }
        function close()  { root.closePower() }
    }
}
