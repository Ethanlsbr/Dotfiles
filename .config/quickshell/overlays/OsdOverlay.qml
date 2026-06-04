import QtQuick
import Quickshell

// GNOME-style on-screen display, centred near the bottom of the screen.
// Shows volume / brightness as an icon + bar, and media as an icon + track
// text. Driven by shellRoot.osd* (set when a volume/brightness/media event
// arrives); auto-hides. These replace the notifications for those events.
PanelWindow {
    id: osd

    required property var shellRoot
    required property var theme

    readonly property bool   _open: shellRoot.osdVisible
    readonly property string kind:  shellRoot.osdKind
    readonly property bool   isBar: kind === "audio" || kind === "brightness"

    visible: _open || exitAnim.running

    anchors { bottom: true }      // bottom + no left/right ⇒ horizontally centred
    margins.bottom: 90
    exclusiveZone: 0
    color: "transparent"

    // Fixed width so the centred layer-shell surface never resizes — and thus
    // never re-centres horizontally — when the pill's content width changes.
    // That re-centring was the sideways "glitch" on apparition; the pill itself
    // stays content-sized and centred within this stable window.
    implicitWidth:  460
    implicitHeight: pill.height + 40

    // Keep only the pill interactive; the transparent margins around it stay
    // click-through.
    mask: Region { item: pill }

    // Battery is "low" when discharging at/under the 15% warning threshold —
    // drives a warning-coloured icon + glyph instead of the neutral one.
    readonly property bool batteryLow: kind === "battery" && !shellRoot.osdCharging
                                       && shellRoot.osdValue > 0 && shellRoot.osdValue <= 15

    function _icon() {
        if (kind === "brightness") return "󰃟"
        if (kind === "media")      return "󰝚"
        if (kind === "battery") {
            if (shellRoot.osdCharging) return "󰂄"
            const v = shellRoot.osdValue
            if (v <= 0)  return "󰁹"   // unknown / charge-state event (no level)
            if (v <= 5)  return "󰂃"   // battery alert
            if (v <= 10) return "󰁺"   // ~10%
            if (v <= 15) return "󰁻"   // ~20%
            return "󰁹"
        }
        if (shellRoot.osdMuted)    return "󰝟"
        const v = shellRoot.osdValue
        return v < 33 ? "󰕿" : v < 67 ? "󰖀" : "󰕾"
    }

    // Stop the opposing animation before (re)starting, so a quick hide→show
    // (e.g. rapid track-skips) can't leave enter+exit both driving opacity/y.
    on_OpenChanged: {
        if (_open) { exitAnim.stop();  enterAnim.restart() }
        else       { enterAnim.stop(); exitAnim.restart() }
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: pill;  property: "opacity"; from: 0;  to: 1; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: slide; property: "y";       from: 16; to: 0; duration: 220; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: pill;  property: "opacity"; to: 0;  duration: 200; easing.type: Easing.InCubic }
        NumberAnimation { target: slide; property: "y";       to: 16; duration: 200; easing.type: Easing.InCubic }
    }

    Rectangle {
        id: pill
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 20 }
        width:  osd.isBar ? 280 : Math.min(420, mediaRow.implicitWidth + 44)
        height: 46
        radius: 13
        color: osd.theme.bg
        border.color: osd.theme.sep
        border.width: 1
        opacity: 0
        transform: Translate { id: slide; y: 16 }

        // ── Volume / brightness: icon + bar + value ──────────────────────
        Row {
            visible: osd.isBar
            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
            spacing: 12

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                horizontalAlignment: Text.AlignHCenter
                text: osd._icon()
                color: osd.shellRoot.osdMuted ? osd.theme.outline : osd.theme.fg
                font.family: osd.theme.ff
                font.pixelSize: osd.theme.fs + 4
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 22 - 12 - 42 - 12
                height: 6; radius: 3
                color: osd.theme.field
                Rectangle {
                    height: parent.height; radius: parent.radius
                    width: parent.width * (osd.shellRoot.osdValue / 100)
                    color: osd.shellRoot.osdMuted ? osd.theme.outline : osd.theme.primary
                    Behavior on width { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 42
                horizontalAlignment: Text.AlignRight
                text: osd.shellRoot.osdMuted ? "Mute" : osd.shellRoot.osdValue + "%"
                color: osd.theme.fg
                font.family: osd.theme.ff
                font.pixelSize: osd.theme.fs - 1
            }
        }

        // ── Media: icon + track text ─────────────────────────────────────
        Row {
            id: mediaRow
            visible: !osd.isBar
            anchors.centerIn: parent
            spacing: 12

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: osd._icon()
                color: osd.batteryLow ? osd.theme.error : osd.theme.primary
                font.family: osd.theme.ff
                font.pixelSize: osd.theme.fs + 4
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: osd.shellRoot.osdText || "Media"
                color: osd.theme.fg
                font.family: osd.theme.ff
                font.pixelSize: osd.theme.fs - 1
                font.bold: true
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 340)
            }
        }
    }
}
