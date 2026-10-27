import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs.modules.account
import qs.modules.battery
import qs.modules.power

// One monitor's lockscreen, Windows 11 style: wallpaper + big clock; any
// key / click blurs it and brings up avatar, name and the password field.
// State lives in LockService so every monitor shows the same thing.
FocusScope {
    id: root

    required property var theme
    property string screenName: ""

    readonly property bool prompt: LockService.prompt
    readonly property color ink: "white"
    readonly property color inkDim: Qt.rgba(1, 1, 1, 0.72)
    // Text face closest to Segoe UI; theme.ff (Nerd Font) stays for icons.
    readonly property string sans: "Noto Sans"

    focus: true
    Component.onCompleted: forceActiveFocus()

    // Fades out before the lock is released.
    opacity: LockService.unlocking ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

    Keys.onPressed: e => {
        LockService.poke()
        if (e.key === Qt.Key_Shift || e.key === Qt.Key_Control || e.key === Qt.Key_Alt
                || e.key === Qt.Key_Meta || e.key === Qt.Key_Super_L || e.key === Qt.Key_Super_R
                || e.key === Qt.Key_CapsLock) return
        const printable = e.text.length > 0 && e.text.charCodeAt(0) >= 32
                          && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier))
        if (!LockService.prompt) {
            // The waking key only reveals the field; it isn't typed into it.
            if (e.key !== Qt.Key_Escape) LockService.showPrompt()
        } else if (e.key === Qt.Key_Escape) {
            powerMenu.open = false
            LockService.hidePrompt()
        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            LockService.submit()
        } else if (e.key === Qt.Key_Backspace) {
            LockService.backspace(e.modifiers & Qt.ControlModifier)
        } else if (e.key === Qt.Key_U && (e.modifiers & Qt.ControlModifier)) {
            LockService.backspace(true)
        } else if (printable) {
            LockService.type(e.text)
        }
        e.accepted = true
    }

    // Click anywhere: curtain → prompt (and closes the power menu).
    MouseArea {
        anchors.fill: parent
        onClicked: {
            LockService.poke()
            powerMenu.open = false
            LockService.showPrompt()
            root.forceActiveFocus()
        }
    }

    // ── Background ───────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: "black" }
    Image {
        id: wallpaper
        anchors.fill: parent
        visible: false
        source: LockService.wallpaperFor(root.screenName) ? "file://" + LockService.wallpaperFor(root.screenName) : ""
        sourceSize: Qt.size(root.width, root.height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: root.prompt ? 1 : 0
        brightness: root.prompt ? -0.18 : -0.04
        Behavior on blur { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on brightness { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
    }
    // Soft bottom shade so the status icons stay legible.
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: parent.height * 0.35
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.35) }
        }
    }

    // ── Clock (curtain) ──────────────────────────────────────────────────
    Column {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.12 + (root.prompt ? -60 : 0)
        opacity: root.prompt ? 0 : 1
        spacing: 0
        Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 250 } }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(LockService.now, "HH:mm")
            color: root.ink
            font.family: root.sans
            font.weight: Font.Medium
            font.pixelSize: Math.round(root.height * 0.12)
            style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.25)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(LockService.now, "dddd d MMMM")
            color: root.ink
            font.family: root.sans
            font.pixelSize: Math.round(root.height * 0.024)
            style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.25)
        }
    }
    // Fingerprint ready (curtain): touching the sensor unlocks directly.
    Text {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 36 }
        visible: LockService.fingerprintReady && !root.prompt
        text: "\udb80\ude37"
        color: root.inkDim
        font.family: root.theme.ff
        font.pixelSize: 26
        style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.25)
    }

    // ── Sign-in prompt ───────────────────────────────────────────────────
    Column {
        id: signIn
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -root.height * 0.04
        spacing: 18
        opacity: root.prompt ? 1 : 0
        visible: opacity > 0
        scale: root.prompt ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        ClippingRectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 168; height: 168; radius: 84
            color: Qt.rgba(1, 1, 1, 0.15)
            Image {
                anchors.fill: parent
                visible: AccountService.hasAvatar
                source: AccountService.hasAvatar ? AccountService.avatarUrl : ""
                sourceSize: Qt.size(336, 336)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Text {
                anchors.centerIn: parent
                visible: !AccountService.hasAvatar
                text: ""
                color: root.ink
                font.family: root.theme.ff
                font.pixelSize: 72
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: AccountService.displayName
            color: root.ink
            font.family: root.sans
            font.weight: Font.DemiBold
            font.pixelSize: 28
        }

        // Password field (or "Welcome" while PAM checks).
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 320; height: 42

            Text {
                anchors.centerIn: parent
                visible: LockService.busy || LockService.unlocking
                text: LockService.unlocking ? "Welcome" : "Checking…"
                color: root.ink
                font.family: root.sans
                font.pixelSize: 18
            }

            Rectangle {
                id: field
                anchors.fill: parent
                visible: !LockService.busy && !LockService.unlocking
                radius: 6
                color: Qt.rgba(1, 1, 1, 0.12)
                border.color: Qt.rgba(1, 1, 1, 0.25)
                border.width: 1
                clip: true
                transform: Translate { id: shake }

                // Windows-style accent underline.
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 2
                    color: root.theme.primary
                }

                TextInput {
                    id: pwDisplay
                    anchors { left: parent.left; leftMargin: 14
                              right: reveal.left; rightMargin: 6
                              verticalCenter: parent.verticalCenter }
                    readOnly: true
                    activeFocusOnPress: false
                    echoMode: revealArea.pressed ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "●"
                    text: LockService.buffer
                    color: root.ink
                    font.family: root.sans
                    font.pixelSize: 16
                    clip: true

                    Text {
                        visible: LockService.buffer.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: LockService.lockedOut ? "Locked" : "Password"
                        color: root.inkDim
                        font: pwDisplay.font
                    }
                    // Blinking caret (the input itself never takes focus).
                    Rectangle {
                        x: Math.min(pwDisplay.contentWidth + 1, pwDisplay.width - 2)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1.5; height: 20
                        color: root.ink
                        visible: root.prompt
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: root.prompt
                            NumberAnimation { to: 0; duration: 530; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1; duration: 530; easing.type: Easing.InOutQuad }
                        }
                    }
                }

                // Hold to reveal.
                Text {
                    id: reveal
                    anchors { right: submitBtn.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    width: 30
                    horizontalAlignment: Text.AlignHCenter
                    visible: LockService.buffer.length > 0
                    text: revealArea.pressed ? "" : ""
                    color: root.inkDim
                    font.family: root.theme.ff
                    font.pixelSize: 15
                    MouseArea {
                        id: revealArea
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                Rectangle {
                    id: submitBtn
                    anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
                    width: 32; height: 32; radius: 5
                    opacity: LockService.lockedOut ? 0.35 : 1
                    color: submitHover.hovered ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1)
                    HoverHandler { id: submitHover }
                    Text {
                        anchors.centerIn: parent
                        text: ""
                        color: root.ink
                        font.family: root.theme.ff
                        font.pixelSize: 15
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { LockService.submit(); root.forceActiveFocus() }
                    }
                }
            }

            // Shake on a wrong password.
            SequentialAnimation {
                id: shakeAnim
                NumberAnimation { target: shake; property: "x"; to: -12; duration: 50 }
                NumberAnimation { target: shake; property: "x"; to: 10;  duration: 70 }
                NumberAnimation { target: shake; property: "x"; to: -6;  duration: 70 }
                NumberAnimation { target: shake; property: "x"; to: 0;   duration: 60 }
            }
            Connections {
                target: LockService
                function onFailTickChanged() { shakeAnim.restart() }
            }
        }

        // Fingerprint status (another way in, Windows Hello style).
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: LockService.fingerprintReady && LockService.fpMessage !== ""
                     && !LockService.busy && !LockService.unlocking
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\udb80\ude37"
                color: LockService.fpError ? "#ffb4ab" : root.ink
                font.family: root.theme.ff
                font.pixelSize: 20
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: LockService.fpMessage
                color: LockService.fpError ? "#ffb4ab" : root.inkDim
                font.family: root.sans
                font.pixelSize: 14
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 360
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: LockService.error
            opacity: LockService.error !== "" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            color: root.ink
            font.family: root.sans
            font.pixelSize: 14
        }
    }

    // ── Status + power (bottom right) ────────────────────────────────────
    Row {
        anchors { right: parent.right; bottom: parent.bottom; margins: 28 }
        spacing: 22

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            visible: battery.pct > 0
            BatteryIcon {
                id: battery
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                size: 14
                color: root.ink
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(battery.pct * 100) + "%"
                color: root.ink
                font.family: root.sans
                font.pixelSize: 15
            }
        }

        // Power button → Sleep / Restart / Shut down (like Windows).
        Rectangle {
            id: powerBtn
            anchors.verticalCenter: parent.verticalCenter
            width: 40; height: 40; radius: 6
            color: powerHover.hovered || powerMenu.open ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
            HoverHandler { id: powerHover }
            Text {
                anchors.centerIn: parent
                text: ""
                color: root.ink
                font.family: root.theme.ff
                font.pixelSize: 18
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { LockService.poke(); powerMenu.open = !powerMenu.open }
            }
        }
    }

    Rectangle {
        id: powerMenu
        property bool open: false
        anchors { right: parent.right; rightMargin: 28; bottom: parent.bottom; bottomMargin: 80 }
        width: 180
        height: powerCol.implicitHeight + 12
        radius: 8
        color: Qt.rgba(0.12, 0.12, 0.14, 0.92)
        border.color: Qt.rgba(1, 1, 1, 0.12)
        border.width: 1
        opacity: open ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        // Swallow clicks so the backdrop handler doesn't close it.
        MouseArea { anchors.fill: parent }

        Column {
            id: powerCol
            anchors { fill: parent; margins: 6 }
            Repeater {
                model: [
                    { id: "suspend",  icon: "", label: "Sleep" },
                    { id: "reboot",   icon: "", label: "Restart" },
                    { id: "shutdown", icon: "", label: "Shut down" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: powerCol.width; height: 38; radius: 5
                    color: itemHover.hovered ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    HoverHandler { id: itemHover }
                    Row {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 12
                        Text {
                            width: 18
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.icon
                            color: root.ink
                            font.family: root.theme.ff; font.pixelSize: 15
                        }
                        Text {
                            text: modelData.label
                            color: root.ink
                            font.family: root.sans; font.pixelSize: 14
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { powerMenu.open = false; PowerService.powerAction(modelData.id) }
                    }
                }
            }
        }
    }
}
