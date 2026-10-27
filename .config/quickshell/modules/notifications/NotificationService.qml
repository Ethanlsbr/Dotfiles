pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.common
import qs.modules.osd

// Notification daemon (Quickshell owns org.freedesktop.Notifications —
// swaync must not run), do-not-disturb, and the transient toast queue.
Singleton {
    id: root

    // Bell icon: any pending notification (from the server's tracked list).
    property string notifIcon:  dndEnabled
                                ? "󰂛"
                                : (notifServer.trackedNotifications.values.length > 0 ? "󰵙" : "󰂚")
    // Exposed so overlays can read the tracked notification list.
    readonly property alias notifServer: notifServer
    property bool   dndEnabled:  false
    function toggleDnd() { root.dndEnabled = !root.dndEnabled }

    // External control: `qs ipc call notifications toggle|open|close`
    IpcHandler {
        target: "notifications"
        function toggle() {
            if (PopupService.notifPopupOpen) PopupService.notifPopupOpen = false
            else                             PopupService.showPopup("notif")
        }
        function open()   { PopupService.showPopup("notif")     }
        function close()  { PopupService.notifPopupOpen = false }
    }

    function toggleNotifPanel() { PopupService.notifPopupOpen = !PopupService.notifPopupOpen }
    function clearAllNotifs() {
        const list = [...notifServer.trackedNotifications.values]
        for (const n of list) n.dismiss()
        for (let i = 0; i < toastModel.count; i++) toastModel.setProperty(i, "closing", true)
        _recount()
    }
    function dismissNotif(n) { if (n) { removeToast(n); n.dismiss() } }

    // ── Transient toasts (shown briefly when a notification arrives) ─────
    // Volume/brightness/media fire per key-press; their sync hint isn't
    // honoured, so same-group notifications update the toast in place.
    // Removal is two-step so toasts close like the bar popups: removeToast()
    // flags the entry `closing` (the toast plays its exit animation), then
    // the presenter drops it (_dropToastAt / _dropClosing) once it's gone.
    // Presenter: BarToastPanel, hanging from the bar's right pill; the
    // floating NotificationToast only when no bar shows them.
    ListModel { id: toastModel; dynamicRoles: true }
    readonly property alias toasts: toastModel
    readonly property int toastCount: toastModel.count
    // Toasts not yet closing (what's actually on screen).
    property int openToastCount: 0
    // A bar's toast panel is presenting the toasts (set by BarToastPanel).
    property bool barToastHost: false
    // How far that panel has opened (0..1) — the pill squares its bottom
    // corners with it, like for the hover popups.
    property real toastProgress: 0

    function _recount() {
        let n = 0
        for (let i = 0; i < toastModel.count; i++) if (!toastModel.get(i).closing) n++
        openToastCount = n
    }

    // Plain copy of a notification for the toast content (the object is
    // destroyed when dismissed, possibly mid exit animation).
    function snapshot(n) {
        return n ? { appName: n.appName, summary: n.summary, body: n.body,
                     image: n.image, appIcon: n.appIcon, urgency: n.urgency } : null
    }

    function notifGroup(n) {
        const s = (n && n.summary ? String(n.summary) : "").toLowerCase()
        if (s.indexOf("brightness") === 0)                            return "brightness"
        if (s.indexOf("volume") === 0    || s.indexOf("mic-level") === 0 ||
            s.indexOf("microphone") === 0)                            return "audio"
        if (s.indexOf("now playing") === 0 || s.indexOf("media ") === 0 ||
            s.indexOf("playback ") === 0)                             return "media"
        // Charging / Discharging / Fully charged (BatteryService) → one
        // updating OSD. Prefixes only: a match anywhere in the summary
        // ("mute", "charg") hijacked unrelated notifications into the OSD.
        if (/^(charging|discharging|fully charged)\b/.test(s))       return "battery"
        return ""
    }

    function addToast(n) {
        const g = root.notifGroup(n)
        if (g !== "") {
            for (let i = 0; i < toastModel.count; i++) {
                if (toastModel.get(i).gid === g) {
                    const old = toastModel.get(i).notif
                    toastModel.set(i, { notif: n, gid: g, closing: false })   // update existing toast in place
                    if (old && old !== n) old.dismiss()        // drop the superseded one from history too
                    _recount()
                    return
                }
            }
        }
        toastModel.append({ notif: n, gid: g, closing: false })
        _recount()
    }
    function removeToast(n) {
        for (let i = 0; i < toastModel.count; i++) {
            if (toastModel.get(i).notif === n) { closeToastAt(i); return }
        }
    }
    function closeToastAt(i) {
        if (i < 0 || i >= toastModel.count) return
        toastModel.setProperty(i, "closing", true)
        _recount()
    }
    function _dropToastAt(i) {
        if (i >= 0 && i < toastModel.count && toastModel.get(i).closing) toastModel.remove(i)
    }
    // Drop every closing toast (the panel finished shrinking back).
    function _dropClosing() {
        for (let i = toastModel.count - 1; i >= 0; i--)
            if (toastModel.get(i).closing) toastModel.remove(i)
    }

    // ── Notifications (native Quickshell daemon) ─────────────────────────
    // Quickshell owns org.freedesktop.Notifications — swaync must not run.
    NotificationServer {
        id: notifServer
        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        actionIconsSupported: true
        imageSupported: true
        // Track until dismissed so the panel can list them.
        onNotification: n => {
            // Volume/brightness/media/battery → bottom OSD; never tracked
            // or toasted.
            const g = root.notifGroup(n)
            if (g === "audio" || g === "brightness" || g === "media" || g === "battery") {
                OsdService.showFromNotification(g, n)
                n.tracked = false
                return
            }
            n.tracked = true
            // Toast it (also stays tracked for the panel); the panel itself
            // only opens on hover.
            if (!root.dndEnabled) root.addToast(n)
        }
    }
}
