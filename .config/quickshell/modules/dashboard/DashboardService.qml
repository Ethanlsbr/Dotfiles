pragma Singleton
import QtQuick
import Quickshell
import qs.common

// Dashboard (hover-opened from the bar's Arch button) open state + tab, plus
// the user's choice of whether it opens at all and which tabs it shows
// (state/dashboard.txt, edited from Settings → Appearance).
Singleton {
    id: root

    property bool dashboardOpen: false
    property int  dashboardTab:  0  // 0=Dashboard 1=Media 2=Performance 3=Weather

    // Tab metadata, in tab order; `idx` is the dashboardTab value.
    readonly property var tabs: [
        { idx: 0, key: "dashboard",   label: "Dashboard",   icon: "󰕮",
          description: "Weather, clock, system info, resources and media at a glance" },
        { idx: 1, key: "media",       label: "Media",       icon: "󰝚",
          description: "Full player with artwork and controls" },
        { idx: 2, key: "performance", label: "Performance", icon: "󰓅",
          description: "CPU, memory and disk usage" },
        { idx: 3, key: "weather",     label: "Weather",     icon: "\uf0c2",
          description: "Current conditions and forecast" }
    ]

    // ── Settings ─────────────────────────────────────────────────────────
    property bool dashboardEnabled: true
    property var  tabEnabled: [true, true, true, true]
    // Indices of the shown tabs, in order.
    readonly property var visibleTabs: tabs.filter(t => tabEnabled[t.idx]).map(t => t.idx)

    function isTabEnabled(i) { return !!root.tabEnabled[i] }
    function setDashboardEnabled(on) {
        root.dashboardEnabled = !!on
        if (!root.dashboardEnabled) closeDashboard()
        _save()
    }
    function setTabEnabled(i, on) {
        if (i < 0 || i >= root.tabs.length) return
        // Always keep at least one tab.
        if (!on && root.visibleTabs.length <= 1 && root.tabEnabled[i]) return
        const t = root.tabEnabled.slice()
        t[i] = !!on
        root.tabEnabled = t
        _ensureValidTab()
        _save()
    }
    function _ensureValidTab() {
        if (root.visibleTabs.indexOf(root.dashboardTab) < 0 && root.visibleTabs.length > 0)
            root.dashboardTab = root.visibleTabs[0]
    }
    // File format: "enabled 0|1" and "tabs <key>,<key>,…" (the shown tabs).
    function _save() {
        const keys = root.tabs.filter(t => root.tabEnabled[t.idx]).map(t => t.key)
        settingsFile.save("enabled " + (root.dashboardEnabled ? 1 : 0) + "\ntabs " + keys.join(","))
    }
    StateFile {
        id: settingsFile
        name: "dashboard.txt"
        onLoaded: lines => {
            for (const line of lines) {
                const m = line.trim().match(/^(\w+)\s*(.*)$/)
                if (!m) continue
                if (m[1] === "enabled") {
                    root.dashboardEnabled = m[2].trim() !== "0"
                } else if (m[1] === "tabs") {
                    const keys = m[2].split(",").map(k => k.trim())
                    const t = root.tabs.map(tab => keys.indexOf(tab.key) >= 0)
                    if (t.some(v => v)) root.tabEnabled = t
                }
            }
            root._ensureValidTab()
        }
    }

    // ── Open / close ─────────────────────────────────────────────────────
    function openDashboard() {
        if (!root.dashboardEnabled) return
        dashboardHideTimer.stop(); dashboardOpen = true
    }
    function closeDashboard() { dashboardHideTimer.stop(); dashboardOpen = false }
    function showDashboardTab(i) {
        if (!root.isTabEnabled(i)) return
        dashboardTab = i; openDashboard()
    }
    function startDashboardHide() { dashboardHideTimer.restart() }
    function stopDashboardHide()  { dashboardHideTimer.stop() }

    // Bar trigger hover: opens after a 500 ms dwell so passing the cursor
    // over the bar doesn't pop the dashboard; leaving cancels it.
    function hoverDashboard(on) {
        if (on) {
            if (dashboardOpen) stopDashboardHide()
            else dashboardShowTimer.restart()
        } else {
            dashboardShowTimer.stop()
            startDashboardHide()
        }
    }
    Timer {
        id: dashboardShowTimer
        interval: 500; repeat: false
        onTriggered: root.openDashboard()
    }

    Timer {
        id: dashboardHideTimer
        interval: 300; repeat: false
        onTriggered: root.dashboardOpen = false
    }
}
