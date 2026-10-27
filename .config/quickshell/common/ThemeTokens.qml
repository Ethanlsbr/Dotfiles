import QtQuick
import qs.modules.appearance

// Shared design tokens (palette + spacing), passed to every component as
// `theme:`. Instantiated in shell.qml: one shared instance for overlays and
// settings, plus one per bar (with monitorName) for per-monitor shell size.
// Theme id + per-monitor scale come from AppearanceService.
// All colours are bindings, so the whole shell recolours live.
QtObject {
    id: theme

    // Full colour roles per theme id. Keep ids in sync with AppearanceService
    // themePalettes (the picker-card preview subset).
    readonly property var _palettes: ({
        tokyonight: {
            light: false, bg: "#1A1B26", fg: "#C0CAF5", sep: "#3B4261",
            active: "#3B4261", primary: "#7AA2F7", secondary: "#BB9AF7",
            tertiary: "#9ECE6A", warn: "#E0AF68", error: "#F7768E",
            surface: "#24283B", surface2: "#414868", txt2: "#A9B1D6",
            outline: "#565F89"
        },
        light: {
            light: true, bg: "#E8EAEE", fg: "#474A5C", sep: "#CDD1D9",
            active: "#D5DBE6", primary: "#4A6FA8", secondary: "#9A6A99",
            tertiary: "#5A8A4A", warn: "#C07A3E", error: "#B84A5A",
            surface: "#E0E3E9", surface2: "#D6DAE2", txt2: "#5C5F77",
            outline: "#8C8FA1"
        },
        catppuccin: {
            light: false, bg: "#1E1E2E", fg: "#CDD6F4", sep: "#45475A",
            active: "#45475A", primary: "#89B4FA", secondary: "#F5C2E7",
            tertiary: "#A6E3A1", warn: "#FAB387", error: "#F38BA8",
            surface: "#313244", surface2: "#585B70", txt2: "#BAC2DE",
            outline: "#6C7086"
        },
        onedark: {
            light: false, bg: "#282C34", fg: "#ABB2BF", sep: "#3E4451",
            active: "#3E4451", primary: "#61AFEF", secondary: "#C678DD",
            tertiary: "#98C379", warn: "#D19A66", error: "#E06C75",
            surface: "#31353F", surface2: "#3E4451", txt2: "#B6BDCA",
            outline: "#5C6370"
        },
        everforest: {
            light: false, bg: "#2D353B", fg: "#D3C6AA", sep: "#475258",
            active: "#475258", primary: "#7FBBB3", secondary: "#D699B6",
            tertiary: "#A7C080", warn: "#E69875", error: "#E67E80",
            surface: "#343F44", surface2: "#475258", txt2: "#D3C6AA",
            outline: "#859289"
        },
        gruvbox: {
            light: false, bg: "#282828", fg: "#EBDBB2", sep: "#504945",
            active: "#504945", primary: "#83A598", secondary: "#D3869B",
            tertiary: "#B8BB26", warn: "#FE8019", error: "#FB4934",
            surface: "#3C3836", surface2: "#504945", txt2: "#D5C4A1",
            outline: "#928374"
        },
        nord: {
            light: false, bg: "#2E3440", fg: "#ECEFF4", sep: "#434C5E",
            active: "#434C5E", primary: "#88C0D0", secondary: "#B48EAD",
            tertiary: "#A3BE8C", warn: "#D08770", error: "#BF616A",
            surface: "#3B4252", surface2: "#434C5E", txt2: "#D8DEE9",
            outline: "#616E88"
        },
        // Rosé Pine (main): base / surface / highlight-med & -high / text /
        // subtle / muted, accents iris, rose, foam, gold, love.
        rosepine: {
            light: false, bg: "#191724", fg: "#E0DEF4", sep: "#403D52",
            active: "#403D52", primary: "#C4A7E7", secondary: "#EBBCBA",
            tertiary: "#9CCFD8", warn: "#F6C177", error: "#EB6F92",
            surface: "#1F1D2E", surface2: "#524F67", txt2: "#908CAA",
            outline: "#6E6A86"
        }
    })
    readonly property var _p: _palettes[AppearanceService.themeName] ?? _palettes.tokyonight

    readonly property bool   light:     _p.light
    readonly property color  bg:        _p.bg
    readonly property color  fg:        _p.fg
    readonly property color  sep:       _p.sep
    readonly property color  active:    _p.active
    readonly property color  green:     "#1ed760"
    readonly property color  primary:   _p.primary
    readonly property color  secondary: _p.secondary
    readonly property color  tertiary:  _p.tertiary
    readonly property color  warn:      _p.warn
    readonly property color  error:     _p.error
    readonly property color  surface:   _p.surface
    readonly property color  surface2:  _p.surface2
    // Field/track background: near-white on light so dark text stays legible.
    // Card/field fill on light: off-white, pure white glares against bg.
    readonly property color  paper:     "#F5F6F8"
    readonly property color  field:     light ? paper : Qt.darker(bg, 1.3)
    // Recessed panel (settings sidebar) and key-hint chip. Darkening the
    // bg reads as depth on dark themes but turns muddy grey on light.
    readonly property color  inset:     light ? surface : Qt.darker(bg, 1.25)
    readonly property color  chip:      light ? paper : Qt.darker(bg, 1.2)
    readonly property color  txt2:      _p.txt2
    readonly property color  outline:   _p.outline
    // Monitor whose shell-size setting `scale` follows ("" → first screen).
    // Set per bar in shell.qml; overlay windows derive their own uiScale.
    property string monitorName: ""
    // Bars lay out in final pixels, so their instances scale the size tokens
    // below. The shared instance keeps tokens at 100% — overlays scale their
    // whole content via a render transform instead.
    property bool scaleTokens: false
    readonly property real   scale:     AppearanceService.scaleFor(monitorName)
    readonly property real   _t:        scaleTokens ? scale : 1
    readonly property string ff:        "CaskaydiaCove Nerd Font Propo"
    readonly property int    fs:        Math.round(14 * _t)
    readonly property int    ph:        Math.round(30 * _t)
    readonly property int    pr:        Math.round(15 * _t)

    // Scale a pixel size by the shell size (token mode only).
    function sc(px) { return Math.round(px * _t) }

    // Hover/selected/accent tint derived from `active`: lighter on dark,
    // darker on light (lightening a pale colour trends to white). Larger
    // f ⇒ more prominent. Light steps are gentler — darkening a pastel by
    // the full factor lands on heavy grey.
    function hi(f) { return light ? Qt.darker(active, 1 + (f - 1) * 0.35) : Qt.lighter(active, f) }

    // Raise a fill for hover/highlight: lighter on dark, slightly darker on
    // light (lightening a light surface just washes it out to white).
    function lift(c, f) { return light ? Qt.darker(c, 1 + (f - 1) * 0.4) : Qt.lighter(c, f) }
}
