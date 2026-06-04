import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: overlay

    required property var  shellRoot
    required property var  theme
    required property real anchorWidth

    // Stays visible while password entry is active — but only when the
    // overlay itself initiated the prompt (settings has its own input).
    readonly property bool ownsPassword: shellRoot.wifiPasswordOpen
                                       && shellRoot.wifiPasswordSource === "overlay"
    readonly property bool _open: shellRoot.wifiPopupOpen || ownsPassword
    visible: _open || exitAnim.running
    on_OpenChanged: {
        if (_open) { exitAnim.stop(); enterAnim.restart() }
        else       { enterAnim.stop(); exitAnim.restart() }
    }
    // Request keyboard focus only when our own password section is open.
    WlrLayershell.keyboardFocus: ownsPassword
                                 ? WlrKeyboardFocus.OnDemand
                                 : WlrKeyboardFocus.None

    anchors { top: true; right: true }
    margins.right: 10
    margins.top:   6      // sit just below the bar (bar exclusiveZone is 34)
    exclusiveZone: 0
    color: "transparent"

    implicitWidth:  Math.max(anchorWidth, 320)
    implicitHeight: col.implicitHeight + 20

    function signalIcon(strength) {
        if (strength >= 80) return ""
        if (strength >= 60) return ""
        if (strength >= 40) return ""
        if (strength >= 20) return ""
        return ""
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: card;      property: "opacity"; from: 0; to: 1; duration: 360; easing.type: Easing.OutCubic }
        NumberAnimation { target: card;      property: "scale"; from: 0.96; to: 1; duration: 360; easing.type: Easing.OutCubic }
    }
    // Reverse of enterAnim — plays before the panel is hidden so it slides
    // back out instead of snapping away. `visible` stays true while running.
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: card;      property: "opacity"; to: 0;   duration: 280; easing.type: Easing.InCubic }
        NumberAnimation { target: card;      property: "scale"; to: 0.96; duration: 280; easing.type: Easing.InCubic }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        color: overlay.theme.bg
        radius: overlay.theme.pr
        focus: overlay.ownsPassword
        Keys.onEscapePressed: if (overlay.ownsPassword) overlay.shellRoot.cancelWifiPassword()
        opacity: 0
        scale: 0.96
        transformOrigin: Item.Top

        HoverHandler {
            onHoveredChanged: hovered ? overlay.shellRoot.stopHideTimer("wifi")
                                      : overlay.shellRoot.startHideTimer("wifi")
        }

        Column {
            id: col
            anchors { fill: parent; margins: 12 }
            spacing: 8

            // ── Wifi enable toggle + rescan ──────────────────────────
            Rectangle {
                width: col.width
                height: 32
                radius: 8
                color: Qt.lighter(overlay.theme.active, 1.3)

                Row {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Wi-Fi"
                        color: overlay.theme.fg
                        font.family: overlay.theme.ff; font.bold: true; font.pixelSize: overlay.theme.fs - 1
                        width: parent.width - wifiToggleSwitch.width - rescanIcon.width - 24
                    }

                    Rectangle {
                        id: rescanIcon
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 22; radius: 6
                        color: rescanHover.hovered ? Qt.lighter(overlay.theme.active, 1.6) : "transparent"
                        opacity: overlay.shellRoot.wifiEnabled ? 1 : 0.4

                        HoverHandler { id: rescanHover }
                        Text {
                            anchors.centerIn: parent
                            // Square box + centred glyph so the spin axis is the
                            // glyph's true centre rather than its bounding box.
                            width:  implicitHeight
                            height: implicitHeight
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment:   Text.AlignVCenter
                            transformOrigin: Item.Center
                            text: overlay.shellRoot.wifiScanning ? "⟳" : ""
                            color: overlay.theme.fg
                            font.family: overlay.theme.ff
                            font.pixelSize: overlay.theme.fs - 1
                            // Animator (render-thread) instead of a rotation
                            // binding + RotationAnimation, which fought each
                            // other and snapped the glyph back to 0.
                            RotationAnimator on rotation {
                                running: overlay.shellRoot.wifiScanning
                                loops: Animation.Infinite
                                from: 0; to: 360; duration: 1000
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: overlay.shellRoot.wifiEnabled && !overlay.shellRoot.wifiScanning
                            cursorShape: Qt.PointingHandCursor
                            onClicked: overlay.shellRoot.rescanWifi()
                        }
                    }

                    Rectangle {
                        id: wifiToggleSwitch
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42; height: 22
                        radius: 11
                        color: overlay.shellRoot.wifiEnabled ? "#A6E3A1" : Qt.darker(overlay.theme.bg, 1.4)

                        Rectangle {
                            width: 16; height: 16; radius: 8
                            color: overlay.theme.fg
                            anchors.verticalCenter: parent.verticalCenter
                            x: overlay.shellRoot.wifiEnabled ? parent.width - width - 3 : 3
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: overlay.shellRoot.toggleWifi(!overlay.shellRoot.wifiEnabled)
                        }
                    }
                }
            }

            // ── Status line ──────────────────────────────────────────
            Text {
                text: !overlay.shellRoot.wifiEnabled
                      ? "Wi-Fi is off"
                      : overlay.shellRoot.wifiList.length + " network" + (overlay.shellRoot.wifiList.length === 1 ? "" : "s") + " visible"
                color: overlay.theme.fg
                opacity: 0.6
                font.family: overlay.theme.ff
                font.pixelSize: overlay.theme.fs - 2
            }

            // ── Network list (top 6) ─────────────────────────────────
            Repeater {
                model: overlay.shellRoot.wifiEnabled ? overlay.shellRoot.wifiList.slice(0, 6) : []
                delegate: Rectangle {
                    required property var modelData
                    width: col.width
                    height: 30
                    radius: 7
                    color: rowHover.hovered
                            ? Qt.lighter(overlay.theme.active, 1.2)
                            : (modelData.active ? Qt.lighter(overlay.theme.active, 1.4) : "transparent")

                    HoverHandler { id: rowHover }

                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: overlay.signalIcon(modelData.strength)
                            color: modelData.active ? "#A6E3A1" : overlay.theme.fg
                            font.family: overlay.theme.ff
                            font.pixelSize: overlay.theme.fs - 1
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: modelData.secure
                            text: ""
                            color: overlay.theme.fg
                            opacity: 0.7
                            font.family: overlay.theme.ff
                            font.pixelSize: overlay.theme.fs - 3
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.ssid
                            color: overlay.theme.fg
                            font.family: overlay.theme.ff
                            font.pixelSize: overlay.theme.fs - 1
                            font.bold: modelData.active
                            elide: Text.ElideRight
                            width: col.width - 90
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.active) overlay.shellRoot.disconnectWifi()
                            else                  overlay.shellRoot.connectWifi(modelData.ssid, modelData.secure, "overlay")
                        }
                    }
                }
            }

            // ── Inline password section ──────────────────────────────
            Rectangle {
                visible: overlay.ownsPassword
                width: col.width
                height: pwCol.implicitHeight + 16
                radius: 10
                color: Qt.darker(overlay.theme.bg, 1.15)
                border.color: overlay.theme.sep
                border.width: 1

                Column {
                    id: pwCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                    spacing: 6

                    Text {
                        text: "Password for " + overlay.shellRoot.wifiPasswordSsid
                        color: overlay.theme.fg
                        font.family: overlay.theme.ff
                        font.bold: true
                        font.pixelSize: overlay.theme.fs - 1
                        elide: Text.ElideRight
                        width: pwCol.width
                    }

                    Rectangle {
                        id: pwBox
                        property bool revealed: false
                        width: pwCol.width
                        height: 30
                        radius: 7
                        color: overlay.theme.field
                        border.color: pwInput.activeFocus ? "#A6E3A1" : overlay.theme.sep
                        border.width: 1

                        TextInput {
                            id: pwInput
                            anchors { fill: parent; leftMargin: 10; rightMargin: 34 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: overlay.theme.fg
                            selectionColor: Qt.lighter(overlay.theme.active, 1.4)
                            font.family: overlay.theme.ff
                            font.pixelSize: overlay.theme.fs - 1
                            echoMode: pwBox.revealed ? TextInput.Normal : TextInput.Password
                            activeFocusOnPress: true
                            onAccepted: if (text.length > 0) overlay.shellRoot.submitWifiPassword(text)

                            // Defer forceActiveFocus to the next event-loop turn
                            // so the layer-shell compositor has time to grant
                            // keyboard focus to the surface (OnDemand mode).
                            Connections {
                                target: overlay
                                function onOwnsPasswordChanged() {
                                    if (overlay.ownsPassword) {
                                        pwInput.text = ""
                                        pwBox.revealed = false
                                        Qt.callLater(() => pwInput.forceActiveFocus())
                                    }
                                }
                            }

                            // Placeholder hint
                            Text {
                                anchors { fill: parent; leftMargin: 0 }
                                verticalAlignment: TextInput.AlignVCenter
                                visible: pwInput.text.length === 0
                                text: "Network password"
                                color: overlay.theme.outline
                                font: pwInput.font
                            }
                        }

                        // Show / hide password toggle.
                        Text {
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: pwBox.revealed ? "" : ""
                            color: overlay.theme.fg
                            opacity: pwRevealHover.hovered ? 1 : 0.6
                            font.family: overlay.theme.ff
                            font.pixelSize: overlay.theme.fs - 1
                            HoverHandler { id: pwRevealHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pwBox.revealed = !pwBox.revealed
                            }
                        }
                    }

                    Text {
                        visible: overlay.shellRoot.wifiPasswordError.length > 0
                        text: overlay.shellRoot.wifiPasswordError
                        color: "#F38BA8"
                        font.family: overlay.theme.ff
                        font.pixelSize: overlay.theme.fs - 2
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 6

                        Rectangle {
                            width: 70; height: 26
                            radius: 7
                            color: pwCancelHover.hovered ? Qt.lighter(overlay.theme.bg, 1.3) : Qt.darker(overlay.theme.bg, 1.2)
                            border.color: overlay.theme.sep
                            border.width: 1
                            HoverHandler { id: pwCancelHover }
                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: overlay.theme.fg
                                font.family: overlay.theme.ff
                                font.bold: true
                                font.pixelSize: overlay.theme.fs - 2
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: overlay.shellRoot.cancelWifiPassword()
                            }
                        }

                        Rectangle {
                            width: 90; height: 26
                            radius: 7
                            color: pwInput.text.length === 0
                                   ? Qt.darker(overlay.theme.bg, 1.4)
                                   : (pwConnectHover.hovered
                                        ? Qt.lighter(overlay.theme.active, 1.6)
                                        : Qt.lighter(overlay.theme.active, 1.3))
                            opacity: pwInput.text.length === 0 ? 0.5 : 1
                            HoverHandler { id: pwConnectHover }
                            Text {
                                anchors.centerIn: parent
                                text: overlay.shellRoot.wifiConnecting ? "Connecting…" : "Connect"
                                color: overlay.theme.fg
                                font.family: overlay.theme.ff
                                font.bold: true
                                font.pixelSize: overlay.theme.fs - 2
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: pwInput.text.length > 0 && !overlay.shellRoot.wifiConnecting
                                cursorShape: Qt.PointingHandCursor
                                onClicked: overlay.shellRoot.submitWifiPassword(pwInput.text)
                            }
                        }
                    }
                }
            }

            // ── Open settings pill ────────────────────────────────────
            Rectangle {
                width: col.width
                height: 32
                radius: 9
                color: settingsBtnHover.hovered
                        ? Qt.lighter(overlay.theme.active, 1.6)
                        : Qt.lighter(overlay.theme.active, 1.3)

                HoverHandler { id: settingsBtnHover }

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: ""; color: overlay.theme.fg; font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs }
                    Text { text: "Open settings"; color: overlay.theme.fg; font.family: overlay.theme.ff; font.bold: true; font.pixelSize: overlay.theme.fs - 1 }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        overlay.shellRoot.wifiPopupOpen = false
                        overlay.shellRoot.openSettings("wifi")
                    }
                }
            }
        }
    }
}
