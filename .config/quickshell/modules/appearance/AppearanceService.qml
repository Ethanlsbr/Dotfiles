pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Shell theme (state/theme.txt) and per-monitor shell size
// (state/shell-scale.txt). Full colour roles live in common/ThemeTokens.qml.
Singleton {
    id: root

    // ── Theme ────────────────────────────────────────────────────────────
    // Canonical theme ids + preview colours for the picker cards.
    readonly property var themePalettes: [
        { id: "tokyonight", name: "Tokyonight",
          bg: "#1A1B26", fg: "#C0CAF5", surface: "#24283B",
          primary: "#7AA2F7", secondary: "#BB9AF7", tertiary: "#9ECE6A" },
        { id: "light", name: "Light",
          bg: "#E8EAEE", fg: "#474A5C", surface: "#E0E3E9",
          primary: "#4A6FA8", secondary: "#9A6A99", tertiary: "#5A8A4A" },
        { id: "catppuccin", name: "Catppuccin",
          bg: "#1E1E2E", fg: "#CDD6F4", surface: "#313244",
          primary: "#89B4FA", secondary: "#F5C2E7", tertiary: "#A6E3A1" },
        { id: "onedark", name: "One Dark",
          bg: "#282C34", fg: "#ABB2BF", surface: "#31353F",
          primary: "#61AFEF", secondary: "#C678DD", tertiary: "#98C379" },
        { id: "everforest", name: "Everforest",
          bg: "#2D353B", fg: "#D3C6AA", surface: "#343F44",
          primary: "#7FBBB3", secondary: "#D699B6", tertiary: "#A7C080" },
        { id: "gruvbox", name: "Gruvbox",
          bg: "#282828", fg: "#EBDBB2", surface: "#3C3836",
          primary: "#83A598", secondary: "#D3869B", tertiary: "#B8BB26" },
        { id: "nord", name: "Nord",
          bg: "#2E3440", fg: "#ECEFF4", surface: "#3B4252",
          primary: "#88C0D0", secondary: "#B48EAD", tertiary: "#A3BE8C" },
        { id: "rosepine", name: "Rosé Pine",
          bg: "#191724", fg: "#E0DEF4", surface: "#1F1D2E",
          primary: "#C4A7E7", secondary: "#EBBCBA", tertiary: "#9CCFD8" }
    ]
    property string themeName: "tokyonight"
    property bool   themeOpen: false
    function openTheme()  { themeOpen = true }
    function closeTheme() { themeOpen = false }
    function setTheme(name) {
        if (name === "dark") name = "tokyonight"   // pre-rename theme.txt / IPC
        if (!root.themePalettes.some(p => p.id === name)) return
        root.themeName = name
        themeFile.save(name)
    }
    StateFile {
        id: themeFile
        name: "theme.txt"
        onLoaded: lines => {
            for (const line of lines) {
                const t = line.trim() === "dark" ? "tokyonight" : line.trim()
                if (root.themePalettes.some(p => p.id === t)) root.themeName = t
            }
        }
    }
    IpcHandler {
        target: "theme"
        function toggle() { root.themeOpen = !root.themeOpen }
        function open()   { root.openTheme()  }
        function close()  { root.closeTheme() }
        function set(name: string) { root.setTheme(name) }
    }

    // ── Shell size (UI scale) per monitor ────────────────────────────────
    // monitorScales: name → scale; missing (incl. new) monitors = 1.0.
    // Bars bind their own tokens; overlays follow the screen they're on.
    // File format: one "name scale" per line.
    readonly property var shellScaleOptions: [0.5, 0.75, 1.0, 1.25, 1.5]
    property var monitorScales: ({})
    function scaleFor(name) {
        if (!name) {
            const screens = Quickshell.screens
            name = screens.length > 0 ? screens[0].name : ""
        }
        const v = monitorScales[name]
        return root.shellScaleOptions.indexOf(v) >= 0 ? v : 1.0
    }
    function setMonitorScale(name, scale) {
        const v = Number(scale)
        if (!name || root.shellScaleOptions.indexOf(v) < 0) return
        const m = {}
        for (const k in root.monitorScales) m[k] = root.monitorScales[k]
        m[name] = v
        root.monitorScales = m
        const lines = []
        for (const k in m) lines.push(k + " " + m[k])
        shellScaleFile.save(lines.join("\n"))
    }
    StateFile {
        id: shellScaleFile
        name: "shell-scale.txt"
        onLoaded: lines => {
            const m = {}
            for (const line of lines) {
                const parts = line.trim().split(/\s+/)
                if (parts.length !== 2) continue
                const v = parseFloat(parts[1])
                if (root.shellScaleOptions.indexOf(v) >= 0) m[parts[0]] = v
            }
            root.monitorScales = m
        }
    }
    // External control: `qs ipc call shellscale set eDP-1 1.25`
    IpcHandler {
        target: "shellscale"
        function set(monitor: string, value: string) { root.setMonitorScale(monitor, parseFloat(value)) }
    }

    // ── Bar: monitors and elements ───────────────────────────────────────
    // Kept here (not in BarService) so the Appearance pane can use them
    // without importing qs.modules.bar, whose import chain leads back to
    // the settings window. BarService forwards to these.

    // Names of monitors where the bar is hidden (default = shown).
    property var barDisabledMonitors: []
    function barEnabledOn(name) { return !!name && barDisabledMonitors.indexOf(name) < 0 }
    function setBarOnMonitor(name, enabled) {
        if (!name) return
        const s = barDisabledMonitors.slice()
        const i = s.indexOf(name)
        if (enabled && i >= 0)      s.splice(i, 1)
        else if (!enabled && i < 0) s.push(name)
        else return
        root.barDisabledMonitors = s
        barMonitorsFile.save(s.join("\n"))
    }
    StateFile {
        id: barMonitorsFile
        name: "bar-monitors.txt"
        onLoaded: lines => root.barDisabledMonitors = lines.map(l => l.trim()).filter(l => l)
    }

    // Bar elements in bar order; `key` is what Bar.qml checks.
    readonly property var barModules: [
        { key: "launcher",   side: "Left",   label: "Launcher button", icon: "\uf303",
          description: "Arch logo; click to open the app launcher" },
        { key: "workspaces", side: "Left",   label: "Workspaces",      icon: "\uf24d",
          description: "This monitor's workspaces; click one to switch" },
        { key: "media",      side: "Center", label: "Now playing",     icon: "\uf1bc",
          description: "Current track while something plays; click to pause, scroll to skip" },
        { key: "bluetooth",  side: "Right",  label: "Bluetooth",       icon: "\uf294",
          description: "Connected device count; hover for devices" },
        { key: "volume",     side: "Right",  label: "Volume",          icon: "\uf028",
          description: "Output volume; scroll to change, hover for outputs" },
        { key: "battery",    side: "Right",  label: "Battery",         icon: "\uf240",
          description: "Charge level; hover for power details" },
        { key: "network",    side: "Right",  label: "Network",         icon: "\uf1eb",
          description: "Connection status; hover for Wi-Fi networks" },
        { key: "clock",      side: "Right",  label: "Clock",           icon: "\uf017",
          description: "Date and time; hover for the calendar" },
        { key: "notifs",     side: "Right",  label: "Notifications",   icon: "\uf0f3",
          description: "Notification bell; hover or click for the list" }
    ]
    // Keys of hidden elements (default = everything shown).
    property var barHiddenModules: []
    function barModuleShown(key) { return barHiddenModules.indexOf(key) < 0 }
    function setBarModuleShown(key, on) {
        const s = barHiddenModules.filter(k => k !== key)
        if (!on) s.push(key)
        root.barHiddenModules = s
        barModulesFile.save(s.join("\n"))
    }
    StateFile {
        id: barModulesFile
        name: "bar-modules.txt"
        onLoaded: lines => root.barHiddenModules = lines.map(l => l.trim()).filter(l => l)
    }
}
