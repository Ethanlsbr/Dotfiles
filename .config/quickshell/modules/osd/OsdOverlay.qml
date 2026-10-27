import QtQuick
import Quickshell
import qs.modules.appearance
import qs.common

// Bottom-centred OSD: volume / brightness as icon + bar, media as icon +
// track text. Driven by OsdService; auto-hides; replaces those notifs.
PanelWindow {
    id: osd

    required property var theme
    // Shell-size scale of this window's monitor (unset monitors = 100%).
    readonly property real uiScale: AppearanceService.scaleFor(screen?.name ?? "")

    readonly property bool   _open: OsdService.osdVisible
    readonly property string kind:  OsdService.osdKind
    readonly property bool   isBar: kind === "audio" || kind === "brightness"

    visible: pop.shown

    anchors { bottom: true }      // bottom + no left/right ⇒ horizontally centred
    margins.bottom: Math.round(90 * uiScale)
    exclusiveZone: 0
    color: "transparent"

    // Fixed width: a content-sized layer surface would re-centre (sideways
    // glitch) whenever the pill width changed.
    implicitWidth:  460 * uiScale
    implicitHeight: (pill.height + 40) * uiScale

    // Only the pill is interactive; margins stay click-through.
    mask: Region { item: pill }

    // Discharging at ≤15% → warning-coloured icon + glyph.
    readonly property bool batteryLow: kind === "battery" && !OsdService.osdCharging
                                       && OsdService.osdValue > 0 && OsdService.osdValue <= 15

    function _icon() {
        if (kind === "brightness") return "󰃟"
        if (kind === "media")      return "󰝚"
        if (kind === "battery") {
            if (OsdService.osdCharging) return "󰂄"
            const v = OsdService.osdValue
            if (v <= 0)  return "󰁹"   // unknown / charge-state event (no level)
            if (v <= 5)  return "󰂃"   // battery alert
            if (v <= 10) return "󰁺"   // ~10%
            if (v <= 15) return "󰁻"   // ~20%
            return "󰁹"
        }
        if (OsdService.osdMuted)    return "󰝟"
        const v = OsdService.osdValue
        return v < 33 ? "󰕿" : v < 67 ? "󰖀" : "󰕾"
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
        // uiScale transform from the bottom anchor; composes with the pop.
        scale: osd.uiScale
        transformOrigin: Item.Bottom
        // Shared open/close motion, growing up from the bottom centre.
        transform: PopAnim { id: pop; item: pill; open: osd._open; origin.x: pill.width / 2; origin.y: pill.height }

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
                color: OsdService.osdMuted ? osd.theme.outline : osd.theme.fg
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
                    width: parent.width * (OsdService.osdValue / 100)
                    color: OsdService.osdMuted ? osd.theme.outline : osd.theme.primary
                    Behavior on width { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 42
                horizontalAlignment: Text.AlignRight
                text: OsdService.osdMuted ? "Mute" : OsdService.osdValue + "%"
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
                text: OsdService.osdText || "Media"
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
