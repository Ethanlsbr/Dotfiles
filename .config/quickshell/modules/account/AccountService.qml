pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The logged-in user, for the settings Profile pane, its sidebar header and
// the dashboard.
// The avatar is ~/.config/hypr/user.png — also hyprlock's. Changing it is two
// steps: pickAvatar() (zenity) loads the image into the cropper
// (cropSource), then applyCrop() saves the chosen circle as a 512×512 PNG
// with transparent corners.
Singleton {
    id: root

    readonly property string userName: Quickshell.env("USER") ?? ""
    // Full name from the passwd GECOS field ("" when unset).
    property string realName: ""
    readonly property string displayName: realName || userName
    property string hostName: ""
    // From passwd + `id`.
    property string uid: ""
    property string gid: ""
    property string shell: ""
    property string homeDir: ""
    property var    groups: []
    // Session, from the environment the shell was started in.
    readonly property string sessionType: Quickshell.env("XDG_SESSION_TYPE") ?? ""
    readonly property string desktop:     Quickshell.env("XDG_CURRENT_DESKTOP") ?? ""

    readonly property string avatarPath: Paths.homeDir + "/.config/hypr/user.png"
    // Bumped after each change so Images reload instead of serving a cached copy.
    property int avatarRev: 0
    readonly property string avatarUrl: "file://" + avatarPath + "?rev=" + avatarRev
    // Whether a picture is set (re-checked after every change).
    property bool hasAvatar: false

    property bool picking: false
    function pickAvatar() {
        if (picking || saving) return
        picking = true
        pickProc.running = true
    }

    // Cropper input: an auto-oriented PNG copy (≤2048 px) of the picked
    // image, so what the cropper shows maps 1:1 onto what gets cropped.
    readonly property string cropPath: Paths.homeDir + "/.cache/quickshell/avatar-source.png"
    property int    cropRev: 0
    // Non-empty while the cropper is open.
    property string cropSource: ""
    property bool   saving: false

    // x/y/size: the circle's bounding square, in cropPath pixels.
    function applyCrop(x, y, size) {
        if (saving) return
        saving = true
        cropProc.geometry = size + "x" + size + "+" + x + "+" + y
        cropProc.running = false
        cropProc.running = true
    }
    function cancelCrop() { cropSource = "" }
    // Back to the placeholder glyph (hyprlock then shows no avatar either).
    function removeAvatar() {
        removeProc.running = false
        removeProc.running = true
    }

    Process {
        running: true
        command: ["getent", "passwd", root.userName]
        stdout: SplitParser {
            onRead: line => {
                // name:pw:uid:gid:gecos:home:shell
                const f = line.split(":")
                root.uid      = f[2] || ""
                root.gid      = f[3] || ""
                root.realName = (f[4] || "").split(",")[0].trim()
                root.homeDir  = f[5] || ""
                root.shell    = f[6] || ""
            }
        }
    }
    Process {
        running: true
        command: ["sh", "-c", "cat /etc/hostname 2>/dev/null || hostname"]
        stdout: SplitParser { onRead: line => { if (line.trim()) root.hostName = line.trim() } }
    }

    Process {
        running: true
        command: ["id", "-Gn"]
        stdout: SplitParser { onRead: line => root.groups = line.trim().split(/\s+/).filter(g => g) }
    }

    Process {
        id: avatarCheckProc
        running: true
        environment: ({ F: root.avatarPath })
        command: ["sh", "-c", "test -f \"$F\""]
        onExited: code => root.hasAvatar = code === 0
    }
    function _avatarChanged() {
        avatarRev++
        avatarCheckProc.running = false
        avatarCheckProc.running = true
    }
    Process {
        id: removeProc
        environment: ({ F: root.avatarPath })
        command: ["sh", "-c", "rm -f \"$F\""]
        onExited: root._avatarChanged()
    }

    // Pick an image and prepare the cropper's copy. A cancelled picker (or
    // an unreadable file) exits non-zero and leaves everything alone.
    Process {
        id: pickProc
        environment: ({ TMP: root.cropPath, START: Paths.homeDir + "/Pictures/" })
        command: ["sh", "-c",
            "f=$(zenity --file-selection --title='Choose a profile picture' --filename=\"$START\" " +
            "--file-filter='Images | *.png *.jpg *.jpeg *.webp *.bmp *.gif' 2>/dev/null) || exit 1; " +
            "mkdir -p \"$(dirname \"$TMP\")\" && " +
            "magick \"$f[0]\" -auto-orient -resize '2048x2048>' \"png:$TMP\""]
        onExited: code => {
            root.picking = false
            if (code !== 0) return
            root.cropRev++
            root.cropSource = "file://" + root.cropPath + "?rev=" + root.cropRev
        }
    }

    // Crop the chosen square, scale to 512, mask to a circle.
    Process {
        id: cropProc
        property string geometry: ""
        environment: ({ TMP: root.cropPath, OUT: root.avatarPath, GEO: geometry })
        command: ["sh", "-c",
            "mkdir -p \"$(dirname \"$OUT\")\" && " +
            "magick \"$TMP\" -crop \"$GEO\" +repage -resize '512x512!' " +
            "\\( -size 512x512 xc:black -fill white -draw 'circle 256,256 256,0' \\) " +
            "-alpha off -compose CopyOpacity -composite \"png:$OUT\""]
        onExited: code => {
            root.saving = false
            if (code !== 0) { console.log("avatar crop failed, code", code); return }
            root.cropSource = ""
            root._avatarChanged()
        }
    }
}
