import QtQuick

// Single-line text input with placeholder and focus ring.
Rectangle {
    id: field

    required property var theme
    property alias text: input.text
    property alias textInput: input
    property string placeholder: ""
    property string icon: ""
    // Password field: masked, with a show/hide toggle.
    property bool   secret: false
    property bool   revealed: false
    signal accepted(string text)

    width: parent ? parent.width : 0
    height: 38
    radius: 9
    color: theme.light ? theme.paper : Qt.darker(theme.bg, 1.25)
    border.color: input.activeFocus ? theme.primary : Qt.rgba(theme.sep.r, theme.sep.g, theme.sep.b, 0.9)
    border.width: input.activeFocus ? 2 : 1

    Text {
        id: lead
        visible: field.icon !== ""
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        text: field.icon
        color: field.theme.outline
        font.family: field.theme.ff; font.pixelSize: field.theme.fs - 1
    }
    TextInput {
        id: input
        anchors {
            left: lead.visible ? lead.right : parent.left; leftMargin: lead.visible ? 8 : 12
            right: parent.right; rightMargin: field.secret ? 40 : 12
            verticalCenter: parent.verticalCenter
        }
        echoMode: field.secret && !field.revealed ? TextInput.Password : TextInput.Normal
        color: field.theme.fg
        selectionColor: field.theme.hi(1.4)
        font.family: field.theme.ff
        font.pixelSize: field.theme.fs - 1
        clip: true
        onAccepted: field.accepted(text)

        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: input.text.length === 0
            text: field.placeholder
            color: field.theme.outline
            font: input.font
        }
    }

    // Show / hide toggle for secret fields.
    Text {
        visible: field.secret
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        text: field.revealed ? "\uf070" : "\uf06e"
        color: field.theme.fg
        opacity: eyeHover.hovered ? 1 : 0.55
        font.family: field.theme.ff; font.pixelSize: field.theme.fs - 1
        HoverHandler { id: eyeHover }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: field.revealed = !field.revealed
        }
    }
}
