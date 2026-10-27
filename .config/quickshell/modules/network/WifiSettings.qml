import QtQuick
import qs.common.ui

// Settings pane: Wi-Fi radio, saved profiles and nearby networks, with an
// inline sign-in form (WPA-PSK or WPA-Enterprise) under the network being
// connected.
Item {
    id: pane

    required property var theme

    readonly property string activeSsid: {
        const a = (NetworkService.wifiList || []).find(n => n.active)
        return a ? a.ssid : ""
    }

    // Saved profiles; "available" = SSID currently in range.
    readonly property var savedNetworks: {
        const scan = NetworkService.wifiList || []
        return (NetworkService.wifiSaved || []).map(name => {
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

    // Nearby networks without a saved profile (saved ones are listed above).
    readonly property var unsavedNetworks: {
        const saved = NetworkService.wifiSaved || []
        return (NetworkService.wifiList || []).filter(n => !saved.includes(n.ssid))
    }

    function securityText(n) {
        return n.enterprise ? "Enterprise" : (n.secure ? "Secured" : "Open")
    }
    function connect(n) {
        if (n.active) NetworkService.disconnectWifi()
        else          NetworkService.connectWifi(n.ssid, n.secure, "settings", n.enterprise)
    }

    // Small segmented choice used by the enterprise form.
    component SegButton: Rectangle {
        id: seg
        property string label: ""
        property bool selected: false
        signal clicked()
        width: segText.implicitWidth + 24
        height: 28
        radius: 7
        color: selected ? pane.theme.primary
             : (segHover.hovered ? Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.12)
                                 : Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.06))
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: segHover }
        Text {
            id: segText
            anchors.centerIn: parent
            text: seg.label
            color: seg.selected ? pane.theme.bg : pane.theme.fg
            font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs - 3
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: seg.clicked()
        }
    }

    // Inline credential form, created fresh beneath the row being connected
    // (empty fields, self-focusing).
    Component {
        id: passwordForm

        Item {
            id: pwSection

            // Enterprise (802.1X) prompt state — local so it resets each open.
            property string eapMethod: "peap"      // peap | ttls | pwd
            property string phase2Auth: "mschapv2" // mschapv2 | pap | gtc
            // Latched at creation so the title survives the collapse after
            // cancel clears the service's SSID.
            property string ssid: ""
            readonly property bool ready: pwField.text.length > 0
                && (!NetworkService.wifiPasswordEnterprise || idField.text.length > 0)

            width: parent ? parent.width : 0
            implicitHeight: pwCol.implicitHeight + 28

            // Submit the active form; no-op mid-connect or with blank fields.
            function tryConnect() {
                if (NetworkService.wifiConnecting || !ready) return
                if (NetworkService.wifiPasswordEnterprise) {
                    const ph2 = eapMethod === "pwd" ? "" : phase2Auth
                    NetworkService.submitWifiEnterprise(eapMethod, idField.text, pwField.text, ph2, anonField.text)
                } else {
                    NetworkService.submitWifiPassword(pwField.text)
                }
            }

            // Focus the relevant field as soon as the form appears.
            Component.onCompleted: {
                ssid = NetworkService.wifiPasswordSsid
                Qt.callLater(() => {
                    if (NetworkService.wifiPasswordEnterprise) idField.textInput.forceActiveFocus()
                    else                                       pwField.textInput.forceActiveFocus()
                })
            }

            Rectangle {
                anchors { fill: parent; leftMargin: 12; rightMargin: 12; bottomMargin: 12 }
                radius: 10
                color: Qt.rgba(pane.theme.primary.r, pane.theme.primary.g, pane.theme.primary.b, 0.07)
                border.color: Qt.rgba(pane.theme.primary.r, pane.theme.primary.g, pane.theme.primary.b, 0.4)
                border.width: 1
            }

            Column {
                id: pwCol
                x: 28; y: 14
                width: parent.width - 56
                spacing: 10

                Text {
                    width: parent.width
                    text: (NetworkService.wifiPasswordEnterprise ? "Sign in to " : "Enter the password for ")
                          + pwSection.ssid
                    color: pane.theme.fg
                    font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs - 1
                    elide: Text.ElideRight
                }

                // ── Enterprise: EAP method ──
                Row {
                    visible: NetworkService.wifiPasswordEnterprise
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 150
                        text: "EAP method"
                        color: pane.theme.txt2
                        font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                    }
                    SegButton { label: "PEAP"; selected: pwSection.eapMethod === "peap"; onClicked: pwSection.eapMethod = "peap" }
                    SegButton { label: "TTLS"; selected: pwSection.eapMethod === "ttls"; onClicked: pwSection.eapMethod = "ttls" }
                    SegButton { label: "PWD";  selected: pwSection.eapMethod === "pwd";  onClicked: pwSection.eapMethod = "pwd" }
                }

                UiTextField {
                    id: idField
                    visible: NetworkService.wifiPasswordEnterprise
                    theme: pane.theme
                    icon: ""
                    placeholder: "Identity (e.g. user@domain)"
                    onAccepted: pwSection.tryConnect()
                }
                UiTextField {
                    id: pwField
                    theme: pane.theme
                    icon: ""
                    secret: true
                    placeholder: NetworkService.wifiPasswordEnterprise ? "Password" : "Network password"
                    onAccepted: pwSection.tryConnect()
                }

                // ── Enterprise: inner (phase-2) auth — n/a for EAP-PWD ──
                Row {
                    visible: NetworkService.wifiPasswordEnterprise && pwSection.eapMethod !== "pwd"
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 150
                        text: "Inner authentication"
                        color: pane.theme.txt2
                        font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                    }
                    SegButton { label: "MSCHAPv2"; selected: pwSection.phase2Auth === "mschapv2"; onClicked: pwSection.phase2Auth = "mschapv2" }
                    SegButton { label: "PAP";      selected: pwSection.phase2Auth === "pap";      onClicked: pwSection.phase2Auth = "pap" }
                    SegButton { label: "GTC";      selected: pwSection.phase2Auth === "gtc";      onClicked: pwSection.phase2Auth = "gtc" }
                }

                UiTextField {
                    id: anonField
                    visible: NetworkService.wifiPasswordEnterprise
                    theme: pane.theme
                    placeholder: "Anonymous identity (optional)"
                    onAccepted: pwSection.tryConnect()
                }

                Text {
                    visible: NetworkService.wifiPasswordError.length > 0
                    width: parent.width
                    text: NetworkService.wifiPasswordError
                    color: pane.theme.error
                    wrapMode: Text.WordWrap
                    font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8
                    UiButton {
                        theme: pane.theme
                        text: "Cancel"
                        onClicked: NetworkService.cancelWifiPassword()
                    }
                    UiButton {
                        theme: pane.theme
                        kind: "primary"
                        enabled: pwSection.ready && !NetworkService.wifiConnecting
                        text: NetworkService.wifiConnecting ? "Connecting…" : "Connect"
                        onClicked: pwSection.tryConnect()
                    }
                }
            }
        }
    }

    // Centred placeholder line inside an empty group.
    component EmptyRow: Item {
        property string text: ""
        width: parent ? parent.width : 0
        implicitHeight: 56
        Text {
            anchors.centerIn: parent
            text: parent.text
            color: pane.theme.txt2
            font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
        }
    }

    UiPage {
        anchors.fill: parent
        theme: pane.theme

        // ── Radio ─────────────────────────────────────────────────────────
        UiGroup {
            theme: pane.theme
            UiRow {
                theme: pane.theme
                icon: ""
                title: "Wi-Fi"
                subtitle: !NetworkService.wifiEnabled ? "Off"
                        : pane.activeSsid ? "Connected to " + pane.activeSsid : "On  ·  Not connected"
                UiSwitch {
                    theme: pane.theme
                    checked: NetworkService.wifiEnabled
                    onToggled: value => NetworkService.toggleWifi(value)
                }
            }
        }

        // ── Saved networks ────────────────────────────────────────────────
        UiGroup {
            theme: pane.theme
            visible: pane.savedNetworks.length > 0
            title: "Saved networks"

            Repeater {
                model: pane.savedNetworks
                delegate: UiRow {
                    id: savedRow
                    required property var modelData
                    theme: pane.theme
                    // Out-of-range entries are dimmed.
                    opacity: modelData.available ? 1 : 0.5
                    icon: modelData.available ? "" : ""
                    iconColor: modelData.active ? pane.theme.primary : pane.theme.txt2
                    highlighted: modelData.active
                    title: modelData.ssid
                    subtitle: modelData.active    ? "Connected  ·  " + modelData.strength + "%"
                            : modelData.available ? "In range  ·  " + modelData.strength + "%"
                                                  : "Out of range"
                    UiButton {
                        readonly property bool connecting:
                            NetworkService.wifiConnectingSsid === savedRow.modelData.ssid
                        visible: savedRow.modelData.available
                        theme: pane.theme
                        kind: savedRow.modelData.active ? "secondary" : "primary"
                        enabled: !connecting
                        text: savedRow.modelData.active ? "Disconnect"
                            : connecting                ? "Connecting…" : "Connect"
                        onClicked: pane.connect(savedRow.modelData)
                    }
                    UiButton {
                        theme: pane.theme
                        kind: "danger"
                        icon: ""
                        onClicked: NetworkService.forgetWifi(savedRow.modelData.ssid)
                    }
                }
            }
        }

        // ── Nearby networks ───────────────────────────────────────────────
        UiGroup {
            theme: pane.theme
            title: "Available networks"
            description: NetworkService.wifiEnabled && pane.unsavedNetworks.length > 0
                         ? pane.unsavedNetworks.length + " in range" : ""
            actions: [
                UiButton {
                    theme: pane.theme
                    icon: ""
                    text: "nmtui"
                    onClicked: NetworkService.launchNmtui()
                },
                UiButton {
                    theme: pane.theme
                    kind: "primary"
                    enabled: NetworkService.wifiEnabled && !NetworkService.wifiScanning
                    icon: ""
                    text: NetworkService.wifiScanning ? "Scanning…" : "Scan"
                    onClicked: NetworkService.rescanWifi()
                }
            ]

            Repeater {
                model: NetworkService.wifiEnabled ? pane.unsavedNetworks : []
                delegate: Column {
                    id: netDelegate
                    required property var modelData
                    required property int index
                    width: parent.width

                    UiRow {
                        theme: pane.theme
                        showDivider: netDelegate.index > 0
                        icon: ""
                        iconColor: netDelegate.modelData.active ? pane.theme.primary : pane.theme.txt2
                        highlighted: netDelegate.modelData.active
                        title: netDelegate.modelData.ssid
                        subtitle: netDelegate.modelData.strength + "%  ·  " + pane.securityText(netDelegate.modelData)
                                  + (netDelegate.modelData.active ? "  ·  Connected" : "")

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: netDelegate.modelData.secure
                            text: ""
                            color: pane.theme.txt2
                            font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                        }
                        UiButton {
                            readonly property bool connecting:
                                NetworkService.wifiConnectingSsid === netDelegate.modelData.ssid
                            theme: pane.theme
                            kind: netDelegate.modelData.active ? "secondary" : "primary"
                            enabled: !connecting
                            text: netDelegate.modelData.active ? "Disconnect"
                                : connecting                    ? "Connecting…" : "Connect"
                            onClicked: pane.connect(netDelegate.modelData)
                        }
                    }

                    // Credential form directly beneath the connecting row.
                    // Slides open/closed; the form stays loaded until the
                    // collapse finishes (a fresh one is made on each open).
                    Item {
                        id: pwWrap
                        readonly property bool open: NetworkService.wifiPasswordOpen
                                && NetworkService.wifiPasswordSource === "settings"
                                && NetworkService.wifiPasswordSsid === netDelegate.modelData.ssid
                        width: netDelegate.width
                        height: open && pwLoader.item ? pwLoader.item.implicitHeight : 0
                        Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        clip: true
                        visible: height > 0

                        Loader {
                            id: pwLoader
                            width: parent.width
                            active: pwWrap.open || pwWrap.height > 0
                            sourceComponent: passwordForm
                            opacity: pwWrap.open ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
            EmptyRow {
                visible: !NetworkService.wifiEnabled || pane.unsavedNetworks.length === 0
                text: !NetworkService.wifiEnabled ? "Wi-Fi is off"
                    : NetworkService.wifiScanning ? "Scanning for networks…" : "No other networks found"
            }
        }
    }

    Component.onCompleted: NetworkService.refreshWifi()
}
