import QtQuick
import Quickshell
import qs.common
import qs.common.ui
import qs.modules.settings

// Bar popup page: Wi-Fi toggle, network list and password prompt.
// ownsPassword keeps the popup open (and focusable) while typing.
Item {
    id: popup

    required property var theme
    implicitHeight: col.implicitHeight + 24

    // Stay visible during password entry — only when this overlay opened
    // the prompt (settings has its own input).
    readonly property bool ownsPassword: NetworkService.wifiPasswordOpen
                                       && NetworkService.wifiPasswordSource === "overlay"
    // Network the prompt is for — latched on open so the title survives the
    // collapse animation after cancel clears the service's SSID.
    property string promptSsid: ""
    readonly property string activeSsid: {
        const a = (NetworkService.wifiList || []).find(n => n.active)
        return a ? a.ssid : ""
    }

    focus: popup.ownsPassword
    Keys.onEscapePressed: if (popup.ownsPassword) NetworkService.cancelWifiPassword()

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 10

        // ── Header ───────────────────────────────────────────────
        UiRow {
            theme: popup.theme
            compact: true
            showDivider: false
            icon: ""
            title: "Wi-Fi"
            subtitle: !NetworkService.wifiEnabled ? "Off"
                    : popup.activeSsid ? popup.activeSsid
                    : NetworkService.wifiList.length + " networks"

            // Rescan (spins while scanning).
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 32; radius: 8
                opacity: NetworkService.wifiEnabled ? 1 : 0.4
                color: Qt.rgba(popup.theme.fg.r, popup.theme.fg.g, popup.theme.fg.b, rescanHover.hovered ? 0.14 : 0.08)
                HoverHandler { id: rescanHover }
                Text {
                    anchors.centerIn: parent
                    // Square box so the spin axis is the glyph centre.
                    width: implicitHeight; height: implicitHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: ""
                    color: popup.theme.fg
                    font.family: popup.theme.ff; font.pixelSize: popup.theme.fs - 1
                    // Render-thread Animator: a rotation binding + a
                    // RotationAnimation fought and snapped to 0.
                    RotationAnimator on rotation {
                        running: NetworkService.wifiScanning
                        loops: Animation.Infinite
                        from: 0; to: 360; duration: 1000
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: NetworkService.wifiEnabled && !NetworkService.wifiScanning
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NetworkService.rescanWifi()
                }
            }
            UiSwitch {
                anchors.verticalCenter: parent.verticalCenter
                theme: popup.theme
                checked: NetworkService.wifiEnabled
                onToggled: value => NetworkService.toggleWifi(value)
            }
            GearButton {
                theme: popup.theme
                onClicked: {
                    PopupService.wifiPopupOpen = false
                    SettingsService.openSettings("wifi")
                }
            }
        }

        Column {
            width: parent.width

            // ── Networks (top 6) ─────────────────────────────────────
            UiCard {
                theme: popup.theme
                height: netCol.implicitHeight
                Column {
                    id: netCol
                    width: parent.width

                    Repeater {
                        model: NetworkService.wifiEnabled ? NetworkService.wifiList.slice(0, 6) : []
                        delegate: UiRow {
                            id: netRow
                            required property var modelData
                            readonly property bool connecting:
                                NetworkService.wifiConnectingSsid === modelData.ssid
                            theme: popup.theme
                            compact: true
                            clickable: true
                            highlighted: modelData.active
                            icon: ""
                            iconColor: modelData.active ? popup.theme.primary : popup.theme.txt2
                            title: modelData.ssid
                            subtitle: modelData.strength + "%  ·  "
                                      + (modelData.enterprise ? "Enterprise" : modelData.secure ? "Secured" : "Open")
                                      + (modelData.active ? "  ·  Connected"
                                       : connecting       ? "  ·  Connecting…" : "")
                            onClicked: {
                                if (connecting) return
                                if (modelData.active) NetworkService.disconnectWifi()
                                else                  NetworkService.connectWifi(modelData.ssid, modelData.secure, "overlay")
                            }
                            Text {
                                visible: netRow.modelData.secure
                                text: ""
                                color: popup.theme.txt2
                                font.family: popup.theme.ff; font.pixelSize: popup.theme.fs - 3
                            }
                        }
                    }
                    Item {
                        visible: !NetworkService.wifiEnabled || NetworkService.wifiList.length === 0
                        width: parent.width
                        implicitHeight: 48
                        Text {
                            anchors.centerIn: parent
                            text: !NetworkService.wifiEnabled ? "Wi-Fi is off"
                                : NetworkService.wifiScanning ? "Scanning…" : "No networks found"
                            color: popup.theme.txt2
                            font.family: popup.theme.ff; font.pixelSize: popup.theme.fs - 2
                        }
                    }
                }
            }

            // ── Inline password prompt (slides open/closed) ──────────
            Item {
                width: parent.width
                height: popup.ownsPassword ? pwCard.height + 10 : 0
                Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                clip: true
                visible: height > 0

                UiCard {
                    id: pwCard
                    y: 10
                    theme: popup.theme
                    height: pwCol.implicitHeight + 24
                    opacity: popup.ownsPassword ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    border.color: Qt.rgba(popup.theme.primary.r, popup.theme.primary.g, popup.theme.primary.b, 0.5)

                    Column {
                        id: pwCol
                        x: 12; y: 12
                        width: parent.width - 24
                        spacing: 10

                        Text {
                            width: parent.width
                            text: "Password for " + popup.promptSsid
                            color: popup.theme.fg
                            font.family: popup.theme.ff; font.bold: true; font.pixelSize: popup.theme.fs - 1
                            elide: Text.ElideRight
                        }
                        UiTextField {
                            id: pwField
                            theme: popup.theme
                            icon: ""
                            secret: true
                            placeholder: "Network password"
                            onAccepted: t => { if (t.length > 0) NetworkService.submitWifiPassword(t) }

                            // Defer focus one event-loop turn so the compositor can
                            // grant keyboard focus first (OnDemand).
                            Connections {
                                target: popup
                                function onOwnsPasswordChanged() {
                                    if (popup.ownsPassword) {
                                        popup.promptSsid = NetworkService.wifiPasswordSsid
                                        pwField.text = ""
                                        pwField.revealed = false
                                        Qt.callLater(() => pwField.textInput.forceActiveFocus())
                                    }
                                }
                            }
                        }
                        Text {
                            visible: NetworkService.wifiPasswordError.length > 0
                            width: parent.width
                            text: NetworkService.wifiPasswordError
                            color: popup.theme.error
                            wrapMode: Text.WordWrap
                            font.family: popup.theme.ff; font.pixelSize: popup.theme.fs - 2
                        }
                        Row {
                            anchors.right: parent.right
                            spacing: 8
                            UiButton {
                                theme: popup.theme
                                text: "Cancel"
                                onClicked: NetworkService.cancelWifiPassword()
                            }
                            UiButton {
                                theme: popup.theme
                                kind: "primary"
                                enabled: pwField.text.length > 0 && !NetworkService.wifiConnecting
                                text: NetworkService.wifiConnecting ? "Connecting…" : "Connect"
                                onClicked: NetworkService.submitWifiPassword(pwField.text)
                            }
                        }
                    }
                }
            }
        }
    }
}
