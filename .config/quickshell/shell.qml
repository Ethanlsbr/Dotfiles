import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Notifications
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "./bar"
import "./overlays"
import "./settings"

ShellRoot {
    id: root

    // ── Paths ───────────────────────────────────────────────────────────────
    // Resolved at runtime so the config works for any user, not just one
    // hard-coded $HOME. configDir points at this quickshell config directory
    // (derived from where shell.qml lives).
    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string configDir:
        Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")

    // ── State ──────────────────────────────────────────────────────────────
    property string mediaText:  ""
    property string netIcon:    "󰌙"
    // Bell icon reflects whether any notification is pending (set below by
    // the NotificationServer's tracked list).
    property string notifIcon:  dndEnabled
                                ? "󰂛"
                                : (notifServer.trackedNotifications.values.length > 0 ? "󰵙" : "󰂚")
    // Exposed so overlays can read the tracked notification list.
    readonly property alias notifServer: notifServer
    property int    volPct:      -1
    property bool   volMuted:    false
    property int    brightnessPct: -1
    property bool   dndEnabled:  false
    property bool   sinkPopupOpen:    false
    property var    sinkList:         []
    property var    _sinkBuffer:      []
    property var    sourceList:       []
    property var    _sourceBuffer:    []
    property bool   batteryPopupOpen: false
    property bool   bluetoothPopupOpen: false
    property bool   wifiPopupOpen:    false
    property bool   clockPopupOpen:   false
    property bool   notifPopupOpen:   false
    property var    wifiList:         []
    property var    _wifiBuffer:      []
    property var    wifiSaved:        []   // SSIDs with a saved nmcli profile
    property var    _wifiSavedBuffer: []
    property bool   wifiEnabled:      true
    property bool   wifiScanning:     false
    property bool   wifiPasswordOpen: false
    property string wifiPasswordSsid: ""
    property string wifiPasswordError: ""
    property bool   wifiConnecting:   false
    // Which UI triggered the password prompt — "overlay" or "settings".
    // Used so only the originating pane shows the password section.
    property string wifiPasswordSource: ""
    // True when the pending prompt is for a WPA-Enterprise (802.1X) network —
    // the settings pane then shows the extra identity / EAP-method fields.
    property bool   wifiPasswordEnterprise: false

    // ── Settings window state ─────────────────────────────────────────────
    property string settingsPane: "wifi"
    property bool   settingsOpen: false

    // ── Monitors (hyprctl) ────────────────────────────────────────────────
    // List of { name, description, width, height, refresh, x, y, scale,
    // disabled, modes:[ "WxH@R", ... ] } parsed from `hyprctl monitors -j`.
    property var monitorList: []
    function refreshMonitors() {
        monitorQueryProc.running = false
        monitorQueryProc.running = true
    }
    // cfgs: [{ output, mode, x, y, scale, disabled }] → write the dedicated
    // monitor_quickshell.lua + hyprctl reload (see scripts/apply-monitors.py).
    function applyMonitors(cfgs) {
        monitorApplyProc.cfgsJson = JSON.stringify(cfgs)
        monitorApplyProc.running = false
        monitorApplyProc.running = true
    }

    // ── Dashboard state ───────────────────────────────────────────────────
    property bool dashboardOpen: false
    property int  dashboardTab:  0  // 0=Dashboard 1=Media 2=Performance 3=Weather

    // ── App launcher state ───────────────────────────────────────────────
    property bool launcherOpen: false
    // When true the launcher runs the picked app with DRI_PRIME=1 (dedicated
    // GPU). It's the same launcher UI in a different mode (see openGpuLauncher).
    property bool launcherGpuMode: false
    function toggleLauncher() {
        if (launcherOpen && !launcherGpuMode) launcherOpen = false
        else                                  openLauncher()
    }
    function openLauncher()    { launcherGpuMode = false; captureThenOpen("launcher") }
    function closeLauncher()   { launcherOpen = false }
    // GPU launcher — same menu, launches on the dedicated GPU.
    function openGpuLauncher() { launcherGpuMode = true;  captureThenOpen("launcher") }
    function toggleGpuLauncher() {
        if (launcherOpen && launcherGpuMode) launcherOpen = false
        else                                 openGpuLauncher()
    }

    // Address of the toplevel window that was focused just before any of our
    // keyboard-grabbing overlays opened. Captured synchronously-by-process so
    // we can refocus that exact window on close. `last` won't work because
    // Hyprland keeps tracking toplevels independently of layer-surface focus,
    // so a layer-surface open doesn't bump the toplevel into "last" — it'd
    // still point at whatever window came before the currently-active one.
    property string lastFocusedAddr: ""
    property string _pendingOverlay: ""

    function captureThenOpen(which) {
        _pendingOverlay = which
        captureActiveProc.running = false
        captureActiveProc.running = true
    }
    function refocusLastWindow() {
        if (lastFocusedAddr) refocusDelay.restart()
    }
    onLauncherOpenChanged: if (!launcherOpen) refocusLastWindow()

    // External control: `qs ipc call launcher toggle|open|close`
    IpcHandler {
        target: "launcher"
        function toggle() { root.toggleLauncher() }
        function open()   { root.openLauncher()   }
        function close()  { root.closeLauncher()  }
    }

    // GPU launcher: `qs ipc call gpulauncher toggle|open|close`
    IpcHandler {
        target: "gpulauncher"
        function toggle() { root.toggleGpuLauncher() }
        function open()   { root.openGpuLauncher()  }
        function close()  { root.closeLauncher()    }
    }

    // ── Bar visibility ───────────────────────────────────────────────────
    // Hide/show just the top bar (its layer surface + exclusive zone).
    // External control: `qs ipc call bar toggle|show|hide`
    property bool barVisible: true
    // Width of the right-side status pills, published by the bar(s) so the
    // right-anchored popups can align to it.
    property real rightPillWidth: 220
    // Exposed so the per-monitor bars (instantiated under Variants, where the
    // `theme` id is shadowed by Bar's own `theme` property) can reach it.
    readonly property alias themeRef: theme
    IpcHandler {
        target: "bar"
        function toggle() { root.barVisible = !root.barVisible }
        function show()   { root.barVisible = true  }
        function hide()   { root.barVisible = false }
    }

    // ── Per-monitor bar enable (persisted to bar-monitors.txt) ───────────
    // Holds the names of monitors where the bar is HIDDEN (default = shown).
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
        barMonitorsSaveProc.data = s.join("\n")
        barMonitorsSaveProc.running = false
        barMonitorsSaveProc.running = true
    }
    Process {
        id: barMonitorsLoadProc
        running: true
        command: ["sh", "-c", "cat \"$FILE\" 2>/dev/null || true"]
        environment: ({ FILE: root.configDir + "/bar-monitors.txt" })
        property var _buf: []
        onRunningChanged: if (running) _buf = []
        stdout: SplitParser { onRead: line => { const s = line.trim(); if (s) barMonitorsLoadProc._buf.push(s) } }
        onExited: root.barDisabledMonitors = barMonitorsLoadProc._buf.slice()
    }
    Process {
        id: barMonitorsSaveProc
        property string data: ""
        environment: ({ DATA: data, FILE: root.configDir + "/bar-monitors.txt" })
        command: ["sh", "-c", "printf '%s' \"$DATA\" > \"$FILE\""]
    }

    // External control: `qs ipc call notifications toggle|open|close`
    IpcHandler {
        target: "notifications"
        function toggle() {
            if (root.notifPopupOpen) root.notifPopupOpen = false
            else                     root.showPopup("notif")
        }
        function open()   { root.showPopup("notif")     }
        function close()  { root.notifPopupOpen = false }
    }

    // ── Wallpaper picker state ───────────────────────────────────────────
    readonly property string wallpaperFolder: root.homeDir + "/Pictures/wallpaper"
    property bool wallpaperPickerOpen: false

    // All wallpapers, ordered by file modification time (most recently added
    // first). Shared by both the settings pane and the bottom-bar picker.
    // Populated by recentWallpapersProc.
    property var  recentWallpapers:    []
    property var  _recentBuffer:       []

    // Thumbnail cache so the settings grid loads small JPEGs instead of
    // decoding multi-MB originals per cell. thumbForWallpaper() maps a source
    // path to its cached thumb; wallpaperThumbTick bumps as generation
    // progresses so views can retry loading thumbs that weren't ready yet.
    readonly property string wallpaperThumbDir: root.homeDir + "/.cache/quickshell/wallpaper-thumbs"
    property int  wallpaperThumbTick: 0
    readonly property bool wallpaperThumbBusy: wallpaperThumbProc.running
    function thumbForWallpaper(path) {
        if (!path) return ""
        return "file://" + wallpaperThumbDir + "/" + path.split("/").pop() + ".jpg"
    }

    function openWallpaperPicker()  { captureThenOpen("wallpaper") }
    function closeWallpaperPicker() { wallpaperPickerOpen = false }
    onWallpaperPickerOpenChanged: if (!wallpaperPickerOpen) refocusLastWindow()
    function refreshWallpapers() {
        // Wallpaper list, ordered by modification time (most recently added first).
        recentWallpapersProc.running = false
        recentWallpapersProc.running = true
        // (Re)generate any missing/stale thumbnails in the background.
        wallpaperThumbProc.running = false
        wallpaperThumbProc.running = true
    }
    function setWallpaper(path) {
        setWallpaperProc.target = path
        setWallpaperProc.running = false
        setWallpaperProc.running = true
    }

    // ── Clipboard history (cliphist) ─────────────────────────────────────
    // Entries are { id: "107", preview: "margins.top" } pairs parsed from
    // `cliphist list` (tab-separated). Copying back uses `cliphist decode
    // <id> | wl-copy` so the original bytes are restored, not the preview.
    property bool clipboardOpen:     false
    property var  clipboardList:     []
    property var  _clipboardBuffer:  []

    function openClipboard()  { captureThenOpen("clipboard") }
    function closeClipboard() { clipboardOpen = false }
    onClipboardOpenChanged: if (!clipboardOpen) refocusLastWindow()
    function refreshClipboard() {
        clipboardListProc.running = false
        clipboardListProc.running = true
    }
    function copyClipboardEntry(id) {
        copyClipboardProc.target = id
        copyClipboardProc.running = false
        copyClipboardProc.running = true
    }
    function deleteClipboardEntry(id) {
        deleteClipboardProc.target = id
        deleteClipboardProc.running = false
        deleteClipboardProc.running = true
    }

    // External control: `qs ipc call clipboard toggle|open|close`
    IpcHandler {
        target: "clipboard"
        function toggle() {
            if (root.clipboardOpen) root.clipboardOpen = false
            else                    root.openClipboard()
        }
        function open()   { root.openClipboard()  }
        function close()  { root.closeClipboard() }
    }

    // External control: `qs ipc call wallpaper toggle|open|close`
    IpcHandler {
        target: "wallpaper"
        function toggle() {
            if (root.wallpaperPickerOpen) root.wallpaperPickerOpen = false
            else                          root.openWallpaperPicker()
        }
        function open()   { root.openWallpaperPicker()  }
        function close()  { root.closeWallpaperPicker() }
    }

    // ── Keybinds cheat-sheet ─────────────────────────────────────────────
    // Parsed from ~/.config/hypr/modules/keybinds.lua via a helper script.
    // Entries: { section, keys, desc }.
    property bool keybindsOpen:    false
    property var  keybindsList:    []
    property var  _keybindsBuffer: []

    function openKeybinds()  { keybindsOpen = true; refreshKeybinds() }
    function closeKeybinds() { keybindsOpen = false }
    function refreshKeybinds() {
        keybindsProc.running = false
        keybindsProc.running = true
    }

    IpcHandler {
        target: "keybinds"
        function toggle() { root.keybindsOpen = !root.keybindsOpen
                            if (root.keybindsOpen) root.refreshKeybinds() }
        function open()   { root.openKeybinds()  }
        function close()  { root.closeKeybinds() }
    }

    // ── Shell theme (dark / light), persisted to theme.txt ───────────────
    property string themeName: "dark"
    property bool   themeOpen: false
    function openTheme()  { themeOpen = true }
    function closeTheme() { themeOpen = false }
    function setTheme(name) {
        if (name !== "dark" && name !== "light") return
        root.themeName = name
        themeSaveProc.target = name
        themeSaveProc.running = false
        themeSaveProc.running = true
    }
    Process {
        id: themeLoadProc
        running: true
        command: ["sh", "-c", "cat \"$FILE\" 2>/dev/null || true"]
        environment: ({ FILE: root.configDir + "/theme.txt" })
        stdout: SplitParser {
            onRead: line => { const t = line.trim(); if (t === "light" || t === "dark") root.themeName = t }
        }
    }
    Process {
        id: themeSaveProc
        property string target: ""
        environment: ({ T: target, FILE: root.configDir + "/theme.txt" })
        command: ["sh", "-c", "printf '%s' \"$T\" > \"$FILE\""]
    }
    IpcHandler {
        target: "theme"
        function toggle() { root.themeOpen = !root.themeOpen }
        function open()   { root.openTheme()  }
        function close()  { root.closeTheme() }
        function set(name: string) { root.setTheme(name) }
    }

    // ── Power menu (shutdown / reboot / lock) ────────────────────────────
    // Standalone — not in the launcher. `qs ipc call power toggle|open|close`
    property bool powerOpen: false
    function openPower()  { powerOpen = true }
    function closePower() { powerOpen = false }
    function powerAction(which) {
        if      (which === "shutdown")  Quickshell.execDetached(["systemctl", "poweroff"])
        else if (which === "reboot")    Quickshell.execDetached(["systemctl", "reboot"])
        else if (which === "suspend")   Quickshell.execDetached(["systemctl", "suspend"])
        else if (which === "lock")      Quickshell.execDetached(["hyprlock"])
        root.powerOpen = false
    }
    IpcHandler {
        target: "power"
        function toggle() { root.powerOpen = !root.powerOpen }
        function open()   { root.openPower()  }
        function close()  { root.closePower() }
    }

    // ── Monitor mode (extend / mirror / external / internal) ─────────────
    // Live presentation switch (like Win+P). `qs ipc call monitormode toggle`
    property bool monitorModeOpen: false
    function openMonitorMode()  { monitorModeOpen = true }
    function closeMonitorMode() { monitorModeOpen = false }
    function setMonitorMode(mode) {
        monitorModeProc.modeArg = mode
        monitorModeProc.running = false
        monitorModeProc.running = true
        root.monitorModeOpen = false
    }
    Process {
        id: monitorModeProc
        property string modeArg: "extend"
        command: ["python3",
                  Qt.resolvedUrl("./scripts/monitor-mode.py").toString().replace("file://", ""),
                  modeArg]
    }
    IpcHandler {
        target: "monitormode"
        function toggle() { root.monitorModeOpen = !root.monitorModeOpen }
        function open()   { root.openMonitorMode()  }
        function close()  { root.closeMonitorMode() }
        function set(mode: string) { root.setMonitorMode(mode) }
    }

    // ── System icon theme (mirrors GNOME's icon-theme gsetting) ──────────
    // Qt's icon lookup is stuck on hicolor under QT_QPA_PLATFORMTHEME=wayland,
    // so we resolve icon-name → file path ourselves from the active GTK theme
    // (and its Inherits chain) and watch gsettings for live changes.
    property string systemIconTheme: "hicolor"
    property var    iconMap:         ({})
    property var    _iconMapBuffer:  ({})

    function iconFor(name) {
        if (!name) return ""
        if (name.startsWith("/")) {
            // .desktop files sometimes hard-code paths to icons from themes
            // the user no longer has. Prefer the active-theme version when
            // we can resolve it by basename; fall back to the literal path.
            const base = name.split("/").pop().replace(/\.[^.]+$/, "")
            const p = iconMap[base]
            if (p) return "file://" + p
            return "file://" + name
        }
        const p = iconMap[name]
        return p ? "file://" + p : ""
    }
    function rescanIcons() {
        iconScanProc.running = false
        iconScanProc.running = true
    }

    // Nerd Font glyph fallback for icon names that don't resolve to a real
    // themed image (e.g. battery state names — Tela only ships dark symbolic
    // battery icons that would be invisible on the dark notification cards).
    // Used by the notification toast + control-center panel.
    function glyphForIcon(name) {
        const n = (name || "").toLowerCase()
        if (n.indexOf("battery") !== -1)
            return n.indexOf("charg") !== -1 ? String.fromCodePoint(0xf0084)   // charging
                                             : String.fromCodePoint(0xf0079)   // battery
        return ""
    }

    // ── Cava visualizer values (32 bars, 0..1) ────────────────────────────
    readonly property int cavaBarCount: 32
    property var cavaValues: new Array(32).fill(0)

    // ── System info (dashboard) ────────────────────────────────────────────
    property string sysDistro: ""
    property string sysUptime: ""
    readonly property string sysWM: "Hyprland"

    // ── Performance state ─────────────────────────────────────────────────
    property real cpuPerc:        0
    property real cpuTempC:       0
    property real memPerc:        0
    property real memUsedKib:     0
    property real memTotalKib:    0
    property real diskPerc:       0
    property real diskUsedB:      0
    property real diskTotalB:     0
    property string diskMount:    "/"
    property real netDownBps:     0
    property real netUpBps:       0
    property real netDownTotal:   0
    property real netUpTotal:     0
    property var  netDownHistory: []
    property var  netUpHistory:   []

    // ── Weather state ─────────────────────────────────────────────────────
    property var weather: ({
        ready: false,
        city: "", region: "",
        temp: "", feelsLike: "",
        humidity: "", windKph: "",
        description: "",
        icon: "",
        sunrise: "", sunset: "",
        forecast: []
    })
    // User-configurable wttr.in location. Empty = IP-based auto-detect.
    property string weatherLocation: ""

    function openSettings(pane) {
        settingsPane = pane
        settingsOpen = true
    }

    // ── Dashboard helpers ───────────────────────────────────────────────
    function openDashboard()  { dashboardHideTimer.stop(); dashboardOpen = true }
    function closeDashboard() { dashboardHideTimer.stop(); dashboardOpen = false }
    function showDashboardTab(i) { dashboardTab = i; openDashboard() }
    function startDashboardHide() { dashboardHideTimer.restart() }
    function stopDashboardHide()  { dashboardHideTimer.stop() }
    function refreshWeather() {
        weatherProc.running = false
        weatherProc.running = true
    }
    function setWeatherLocation(loc) {
        weatherLocation = (loc || "").trim()
        weatherSaveProc.target = weatherLocation
        weatherSaveProc.running = false
        weatherSaveProc.running = true
        refreshWeather()
    }

    // Mutually-exclusive popup activation — kill the others so the
    // user can sweep across bar components without overlays stacking up.
    function showPopup(name) {
        if (name !== "sink")      { sinkHideTimer.stop();    sinkPopupOpen      = false }
        if (name !== "battery")   { batteryHideTimer.stop(); batteryPopupOpen   = false }
        if (name !== "bluetooth") { btHideTimer.stop();      bluetoothPopupOpen = false }
        if (name !== "wifi")      { wifiHideTimer.stop();    wifiPopupOpen      = false }
        if (name !== "clock")     { clockHideTimer.stop();   clockPopupOpen     = false }
        if (name !== "notif")     { notifHideTimer.stop();   notifPopupOpen     = false }
        if (name === "sink")      sinkPopupOpen      = true
        if (name === "battery")   batteryPopupOpen   = true
        if (name === "bluetooth") bluetoothPopupOpen = true
        if (name === "wifi")      wifiPopupOpen      = true
        if (name === "clock")     clockPopupOpen     = true
        if (name === "notif")     notifPopupOpen     = true
    }

    // ── Wifi helpers ─────────────────────────────────────────────────────
    // Schedules a debounced refresh — coalesces the burst of events nmcli
    // emits during a network switch into one list rebuild.
    function refreshWifi() { wifiRefreshDebounce.restart() }
    function _refreshWifiNow() {
        wifiQueryProc.running = false
        wifiQueryProc.running = true
        wifiSavedProc.running = false
        wifiSavedProc.running = true
    }
    function forgetWifi(ssid) {
        wifiForgetProc.targetSsid = ssid
        wifiForgetProc.running = false
        wifiForgetProc.running = true
    }
    function toggleWifi(on) {
        wifiToggleProc.target = on ? "on" : "off"
        wifiToggleProc.running = false
        wifiToggleProc.running = true
    }
    function connectWifi(ssid, secure, source, enterprise) {
        wifiConnecting            = true
        wifiPasswordSource        = source || "overlay"
        wifiPasswordEnterprise    = !!enterprise
        wifiTryConnectProc.targetSsid   = ssid
        wifiTryConnectProc.targetSecure = secure ? "1" : "0"
        wifiTryConnectProc.running      = false
        wifiTryConnectProc.running      = true
    }
    function submitWifiPassword(password) {
        wifiPasswordError = ""
        wifiConnecting    = true
        wifiPwConnectProc.targetSsid = wifiPasswordSsid
        wifiPwConnectProc.targetPw   = password
        wifiPwConnectProc.running    = false
        wifiPwConnectProc.running    = true
    }
    // WPA-Enterprise (802.1X) connect — builds an explicit nmcli profile with
    // the chosen EAP method. `phase2` / `anonId` may be empty (omitted).
    function submitWifiEnterprise(eap, identity, password, phase2, anonId) {
        wifiPasswordError = ""
        wifiConnecting    = true
        wifiEapConnectProc.targetSsid     = wifiPasswordSsid
        wifiEapConnectProc.targetEap      = eap
        wifiEapConnectProc.targetIdentity = identity
        wifiEapConnectProc.targetPw       = password
        wifiEapConnectProc.targetPhase2   = phase2 || ""
        wifiEapConnectProc.targetAnonId   = anonId || ""
        wifiEapConnectProc.running        = false
        wifiEapConnectProc.running        = true
    }
    function cancelWifiPassword() {
        wifiPasswordOpen       = false
        wifiPasswordSsid       = ""
        wifiPasswordError      = ""
        wifiConnecting         = false
        wifiPasswordSource     = ""
        wifiPasswordEnterprise = false
    }
    function disconnectWifi() {
        wifiDisconnectProc.running = false
        wifiDisconnectProc.running = true
    }
    function rescanWifi() {
        if (root.wifiScanning) return
        root.wifiScanning = true
        // nmcli rescan returns instantly (kicks off a background scan).
        // Hold the spinner for a minimum window so the user gets feedback and
        // we give nmcli time to actually publish results.
        wifiScanMinTimer.restart()
        wifiRescanProc.running = false
        wifiRescanProc.running = true
    }

    // Public API for the settings panes — call these instead of poking procs
    function switchSink(name) {
        switchSinkProc.sinkName = name
        switchSinkProc.running  = false
        switchSinkProc.running  = true
    }
    function switchSource(name) {
        switchSourceProc.sourceName = name
        switchSourceProc.running    = false
        switchSourceProc.running    = true
    }
    function refreshSources() {
        sourceQueryProc.running = false
        sourceQueryProc.running = true
    }
    // While the user is dragging/clicking the slider we (a) reflect the value
    // optimistically and (b) hold off letting incoming wpctl queries overwrite
    // it — otherwise a pactl-subscribe-driven query can read the sink before
    // the new value has propagated and snap the UI back to the old level.
    property bool _volHold: false
    property int  _volPendingPct: -1

    function setVolumePct(pct) {
        const p = Math.max(0, Math.min(100, Math.round(pct)))
        root.volPct = p
        if (p > 0) root.volMuted = false
        root._volHold = true
        volHoldTimer.restart()
        // Coalesce the actual set-volume so a fast drag fires one reliable
        // call instead of dozens of restarted (and possibly killed) procs.
        root._volPendingPct = p
        volSetDebounce.restart()
    }
    function adjustVolume(direction) {  // "+" or "-"
        setVolStepProc.target  = direction === "+" ? "2%+" : "2%-"
        setVolStepProc.running = false
        setVolStepProc.running = true
    }
    function toggleMute() {
        root.volMuted = !root.volMuted   // optimistic; query confirms
        root._volHold = true
        volHoldTimer.restart()
        toggleMuteProc.running = false
        toggleMuteProc.running = true
    }
    function refreshSinks() {
        sinkQueryProc.running = false
        sinkQueryProc.running = true
    }

    // ── Brightness (brightnessctl) ───────────────────────────────────────
    // Same optimistic + hold pattern as volume to avoid the query snapping
    // the UI back while the user drags the slider.
    property bool _briHold: false
    property int  _briPending: -1
    function refreshBrightness() {
        brightnessQueryProc.running = false
        brightnessQueryProc.running = true
    }
    function setBrightnessPct(pct) {
        const p = Math.max(1, Math.min(100, Math.round(pct)))   // never 0 → black
        root.brightnessPct = p
        root._briHold = true
        briHoldTimer.restart()
        root._briPending = p
        briSetDebounce.restart()
    }
    // Brightness has no live subscribe (unlike volume's pactl monitor), so the
    // panel's slider would go stale after the keyboard brightness keys change
    // it. While the notification panel is open, refresh it (and poll), so the
    // slider tracks external changes. The _briHold guard keeps this from
    // fighting an in-progress drag.
    onNotifPopupOpenChanged: {
        if (notifPopupOpen) { refreshBrightness(); briPollTimer.start() }
        else                  briPollTimer.stop()
    }
    Timer {
        id: briPollTimer
        interval: 800; repeat: true
        onTriggered: root.refreshBrightness()
    }

    // ── Do Not Disturb ───────────────────────────────────────────────────
    function toggleDnd() { root.dndEnabled = !root.dndEnabled }

    // ── Hide-timer control (shared between bar + overlays) ───────────────
    function startHideTimer(name) {
        if (name === "sink")      sinkHideTimer.start()
        if (name === "battery")   batteryHideTimer.start()
        if (name === "bluetooth") btHideTimer.start()
        if (name === "wifi" && !wifiPasswordOpen) wifiHideTimer.start()
        if (name === "clock")     clockHideTimer.start()
        if (name === "notif")     notifHideTimer.start()
    }
    function stopHideTimer(name) {
        if (name === "sink")      sinkHideTimer.stop()
        if (name === "battery")   batteryHideTimer.stop()
        if (name === "bluetooth") btHideTimer.stop()
        if (name === "wifi")      wifiHideTimer.stop()
        if (name === "clock")     clockHideTimer.stop()
        if (name === "notif")     notifHideTimer.stop()
    }

    // ── One-shot launchers ───────────────────────────────────────────────
    function launchBlueman()    { launchBluemanProc.running    = false; launchBluemanProc.running    = true }
    function launchPavucontrol(){ launchPavucontrolProc.running = false; launchPavucontrolProc.running = true }
    function launchNmtui()      { launchNmtuiProc.running      = false; launchNmtuiProc.running      = true }
    function toggleNotifPanel() { notifPopupOpen = !notifPopupOpen }
    function clearAllNotifs() {
        const list = [...notifServer.trackedNotifications.values]
        for (const n of list) n.dismiss()
        toastModel.clear()
    }
    function dismissNotif(n) { if (n) { removeToast(n); n.dismiss() } }

    // ── Transient toasts (shown briefly when a notification arrives) ─────
    // Volume / brightness / media notifications fire repeatedly (one per
    // key-press). They carry an x-canonical-private-synchronous hint, but
    // Quickshell's server doesn't honour it, so we collapse them by group:
    // an incoming notification in an existing group UPDATES that toast's row
    // in place (same delegate, no re-animation) instead of stacking a new one.
    ListModel { id: toastModel; dynamicRoles: true }
    readonly property alias toasts: toastModel
    readonly property int toastCount: toastModel.count

    function notifGroup(n) {
        const s = (n && n.summary ? String(n.summary) : "").toLowerCase()
        if (s.indexOf("brightness") === 0)                            return "brightness"
        if (s.indexOf("volume") === 0    || s.indexOf("mic-level") === 0 ||
            s.indexOf("microphone") === 0 || s.indexOf("mute") !== -1) return "audio"
        if (s.indexOf("now playing") === 0 || s.indexOf("media ") === 0 ||
            s.indexOf("playback ") === 0)                             return "media"
        // Charging / Discharging / Fully charged → one updating toast.
        if (s.indexOf("charg") !== -1)                               return "battery"
        return ""
    }

    function addToast(n) {
        const g = root.notifGroup(n)
        if (g !== "") {
            for (let i = 0; i < toastModel.count; i++) {
                if (toastModel.get(i).gid === g) {
                    const old = toastModel.get(i).notif
                    toastModel.set(i, { notif: n, gid: g })   // update existing toast in place
                    if (old && old !== n) old.dismiss()        // drop the superseded one from history too
                    return
                }
            }
        }
        toastModel.append({ notif: n, gid: g })
    }
    function removeToast(n) {
        for (let i = 0; i < toastModel.count; i++) {
            if (toastModel.get(i).notif === n) { toastModel.remove(i); return }
        }
    }
    function playerToggle()     { playerctlToggleProc.running  = false; playerctlToggleProc.running  = true }
    function playerNext()       { playerctlNextProc.running    = false; playerctlNextProc.running    = true }
    function playerPrev()       { playerctlPrevProc.running    = false; playerctlPrevProc.running    = true }

    // ── Media player (playerctl → spotify) ────────────────────────────────
    Process {
        id: mediaProc
        command: ["sh", "-c",
            "playerctl -p spotify metadata --format '{{status}}|||{{artist}} - {{title}}' 2>/dev/null || echo 'Stopped|||'"]
        stdout: SplitParser {
            onRead: line => {
                var sep    = line.indexOf("|||")
                if (sep < 0) { root.mediaText = ""; return }
                var status = line.substring(0, sep).trim()
                var track  = line.substring(sep + 3).trim()
                root.mediaText = (status === "Playing" || status === "Paused") ? track : ""
            }
        }
        onExited: (code, status) => mediaRestartTimer.start()
    }
    Timer {
        id: mediaRestartTimer
        interval: 3000; repeat: false
        onTriggered: mediaProc.running = true
    }

    // ── Network ─ reactive via nmcli monitor ──────────────────────────────
    Process {
        id: netStatusProc
        command: ["sh", "-c",
            "if nmcli -t -f TYPE,STATE dev 2>/dev/null | grep -q 'wifi:connected'; then echo ''; " +
            "elif nmcli -t -f TYPE,STATE dev 2>/dev/null | grep -q 'ethernet:connected'; then echo '󰈀'; " +
            "else echo '󰌙'; fi"]
        stdout: SplitParser {
            onRead: line => root.netIcon = line.trim()
        }
    }

    Process {
        id: nmcliMonitor
        running: true
        command: ["nmcli", "monitor"]
        environment: ({ LANG: "C.UTF-8", LC_ALL: "C.UTF-8" })
        stdout: SplitParser {
            onRead: _ => {
                netStatusProc.running = false
                netStatusProc.running = true
                // Coalesce the burst of events nmcli fires during a switch
                // (associating, DHCP, address change, etc.) into a single
                // list refresh so the Repeater isn't rebuilt on every tick.
                if (root.wifiPopupOpen || root.settingsOpen) wifiRefreshDebounce.restart()
            }
        }
        onExited: (code, status) => nmcliMonitorRestartTimer.start()
    }
    Timer {
        id: wifiRefreshDebounce
        interval: 600; repeat: false
        onTriggered: root._refreshWifiNow()
    }
    Timer {
        id: nmcliMonitorRestartTimer
        interval: 2000; repeat: false
        onTriggered: nmcliMonitor.running = true
    }

    // ── Wifi enabled probe ───────────────────────────────────────────────
    Process {
        id: wifiEnabledProc
        running: true
        command: ["nmcli", "-t", "radio", "wifi"]
        stdout: SplitParser {
            onRead: line => root.wifiEnabled = line.trim() === "enabled"
        }
    }

    // ── Wifi network list ────────────────────────────────────────────────
    // nmcli -t separates fields with `:` and escapes `:` inside values as
    // `\:`. We swap `\:` →   before splitting, then restore.
    Process {
        id: wifiQueryProc
        running: false
        environment: ({ LANG: "C.UTF-8", LC_ALL: "C.UTF-8" })
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY",
                 "device", "wifi", "list"]
        onRunningChanged: if (running) root._wifiBuffer = []
        stdout: SplitParser {
            onRead: line => {
                const parts = line.replace(/\\:/g, " ")
                                  .split(":")
                                  .map(p => p.replace(/ /g, ":"))
                if (parts.length < 4) return
                const ssid = parts[1]
                if (!ssid) return
                // Dedupe by SSID, prefer active or stronger signal
                const existing = root._wifiBuffer.findIndex(n => n.ssid === ssid)
                const entry = {
                    active:     parts[0] === "*",
                    ssid:       ssid,
                    strength:   parseInt(parts[2]) || 0,
                    secure:     parts[3].length > 0,
                    enterprise: parts[3].indexOf("802.1X") >= 0
                }
                if (existing >= 0) {
                    if (entry.active || entry.strength > root._wifiBuffer[existing].strength)
                        root._wifiBuffer[existing] = entry
                } else {
                    root._wifiBuffer.push(entry)
                }
            }
        }
        onExited: {
            const next = root._wifiBuffer.slice()
                .sort((a, b) => (b.active - a.active) || (b.strength - a.strength))
            // Only push a new array reference when the visible content actually
            // changed; otherwise QML would re-instantiate every Repeater row.
            const cur = root.wifiList
            let same = cur.length === next.length
            for (let i = 0; same && i < cur.length; i++) {
                same = cur[i].ssid       === next[i].ssid
                    && cur[i].active     === next[i].active
                    && cur[i].secure     === next[i].secure
                    && cur[i].enterprise === next[i].enterprise
                    && cur[i].strength   === next[i].strength
            }
            if (!same) root.wifiList = next
        }
    }

    Process {
        id: wifiToggleProc
        property string target: "on"
        command: ["nmcli", "radio", "wifi", target]
        onExited: {
            wifiEnabledProc.running = false
            wifiEnabledProc.running = true
            refreshWifi()
        }
    }

    // ── Connect: open networks + secured-with-saved-profile ──────────────
    // For secured networks we first try the saved nmcli profile; if it fails
    // (e.g. password changed since last save) we fall back to prompting.
    Process {
        id: wifiTryConnectProc
        property string targetSsid: ""
        property string targetSecure: "0"
        command: ["sh", "-c",
            "if [ \"$SEC\" = \"1\" ]; then " +
            "  if nmcli -t -f connection.id connection show id \"$SSID\" >/dev/null 2>&1; then " +
            "    if ! nmcli connection up id \"$SSID\" 2>/dev/null; then " +
            "      nmcli connection delete id \"$SSID\" 2>/dev/null; " +
            "      echo NEEDS_PASSWORD; " +
            "    fi; " +
            "  else " +
            "    echo NEEDS_PASSWORD; " +
            "  fi; " +
            "else " +
            "  nmcli device wifi connect \"$SSID\"; " +
            "fi"]
        environment: ({ SSID: targetSsid, SEC: targetSecure })
        stdout: SplitParser {
            onRead: line => {
                if (line.trim() === "NEEDS_PASSWORD") {
                    root.wifiPasswordSsid  = wifiTryConnectProc.targetSsid
                    root.wifiPasswordError = ""
                    root.wifiPasswordOpen  = true
                    root.wifiConnecting    = false
                }
            }
        }
        onExited: (code) => {
            if (!root.wifiPasswordOpen) root.wifiConnecting = false
            refreshWifi()
        }
    }

    Process {
        id: wifiPwConnectProc
        property string targetSsid: ""
        property string targetPw: ""
        command: ["nmcli", "device", "wifi", "connect", targetSsid, "password", targetPw]
        onExited: (code) => {
            root.wifiConnecting = false
            if (code === 0) {
                root.wifiPasswordOpen   = false
                root.wifiPasswordSsid   = ""
                root.wifiPasswordError  = ""
                root.wifiPasswordSource = ""
                refreshWifi()
            } else {
                // nmcli leaves behind a half-saved profile on auth fail; delete
                // it so the next attempt doesn't get stuck in the saved-profile
                // path and silently re-fail.
                wifiCleanupProc.targetSsid = targetSsid
                wifiCleanupProc.running    = false
                wifiCleanupProc.running    = true
                root.wifiPasswordError = "Wrong password or connection failed"
            }
        }
    }

    Process {
        id: wifiCleanupProc
        property string targetSsid: ""
        command: ["nmcli", "connection", "delete", "id", targetSsid]
    }

    // ── Connect: WPA-Enterprise (802.1X — PEAP / TTLS / PWD) ─────────────
    // The simple `device wifi connect … password …` path can't carry 802.1X
    // settings, so we build an explicit profile and bring it up. Optional
    // phase2-auth / anonymous-identity are appended only when provided.
    // CA-cert validation is left off so it works on captive eduroam-style nets
    // without provisioning a certificate.
    Process {
        id: wifiEapConnectProc
        property string targetSsid: ""
        property string targetEap: "peap"
        property string targetIdentity: ""
        property string targetPw: ""
        property string targetPhase2: ""
        property string targetAnonId: ""
        environment: ({
            LANG: "C.UTF-8", LC_ALL: "C.UTF-8",
            SSID: targetSsid, EAP: targetEap, IDENTITY: targetIdentity,
            PASSWORD: targetPw, PHASE2: targetPhase2, ANONID: targetAnonId
        })
        command: ["sh", "-c",
            "DEV=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2==\"wifi\"{print $1; exit}'); " +
            "[ -z \"$DEV\" ] && exit 1; " +
            "set -- ; " +
            "[ -n \"$PHASE2\" ] && set -- \"$@\" 802-1x.phase2-auth \"$PHASE2\"; " +
            "[ -n \"$ANONID\" ] && set -- \"$@\" 802-1x.anonymous-identity \"$ANONID\"; " +
            "nmcli connection delete id \"$SSID\" >/dev/null 2>&1; " +
            "nmcli connection add type wifi con-name \"$SSID\" ifname \"$DEV\" ssid \"$SSID\" " +
            "  wifi-sec.key-mgmt wpa-eap 802-1x.eap \"$EAP\" 802-1x.identity \"$IDENTITY\" " +
            "  802-1x.password \"$PASSWORD\" 802-1x.system-ca-certs no \"$@\" >/dev/null 2>&1 " +
            "  && exec nmcli connection up id \"$SSID\"; " +
            "exit 1"]
        onExited: (code) => {
            root.wifiConnecting = false
            if (code === 0) {
                root.wifiPasswordOpen       = false
                root.wifiPasswordSsid       = ""
                root.wifiPasswordError      = ""
                root.wifiPasswordSource     = ""
                root.wifiPasswordEnterprise = false
                refreshWifi()
            } else {
                // Drop the half-saved profile so the next attempt re-prompts
                // instead of getting stuck in the saved-profile up path.
                wifiCleanupProc.targetSsid = wifiEapConnectProc.targetSsid
                wifiCleanupProc.running    = false
                wifiCleanupProc.running    = true
                root.wifiPasswordError = "Authentication failed — check identity & password"
            }
        }
    }

    Process {
        id: wifiDisconnectProc
        // disconnect the wifi device; finds active wifi device name first
        command: ["sh", "-c",
            "DEV=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2==\"wifi\"{print $1; exit}'); " +
            "[ -n \"$DEV\" ] && nmcli device disconnect \"$DEV\""]
    }

    // ── Saved Wi-Fi profiles (so we can show a Forget button) ────────────
    Process {
        id: wifiSavedProc
        environment: ({ LANG: "C.UTF-8", LC_ALL: "C.UTF-8" })
        // List names of saved 802-11-wireless connection profiles.
        command: ["sh", "-c",
            "nmcli -t -f NAME,TYPE connection show | " +
            "awk -F: '$2==\"802-11-wireless\"{print $1}'"]
        onRunningChanged: if (running) root._wifiSavedBuffer = []
        stdout: SplitParser {
            onRead: line => { const s = line.trim(); if (s) root._wifiSavedBuffer.push(s) }
        }
        onExited: root.wifiSaved = root._wifiSavedBuffer.slice()
    }
    // Delete a saved profile by SSID (profile name usually matches the SSID).
    Process {
        id: wifiForgetProc
        property string targetSsid: ""
        command: ["nmcli", "connection", "delete", "id", targetSsid]
        onExited: refreshWifi()
    }

    Process {
        id: wifiRescanProc
        command: ["nmcli", "device", "wifi", "rescan"]
        onExited: refreshWifi()
    }
    Timer {
        id: wifiScanMinTimer
        interval: 3000; repeat: false
        onTriggered: { root.wifiScanning = false; root.refreshWifi() }
    }

    Timer {
        id: wifiHideTimer
        interval: 600; repeat: false
        onTriggered: root.wifiPopupOpen = false
    }

    // ── Volume (wpctl → pactl subscribe) ──────────────────────────────────
    Process {
        id: volQueryProc
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: line => {
                var m = line.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
                if (!m) return
                // Don't clobber the optimistic value while the user is
                // actively adjusting it (see _volHold).
                if (root._volHold) return
                root.volPct   = Math.round(parseFloat(m[1]) * 100)
                root.volMuted = !!m[2]
            }
        }
    }
    // Coalesces rapid slider updates into one wpctl set-volume.
    Timer {
        id: volSetDebounce
        interval: 40; repeat: false
        onTriggered: {
            if (root._volPendingPct < 0) return
            setVolProc.targetPct = root._volPendingPct
            setVolProc.running   = false
            setVolProc.running   = true
        }
    }
    // Releases the hold a moment after the last user interaction so later
    // queries can resume reconciling the displayed value.
    Timer {
        id: volHoldTimer
        interval: 450; repeat: false
        onTriggered: root._volHold = false
    }

    // ── Brightness (brightnessctl) ───────────────────────────────────────
    Process {
        id: brightnessQueryProc
        running: true
        command: ["sh", "-c", "brightnessctl -m | cut -d, -f4 | tr -d '%'"]
        stdout: SplitParser {
            onRead: line => {
                const v = parseInt(line.trim())
                if (!isNaN(v) && !root._briHold) root.brightnessPct = v
            }
        }
    }
    Process {
        id: briSetProc
        property int target: 0
        command: ["brightnessctl", "-q", "set", target + "%"]
    }
    Timer {
        id: briSetDebounce
        interval: 40; repeat: false
        onTriggered: {
            if (root._briPending < 0) return
            briSetProc.target  = root._briPending
            briSetProc.running = false
            briSetProc.running = true
        }
    }
    Timer {
        id: briHoldTimer
        interval: 450; repeat: false
        onTriggered: { root._briHold = false; root.refreshBrightness() }
    }
    Process {
        id: pactlMonitor
        running: true
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: line => {
                // `Event 'change' on server` fires on default-sink/source changes;
                // `on sink #N` / `on source #N` fire on per-device changes.
                const isSink   = line.includes("on sink")   || line.includes("on server")
                const isSource = line.includes("on source") || line.includes("on server")
                if (isSink) {
                    volQueryProc.running = false
                    volQueryProc.running = true
                    if (root.sinkPopupOpen || root.settingsOpen) {
                        sinkQueryProc.running = false
                        sinkQueryProc.running = true
                    }
                }
                if (isSource && root.settingsOpen) {
                    sourceQueryProc.running = false
                    sourceQueryProc.running = true
                }
            }
        }
        onExited: (code, status) => pactlMonitorRestartTimer.start()
    }
    Timer {
        id: pactlMonitorRestartTimer
        interval: 2000; repeat: false
        onTriggered: pactlMonitor.running = true
    }

    // ── Volume setter (used by settings pane slider) ─────────────────────
    Process {
        id: setVolProc
        property int targetPct: 0
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", (targetPct / 100).toFixed(2)]
        onExited: {
            volQueryProc.running = false
            volQueryProc.running = true
        }
    }

    // ── Switch sink: set default + move all existing sink inputs ─────────
    Process {
        id: switchSinkProc
        property string sinkName: ""
        command: ["sh", "-c",
            "pactl set-default-sink \"" + sinkName + "\" && " +
            "pactl list sink-inputs short | awk '{print $1}' | " +
            "xargs -r -I{} pactl move-sink-input {} \"" + sinkName + "\""]
        onStarted: console.log("[switchSinkProc] started for", sinkName)
        onExited: (code, status) => console.log("[switchSinkProc] exited code=" + code)
    }

    // ── Switch source: set default + move all existing source outputs ────
    Process {
        id: switchSourceProc
        property string sourceName: ""
        command: ["sh", "-c",
            "pactl set-default-source \"" + sourceName + "\" && " +
            "pactl list source-outputs short | awk '{print $1}' | " +
            "xargs -r -I{} pactl move-source-output {} \"" + sourceName + "\""]
    }

    // ── Source list (input device picker) ────────────────────────────────
    Process {
        id: sourceQueryProc
        running: false
        command: ["sh", "-c",
            "DEFAULT=$(pactl get-default-source); " +
            "pactl list sources | awk -v def=\"$DEFAULT\" " +
            "'/\\tName:/{name=$2} /\\tDescription:/{desc=substr($0,index($0,$2)); " +
            "if (name !~ /\\.monitor$/) printf \"%s\\t%s\\t%s\\n\",(name==def?\"1\":\"0\"),name,desc}'"]
        onRunningChanged: if (running) root._sourceBuffer = []
        stdout: SplitParser {
            onRead: line => {
                var parts = line.split("\t")
                if (parts.length >= 3)
                    root._sourceBuffer.push({active: parts[0]==="1", name: parts[1], desc: parts[2]})
            }
        }
        onExited: root.sourceList = root._sourceBuffer.slice()
    }

    // ── Sink list (for device picker) ─────────────────────────────────────
    Process {
        id: sinkQueryProc
        running: false
        command: ["sh", "-c",
            "DEFAULT=$(pactl get-default-sink); " +
            "pactl list sinks | awk -v def=\"$DEFAULT\" " +
            "'/\\tName:/{name=$2} /\\tDescription:/{desc=substr($0,index($0,$2)); " +
            "printf \"%s\\t%s\\t%s\\n\",(name==def?\"1\":\"0\"),name,desc}'"]
        onRunningChanged: if (running) root._sinkBuffer = []
        stdout: SplitParser {
            onRead: line => {
                var parts = line.split("\t")
                if (parts.length >= 3)
                    root._sinkBuffer.push({active: parts[0]==="1", name: parts[1], desc: parts[2]})
            }
        }
        onExited: root.sinkList = root._sinkBuffer.slice()
    }
    Timer {
        id: sinkHideTimer
        interval: 600; repeat: false
        onTriggered: root.sinkPopupOpen = false
    }
    Timer {
        id: batteryHideTimer
        interval: 600; repeat: false
        onTriggered: root.batteryPopupOpen = false
    }
    Timer {
        id: btHideTimer
        interval: 600; repeat: false
        onTriggered: root.bluetoothPopupOpen = false
    }
    Timer {
        id: clockHideTimer
        interval: 600; repeat: false
        onTriggered: root.clockPopupOpen = false
    }

    // ── Notifications (native Quickshell daemon) ─────────────────────────
    // Quickshell registers as the org.freedesktop.Notifications server, so
    // swaync must NOT be running (it would grab the bus name first).
    NotificationServer {
        id: notifServer
        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        actionIconsSupported: true
        imageSupported: true
        // Keep every incoming notification in trackedNotifications until the
        // user (or its own timeout) dismisses it, so the popup can list them.
        onNotification: n => {
            // Volume / brightness / media / battery: show a GNOME-style bottom
            // OSD instead of a notification — never tracked, never toasted.
            const g = root.notifGroup(n)
            if (g === "audio" || g === "brightness" || g === "media" || g === "battery") {
                root._osdFromNotification(g, n)
                n.tracked = false
                return
            }
            n.tracked = true
            // Show a transient toast for the new notification (it also stays
            // in the tracked list for the control-center panel). The full
            // panel only opens on hover — we don't pop it open here.
            if (!root.dndEnabled) root.addToast(n)
        }
    }

    // ── On-screen display (OSD) — volume / brightness / media / battery ──
    property bool   osdVisible:  false
    property string osdKind:     ""    // "audio" | "brightness" | "media" | "battery"
    property int    osdValue:    0     // 0..100 (bar for audio/brightness/battery)
    property bool   osdMuted:    false
    property bool   osdCharging: false // battery: plugged-in state (drives icon)
    property string osdText:     ""    // track text (media) / state label (battery)
    function showOsd(kind, value, muted, text, charging) {
        osdKind     = kind
        osdValue    = Math.max(0, Math.min(100, value))
        osdMuted    = muted || false
        osdCharging = charging || false
        osdText     = text || ""
        osdVisible  = true
        osdHideTimer.restart()
    }
    function _osdFromNotification(g, n) {
        const s = String(n.summary || "")
        const body = String(n.body || "")
        const m = s.match(/(\d+)\s*%/)
        if (g === "audio") {
            // Only the mute KEY ("Volume Switched OFF") shows the muted state.
            // Lowering to the bottom ("Volume: Muted") is just 0%.
            const isMuteKey = /switched off/i.test(s)
            const isUnmute  = /switched on/i.test(s)
            const v = m ? parseInt(m[1]) : (isUnmute ? root.volPct : 0)
            showOsd("audio", v, isMuteKey, "")
        } else if (g === "brightness") {
            showOsd("brightness", m ? parseInt(m[1]) : root.brightnessPct, false, "")
        } else if (g === "battery") {
            // "Charging" / "Discharging" / "Fully charged" → an icon + text OSD
            // (no bar). Trust UPower for the live charging state, falling back
            // to parsing the notification text when the device isn't readable.
            const dev = UPower.displayDevice
            const charging = dev ? !UPower.onBattery : !/discharg/i.test(s)
            const label = /full/i.test(s) ? "Battery fully charged"
                        : charging         ? "Battery charging"
                                           : "Battery discharging"
            showOsd("battery", 0, false, label, charging)
        } else {
            showOsd("media", 0, false, (body || s).replace(/\n+/g, "  —  ").trim())
        }
    }
    // Battery OSDs linger longer (5 s) so a low-battery warning is readable;
    // volume/brightness/media stay snappy at 1.6 s.
    Timer { id: osdHideTimer; interval: root.osdKind === "battery" ? 5000 : 1600; repeat: false; onTriggered: root.osdVisible = false }

    // Hover-out hide (matches the other popups' 600 ms grace period).
    Timer {
        id: notifHideTimer
        interval: 600; repeat: false
        onTriggered: root.notifPopupOpen = false
    }

    // ── Launchers ─────────────────────────────────────────────────────────
    Process { id: launchBluemanProc;     command: ["blueman-manager"] }
    Process { id: launchPavucontrolProc; command: ["pavucontrol"] }
    Process { id: launchNmtuiProc;       command: ["kitty", "nmtui"] }
    Process { id: playerctlToggleProc;   command: ["playerctl", "-p", "spotify", "play-pause"] }
    Process { id: playerctlNextProc;     command: ["playerctl", "-p", "spotify", "next"] }
    Process { id: playerctlPrevProc;     command: ["playerctl", "-p", "spotify", "previous"] }

    // Session-long Bluetooth pairing agent. Quickshell.Bluetooth ships no
    // pairing agent of its own, so BluetoothDevice.pair() can't complete a
    // bond without one — the link key never persists and reconnects die with
    // "br-connection-key-missing". Keep a bluetoothctl instance registered as
    // the default agent for the whole session (echo feeds the command, then
    // sleep holds stdin open so it stays alive) so in-shell pairing bonds.
    Process {
        id: btAgentProc
        running: true
        command: ["sh", "-c", "{ echo default-agent; sleep infinity; } | bluetoothctl"]
        onExited: btAgentRestart.restart()
    }
    Timer { id: btAgentRestart; interval: 2000; onTriggered: btAgentProc.running = true }

    // Snapshot the currently-active toplevel just before opening a keyboard-
    // grabbing overlay; `_pendingOverlay` tells us which one to actually
    // open once the address is in hand.
    Process {
        id: captureActiveProc
        command: ["hyprctl", "activewindow", "-j"]
        property string _buf: ""
        onRunningChanged: if (running) _buf = ""
        stdout: SplitParser {
            onRead: line => captureActiveProc._buf += line
        }
        onExited: {
            try {
                const d = JSON.parse(captureActiveProc._buf)
                root.lastFocusedAddr = d.address || ""
                console.log("[focus] captured", root.lastFocusedAddr, "class:", d.class, "title:", d.title)
            } catch(e) { root.lastFocusedAddr = ""; console.log("[focus] capture parse failed:", e) }
            switch (root._pendingOverlay) {
                case "launcher":  root.launcherOpen        = true; break
                case "clipboard": root.clipboardOpen       = true; root.refreshClipboard(); break
                case "wallpaper": root.wallpaperPickerOpen = true; root.refreshWallpapers(); break
            }
            root._pendingOverlay = ""
        }
    }

    // Refocus a specific toplevel by address. Lua-wrapped Hyprland selector
    // syntax: `hl.dsp.focus({window = "address:0x..."})`.
    Process {
        id: refocusByAddrProc
        property string target: ""
        command: ["hyprctl", "dispatch",
                  "hl.dsp.focus({window = \"address:" + target + "\"})"]
        stdout: SplitParser { onRead: line => console.log("[focus] dispatch stdout:", line) }
        stderr: SplitParser { onRead: line => console.log("[focus] dispatch stderr:", line) }
        onStarted: console.log("[focus] dispatching:", command.join(" "))
        onExited: (code) => {
            console.log("[focus] dispatch exited code=" + code)
            postRefocusProbe.running = false
            postRefocusProbe.running = true
        }
    }

    // After dispatching the refocus, probe activewindow to see what
    // Hyprland actually focused. If this is wrong, the dispatch was
    // misrouted; if it's empty, the surface is still hogging focus.
    Process {
        id: postRefocusProbe
        command: ["hyprctl", "activewindow", "-j"]
        property string _buf: ""
        onRunningChanged: if (running) _buf = ""
        stdout: SplitParser { onRead: line => postRefocusProbe._buf += line }
        onExited: {
            try {
                const d = JSON.parse(postRefocusProbe._buf)
                console.log("[focus] post-dispatch activewindow:", d.address, "class:", d.class)
            } catch(e) { console.log("[focus] probe parse failed; raw:", postRefocusProbe._buf) }
        }
    }

    // The overlay surface is destroyed immediately on close, releasing the
    // Wayland keyboard grab. A short delay lets that destroy + Hyprland's
    // own auto-refocus settle, then we dispatch focus to the exact window
    // that was active before we opened.
    Timer {
        id: refocusDelay
        interval: 120; repeat: false
        onTriggered: {
            if (!root.lastFocusedAddr) { console.log("[focus] no address to refocus"); return }
            refocusByAddrProc.target  = root.lastFocusedAddr
            refocusByAddrProc.running = false
            refocusByAddrProc.running = true
        }
    }

    // ── Volume step (wheel-driven from bar) ───────────────────────────────
    Process {
        id: setVolStepProc
        property string target: "2%+"
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", target]
        onExited: refreshVolumeAfterStep()
    }
    function refreshVolumeAfterStep() {
        volQueryProc.running = false
        volQueryProc.running = true
    }

    // ── Mute toggle ───────────────────────────────────────────────────────
    Process {
        id: toggleMuteProc
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        onExited: refreshVolumeAfterStep()
    }

    // ── Cava (audio visualizer) ─────────────────────────────────────────
    // Spawns cava with a fixed config; each stdout line is "v1;v2;...;vN;".
    // Values are normalised 0..1 against ascii_max_range (1000 in the conf).
    Process {
        id: cavaProc
        running: true
        command: ["cava", "-p", Qt.resolvedUrl("./cava.conf").toString().replace("file://", "")]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(";")
                const n = Math.min(parts.length - 1, root.cavaBarCount)
                const arr = new Array(root.cavaBarCount).fill(0)
                for (let i = 0; i < n; i++) {
                    const v = parseInt(parts[i]) || 0
                    arr[i] = Math.max(0, Math.min(1, v / 1000))
                }
                root.cavaValues = arr
            }
        }
        onExited: (code, status) => cavaRestartTimer.start()
    }
    Timer {
        id: cavaRestartTimer
        interval: 3000; repeat: false
        onTriggered: cavaProc.running = true
    }

    // ── Dashboard hide timer ────────────────────────────────────────────
    Timer {
        id: dashboardHideTimer
        interval: 300; repeat: false
        onTriggered: root.dashboardOpen = false
    }

    // ── Wallpaper list + setter (uses awww) ─────────────────────────────
    // Lists wallpapers ordered by file modification time (most recently added
    // first): `find -printf '<mtime>\t<path>'` then numeric reverse-sort on
    // mtime. Drives both the settings pane and the bottom-bar picker.
    Process {
        id: recentWallpapersProc
        environment: ({ DIR: root.wallpaperFolder })
        command: ["sh", "-c",
            "find \"$DIR\" -maxdepth 1 -type f " +
            "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' " +
            "   -o -iname '*.webp' -o -iname '*.bmp' \\) -printf '%T@\\t%p\\n' 2>/dev/null " +
            "| sort -rn | cut -f2-"]
        onRunningChanged: if (running) root._recentBuffer = []
        stdout: SplitParser {
            onRead: line => {
                const p = line.trim()
                if (p) root._recentBuffer.push(p)
            }
        }
        onExited: root.recentWallpapers = root._recentBuffer.slice()
    }

    // Background thumbnail generation (see scripts/wallpaper-thumbs.sh). While
    // it runs, tick periodically so grid Images retry loading thumbs as they
    // appear on disk; bump once more on exit for the final batch.
    Process {
        id: wallpaperThumbProc
        command: ["sh", "-c",
            Qt.resolvedUrl("./scripts/wallpaper-thumbs.sh").toString().replace("file://", "")
            + " \"$DIR\" \"$CACHE\" 400"]
        environment: ({ DIR: root.wallpaperFolder, CACHE: root.wallpaperThumbDir })
        onExited: root.wallpaperThumbTick++
    }
    Timer {
        id: wallpaperThumbPoll
        interval: 700; repeat: true
        running: wallpaperThumbProc.running
        onTriggered: root.wallpaperThumbTick++
    }

    // Apply the wallpaper, then rewrite the matching `path =` line in
    // hyprlock.conf so the lock screen background follows. Only lines
    // already pointing at the wallpaper folder are touched, so the
    // unrelated `user.png` entry stays put.
    Process {
        id: setWallpaperProc
        property string target: ""
        environment: ({
            WP:       target,
            HYPRLOCK: root.homeDir + "/.config/hypr/hyprlock.conf"
        })
        // awww caches each displayed image per-output, so `awww restore` at
        // login brings this back — no waypaper involved (see
        // scripts/restore-wallpaper.sh + hypr startup.lua).
        command: ["sh", "-c",
            "awww img --transition-type center --transition-duration 1.5 --transition-fps 60 \"$WP\" && " +
            "sed -i -E " +
            "\"s|^([[:space:]]*path[[:space:]]*=[[:space:]]*).*/Pictures/wallpaper/.*|\\1$WP|\" " +
            "\"$HYPRLOCK\""]
    }

    // ── Clipboard processes (cliphist) ──────────────────────────────────
    Process {
        id: clipboardListProc
        command: ["cliphist", "list"]
        onRunningChanged: if (running) root._clipboardBuffer = []
        stdout: SplitParser {
            onRead: line => {
                const t = line.indexOf("\t")
                if (t <= 0) return
                root._clipboardBuffer.push({
                    id:      line.substring(0, t),
                    preview: line.substring(t + 1)
                })
            }
        }
        onExited: root.clipboardList = root._clipboardBuffer.slice()
    }
    Process {
        id: copyClipboardProc
        property string target: ""
        environment: ({ ID: target })
        command: ["sh", "-c", "cliphist decode \"$ID\" | wl-copy"]
    }
    Process {
        id: deleteClipboardProc
        property string target: ""
        environment: ({ ID: target })
        // cliphist delete reads "id<TAB>preview" lines from stdin; pipe just
        // the matching one so we don't nuke unrelated entries.
        command: ["sh", "-c",
                  "cliphist list | awk -v id=\"$ID\" 'index($0,id\"\\t\")==1' | cliphist delete"]
        onExited: root.refreshClipboard()
    }

    // ── Keybinds parser (reads keybinds.lua) ────────────────────────────
    Process {
        id: keybindsProc
        command: ["python3",
                  Qt.resolvedUrl("./scripts/parse-keybinds.py")
                    .toString().replace("file://", "")]
        onRunningChanged: if (running) root._keybindsBuffer = []
        stdout: SplitParser {
            onRead: line => {
                const p = line.split("\t")
                if (p.length >= 3)
                    root._keybindsBuffer.push({ section: p[0], keys: p[1], desc: p[2] })
            }
        }
        onExited: root.keybindsList = root._keybindsBuffer.slice()
    }

    // ── Icon theme: initial read + scan + live monitor ──────────────────
    Process {
        id: iconThemeQueryProc
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"]
        stdout: SplitParser {
            onRead: line => {
                // gsettings returns quoted: 'Tela'
                const m = line.match(/'([^']+)'/) || line.match(/"([^"]+)"/)
                const t = (m ? m[1] : line.trim()) || "hicolor"
                if (t !== root.systemIconTheme) root.systemIconTheme = t
            }
        }
        onExited: root.rescanIcons()
    }

    Process {
        id: iconScanProc
        command: ["python3",
                  Qt.resolvedUrl("./scripts/icon-resolver.py")
                    .toString().replace("file://", ""),
                  root.systemIconTheme]
        onRunningChanged: if (running) root._iconMapBuffer = {}
        stdout: SplitParser {
            onRead: line => {
                const i = line.indexOf("\t")
                if (i > 0) root._iconMapBuffer[line.substring(0, i)]
                         = line.substring(i + 1)
            }
        }
        onExited: root.iconMap = root._iconMapBuffer
    }

    Process {
        id: iconThemeMonitorProc
        running: true
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "icon-theme"]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/'([^']+)'/)
                if (m && m[1] !== root.systemIconTheme) {
                    root.systemIconTheme = m[1]
                    root.rescanIcons()
                }
            }
        }
        onExited: iconThemeMonitorRestartTimer.start()
    }
    Timer {
        id: iconThemeMonitorRestartTimer
        interval: 3000; repeat: false
        onTriggered: iconThemeMonitorProc.running = true
    }

    // ── Weather (wttr.in JSON, refreshed every 15 min) ──────────────────
    // wttr.in returns multi-line JSON, so collect all lines then parse.
    // Persist + load the user's weather location preference
    Process {
        id: weatherLoadProc
        running: true
        command: ["sh", "-c", "cat \"$FILE\" 2>/dev/null || true"]
        environment: ({ FILE: root.configDir + "/weather-location.txt" })
        stdout: SplitParser {
            onRead: line => root.weatherLocation = line.trim()
        }
        onExited: root.refreshWeather()
    }
    Process {
        id: weatherSaveProc
        property string target: ""
        command: ["sh", "-c", "printf '%s' \"$LOC\" > \"$FILE\""]
        environment: ({ LOC: target, FILE: root.configDir + "/weather-location.txt" })
    }

    Process {
        id: weatherProc
        property string buffer: ""
        // Empty location → wttr.in auto-detects via IP; otherwise hits /<city>.
        command: ["sh", "-c",
            "curl -sSf --max-time 8 \"https://wttr.in/$LOC?format=j1\" || true"]
        environment: ({ LOC: encodeURIComponent(root.weatherLocation) })
        onRunningChanged: if (running) buffer = ""
        stdout: SplitParser {
            onRead: line => weatherProc.buffer += line + "\n"
        }
        onExited: (code, status) => {
            const buf = weatherProc.buffer
            if (!buf || buf.length < 50) return
            try {
                const j = JSON.parse(buf)
                const cur   = j.current_condition?.[0]
                const area  = j.nearest_area?.[0]
                const astro = j.weather?.[0]?.astronomy?.[0]
                if (!cur) return
                const wcode = parseInt(cur.weatherCode)
                root.weather = {
                    ready: true,
                    city:        area?.areaName?.[0]?.value ?? "",
                    region:      area?.region?.[0]?.value   ?? "",
                    temp:        cur.temp_C + "°C",
                    feelsLike:   cur.FeelsLikeC + "°C",
                    humidity:    cur.humidity,
                    windKph:     cur.windspeedKmph,
                    description: cur.weatherDesc?.[0]?.value ?? "",
                    icon:        wttrIcon(wcode),
                    sunrise:     astro?.sunrise ?? "",
                    sunset:      astro?.sunset  ?? "",
                    forecast:    (j.weather || []).map(d => ({
                        date:     d.date,
                        icon:     wttrIcon(parseInt(d.hourly?.[4]?.weatherCode ?? wcode)),
                        maxTempC: d.maxtempC,
                        minTempC: d.mintempC,
                        desc:     d.hourly?.[4]?.weatherDesc?.[0]?.value ?? ""
                    }))
                }
            } catch(e) {
                console.log("weather parse failed:", e)
            }
        }
    }
    // wttr.in WWO weather codes → Nerd Font weather glyphs
    function wttrIcon(code) {
        if (code === 113) return ""      // clear/sunny
        if ([116].includes(code)) return ""           // partly cloudy
        if ([119, 122].includes(code)) return ""      // cloudy / overcast
        if ([143, 248, 260].includes(code)) return "" // fog / mist
        if ([200, 386, 389, 392, 395].includes(code)) return "" // thunder
        if ([179, 182, 185, 227, 230, 320, 323, 326, 329, 332, 335,
             338, 350, 362, 365, 368, 371, 374, 377].includes(code)) return "" // snow/sleet
        if ([176, 263, 266, 281, 284, 293, 296, 299, 302, 305, 308,
             311, 314, 353, 356, 359].includes(code)) return ""    // rain
        return ""
    }
    Timer {
        id: weatherTimer
        interval: 15 * 60 * 1000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: root.refreshWeather()
    }

    // ── CPU usage (delta of /proc/stat aggregate row) ───────────────────
    Process {
        id: cpuProc
        property real prevTotal: 0
        property real prevIdle:  0
        command: ["sh", "-c", "head -n1 /proc/stat"]
        stdout: SplitParser {
            onRead: line => {
                // "cpu  user nice system idle iowait irq softirq steal ..."
                const f = line.trim().split(/\s+/).slice(1).map(Number)
                if (f.length < 4) return
                const idle  = f[3] + (f[4] || 0)
                const total = f.reduce((a, b) => a + b, 0)
                const dt = total - cpuProc.prevTotal
                const di = idle  - cpuProc.prevIdle
                if (cpuProc.prevTotal > 0 && dt > 0)
                    root.cpuPerc = Math.max(0, Math.min(1, 1 - (di / dt)))
                cpuProc.prevTotal = total
                cpuProc.prevIdle  = idle
            }
        }
    }

    // ── CPU temperature (hwmon, °C) ─────────────────────────────────────
    // hwmon indices aren't stable across boots, so resolve by chip name at
    // runtime: coretemp "Package id 0" (Intel), then k10temp Tctl/Tdie
    // (AMD), then the x86_pkg_temp thermal zone. Value read is in m°C.
    Process {
        id: cpuTempProc
        command: ["sh", "-c",
            "read_label() { " +
            "for h in /sys/class/hwmon/hwmon*; do " +
            "  [ \"$(cat \"$h/name\" 2>/dev/null)\" = \"$1\" ] || continue; " +
            "  for lf in \"$h\"/temp*_label; do " +
            "    [ -e \"$lf\" ] || continue; " +
            "    case \"$(cat \"$lf\" 2>/dev/null)\" in " +
            "      $2) cat \"${lf%_label}_input\" 2>/dev/null && return 0;; " +
            "    esac; " +
            "  done; " +
            "done; return 1; }; " +
            "read_label coretemp 'Package id 0' || " +
            "read_label k10temp 'Tctl' || " +
            "read_label k10temp 'Tdie' || " +
            "for z in /sys/class/thermal/thermal_zone*; do " +
            "  [ \"$(cat \"$z/type\" 2>/dev/null)\" = x86_pkg_temp ] && " +
            "  cat \"$z/temp\" 2>/dev/null && break; " +
            "done"]
        stdout: SplitParser {
            onRead: line => {
                const v = parseInt(line.trim())
                if (!isNaN(v) && v > 0) root.cpuTempC = v / 1000
            }
        }
    }

    // ── Memory (/proc/meminfo) ──────────────────────────────────────────
    Process {
        id: memProc
        property real total: 0
        property real avail: 0
        command: ["sh", "-c", "grep -E '^(MemTotal|MemAvailable):' /proc/meminfo"]
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/^(\w+):\s+(\d+)\s+kB/)
                if (!m) return
                if (m[1] === "MemTotal")     memProc.total = parseInt(m[2])
                if (m[1] === "MemAvailable") memProc.avail = parseInt(m[2])
            }
        }
        onExited: {
            if (memProc.total > 0) {
                root.memTotalKib = memProc.total
                root.memUsedKib  = Math.max(0, memProc.total - memProc.avail)
                root.memPerc     = root.memUsedKib / memProc.total
            }
        }
    }

    // ── System info: distro name (once) + uptime (every minute) ─────────
    Process {
        id: sysDistroProc
        running: true
        command: ["sh", "-c", ". /etc/os-release 2>/dev/null; echo \"$NAME\""]
        stdout: SplitParser { onRead: line => { const s = line.trim(); if (s) root.sysDistro = s } }
    }
    Process {
        id: sysUptimeProc
        command: ["uptime", "-p"]
        stdout: SplitParser { onRead: line => root.sysUptime = line.trim() }
    }
    Timer {
        id: sysUptimeTimer
        interval: 60000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: { sysUptimeProc.running = false; sysUptimeProc.running = true }
    }

    // Static hardware/OS details for the settings System pane, gathered once
    // as key=value lines and exposed as an object.
    property var sysInfo: ({})
    Process {
        id: sysInfoProc
        running: true
        command: ["sh", Qt.resolvedUrl("./scripts/system-info.sh").toString().replace("file://", "")]
        property var _acc: ({})
        onRunningChanged: if (running) _acc = ({})
        stdout: SplitParser {
            onRead: line => {
                const i = line.indexOf("=")
                if (i > 0) sysInfoProc._acc[line.slice(0, i)] = line.slice(i + 1).trim()
            }
        }
        onExited: root.sysInfo = sysInfoProc._acc
    }

    // ── Monitors: query (hyprctl) + apply (write lua + reload) ──────────
    Process {
        id: monitorQueryProc
        command: ["hyprctl", "monitors", "-j"]
        property string _buf: ""
        onRunningChanged: if (running) _buf = ""
        stdout: SplitParser { onRead: line => monitorQueryProc._buf += line }
        onExited: {
            try {
                const arr = JSON.parse(monitorQueryProc._buf)
                root.monitorList = arr.map(m => ({
                    name:        m.name,
                    description: m.description || "",
                    width:       m.width,
                    height:      m.height,
                    refresh:     Math.round((m.refreshRate || 0) * 100) / 100,
                    x:           m.x,
                    y:           m.y,
                    scale:       m.scale,
                    transform:   m.transform || 0,
                    disabled:    !!m.disabled,
                    modes:       (m.availableModes || []).map(s => s.replace(/Hz$/i, ""))
                }))
            } catch (e) { console.log("monitor parse failed:", e) }
        }
    }
    Process {
        id: monitorApplyProc
        property string cfgsJson: "[]"
        command: ["python3",
                  Qt.resolvedUrl("./scripts/apply-monitors.py").toString().replace("file://", ""),
                  cfgsJson]
        onExited: root.refreshMonitors()
    }

    // ── Disk (df / in bytes) ────────────────────────────────────────────
    Process {
        id: diskProc
        command: ["sh", "-c", "df -B1 --output=target,used,size / | tail -n1"]
        stdout: SplitParser {
            onRead: line => {
                const p = line.trim().split(/\s+/)
                if (p.length < 3) return
                root.diskMount  = p[0]
                root.diskUsedB  = parseFloat(p[1])
                root.diskTotalB = parseFloat(p[2])
                root.diskPerc   = root.diskTotalB > 0 ? root.diskUsedB / root.diskTotalB : 0
            }
        }
    }

    // ── Network (/proc/net/dev — sum of all non-lo interfaces) ──────────
    Process {
        id: netProc
        property real prevRx: 0
        property real prevTx: 0
        property real prevT:  0
        property real curRx:  0
        property real curTx:  0
        command: ["sh", "-c",
            "awk 'NR>2 && $1 !~ /^lo:/ {gsub(\":\",\"\",$1); rx+=$2; tx+=$10} END{print rx, tx}' /proc/net/dev"]
        stdout: SplitParser {
            onRead: line => {
                const p = line.trim().split(/\s+/).map(Number)
                if (p.length < 2) return
                netProc.curRx = p[0]
                netProc.curTx = p[1]
            }
        }
        onExited: {
            const now = Date.now() / 1000
            if (netProc.prevT > 0) {
                const dt = Math.max(0.001, now - netProc.prevT)
                root.netDownBps = Math.max(0, (netProc.curRx - netProc.prevRx) / dt)
                root.netUpBps   = Math.max(0, (netProc.curTx - netProc.prevTx) / dt)
                root.netDownHistory = root.netDownHistory.concat([root.netDownBps]).slice(-30)
                root.netUpHistory   = root.netUpHistory.concat([root.netUpBps]).slice(-30)
            }
            root.netDownTotal = netProc.curRx
            root.netUpTotal   = netProc.curTx
            netProc.prevRx = netProc.curRx
            netProc.prevTx = netProc.curTx
            netProc.prevT  = now
        }
    }

    Timer {
        id: perfTimer
        interval: 2000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: {
            cpuProc.running     = false; cpuProc.running     = true
            cpuTempProc.running = false; cpuTempProc.running = true
            memProc.running     = false; memProc.running     = true
            diskProc.running    = false; diskProc.running    = true
            netProc.running     = false; netProc.running     = true
        }
    }

    // ── Battery charge-state popups ──────────────────────────────────────
    // Fire a notification (so it shows as a toast + in the panel) when the
    // charger is plugged/unplugged. Guarded by _batReady so the initial
    // UPower population at startup doesn't spawn a spurious popup.
    property bool _batReady: false
    Timer { interval: 4000; repeat: false; running: true; onTriggered: { root._batReady = true; root._checkLowBattery() } }
    Process {
        id: batteryNotifyProc
        property string title: ""
        property string body:  ""
        property string icon:  "battery"
        command: ["notify-send", "-a", "Battery", "-u", "low",
                  "-h", "string:x-canonical-private-synchronous:battery-state",
                  "-i", icon, title, body]
    }
    function _notifyBattery() {
        const d = UPower.displayDevice
        const pct = (d && d.isPresent) ? "  •  " + Math.round(d.percentage * 100) + "%" : ""
        if (!UPower.onBattery) {
            const full = d && d.state === UPowerDeviceState.FullyCharged
            batteryNotifyProc.title = full ? "Fully charged" : "Charging"
            batteryNotifyProc.icon  = full ? "battery-full" : "battery-charging"
            batteryNotifyProc.body  = "Plugged in" + pct
        } else {
            batteryNotifyProc.title = "Discharging"
            batteryNotifyProc.icon  = "battery"
            batteryNotifyProc.body  = "On battery" + pct
        }
        batteryNotifyProc.running = false
        batteryNotifyProc.running = true
    }
    Connections {
        target: UPower
        function onOnBatteryChanged() {
            if (root._batReady) { root._notifyBattery(); root._checkLowBattery() }
        }
    }

    // ── Low-battery warning OSDs ─────────────────────────────────────────
    // Pop a GNOME-style OSD (same surface as volume / brightness / media)
    // when the charge crosses 15% / 10% / 5% while on battery. Each level
    // fires once per discharge cycle; plugging in — or climbing back above a
    // level — re-arms it so it can warn again next time.
    readonly property var _batLowLevels: [5, 10, 15]   // ascending = most-urgent first
    property var          _batWarned:    []             // levels already shown this cycle
    function _checkLowBattery() {
        const d = UPower.displayDevice
        if (!d || !d.isPresent) return
        const pct = Math.round(d.percentage * 100)
        // Charging / plugged in → clear all warnings so they can re-fire.
        if (!UPower.onBattery) { if (root._batWarned.length) root._batWarned = []; return }
        // Re-arm any levels we've since climbed back above.
        let warned = root._batWarned.filter(l => pct <= l)
        // The lowest crossed level not yet warned is the one to show.
        let fire = -1
        for (const lvl of root._batLowLevels)
            if (pct <= lvl && warned.indexOf(lvl) < 0) { fire = lvl; break }
        if (fire >= 0) {
            // Mark this and every less-urgent crossed level as warned too, so a
            // big jump (e.g. 20% → 4%) shows only the single most-urgent OSD.
            for (const lvl of root._batLowLevels) if (pct <= lvl) warned.push(lvl)
            const label = (fire <= 5 ? "Battery critically low" : "Battery low") + "  •  " + pct + "%"
            root.showOsd("battery", pct, false, label, false)
        }
        root._batWarned = warned
    }
    // displayDevice.percentage drives the check; the target rebinds if the
    // active battery device changes.
    Connections {
        target: UPower.displayDevice
        function onPercentageChanged() { if (root._batReady) root._checkLowBattery() }
    }

    // ── Shared design tokens (read by bar + overlays + settings) ─────────
    QtObject {
        id: theme
        // Palette switches with root.themeName ("dark" = current, "light" =
        // a white theme derived from it / Catppuccin Latte). All colours are
        // bindings so the whole shell recolours live when the theme changes.
        readonly property bool   light:     root.themeName === "light"
        readonly property color  bg:        light ? "#EFF1F5" : "#1E1E2E"
        readonly property color  fg:        light ? "#4C4F69" : "#f1dfda"
        readonly property color  sep:       light ? "#CCD0DA" : "#38375B"
        readonly property color  active:    light ? "#CCD0DA" : "#38375B"
        readonly property color  green:     "#1ed760"
        readonly property color  primary:   light ? "#1E66F5" : "#89B4FA"
        readonly property color  secondary: light ? "#EA76CB" : "#F5C2E7"
        readonly property color  tertiary:  light ? "#40A02B" : "#A6E3A1"
        readonly property color  warn:      light ? "#FE640B" : "#FAB387"
        readonly property color  error:     light ? "#D20F39" : "#F38BA8"
        readonly property color  surface:   light ? "#E6E9EF" : "#313244"
        readonly property color  surface2:  light ? "#DCE0E8" : "#45475A"
        // Input-field / track background. Darkening the bg only reads well on a
        // dark theme; on light, use near-white so dark text stays legible.
        readonly property color  field:     light ? "#FFFFFF" : Qt.darker(bg, 1.3)
        readonly property color  txt2:      light ? "#5C5F77" : "#CDD6F4"
        readonly property color  outline:   light ? "#9CA0B0" : "#6C7086"
        readonly property string ff:        "JetBrainsMono Nerd Font Propo"
        readonly property int    fs:        14
        readonly property int    ph:        30
        readonly property int    pr:        15

        // Highlight tint derived from `active`, used for hover / selected /
        // accent fills shell-wide. On the dark theme "more prominent" means
        // lighter; on light, `active` is already pale so lightening trends to
        // white (invisible) — there, darken by the same factor instead. Larger
        // f ⇒ more prominent in both themes. Reads `light`/`active`, so bound
        // call sites recolour live when the theme changes.
        function hi(f) { return light ? Qt.darker(active, f) : Qt.lighter(active, f) }
    }

    Component.onCompleted: {
        mediaProc.running     = true
        netStatusProc.running = true
        volQueryProc.running  = true
    }

    // ══════════════════════════════════════════════════════════════════════
    // UI components — defined under bar/ and overlays/.
    // ══════════════════════════════════════════════════════════════════════
    // One bar per monitor (toggle per-monitor via the settings Monitor pane).
    Variants {
        model: Quickshell.screens
        Bar {
            required property var modelData
            screen:      modelData
            monitorName: modelData.name
            shellRoot:   root
            theme:       root.themeRef
        }
    }

    SinkOverlay      { shellRoot: root; theme: theme; anchorWidth: root.rightPillWidth }
    BatteryOverlay   { shellRoot: root; theme: theme; anchorWidth: root.rightPillWidth }
    BluetoothOverlay { shellRoot: root; theme: theme; anchorWidth: root.rightPillWidth }
    WifiOverlay      { shellRoot: root; theme: theme; anchorWidth: root.rightPillWidth }
    CalendarOverlay  { shellRoot: root; theme: theme }
    DashboardOverlay { shellRoot: root; theme: theme }
    LauncherOverlay  { shellRoot: root; theme: theme }
    WallpaperOverlay { shellRoot: root; theme: theme }
    ClipboardOverlay { shellRoot: root; theme: theme }
    KeybindsOverlay  { shellRoot: root; theme: theme }
    ThemeOverlay     { shellRoot: root; theme: theme }
    PowerOverlay     { shellRoot: root; theme: theme }
    MonitorModeOverlay { shellRoot: root; theme: theme }
    OsdOverlay       { shellRoot: root; theme: theme }
    NotificationOverlay { shellRoot: root; theme: theme }
    NotificationToast   { shellRoot: root; theme: theme }

    // ── Settings window ────────────────────────────────────────────────────
    // Driven imperatively (not via `visible:` binding) because the WM close
    // button writes to `visible`, which would break a binding and prevent
    // future reopens. Connections push state in, signal pushes state back.
    SettingsWindow {
        id: settingsWindow
        shellRoot:  root
        theme:      theme
        activePane: root.settingsPane
        onCloseRequested: root.settingsOpen = false
    }

    Connections {
        target: root
        function onSettingsOpenChanged() {
            if (root.settingsOpen) { settingsWindow.show(); settingsFocusDelay.restart() }
            else                     settingsWindow.hide()
        }
    }

    // The settings window is a toplevel opened from the launcher (whose layer
    // closes in the same frame), so Hyprland often leaves the keyboard on the
    // app that was focused. Once it's mapped, explicitly focus it by title.
    Timer {
        id: settingsFocusDelay
        interval: 140; repeat: false
        onTriggered: { focusSettingsProc.running = false; focusSettingsProc.running = true }
    }
    Process {
        id: focusSettingsProc
        command: ["hyprctl", "dispatch", "hl.dsp.focus({window = \"title:Quickshell settings\"})"]
    }
}

