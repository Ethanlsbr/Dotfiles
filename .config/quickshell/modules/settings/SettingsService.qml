pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Settings window open state + active pane.
// External control: `qs ipc call settings open appearance`
Singleton {
    id: root

    property string settingsPane: "wifi"
    property bool   settingsOpen: false

    function openSettings(pane) {
        settingsPane = pane
        settingsOpen = true
    }
    IpcHandler {
        target: "settings"
        function open(pane: string) { root.openSettings(pane || "wifi") }
        function close() { root.settingsOpen = false }
    }
}
