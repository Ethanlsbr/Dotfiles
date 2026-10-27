import QtQuick
import Quickshell
import qs.modules.appearance
import qs.common

// Fallback toasts, stacked top-right, for when no bar presents them (bar
// hidden / disabled on that monitor) — normally BarToastPanel hangs them
// from the bar's right pill. Auto-dismiss after 5 s; critical ones persist
// until clicked. Same motion as the bar popups: grow out of the top-right
// corner, shrink back into it on close; the rest of the stack slides up.
PanelWindow {
    id: overlay

    required property var theme
    // Shell-size scale of this window's monitor (unset monitors = 100%).
    readonly property real uiScale: AppearanceService.scaleFor(screen?.name ?? "")

    visible: NotificationService.toastCount > 0 && !NotificationService.barToastHost

    anchors { top: true; right: true }
    margins.right: 10
    margins.top:   Math.round(6 * uiScale)
    exclusiveZone: 0
    color: "transparent"

    implicitWidth:  360 * uiScale
    implicitHeight: Math.max(1, stack.implicitHeight * uiScale)

    Column {
        id: stack
        // 100% layout rendered at uiScale, right edge pinned to the screen.
        y: 0
        width: parent.width / overlay.uiScale
        x: parent.width - width
        scale: overlay.uiScale
        transformOrigin: Item.TopRight
        spacing: 8

        // Toasts below a closed one slide up (bar popup resize timing).
        move: Transition {
            NumberAnimation { properties: "y"; duration: 160; easing.type: Easing.OutCubic }
        }

        Repeater {
            // Only one presenter owns the toasts (timers + drops).
            model: overlay.visible ? NotificationService.toasts : null

            delegate: Rectangle {
                id: toast
                required property var  notif
                required property bool closing
                required property int  index
                property var info: ({})

                width: stack.width
                implicitHeight: body.implicitHeight
                radius: 12
                color: overlay.theme.bg
                border.color: info.urgency === 2 ? overlay.theme.error : overlay.theme.sep
                border.width: 1

                // ListModel.set() updates `notif` in place (no pop-in replay);
                // refresh the content and restart the countdown.
                onNotifChanged: {
                    const s = NotificationService.snapshot(notif)
                    if (s) info = s
                    if (info.urgency !== 2) dismissTimer.restart()
                }

                // Bar-popup motion: grow out of the top-right corner; on
                // close, shrink back into it, then leave the model.
                transform: PopAnim {
                    id: pop
                    item: toast
                    origin.x: toast.width
                    origin.y: 0
                    onShownChanged: if (!shown) NotificationService._dropToastAt(toast.index)
                }
                opacity: 0
                Component.onCompleted: {
                    info = NotificationService.snapshot(notif) || {}
                    pop.open = !closing
                }
                onClosingChanged: pop.open = !closing

                Timer {
                    id: dismissTimer
                    interval: 5000; repeat: false
                    running: toast.info.urgency !== 2 && !toast.closing
                    onTriggered: NotificationService.closeToastAt(toast.index)
                }

                ToastContent {
                    id: body
                    anchors.fill: parent
                    theme: overlay.theme
                    info: toast.info
                    onCloseClicked: NotificationService.closeToastAt(toast.index)
                }
            }
        }
    }
}
