import QtQuick
import Quickshell.Services.UPower

// Windows 11-style battery drawn from rectangles: the outline + nub stay
// `color`; only the inner charge bar changes (green while charging, red
// below 15%, yellow/orange in power saver). Every dimension is a whole pixel derived from `size` (body height),
// and the nub height shares the body's parity (body minus an even number)
// so it centres exactly at any size.
Item {
    id: icon

    required property var theme
    property real  size: 12
    property color color: theme.fg

    readonly property real pct: Math.max(0, Math.min(1, UPower.displayDevice?.percentage ?? 0))
    // Actively charging only — full (or plugged in but held, e.g. at a
    // charge limit) goes back to the normal colour. Some batteries keep
    // reporting Charging at 100%, hence the percentage guard.
    readonly property bool charging: UPower.displayDevice?.state === UPowerDeviceState.Charging
                                     && pct < 0.995
    readonly property bool powerSaver: PowerProfiles.profile === PowerProfile.PowerSaver
    readonly property color fillColor: charging   ? theme.green
                                     : pct < 0.15 ? theme.error
                                     : powerSaver ? theme.warn
                                     : color

    readonly property int bodyH:  Math.max(8, Math.round(size))
    readonly property int bodyW:  Math.round(bodyH * 11 / 6)
    readonly property int stroke: Math.max(1, Math.round(bodyH / 12))
    readonly property int gap:    stroke
    readonly property int nubW:   Math.max(2, Math.round(bodyH / 6))
    readonly property int nubH:   bodyH - 2 * Math.round(bodyH / 4)

    implicitWidth:  bodyW + gap + nubW
    implicitHeight: bodyH

    // UPower's first reading arrives just after creation: show it directly
    // rather than animating the fill up from empty.
    property bool _settled: false
    Timer { interval: 1500; running: true; onTriggered: icon._settled = true }

    Rectangle {
        id: body
        width: icon.bodyW; height: icon.bodyH
        radius: Math.round(icon.bodyH / 4)
        color: "transparent"
        border.color: icon.color
        border.width: icon.stroke

        Rectangle {
            readonly property int inset: icon.stroke + icon.gap
            readonly property int track: body.width - inset * 2
            x: inset; y: inset
            height: body.height - inset * 2
            width: icon.pct > 0 ? Math.max(1, Math.round(track * icon.pct)) : 0
            radius: Math.max(1, body.radius - inset)
            color: icon.fillColor
            Behavior on width { enabled: icon._settled; NumberAnimation { duration: 200 } }
            Behavior on color { enabled: icon._settled; ColorAnimation  { duration: 200 } }
        }
    }

    Rectangle {
        x: body.width + icon.gap
        y: (icon.bodyH - icon.nubH) / 2
        width: icon.nubW; height: icon.nubH
        radius: icon.nubW > 2 ? icon.nubW / 2 : 0
        color: icon.color
    }
}
