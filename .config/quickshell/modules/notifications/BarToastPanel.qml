import QtQuick
import Quickshell
import qs.common

// Notification toasts hanging from the bar's right status pill, drawn in
// the bar window exactly like the hover popups (BarPopupPanel): the pill's
// width, flush under it (the pill squares its bottom corners as it opens),
// same open/close motion out of / back into the pill. Stacked toasts share
// the panel: a new one grows it, a dismissed one collapses out, and the
// last one shrinks the whole panel back into the pill. Steps aside while a
// hover popup owns the pill.
Item {
    id: host

    // Unscaled design tokens (the panel lays out at 100% and is scaled).
    required property var theme
    // The bar's right status pill this panel hangs from.
    required property Item pill
    // Shell size of this bar's monitor.
    required property real uiScale
    // Only one bar presents the toasts (the hover-popup monitor).
    property bool hostActive: false

    // Input region for the bar window: the visible panel.
    readonly property alias maskItem: maskItem

    // A hover popup is open / animating under the pill → stay out of its way.
    readonly property bool blocked: PopupService.rightPopupProgress > 0 || PopupService.openPopup() !== ""
    readonly property bool wantOpen: hostActive && !blocked && NotificationService.openToastCount > 0

    // On screen: from the start of the enter animation to the end of the exit.
    property bool expanded: false
    visible: expanded

    onWantOpenChanged: {
        if (wantOpen) {
            if (!expanded) {
                panel.opacity = 0
                panelScale.xScale = panelScale.yScale = 0.05
            }
            expanded = true
            exitAnim.stop()
            if (!enterAnim.running && (panelScale.xScale < 1 || panel.opacity < 1))
                enterAnim.restart()
        } else {
            enterAnim.stop()
            if (expanded) exitAnim.restart()
            else          NotificationService._dropClosing()
        }
    }

    Binding {
        target: NotificationService; property: "barToastHost"
        when: host.hostActive
        value: true
    }
    Binding {
        target: NotificationService; property: "toastProgress"
        when: host.hostActive
        value: host.expanded ? Math.max(0, Math.min(1, (panelScale.xScale - 0.05) / 0.95)) : 0
    }

    // Same open/close timing as the hover popups: fade + scale up from 5%,
    // here around the pill's top-right end; the reverse shrinks back into it.
    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: panel;      property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { target: panelScale; property: "xScale";  to: 1; duration: 250; easing.type: Easing.OutCubic }
        NumberAnimation { target: panelScale; property: "yScale";  to: 1; duration: 250; easing.type: Easing.OutCubic }
    }
    SequentialAnimation {
        id: exitAnim
        ParallelAnimation {
            NumberAnimation { target: panel;      property: "opacity"; to: 0;    duration: 150; easing.type: Easing.InCubic }
            NumberAnimation { target: panelScale; property: "xScale";  to: 0.05; duration: 200; easing.type: Easing.InCubic }
            NumberAnimation { target: panelScale; property: "yScale";  to: 0.05; duration: 200; easing.type: Easing.InCubic }
        }
        ScriptAction { script: {
            host.expanded = false
            NotificationService._dropClosing()
        } }
    }

    // Stack height (100% units). Toasts animate their own height in / out,
    // so the panel just follows.
    readonly property real openHeight: stack.implicitHeight

    // The pill-overlap row (1px) + the expanded part.
    readonly property real overlap: 1 / uiScale
    // The panel overhangs the clip box's top and side edges by this much so
    // they're clipped crisp instead of anti-aliased against the wallpaper.
    readonly property real bleed: 2

    Item {
        id: maskItem
        x: clipBox.x
        y: clipBox.y
        width:  clipBox.width
        height: host.expanded ? Math.ceil((host.openHeight + host.overlap) * host.uiScale) : 0
    }

    // Box under the pill, exactly its width.
    Item {
        id: clipBox
        x: host.pill.x
        y: host.pill.y + host.pill.height - 1   // 1px over the pill's AA'd last row
        width: host.pill.width
        height: Math.max(0, host.height - y)
        clip: true

        Item {
            id: content
            // 100% layout rendered at uiScale.
            width:  clipBox.width / host.uiScale
            height: clipBox.height / host.uiScale
            scale: host.uiScale
            transformOrigin: Item.TopLeft

            Rectangle {
                id: panel
                x: -host.bleed
                y: -host.bleed
                width:  parent.width + 2 * host.bleed
                height: host.openHeight + host.overlap + host.bleed
                color: host.theme.bg
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius:  Math.min(host.theme.pr, height / 2)
                bottomRightRadius: Math.min(host.theme.pr, height / 2)
                clip: true
                opacity: 0
                transform: Scale {
                    id: panelScale
                    origin.x: panel.width - host.bleed   // the pill's right end
                    origin.y: 0
                    xScale: 0.05
                    yScale: 0.05
                }

                Column {
                    id: stack
                    x: host.bleed
                    y: host.bleed + host.overlap
                    width: content.width

                    Repeater {
                        // Only one presenter owns the toasts (timers + drops):
                        // another bar's closed panel dropped each closing toast
                        // at once, cutting this one's exit animation.
                        model: host.hostActive ? NotificationService.toasts : null

                        delegate: Item {
                            id: toast
                            required property var  notif
                            required property bool closing
                            required property int  index

                            property var info: ({})
                            // Height factor: 0 → 1 when joining an open stack,
                            // 1 → 0 when dismissed while others stay up.
                            property real appear: 1
                            readonly property real fullHeight: body.y + body.implicitHeight

                            width: stack.width
                            height: fullHeight * appear
                            clip: true

                            // ListModel.set() updates `notif` in place: refresh
                            // the content and restart the countdown.
                            onNotifChanged: {
                                const s = NotificationService.snapshot(notif)
                                if (s) info = s
                                if (info.urgency !== 2) dismissTimer.restart()
                            }
                            Component.onCompleted: {
                                info = NotificationService.snapshot(notif) || {}
                                // Joining an open stack: pop out of the right end.
                                if (host.expanded) {
                                    appear = 0
                                    body.opacity = 0
                                    bodyScale.xScale = bodyScale.yScale = 0.05
                                    enterAnim.start()
                                }
                            }
                            // Decide once the service has recounted the open toasts.
                            onClosingChanged: if (closing) Qt.callLater(_close)
                            function _close() {
                                if (!host.expanded)                              NotificationService._dropToastAt(index)
                                else if (NotificationService.openToastCount > 0) { enterAnim.stop(); exitAnim.start() }
                                // else: the panel shrinks into the pill, then drops it.
                            }

                            // Same motion as the panel itself, per toast.
                            ParallelAnimation {
                                id: enterAnim
                                NumberAnimation { target: toast;     property: "appear";  to: 1; duration: 250; easing.type: Easing.OutCubic }
                                NumberAnimation { target: body;      property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
                                NumberAnimation { target: bodyScale; property: "xScale";  to: 1; duration: 250; easing.type: Easing.OutCubic }
                                NumberAnimation { target: bodyScale; property: "yScale";  to: 1; duration: 250; easing.type: Easing.OutCubic }
                            }
                            SequentialAnimation {
                                id: exitAnim
                                ParallelAnimation {
                                    NumberAnimation { target: body;      property: "opacity"; to: 0;    duration: 150; easing.type: Easing.InCubic }
                                    NumberAnimation { target: bodyScale; property: "xScale";  to: 0.05; duration: 200; easing.type: Easing.InCubic }
                                    NumberAnimation { target: bodyScale; property: "yScale";  to: 0.05; duration: 200; easing.type: Easing.InCubic }
                                    NumberAnimation { target: toast;     property: "appear";  to: 0;    duration: 200; easing.type: Easing.InCubic }
                                }
                                ScriptAction { script: NotificationService._dropToastAt(toast.index) }
                            }

                            Timer {
                                id: dismissTimer
                                interval: 5000; repeat: false
                                running: toast.info.urgency !== 2 && !toast.closing
                                onTriggered: NotificationService.closeToastAt(toast.index)
                            }
                            // Divider between stacked toasts.
                            Rectangle {
                                visible: toast.index > 0
                                x: 14; width: parent.width - 28
                                height: 1
                                color: host.theme.sep
                                opacity: 0.7
                            }

                            ToastContent {
                                id: body
                                y: toast.index > 0 ? 1 : 0
                                width: parent.width
                                theme: host.theme
                                info: toast.info
                                transform: Scale {
                                    id: bodyScale
                                    origin.x: body.width        // the panel's right edge
                                    origin.y: 0
                                }
                                onCloseClicked: NotificationService.closeToastAt(toast.index)
                            }
                        }
                    }
                }
            }
        }
    }
}
