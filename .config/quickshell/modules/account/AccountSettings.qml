import QtQuick
import Quickshell.Widgets
import qs.common.ui
import qs.modules.system

// Settings pane: the logged-in user (like Windows 11's "Your info") — big
// avatar with a pen badge to change it, then account and session details.
Item {
    id: pane

    required property var theme

    function orDash(s) { return (s && ("" + s).length > 0) ? ("" + s) : "—" }

    UiPage {
        anchors.fill: parent
        theme: pane.theme

        // ── Header: avatar, name, picture actions ────────────────────────
        UiCard {
            theme: pane.theme
            height: 152

            // Avatar with a pen badge; clicking either changes the picture.
            Item {
                id: avatarWrap
                anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                width: 108; height: 108

                ClippingRectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: pane.theme.surface2

                    Text {
                        anchors.centerIn: parent
                        text: ""
                        color: pane.theme.outline
                        font.family: pane.theme.ff; font.pixelSize: 52
                        visible: avatarImg.status !== Image.Ready
                    }
                    Image {
                        id: avatarImg
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: AccountService.avatarUrl
                        cache: false
                        asynchronous: true
                        sourceSize: Qt.size(216, 216)
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: "#40000000"
                        opacity: avatarHover.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                }

                // Pen badge, overlapping the avatar's bottom-right edge.
                Rectangle {
                    width: 34; height: 34
                    radius: width / 2
                    x: parent.width - width + 2
                    y: parent.height - height + 2
                    color: avatarHover.hovered ? Qt.lighter(pane.theme.primary, 1.1) : pane.theme.primary
                    border.color: pane.theme.light ? pane.theme.paper : pane.theme.surface
                    border.width: 3
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: AccountService.picking ? "…" : "󰏫"
                        color: pane.theme.bg
                        font.family: pane.theme.ff; font.pixelSize: 16
                    }
                }

                HoverHandler { id: avatarHover }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: AccountService.pickAvatar()
                }
            }

            Column {
                anchors { left: avatarWrap.right; leftMargin: 24; verticalCenter: parent.verticalCenter }
                spacing: 4

                Text {
                    text: AccountService.displayName
                    color: pane.theme.fg
                    font.family: pane.theme.ff; font.bold: true
                    font.pixelSize: pane.theme.fs + 10
                }
                Text {
                    text: AccountService.userName
                          + (AccountService.hostName ? "@" + AccountService.hostName : "")
                    color: pane.theme.txt2
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 1
                }
                Item { width: 1; height: 8; visible: AccountService.hasAvatar }
                UiButton {
                    visible: AccountService.hasAvatar
                    theme: pane.theme
                    kind: "danger"
                    icon: ""
                    text: "Remove picture"
                    onClicked: AccountService.removeAvatar()
                }
            }
        }

        UiGroup {
            theme: pane.theme
            title: "Account"
            UiInfoRow { theme: pane.theme; label: "Username";  value: pane.orDash(AccountService.userName) }
            UiInfoRow { theme: pane.theme; label: "Computer name"; value: pane.orDash(AccountService.hostName) }
            UiInfoRow {
                theme: pane.theme
                label: "User / group ID"
                value: pane.orDash(AccountService.uid) + " / " + pane.orDash(AccountService.gid)
            }
            UiInfoRow { theme: pane.theme; label: "Groups"; value: pane.orDash(AccountService.groups.join(", ")) }
            UiInfoRow { theme: pane.theme; label: "Shell";  value: pane.orDash(AccountService.shell) }
            UiInfoRow { theme: pane.theme; label: "Home";   value: pane.orDash(AccountService.homeDir) }
        }

        // ── Fingerprint (only when fprintd is installed) ─────────────────
        UiGroup {
            id: fpGroup
            visible: FingerprintService.installed
            theme: pane.theme
            title: "Fingerprint"
            description: !FingerprintService.hasDevice ? "No fingerprint reader found"
                       : (FingerprintService.deviceName || "Fingerprint reader") + " · unlocks the lockscreen with a touch"

            // Finger picked on the hands; defaults to the first one not yet
            // enrolled (or the first enrolled when all ten are).
            property string picked: ""
            readonly property string current: picked !== "" ? picked
                : (FingerprintService.fingers.find(f => FingerprintService.enrolled.indexOf(f) < 0)
                   || FingerprintService.enrolled[0] || "")
            readonly property bool currentEnrolled: FingerprintService.enrolled.indexOf(current) >= 0

            actions: [
                UiButton {
                    visible: FingerprintService.enrolled.length > 0
                    theme: pane.theme
                    enabled: !FingerprintService.busy || FingerprintService.verifyState === "scanning"
                    icon: "󰈷"
                    text: FingerprintService.verifyState === "scanning" ? "Touch the sensor…"
                        : FingerprintService.verifyState === "match"    ? "Recognized"
                        : FingerprintService.verifyState === "nomatch"  ? "Not recognized"
                        : FingerprintService.verifyState === "error"    ? "Reader error"
                        : "Test"
                    onClicked: FingerprintService.verify()
                }
            ]

            // Click a finger on the hands, then add or remove it below.
            Item {
                visible: FingerprintService.hasDevice && FingerprintService.enrollState === ""
                width: parent.width
                implicitHeight: fingerPicker.implicitHeight + 36
                FingerPicker {
                    id: fingerPicker
                    anchors.centerIn: parent
                    theme: pane.theme
                    enrolled: FingerprintService.enrolled
                    picked: fpGroup.current
                    onPick: finger => fpGroup.picked = finger
                }
            }
            UiRow {
                visible: FingerprintService.hasDevice && FingerprintService.enrollState === ""
                         && fpGroup.current !== ""
                theme: pane.theme
                icon: "\udb80\ude37"
                iconColor: fpGroup.currentEnrolled ? pane.theme.primary : pane.theme.outline
                title: FingerprintService.fingerLabel(fpGroup.current)
                subtitle: fpGroup.currentEnrolled ? "Enrolled · unlocks the lockscreen with a touch"
                        : FingerprintService.enrolled.length === 0
                          ? "No fingerprints yet. Add one to unlock without typing your password"
                          : "Not enrolled"
                UiButton {
                    visible: fpGroup.currentEnrolled
                    theme: pane.theme
                    kind: "danger"
                    enabled: !FingerprintService.busy
                    text: "Remove"
                    onClicked: FingerprintService.remove(fpGroup.current)
                }
                UiButton {
                    visible: !fpGroup.currentEnrolled
                    theme: pane.theme
                    kind: "primary"
                    enabled: !FingerprintService.busy
                    text: "Add fingerprint"
                    onClicked: FingerprintService.enroll(fpGroup.current)
                }
            }

            // Enrollment progress (touch the sensor numStages times).
            Item {
                visible: FingerprintService.enrollState !== ""
                width: parent.width
                implicitHeight: enrollCol.implicitHeight + 32

                Column {
                    id: enrollCol
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: 18; rightMargin: 18 }
                    spacing: 10

                    Item {
                        width: parent.width
                        height: Math.max(enrollTitle.implicitHeight, enrollBtn.height)
                        Text {
                            id: enrollTitle
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: FingerprintService.enrollState === "done"   ? "Fingerprint added"
                                : FingerprintService.enrollState === "failed" ? "Couldn't add the fingerprint"
                                : FingerprintService.authRequired             ? "Confirm it's you"
                                : "Adding " + FingerprintService.fingerLabel(FingerprintService.enrollFinger).toLowerCase()
                            color: FingerprintService.enrollState === "failed" ? pane.theme.error : pane.theme.fg
                            font.family: pane.theme.ff; font.bold: true
                            font.pixelSize: pane.theme.fs - 1
                        }
                        UiButton {
                            id: enrollBtn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            theme: pane.theme
                            kind: FingerprintService.enrollState === "enrolling" ? "secondary" : "primary"
                            text: FingerprintService.enrollState === "enrolling" ? "Cancel" : "Done"
                            onClicked: FingerprintService.enrollState === "enrolling"
                                       ? FingerprintService.cancelEnroll() : FingerprintService.dismissEnroll()
                        }
                    }

                    // Polkit asks for the password before fprintd lets us enroll.
                    Column {
                        visible: FingerprintService.authRequired
                        width: parent.width
                        spacing: 8
                        UiTextField {
                            id: authField
                            theme: pane.theme
                            secret: true
                            icon: ""
                            placeholder: "Password for " + AccountService.userName
                            onAccepted: text => { FingerprintService.submitAuth(text); authField.text = "" }
                            onVisibleChanged: if (visible) textInput.forceActiveFocus()
                        }
                        Text {
                            visible: FingerprintService.authError !== ""
                            text: FingerprintService.authError
                            color: pane.theme.error
                            font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
                        }
                    }

                    Rectangle {
                        visible: !FingerprintService.authRequired && FingerprintService.enrollState !== "failed"
                        width: parent.width; height: 6; radius: 3
                        color: Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.1)
                        Rectangle {
                            height: parent.height; radius: parent.radius
                            width: parent.width * Math.min(1, FingerprintService.enrollStage / Math.max(1, FingerprintService.numStages))
                            color: FingerprintService.enrollState === "done" ? pane.theme.green : pane.theme.primary
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                    }

                    Text {
                        visible: !FingerprintService.authRequired
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: FingerprintService.enrollState === "done"
                              ? "You can now unlock the lockscreen with this finger."
                              : FingerprintService.enrollState === "failed"
                              ? FingerprintService.enrollHint
                              : (FingerprintService.enrollHint || "Touch the sensor with your finger.")
                                + (FingerprintService.numStages ? "  (" + FingerprintService.enrollStage + " / " + FingerprintService.numStages + ")" : "")
                        color: pane.theme.txt2
                        font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
                    }
                }
            }

            // Removal needs the same polkit auth.
            Item {
                visible: FingerprintService.deleting && FingerprintService.authRequired || FingerprintService.deleteError !== ""
                width: parent.width
                implicitHeight: delCol.implicitHeight + 28
                Column {
                    id: delCol
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: 18; rightMargin: 18 }
                    spacing: 8
                    UiTextField {
                        id: delAuthField
                        visible: FingerprintService.deleting && FingerprintService.authRequired
                        theme: pane.theme
                        secret: true
                        icon: ""
                        placeholder: "Password for " + AccountService.userName + " to remove the fingerprint"
                        onAccepted: text => { FingerprintService.submitAuth(text); delAuthField.text = "" }
                        onVisibleChanged: if (visible) textInput.forceActiveFocus()
                    }
                    Text {
                        visible: text !== ""
                        text: FingerprintService.authError || FingerprintService.deleteError
                        color: pane.theme.error
                        font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
                    }
                }
            }
        }

        UiGroup {
            theme: pane.theme
            title: "Session"
            UiInfoRow { theme: pane.theme; label: "Hostname"; value: pane.orDash(AccountService.hostName) }
            UiInfoRow { theme: pane.theme; label: "OS";       value: pane.orDash(SystemService.sysDistro) }
            UiInfoRow {
                theme: pane.theme
                label: "Desktop"
                value: pane.orDash([AccountService.desktop,
                                    AccountService.sessionType ? "(" + AccountService.sessionType + ")" : ""]
                                   .filter(Boolean).join(" "))
            }
            UiInfoRow {
                theme: pane.theme
                label: "Uptime"
                value: pane.orDash((SystemService.sysUptime || "").replace(/^up\s+/, ""))
            }
        }
    }

    // Circular crop step after picking a new picture.
    AvatarCropper {
        anchors.fill: parent
        z: 10
        theme: pane.theme
        visible: AccountService.cropSource !== ""
    }
}
