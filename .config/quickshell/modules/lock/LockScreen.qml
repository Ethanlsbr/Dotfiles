import QtQuick
import Quickshell
import Quickshell.Wayland

// Session lock: one LockContent surface per monitor while LockService.locked.
Scope {
    id: scope

    required property var theme

    WlSessionLock {
        locked: LockService.locked

        WlSessionLockSurface {
            id: surface
            color: "black"
            LockContent {
                anchors.fill: parent
                theme: scope.theme
                screenName: surface.screen?.name ?? ""
            }
        }
    }
}
