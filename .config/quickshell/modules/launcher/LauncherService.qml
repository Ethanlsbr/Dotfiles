pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// App launcher open state; GPU mode launches picks with DRI_PRIME=1.
Singleton {
    id: root

    property bool launcherOpen: false
    property bool launcherGpuMode: false

    function toggleLauncher() {
        if (launcherOpen && !launcherGpuMode) launcherOpen = false
        else                                  openLauncher()
    }
    function openLauncher()    { launcherGpuMode = false; FocusService.captureThenOpen(() => root.launcherOpen = true) }
    function closeLauncher()   { launcherOpen = false }
    // GPU launcher — same menu, launches on the dedicated GPU.
    function openGpuLauncher() { launcherGpuMode = true;  FocusService.captureThenOpen(() => root.launcherOpen = true) }
    function toggleGpuLauncher() {
        if (launcherOpen && launcherGpuMode) launcherOpen = false
        else                                 openGpuLauncher()
    }
    onLauncherOpenChanged: if (!launcherOpen) FocusService.refocusLastWindow()

    // External control: `qs ipc call launcher toggle|open|close`
    IpcHandler {
        target: "launcher"
        function toggle() { root.toggleLauncher() }
        function open()   { root.openLauncher()   }
        function close()  { root.closeLauncher()  }
    }
    // GPU launcher: `qs ipc call gpulauncher toggle|open|close`
    IpcHandler {
        target: "gpulauncher"
        function toggle() { root.toggleGpuLauncher() }
        function open()   { root.openGpuLauncher()  }
        function close()  { root.closeLauncher()    }
    }
}
