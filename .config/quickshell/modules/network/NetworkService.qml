pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.modules.settings

// Network status icon (reactive via `nmcli monitor`) and Wi-Fi: scan,
// connect (open / saved / password / WPA-Enterprise), forget, toggle.
Singleton {
    id: root

    property string netIcon:    "󰌙"
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
    // Saved network being connected to — its row shows "Connecting…"
    // (new networks only get it on the password form's button). Kept
    // past a successful connect until the list refresh marks it active, so
    // the row goes straight to "Connected" instead of flashing "Connect".
    property string wifiConnectingSsid: ""
    // Prompt origin ("overlay" | "settings") — only that pane shows it.
    property string wifiPasswordSource: ""
    // Pending prompt is WPA-Enterprise → settings shows identity/EAP fields.
    property bool   wifiPasswordEnterprise: false

    // ── Wifi helpers ─────────────────────────────────────────────────────
    // Debounced — coalesces nmcli's event burst into one rebuild.
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
        wifiConnectingSsid        = wifiSaved.indexOf(ssid) >= 0 ? ssid : ""
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
    // WPA-Enterprise connect: explicit nmcli profile with the chosen EAP
    // method; phase2/anonId optional.
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
        wifiConnectingSsid     = ""
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
        // Rescan returns instantly; hold the spinner a minimum window for
        // feedback and results.
        wifiScanMinTimer.restart()
        wifiRescanProc.running = false
        wifiRescanProc.running = true
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

    // setpriv: ends with the shell even if it crashes (no orphan).
    Process {
        id: nmcliMonitor
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "--", "nmcli", "monitor"]
        environment: ({ LANG: "C.UTF-8", LC_ALL: "C.UTF-8" })
        stdout: SplitParser {
            onRead: _ => {
                netStatusProc.running = false
                netStatusProc.running = true
                // Coalesce nmcli's switch-time event burst into one refresh.
                if (PopupService.wifiPopupOpen || SettingsService.settingsOpen) wifiRefreshDebounce.restart()
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
    // nmcli -t escapes ':' as '\:'; swap those for NUL before splitting,
    // restore after.
    Process {
        id: wifiQueryProc
        running: false
        environment: ({ LANG: "C.UTF-8", LC_ALL: "C.UTF-8" })
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY",
                 "device", "wifi", "list"]
        onRunningChanged: if (running) root._wifiBuffer = []
        stdout: SplitParser {
            onRead: line => {
                const parts = line.replace(/\\:/g, "\u0000")
                                  .split(":")
                                  .map(p => p.replace(/\u0000/g, ":"))
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
            // Push a new array only on real changes — otherwise every
            // Repeater row re-instantiates.
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
            if (!root.wifiConnecting) root.wifiConnectingSsid = ""
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
    // Secured: try the saved profile first; on failure fall back to a prompt.
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
                    // Clear the connecting state before the prompt appears
                    // so its button never starts out as "Connecting…".
                    root.wifiConnecting     = false
                    root.wifiConnectingSsid = ""
                    root.wifiPasswordSsid   = wifiTryConnectProc.targetSsid
                    root.wifiPasswordError  = ""
                    root.wifiPasswordOpen   = true
                }
            }
        }
        onExited: (code) => {
            if (!root.wifiPasswordOpen) root.wifiConnecting = false
            if (code !== 0) root.wifiConnectingSsid = ""
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
                // Auth fail leaves a half-saved profile; delete it so the
                // next attempt re-prompts.
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
    // `device wifi connect` can't carry 802.1X settings — build an explicit
    // profile. CA-cert validation off (captive eduroam-style nets).
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
                // Drop the half-saved profile so the next attempt re-prompts.
                wifiCleanupProc.targetSsid = wifiEapConnectProc.targetSsid
                wifiCleanupProc.running    = false
                wifiCleanupProc.running    = true
                root.wifiPasswordError = "Authentication failed — check identity & password"
            }
        }
    }

    Process {
        id: wifiDisconnectProc
        // Disconnect the active wifi device (name resolved first).
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

    function launchNmtui() { launchNmtuiProc.running = false; launchNmtuiProc.running = true }
    Process { id: launchNmtuiProc; command: ["kitty", "nmtui"] }

    Component.onCompleted: netStatusProc.running = true
}
