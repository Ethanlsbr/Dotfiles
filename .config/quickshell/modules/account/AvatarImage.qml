import QtQuick
import Quickshell

// The profile picture: AccountService's PNG, replaced by its GIF when the
// picture is animated. The PNG is the GIF's first frame, so it shows while
// the GIF loads, if it fails, and whenever the picture isn't on screen (the
// GIF is only kept loaded while it plays).
Item {
    id: root

    // Off: no picture at all (status stays Image.Null).
    property bool active: true
    // Off: hold the first frame, for a picture hidden by opacity.
    property bool playing: true
    property alias cache: still.cache
    property alias sourceSize: still.sourceSize
    readonly property int status: still.status

    Image {
        id: still
        anchors.fill: parent
        visible: !gif.item || gif.item.status !== Image.Ready
        source: root.active ? AccountService.avatarUrl : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Loader {
        id: gif
        anchors.fill: parent
        active: root.active && root.playing && root.visible && AccountService.avatarAnimated
                && (QsWindow.window?.visible ?? true)
        sourceComponent: AnimatedImage {
            source: AccountService.avatarGifUrl
            fillMode: Image.PreserveAspectCrop
            cache: false
            mipmap: true
        }
    }
}
