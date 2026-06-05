import QtQuick

Item {
    id: pane

    required property var shellRoot
    required property var theme

    function signalIcon(strength) {
        if (strength >= 80) return ""
        if (strength >= 60) return ""
        if (strength >= 40) return ""
        if (strength >= 20) return ""
        return ""
    }

    // A themed single-line input with placeholder. `secret` masks the text;
    // secret fields gain an eye toggle to reveal what's typed.
    component FieldBox: Rectangle {
        id: fb
        property alias input: ti
        property string placeholder: ""
        property bool secret: false
        property bool revealed: false
        signal accepted()
        width: parent ? parent.width : 0
        height: 34
        radius: 8
        color: pane.theme.field
        border.color: ti.activeFocus ? pane.theme.tertiary : pane.theme.sep
        border.width: 1
        TextInput {
            id: ti
            anchors { fill: parent; leftMargin: 12; rightMargin: fb.secret ? 38 : 12 }
            verticalAlignment: TextInput.AlignVCenter
            color: pane.theme.fg
            selectionColor: pane.theme.hi(1.4)
            font.family: pane.theme.ff
            font.pixelSize: pane.theme.fs
            echoMode: (fb.secret && !fb.revealed) ? TextInput.Password : TextInput.Normal
            activeFocusOnPress: true
            onAccepted: fb.accepted()
            Text {
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                visible: ti.text.length === 0
                text: fb.placeholder
                color: pane.theme.outline
                font: ti.font
            }
        }
        // Show / hide password toggle.
        Text {
            visible: fb.secret
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: fb.revealed ? "" : ""
            color: pane.theme.fg
            opacity: revealHover.hovered ? 1 : 0.6
            font.family: pane.theme.ff
            font.pixelSize: pane.theme.fs
            HoverHandler { id: revealHover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: fb.revealed = !fb.revealed
            }
        }
    }

    // A small pill button used as a segmented selector.
    component SegButton: Rectangle {
        id: seg
        property string label: ""
        property bool selected: false
        signal clicked()
        width: segText.implicitWidth + 22
        height: 28
        radius: 7
        color: selected ? pane.theme.hi(1.4)
                        : (segHover.hovered ? pane.theme.surface
                                            : Qt.darker(pane.theme.bg, 1.2))
        border.color: selected ? pane.theme.tertiary : pane.theme.sep
        border.width: 1
        HoverHandler { id: segHover }
        Text {
            id: segText
            anchors.centerIn: parent
            text: seg.label
            color: pane.theme.fg
            font.family: pane.theme.ff
            font.bold: true
            font.pixelSize: pane.theme.fs - 2
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: seg.clicked()
        }
    }

    // Saved profiles cross-referenced against the current scan: a saved
    // network is "available" only if its SSID is currently in range.
    readonly property var savedNetworks: {
        const scan = pane.shellRoot.wifiList || []
        return (pane.shellRoot.wifiSaved || []).map(name => {
            const hit = scan.find(n => n.ssid === name)
            return {
                ssid:       name,
                available:  !!hit,
                active:     hit ? hit.active     : false,
                secure:     hit ? hit.secure     : true,
                enterprise: hit ? hit.enterprise : false,
                strength:   hit ? hit.strength   : 0
            }
        }).sort((a, b) => (b.available - a.available) || a.ssid.localeCompare(b.ssid))
    }

    // Inline credential form. A Loader in the network list creates one fresh
    // beneath the row being connected to, so its fields start empty and it
    // focuses itself the moment it appears.
    Component {
        id: passwordForm

        Rectangle {
            id: pwSection

            // Enterprise (802.1X) prompt state — local so it resets each open.
            property string eapMethod: "peap"      // peap | ttls | pwd
            property string phase2Auth: "mschapv2" // mschapv2 | pap | gtc

            width: parent ? parent.width : 0
            height: pwCol.implicitHeight + 24
            radius: 12
            color: Qt.darker(pane.theme.bg, 1.15)
            border.color: pane.theme.tertiary
            border.width: 1

            // Submit whichever credential form is active. No-ops while a connect
            // is already in flight or required fields are blank.
            function tryConnect() {
                if (pane.shellRoot.wifiConnecting) return
                if (pane.shellRoot.wifiPasswordEnterprise) {
                    if (eapIdField.input.text.length === 0 || eapPwField.input.text.length === 0) return
                    const ph2 = pwSection.eapMethod === "pwd" ? "" : pwSection.phase2Auth
                    pane.shellRoot.submitWifiEnterprise(pwSection.eapMethod, eapIdField.input.text,
                                                        eapPwField.input.text, ph2, eapAnonField.input.text)
                } else {
                    if (eapPwField.input.text.length === 0) return
                    pane.shellRoot.submitWifiPassword(eapPwField.input.text)
                }
            }

            // Focus the relevant field as soon as the form appears.
            Component.onCompleted: Qt.callLater(() => {
                if (pane.shellRoot.wifiPasswordEnterprise) eapIdField.input.forceActiveFocus()
                else                                       eapPwField.input.forceActiveFocus()
            })

            Column {
                id: pwCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 8

                Text {
                    text: (pane.shellRoot.wifiPasswordEnterprise ? "Sign in to " : "Password for ")
                          + pane.shellRoot.wifiPasswordSsid
                    color: pane.theme.fg
                    font.family: pane.theme.ff
                    font.bold: true
                    font.pixelSize: pane.theme.fs
                    elide: Text.ElideRight
                    width: pwCol.width
                }

                // ── Enterprise: EAP method ──
                Column {
                    visible: pane.shellRoot.wifiPasswordEnterprise
                    width: pwCol.width
                    spacing: 4
                    Text {
                        text: "EAP method"
                        color: pane.theme.fg; opacity: 0.7
                        font.family: pane.theme.ff
                        font.pixelSize: pane.theme.fs - 2
                    }
                    Row {
                        spacing: 6
                        SegButton { label: "PEAP"; selected: pwSection.eapMethod === "peap"; onClicked: pwSection.eapMethod = "peap" }
                        SegButton { label: "TTLS"; selected: pwSection.eapMethod === "ttls"; onClicked: pwSection.eapMethod = "ttls" }
                        SegButton { label: "PWD";  selected: pwSection.eapMethod === "pwd";  onClicked: pwSection.eapMethod = "pwd" }
                    }
                }

                // ── Enterprise: identity (username) ──
                FieldBox {
                    id: eapIdField
                    visible: pane.shellRoot.wifiPasswordEnterprise
                    placeholder: "Identity (e.g. user@domain)"
                    onAccepted: pwSection.tryConnect()
                }

                // ── Password (all secured networks) ──
                FieldBox {
                    id: eapPwField
                    placeholder: pane.shellRoot.wifiPasswordEnterprise ? "Password" : "Network password"
                    secret: true
                    onAccepted: pwSection.tryConnect()
                }

                // ── Enterprise: inner (phase-2) auth — n/a for EAP-PWD ──
                Column {
                    visible: pane.shellRoot.wifiPasswordEnterprise && pwSection.eapMethod !== "pwd"
                    width: pwCol.width
                    spacing: 4
                    Text {
                        text: "Inner authentication"
                        color: pane.theme.fg; opacity: 0.7
                        font.family: pane.theme.ff
                        font.pixelSize: pane.theme.fs - 2
                    }
                    Row {
                        spacing: 6
                        SegButton { label: "MSCHAPv2"; selected: pwSection.phase2Auth === "mschapv2"; onClicked: pwSection.phase2Auth = "mschapv2" }
                        SegButton { label: "PAP";      selected: pwSection.phase2Auth === "pap";      onClicked: pwSection.phase2Auth = "pap" }
                        SegButton { label: "GTC";      selected: pwSection.phase2Auth === "gtc";      onClicked: pwSection.phase2Auth = "gtc" }
                    }
                }

                // ── Enterprise: anonymous identity (optional) ──
                FieldBox {
                    id: eapAnonField
                    visible: pane.shellRoot.wifiPasswordEnterprise
                    placeholder: "Anonymous identity (optional)"
                    onAccepted: pwSection.tryConnect()
                }

                Text {
                    visible: pane.shellRoot.wifiPasswordError.length > 0
                    text: pane.shellRoot.wifiPasswordError
                    color: pane.theme.error
                    width: pwCol.width
                    wrapMode: Text.WordWrap
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 1
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8

                    Rectangle {
                        width: 90; height: 30
                        radius: 7
                        color: pwCancelHover.hovered ? pane.theme.surface : Qt.darker(pane.theme.bg, 1.2)
                        border.color: pane.theme.sep
                        border.width: 1
                        HoverHandler { id: pwCancelHover }
                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: pane.theme.fg
                            font.family: pane.theme.ff
                            font.bold: true
                            font.pixelSize: pane.theme.fs - 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pane.shellRoot.cancelWifiPassword()
                        }
                    }

                    Rectangle {
                        // Enterprise needs both identity + password; basic nets
                        // just a password.
                        readonly property bool ready: eapPwField.input.text.length > 0
                            && (!pane.shellRoot.wifiPasswordEnterprise || eapIdField.input.text.length > 0)
                        width: 110; height: 30
                        radius: 7
                        color: !ready
                               ? Qt.darker(pane.theme.bg, 1.4)
                               : (pwConnectHover.hovered ? pane.theme.hi(1.6) : pane.theme.hi(1.3))
                        opacity: ready ? 1 : 0.5
                        HoverHandler { id: pwConnectHover }
                        Text {
                            anchors.centerIn: parent
                            text: pane.shellRoot.wifiConnecting ? "Connecting…" : "Connect"
                            color: pane.theme.fg
                            font.family: pane.theme.ff
                            font.bold: true
                            font.pixelSize: pane.theme.fs - 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.ready && !pane.shellRoot.wifiConnecting
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pwSection.tryConnect()
                        }
                    }
                }
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: wifiCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
        id: wifiCol
        width: parent.width
        spacing: 16

        // ── Adapter toggle card ──────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 56
            radius: 12
            color: Qt.darker(pane.theme.bg, 1.2)
            border.color: pane.theme.sep
            border.width: 1

            Row {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Wi-Fi"
                    color: pane.theme.fg
                    font.family: pane.theme.ff
                    font.bold: true
                    font.pixelSize: pane.theme.fs + 1
                    width: parent.width - wifiToggleSwitch.width - 16
                }

                Rectangle {
                    id: wifiToggleSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    width: 42; height: 22
                    radius: 11
                    color: pane.shellRoot.wifiEnabled ? pane.theme.tertiary : Qt.darker(pane.theme.bg, 1.4)

                    Rectangle {
                        width: 16; height: 16; radius: 8
                        color: pane.theme.fg
                        anchors.verticalCenter: parent.verticalCenter
                        x: pane.shellRoot.wifiEnabled ? parent.width - width - 3 : 3
                        Behavior on x { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pane.shellRoot.toggleWifi(!pane.shellRoot.wifiEnabled)
                    }
                }
            }
        }

        // ── Saved networks header ────────────────────────────────────────
        Text {
            visible: pane.savedNetworks.length > 0
            text: "Saved networks (" + pane.savedNetworks.length + ")"
            color: pane.theme.fg
            font.family: pane.theme.ff
            font.bold: true
            font.pixelSize: pane.theme.fs + 1
        }

        // ── Saved networks list ──────────────────────────────────────────
        Rectangle {
            visible: pane.savedNetworks.length > 0
            width: parent.width
            height: savedCol.implicitHeight + 12
            color: Qt.darker(pane.theme.bg, 1.2)
            radius: 12
            border.color: pane.theme.sep
            border.width: 1

            Column {
                id: savedCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 2

                Repeater {
                    model: pane.savedNetworks
                    delegate: Rectangle {
                        required property var modelData
                        width:  savedCol.width
                        height: 38
                        radius: 8
                        // Out-of-range entries are dimmed.
                        opacity: modelData.available ? 1 : 0.45
                        color: savedRowHover.hovered
                                ? pane.theme.hi(1.2)
                                : (modelData.active ? pane.theme.hi(1.4) : "transparent")

                        HoverHandler { id: savedRowHover }

                        Row {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.available ? pane.signalIcon(modelData.strength) : ""
                                color: modelData.active ? pane.theme.tertiary : pane.theme.fg
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs + 1
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1
                                Text {
                                    text: modelData.ssid
                                    color: pane.theme.fg
                                    font.family: pane.theme.ff
                                    font.bold: true
                                    font.pixelSize: pane.theme.fs
                                    elide: Text.ElideRight
                                    width: savedCol.width - 200
                                }
                                Text {
                                    text: modelData.active    ? "Connected"
                                        : modelData.available ? "Available"
                                                              : "Out of range"
                                    color: pane.theme.fg
                                    opacity: 0.6
                                    font.family: pane.theme.ff
                                    font.pixelSize: pane.theme.fs - 2
                                }
                            }
                        }

                        Row {
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            spacing: 6

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 70; height: 26
                                radius: 7
                                color: savedForgetHover.hovered ? pane.theme.error : Qt.darker(pane.theme.bg, 1.2)
                                border.color: pane.theme.sep
                                border.width: 1
                                HoverHandler { id: savedForgetHover }
                                Text {
                                    anchors.centerIn: parent
                                    text: "Forget"
                                    color: pane.theme.fg
                                    font.family: pane.theme.ff
                                    font.pixelSize: pane.theme.fs - 2
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pane.shellRoot.forgetWifi(modelData.ssid)
                                }
                            }

                            Rectangle {
                                visible: modelData.available
                                anchors.verticalCenter: parent.verticalCenter
                                width: 90; height: 26
                                radius: 7
                                color: savedConnHover.hovered
                                        ? pane.theme.hi(1.6)
                                        : pane.theme.hi(1.3)
                                HoverHandler { id: savedConnHover }
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.active ? "Disconnect" : "Connect"
                                    color: pane.theme.fg
                                    font.family: pane.theme.ff
                                    font.pixelSize: pane.theme.fs - 2
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData.active) pane.shellRoot.disconnectWifi()
                                        else                  pane.shellRoot.connectWifi(modelData.ssid, modelData.secure, "settings", modelData.enterprise)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // ── Networks header + rescan / nmtui ─────────────────────────────
        Row {
            width: parent.width
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Networks (" + pane.shellRoot.wifiList.length + ")"
                color: pane.theme.fg
                font.family: pane.theme.ff
                font.bold: true
                font.pixelSize: pane.theme.fs + 1
                width: parent.width - rescanBtn.width - nmtuiBtn.width - 16
            }

            Rectangle {
                id: nmtuiBtn
                anchors.verticalCenter: parent.verticalCenter
                width: 130; height: 28
                radius: 8
                color: nmtuiHover.hovered
                       ? pane.theme.hi(1.4)
                       : Qt.darker(pane.theme.bg, 1.2)
                border.color: pane.theme.sep
                border.width: 1

                HoverHandler { id: nmtuiHover }

                Text {
                    anchors.centerIn: parent
                    text: "Open in nmtui"
                    color: pane.theme.fg
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 1
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pane.shellRoot.launchNmtui()
                }
            }

            Rectangle {
                id: rescanBtn
                anchors.verticalCenter: parent.verticalCenter
                width: 130; height: 28
                radius: 8
                color: pane.shellRoot.wifiScanning
                       ? pane.theme.hi(1.6)
                       : (scanHover.hovered ? pane.theme.hi(1.4)
                                            : Qt.darker(pane.theme.bg, 1.2))
                border.color: pane.theme.sep
                border.width: 1
                opacity: pane.shellRoot.wifiEnabled ? 1 : 0.5

                HoverHandler { id: scanHover }

                Text {
                    anchors.centerIn: parent
                    text: pane.shellRoot.wifiScanning ? "Scanning…" : "Scan"
                    color: pane.theme.fg
                    font.family: pane.theme.ff
                    font.pixelSize: pane.theme.fs - 1
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: pane.shellRoot.wifiEnabled && !pane.shellRoot.wifiScanning
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pane.shellRoot.rescanWifi()
                }
            }
        }

        // ── Network list ─────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            // Hug the rows when there are networks; only reserve the 60px
            // minimum for the centred empty-state / Wi-Fi-off message.
            height: (pane.shellRoot.wifiEnabled && pane.shellRoot.wifiList.length > 0)
                    ? netCol.implicitHeight + 12
                    : 60
            color: Qt.darker(pane.theme.bg, 1.2)
            radius: 12
            border.color: pane.theme.sep
            border.width: 1

            Text {
                visible: !pane.shellRoot.wifiEnabled
                anchors.centerIn: parent
                text: "Wi-Fi is off"
                color: pane.theme.fg
                opacity: 0.6
                font.family: pane.theme.ff
                font.pixelSize: pane.theme.fs
            }

            Text {
                visible: pane.shellRoot.wifiEnabled && pane.shellRoot.wifiList.length === 0
                anchors.centerIn: parent
                text: pane.shellRoot.wifiScanning ? "Scanning for networks…" : "No networks found"
                color: pane.theme.fg
                opacity: 0.5
                font.family: pane.theme.ff
                font.pixelSize: pane.theme.fs - 1
            }

            Column {
                id: netCol
                visible: pane.shellRoot.wifiEnabled
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 2

                Repeater {
                    model: pane.shellRoot.wifiList
                    delegate: Column {
                        id: netDelegate
                        required property var modelData
                        width:  netCol.width
                        spacing: 2

                        Rectangle {
                        width:  parent.width
                        height: 38
                        radius: 8
                        color: rowHover.hovered
                                ? pane.theme.hi(1.2)
                                : (modelData.active ? pane.theme.hi(1.4) : "transparent")

                        HoverHandler { id: rowHover }

                        Row {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: pane.signalIcon(modelData.strength)
                                color: modelData.active ? pane.theme.tertiary : pane.theme.fg
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs + 1
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: modelData.secure
                                text: ""
                                color: pane.theme.fg
                                opacity: 0.7
                                font.family: pane.theme.ff
                                font.pixelSize: pane.theme.fs - 2
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1
                                Text {
                                    text: modelData.ssid
                                    color: pane.theme.fg
                                    font.family: pane.theme.ff
                                    font.bold: true
                                    font.pixelSize: pane.theme.fs
                                    elide: Text.ElideRight
                                    width: netCol.width - 200
                                }
                                Text {
                                    text: modelData.strength + "%"
                                            + (modelData.enterprise ? "  •  Enterprise"
                                                                    : (modelData.secure ? "  •  Secured" : "  •  Open"))
                                            + (modelData.active ? "  •  Connected" : "")
                                    color: pane.theme.fg
                                    opacity: 0.6
                                    font.family: pane.theme.ff
                                    font.pixelSize: pane.theme.fs - 2
                                }
                            }
                        }

                        Row {
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            spacing: 6

                            // Forget — only for networks with a saved profile.
                            Rectangle {
                                visible: pane.shellRoot.wifiSaved.indexOf(modelData.ssid) >= 0
                                anchors.verticalCenter: parent.verticalCenter
                                width: 70; height: 26
                                radius: 7
                                color: forgetBtnHover.hovered ? pane.theme.error : Qt.darker(pane.theme.bg, 1.2)
                                border.color: pane.theme.sep
                                border.width: 1
                                HoverHandler { id: forgetBtnHover }
                                Text {
                                    anchors.centerIn: parent
                                    text: "Forget"
                                    color: pane.theme.fg
                                    font.family: pane.theme.ff
                                    font.pixelSize: pane.theme.fs - 2
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pane.shellRoot.forgetWifi(modelData.ssid)
                                }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 90; height: 26
                                radius: 7
                                color: connBtnHover.hovered
                                        ? pane.theme.hi(1.6)
                                        : pane.theme.hi(1.3)
                                HoverHandler { id: connBtnHover }
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.active ? "Disconnect" : "Connect"
                                    color: pane.theme.fg
                                    font.family: pane.theme.ff
                                    font.pixelSize: pane.theme.fs - 2
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData.active) pane.shellRoot.disconnectWifi()
                                        else                  pane.shellRoot.connectWifi(modelData.ssid, modelData.secure, "settings", modelData.enterprise)
                                    }
                                }
                            }
                        }
                        }

                        // Credential form for the network being connected to —
                        // rendered directly beneath its row.
                        Loader {
                            width: netDelegate.width
                            active: pane.shellRoot.wifiPasswordOpen
                                    && pane.shellRoot.wifiPasswordSource === "settings"
                                    && pane.shellRoot.wifiPasswordSsid === netDelegate.modelData.ssid
                            visible: active
                            sourceComponent: passwordForm
                        }
                    }
                }
            }
        }

        }
    }

    Component.onCompleted: pane.shellRoot.refreshWifi()
}
