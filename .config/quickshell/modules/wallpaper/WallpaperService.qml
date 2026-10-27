pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Wallpapers: listing (newest-first), thumbnailing, applying (awww), the
// bottom picker, and the desktop widgets (cava strip + clock) toggled from
// the Wallpaper settings pane.
Singleton {
    id: root

    readonly property string wallpaperFolder: Paths.homeDir + "/Pictures/wallpaper"

    // ── Picker ──────────────────────────────────────────────────────────
    property bool wallpaperPickerOpen: false
    function openWallpaperPicker() {
        FocusService.captureThenOpen(() => { root.wallpaperPickerOpen = true; root.refreshWallpapers() })
    }
    function closeWallpaperPicker() { wallpaperPickerOpen = false }
    onWallpaperPickerOpenChanged: if (!wallpaperPickerOpen) FocusService.refocusLastWindow()

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

    // ── Listing + thumbnails ────────────────────────────────────────────
    // Shared by the settings pane and the picker.
    property var recentWallpapers: []
    property var _recentBuffer:    []

    // Thumb cache: the grid loads small JPEGs, not multi-MB originals.
    // thumbForWallpaper() maps path → thumb; wallpaperThumbTick bumps as
    // generation progresses so views retry.
    readonly property string wallpaperThumbDir: Paths.homeDir + "/.cache/quickshell/wallpaper-thumbs"
    property int  wallpaperThumbTick: 0
    // True while thumbnails are generating.
    readonly property bool wallpaperThumbBusy: wallpaperThumbProc.running
    function thumbForWallpaper(path) {
        if (!path) return ""
        return "file://" + wallpaperThumbDir + "/" + path.split("/").pop() + ".jpg"
    }

    // (Re)list wallpapers and regenerate missing/stale thumbnails.
    function refreshWallpapers() {
        recentWallpapersProc.running = false
        recentWallpapersProc.running = true
        wallpaperThumbProc.running = false
        wallpaperThumbProc.running = true
    }
    function setWallpaper(path) {
        setWallpaperProc.target = path
        setWallpaperProc.running = false
        setWallpaperProc.running = true
    }

    // ── Desktop widgets (state/wp-cava.txt, state/wp-clock.txt) ─────────
    // Cava strip + clock on a click-through layer (WallpaperWidgets.qml).
    property bool wpCavaEnabled:  false
    property bool wpClockEnabled: false
    function setWpCava(on) {
        root.wpCavaEnabled = !!on
        wpCavaFile.save(on ? "1" : "0")
    }
    function setWpClock(on) {
        root.wpClockEnabled = !!on
        wpClockFile.save(on ? "1" : "0")
    }
    StateFile {
        id: wpCavaFile
        name: "wp-cava.txt"
        onLoaded: lines => { if (lines.some(l => l.trim() === "1")) root.wpCavaEnabled = true }
    }
    StateFile {
        id: wpClockFile
        name: "wp-clock.txt"
        onLoaded: lines => { if (lines.some(l => l.trim() === "1")) root.wpClockEnabled = true }
    }

    // List wallpapers newest-first: find -printf '<mtime>\t<path>' | sort -rn.
    // Drives the settings pane and the bottom picker.
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

    // Thumbnail generation (wallpaper-thumbs.sh). Tick while running
    // so grid Images retry thumbs as they land; final bump on exit.
    Process {
        id: wallpaperThumbProc
        command: ["sh", "-c",
            Paths.local(Qt.resolvedUrl("wallpaper-thumbs.sh"))
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

    // Apply the wallpaper.
    Process {
        id: setWallpaperProc
        property string target: ""
        // awww caches per-output; `awww restore` at login re-applies it
        // (startup.lua).
        command: ["awww", "img", "--transition-type", "center",
                  "--transition-duration", "1.5", "--transition-fps", "60", target]
    }
}
