import QtQuick

// The shell's shared open/close motion (first used by the dashboard): fade
// in over 200 ms while scaling from 5% to full size over 250 ms (OutCubic)
// around `origin`; closing reverses it (150 / 200 ms, InCubic). A fresh
// open starts small; reopening mid-close reverses from the current size.
//
// Use it as the animated item's transform, with the origin on the edge the
// surface grows out of, and map the window while it's `shown`:
//     visible: pop.shown
//     transform: PopAnim { id: pop; item: card; open: overlay._open
//                          origin.x: card.width / 2; origin.y: 0 }
// `shown` is set imperatively (true on open, false only once the close has
// finished); `open || closing` would read false for an instant between the
// two and unmap/remap the window — a visible flicker.
Scale {
    id: pop

    // Item whose opacity fades with the scale (usually the transformed one).
    required property Item item
    property bool open: false
    property bool shown: false

    xScale: 0.05
    yScale: 0.05

    onOpenChanged: {
        if (open) {
            shown = true
            if (!exitAnim.running) {
                item.opacity = 0
                xScale = yScale = 0.05
            }
            exitAnim.stop()
            enterAnim.restart()
        } else {
            enterAnim.stop()
            exitAnim.restart()
        }
    }

    readonly property Animation enterAnim: ParallelAnimation {
        NumberAnimation { target: pop.item; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { target: pop;      property: "xScale";  to: 1; duration: 250; easing.type: Easing.OutCubic }
        NumberAnimation { target: pop;      property: "yScale";  to: 1; duration: 250; easing.type: Easing.OutCubic }
    }
    readonly property Animation exitAnim: SequentialAnimation {
        ParallelAnimation {
            NumberAnimation { target: pop.item; property: "opacity"; to: 0;    duration: 150; easing.type: Easing.InCubic }
            NumberAnimation { target: pop;      property: "xScale";  to: 0.05; duration: 200; easing.type: Easing.InCubic }
            NumberAnimation { target: pop;      property: "yScale";  to: 0.05; duration: 200; easing.type: Easing.InCubic }
        }
        // Only reached if not interrupted by a reopen.
        ScriptAction { script: pop.shown = false }
    }
}
