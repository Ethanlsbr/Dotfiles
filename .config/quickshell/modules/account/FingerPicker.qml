import QtQuick

// Two hands seen from above (back of the hands, as they rest on a desk):
// click a finger to pick it. Enrolled fingers are filled and carry a
// fingerprint mark; the picked one is outlined. Pure presentation — the
// Profile pane owns `picked` and acts on it.
Item {
    id: picker

    required property var theme
    property string picked: ""
    property var enrolled: []
    signal pick(string finger)

    implicitWidth: hands.implicitWidth
    implicitHeight: hands.implicitHeight

    // Right hand, thumb first (left to right): x, length, tilt and how far
    // below the palm's top edge the base sits, in a 160 × 170 box; the
    // left hand is the mirror image.
    readonly property var layout: [
        { f: "thumb",         x: 28,  h: 66, rot: -44, base: 58 },
        { f: "index-finger",  x: 40,  h: 74, rot: -6,  base: 22 },
        { f: "middle-finger", x: 68,  h: 84, rot: 0,   base: 22 },
        { f: "ring-finger",   x: 96,  h: 76, rot: 5,   base: 22 },
        { f: "little-finger", x: 122, h: 58, rot: 12,  base: 22 }
    ]
    readonly property int handW: 160
    readonly property int fingerW: 24
    readonly property int palmTop: 86

    Row {
        id: hands
        spacing: 56

        Repeater {
            model: ["left", "right"]
            delegate: Column {
                id: hand
                required property string modelData
                readonly property bool mirrored: modelData === "left"
                spacing: 8

                Item {
                    width: picker.handW
                    height: 170

                    // Fingers first, so the palm covers their bases.
                    Repeater {
                        model: picker.layout
                        delegate: Rectangle {
                            id: finger
                            required property var modelData
                            readonly property string name: hand.modelData + "-" + modelData.f
                            readonly property bool isEnrolled: picker.enrolled.indexOf(name) >= 0
                            readonly property bool isPicked: picker.picked === name

                            x: hand.mirrored ? picker.handW - modelData.x - picker.fingerW : modelData.x
                            y: picker.palmTop + modelData.base - modelData.h
                            width: picker.fingerW
                            height: modelData.h
                            radius: width / 2
                            transformOrigin: Item.Bottom
                            rotation: hand.mirrored ? -modelData.rot : modelData.rot

                            color: isEnrolled ? picker.theme.primary
                                 : isPicked ? Qt.rgba(picker.theme.primary.r, picker.theme.primary.g, picker.theme.primary.b, 0.28)
                                 : fingerHover.hovered ? Qt.lighter(picker.theme.surface2, 1.25)
                                 : picker.theme.surface2
                            border.width: isPicked ? 2 : 1
                            border.color: isPicked ? (isEnrolled ? picker.theme.fg : picker.theme.primary)
                                                   : Qt.rgba(picker.theme.sep.r, picker.theme.sep.g, picker.theme.sep.b, 0.9)
                            Behavior on color { ColorAnimation { duration: 140 } }

                            // Fingerprint mark on enrolled fingertips.
                            Text {
                                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 4 }
                                visible: finger.isEnrolled
                                text: "󰈷"
                                color: picker.theme.bg
                                font.family: picker.theme.ff; font.pixelSize: 15
                            }

                            HoverHandler { id: fingerHover }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -3
                                cursorShape: Qt.PointingHandCursor
                                onClicked: picker.pick(finger.name)
                            }
                        }
                    }

                    // Palm.
                    Rectangle {
                        x: hand.mirrored ? picker.handW - 36 - width : 36
                        y: picker.palmTop
                        width: 114; height: 78
                        radius: 28
                        color: picker.theme.surface2
                        border.width: 1
                        border.color: Qt.rgba(picker.theme.sep.r, picker.theme.sep.g, picker.theme.sep.b, 0.9)
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: hand.mirrored ? "Left hand" : "Right hand"
                    color: picker.theme.txt2
                    font.family: picker.theme.ff; font.pixelSize: picker.theme.fs - 3
                }
            }
        }
    }
}
