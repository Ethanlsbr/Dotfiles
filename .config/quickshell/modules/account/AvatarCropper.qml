import QtQuick

// Modal circular cropper for a new profile picture (AccountService.cropSource).
// Drag to move, scroll or use the slider to zoom (1–4×); the image always
// covers the circle. Save hands the circle's bounding square, in source
// pixels, to AccountService.applyCrop().
Rectangle {
    id: cropper

    required property var theme

    color: "#b3000000"

    // Swallow input to the pane underneath.
    MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: wheel => wheel.accepted = true }

    // Viewport side; the crop circle is inscribed in it.
    readonly property int  vp: 300
    readonly property real minZoom: 1
    readonly property real maxZoom: 4
    property real zoom: 1
    // "Cover" fit at zoom 1, so the circle never shows empty space.
    readonly property real baseScale: img.implicitWidth > 0
        ? Math.max(vp / img.implicitWidth, vp / img.implicitHeight) : 1
    readonly property real imgScale: baseScale * zoom
    // Image top-left in viewport coordinates.
    property real ix: 0
    property real iy: 0

    function clampPos() {
        const w = img.implicitWidth * imgScale, h = img.implicitHeight * imgScale
        ix = Math.min(0, Math.max(vp - w, ix))
        iy = Math.min(0, Math.max(vp - h, iy))
    }
    function reset() {
        zoom = 1
        ix = (vp - img.implicitWidth * imgScale) / 2
        iy = (vp - img.implicitHeight * imgScale) / 2
    }
    // Zoom about the viewport centre.
    function setZoom(z) {
        z = Math.max(minZoom, Math.min(maxZoom, z))
        const cx = (vp / 2 - ix) / imgScale, cy = (vp / 2 - iy) / imgScale
        zoom = z
        ix = vp / 2 - cx * imgScale
        iy = vp / 2 - cy * imgScale
        clampPos()
    }
    function save() {
        const W = img.implicitWidth, H = img.implicitHeight
        const size = Math.max(1, Math.min(Math.round(vp / imgScale), W, H))
        const x = Math.max(0, Math.min(W - size, Math.round(-ix / imgScale)))
        const y = Math.max(0, Math.min(H - size, Math.round(-iy / imgScale)))
        AccountService.applyCrop(x, y, size)
    }

    // ── Pill button ──────────────────────────────────────────────────────
    component PillButton: Rectangle {
        id: btn
        property string label: ""
        property bool   primary: false
        signal clicked()

        width: btnLabel.implicitWidth + 32
        height: 34
        radius: 10
        color: primary
               ? (btnHover.hovered ? Qt.lighter(cropper.theme.primary, 1.1) : cropper.theme.primary)
               : (btnHover.hovered ? cropper.theme.hi(1.6) : cropper.theme.hi(1.3))
        Behavior on color { ColorAnimation { duration: 120 } }

        HoverHandler { id: btnHover }
        Text {
            id: btnLabel
            anchors.centerIn: parent
            text: btn.label
            color: btn.primary ? cropper.theme.bg : cropper.theme.fg
            font.family: cropper.theme.ff; font.bold: true; font.pixelSize: cropper.theme.fs - 1
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: col.implicitWidth + 48
        height: col.implicitHeight + 40
        radius: 16
        color: cropper.theme.bg
        border.color: cropper.theme.sep
        border.width: 1

        Column {
            id: col
            anchors.centerIn: parent
            spacing: 16

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Crop profile picture"
                color: cropper.theme.fg
                font.family: cropper.theme.ff; font.bold: true; font.pixelSize: cropper.theme.fs + 2
            }

            // ── Viewport: image + circular mask ──────────────────────────
            Item {
                id: viewport
                anchors.horizontalCenter: parent.horizontalCenter
                width: cropper.vp; height: cropper.vp
                clip: true

                Rectangle { anchors.fill: parent; color: cropper.theme.surface2 }

                Image {
                    id: img
                    source: AccountService.cropSource
                    cache: false
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    x: cropper.ix
                    y: cropper.iy
                    width:  implicitWidth  * cropper.imgScale
                    height: implicitHeight * cropper.imgScale
                    onStatusChanged: if (status === Image.Ready) cropper.reset()
                }

                // Dim everything outside the circle; outline the circle.
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const r = width / 2
                        ctx.fillStyle = "rgba(0, 0, 0, 0.6)"
                        ctx.fillRule = Qt.OddEvenFill
                        ctx.beginPath()
                        ctx.rect(0, 0, width, height)
                        ctx.arc(r, r, r - 1, 0, 2 * Math.PI)
                        ctx.fill()
                        ctx.strokeStyle = "rgba(255, 255, 255, 0.85)"
                        ctx.lineWidth = 2
                        ctx.beginPath()
                        ctx.arc(r, r, r - 1, 0, 2 * Math.PI)
                        ctx.stroke()
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property real px: 0
                    property real py: 0
                    onPressed: mouse => { px = mouse.x; py = mouse.y }
                    onPositionChanged: mouse => {
                        cropper.ix += mouse.x - px
                        cropper.iy += mouse.y - py
                        px = mouse.x; py = mouse.y
                        cropper.clampPos()
                    }
                    onWheel: wheel => cropper.setZoom(cropper.zoom * (wheel.angleDelta.y > 0 ? 1.1 : 1 / 1.1))
                }

                Text {
                    anchors.centerIn: parent
                    visible: img.status !== Image.Ready
                    text: img.status === Image.Error ? "Couldn't load image" : "Loading…"
                    color: cropper.theme.txt2
                    font.family: cropper.theme.ff; font.pixelSize: cropper.theme.fs - 1
                }
            }

            // ── Zoom slider ──────────────────────────────────────────────
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    color: cropper.theme.txt2
                    font.family: cropper.theme.ff; font.pixelSize: cropper.theme.fs
                }
                Item {
                    id: slider
                    anchors.verticalCenter: parent.verticalCenter
                    width: 220; height: 20
                    readonly property real frac: (cropper.zoom - cropper.minZoom) / (cropper.maxZoom - cropper.minZoom)

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 4; radius: 2
                        color: cropper.theme.surface2
                        Rectangle {
                            width: parent.width * slider.frac
                            height: parent.height; radius: 2
                            color: cropper.theme.primary
                        }
                    }
                    Rectangle {
                        width: 14; height: 14; radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        x: slider.frac * (slider.width - width)
                        color: cropper.theme.primary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function apply(mx) {
                            const f = Math.max(0, Math.min(1, mx / width))
                            cropper.setZoom(cropper.minZoom + f * (cropper.maxZoom - cropper.minZoom))
                        }
                        onPressed: mouse => apply(mouse.x)
                        onPositionChanged: mouse => apply(mouse.x)
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    color: cropper.theme.txt2
                    font.family: cropper.theme.ff; font.pixelSize: cropper.theme.fs
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                PillButton {
                    label: "Cancel"
                    onClicked: AccountService.cancelCrop()
                }
                PillButton {
                    primary: true
                    label: AccountService.saving ? "Saving…" : "Save"
                    onClicked: if (img.status === Image.Ready) cropper.save()
                }
            }
        }
    }
}
