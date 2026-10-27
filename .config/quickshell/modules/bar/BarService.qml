pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.modules.appearance

// Bar visibility (IPC), plus the per-monitor enable list and shown elements
// from AppearanceService.
Singleton {
    id: root

    // External control: `qs ipc call bar toggle|show|hide`
    property bool barVisible: true
    IpcHandler {
        target: "bar"
        function toggle() { root.barVisible = !root.barVisible }
        function show()   { root.barVisible = true  }
        function hide()   { root.barVisible = false }
    }

    // Per-monitor enable list and shown elements live in AppearanceService
    // (state/bar-monitors.txt, state/bar-modules.txt); forwarded here.
    readonly property var barDisabledMonitors: AppearanceService.barDisabledMonitors
    function barEnabledOn(name) { return AppearanceService.barEnabledOn(name) }
    function setBarOnMonitor(name, enabled) { AppearanceService.setBarOnMonitor(name, enabled) }
    function isShown(key) { return AppearanceService.barModuleShown(key) }
}
