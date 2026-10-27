import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.common
import qs.modules.appearance
import qs.modules.audio
import qs.modules.battery
import qs.modules.bluetooth
import qs.modules.calendar
import qs.modules.network
import qs.modules.notifications

// Hover popups of the bar's right status pill: one panel attached under the
// pill, drawn inside the bar's own window so it follows the pill's width in
// the same frame (a separate surface lagged behind every resize). Same width,
// flush with the pill's bottom edge (the pill squares its bottom corners
// while this is expanded). Opens/closes like the dashboard; pages sit side
// by side in bar order, so hovering across the pill slides the content.
Item {
    id: host

    // Unscaled design tokens (the popup lays out at 100% and is scaled).
    required property var theme
    // The bar's right status pill this panel hangs from.
    required property Item pill
    // Shell size of this bar's monitor.
    required property real uiScale
    // Only the bar the popups belong to (last hovered monitor) shows them.
    property bool hostActive: false

    // Keyboard only while the Wi-Fi password prompt is up.
    readonly property bool wantsKeyboard: active === "wifi" && wifiPage.ownsPassword
    // Input region for the bar window: the visible panel.
    readonly property alias maskItem: maskItem
    // Bottom edge of the expanded panel (window px), for sizing the bar.
    readonly property real panelBottom: clipBox.y + (openHeight + overlap) * uiScale

    visible: expanded

    // Same order as the pill's modules, left → right.
    readonly property var order: ["bluetooth", "sink", "battery", "wifi", "clock", "notif"]
    readonly property string active: !host.hostActive ? "" :
          PopupService.bluetoothPopupOpen                                               ? "bluetooth"
        : PopupService.sinkPopupOpen && AudioService.sinkList.length > 0                ? "sink"
        : PopupService.batteryPopupOpen && (UPower.displayDevice?.isPresent ?? false)  ? "battery"
        : PopupService.wifiPopupOpen || wifiPage.ownsPassword                           ? "wifi"
        : PopupService.clockPopupOpen                                                   ? "clock"
        : PopupService.notifPopupOpen                                                   ? "notif"
        : ""
    // Page on display — kept while closing so the content doesn't vanish.
    property string shown: ""
    // On screen: from the start of the enter animation to the end of the
    // exit animation.
    property bool expanded: false
    // Page changes on an expanded panel slide (and resize); a fresh open
    // jumps to its page and plays the enter animation.
    property bool slide: false
    onActiveChanged: {
        if (active) {
            slide = expanded
            if (!expanded) {
                panel.opacity = 0
                panelScale.xScale = panelScale.yScale = 0.05
            }
            shown = active
            expanded = true
            // Switching modules passes through "" for an instant (showPopup
            // closes the old flag before opening the new one), which starts
            // the exit — always cancel it, then finish opening if needed.
            exitAnim.stop()
            if (!enterAnim.running && (panelScale.xScale < 1 || panel.opacity < 1))
                enterAnim.restart()
        } else {
            enterAnim.stop()
            exitAnim.restart()
        }
    }
    readonly property int index: Math.max(0, order.indexOf(shown))
    readonly property Item page: strip.children[index] ?? null

    // Shown page's height (100% units); animated only when sliding.
    property real openHeight: page?.implicitHeight ?? 0
    Behavior on openHeight {
        enabled: host.slide
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    // Same open/close as the dashboard: fade + scale up from 5% around the
    // top centre, i.e. out of the pill; the reverse shrinks back into it.
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
            host.expanded = false; host.slide = false
            // A hidden panel can't be hovered; don't let a missed leave
            // keep holding future popups open.
            if (host.hostActive) PopupService.panelHovered = false
        } }
    }

    Binding {
        target: PopupService; property: "rightPopupProgress"
        when: host.hostActive
        value: host.expanded ? Math.max(0, Math.min(1, (panelScale.xScale - 0.05) / 0.95)) : 0
    }

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
        height: host.expanded && host.active ? Math.ceil((host.openHeight + host.overlap) * host.uiScale) : 0
    }

    // Box under the pill, exactly its width; clipping keeps the panel's
    // overhanging (bleed) edges crisp.
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
                    origin.x: panel.width / 2
                    origin.y: 0
                    xScale: 0.05
                    yScale: 0.05
                }

                // Geometry-based hover — unaffected by nested MouseAreas.
                HoverHandler {
                    onHoveredChanged: PopupService.setPanelHovered(hovered)
                }

                Row {
                    id: strip
                    x: host.bleed - host.index * content.width
                    y: host.bleed + host.overlap
                    Behavior on x {
                        enabled: host.slide
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    BluetoothPopup    { id: bt;       theme: host.theme; width: content.width }
                    SinkPopup         { id: sink;     theme: host.theme; width: content.width }
                    BatteryPopup      { id: battery;  theme: host.theme; width: content.width }
                    WifiPopup         { id: wifiPage; theme: host.theme; width: content.width }
                    CalendarPopup     { id: calendar; theme: host.theme; width: content.width }
                    NotificationPopup { id: notif;    theme: host.theme; width: content.width }
                }
            }
        }
    }
}
