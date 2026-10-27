import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.common.ui
import qs.modules.icons

// Settings pane: opens on a chooser between default apps (Windows-style:
// one app tile per category plus a by-file-type list, each opening a
// "Choose an app" sheet) and the installed apps with an uninstall action
// (yay -Rncs in a terminal, see AppsService).
Item {
    id: pane

    required property var theme

    // "" = chooser, "defaults" or "installed".
    property string view: ""
    // Back arrow beside the settings window title (SettingsWindow).
    readonly property bool canGoBack: view !== ""
    function goBack() { view = "" }
    onViewChanged: { confirming = ""; picker = null; page.contentY = 0 }
    // Package waiting for the remove confirmation ("" = none).
    property string confirming: ""
    property string query: ""
    property string typeQuery: ""

    // The installed list shows launcher-visible apps only.
    readonly property var shownApps: {
        const q = query.trim().toLowerCase()
        return AppsService.apps.filter(a => a.shown && (!q || a.name.toLowerCase().indexOf(q) >= 0
                                                           || a.pkg.toLowerCase().indexOf(q) >= 0))
    }
    readonly property var shownTypes: {
        const q = typeQuery.trim().toLowerCase()
        if (!q) return AppsService.types
        return AppsService.types.filter(t => (t.ext + " " + t.desc + " " + t.category + " "
                                              + AppsService.app(t.current).name).toLowerCase().indexOf(q) >= 0)
    }

    // "Choose an app" sheet: { kind: "category" | "type", key, title,
    // subtitle, current, candidates: [desktop id] } or null.
    property var picker: null
    property string pickerSel: ""
    property bool pickerMore: false
    readonly property var otherApps: picker
        ? AppsService.apps.filter(a => a.shown && picker.candidates.indexOf(a.id) < 0) : []
    function openPicker(p) {
        picker = p
        pickerSel = p.current
        pickerMore = p.candidates.length === 0
    }
    function applyPicker() {
        if (picker && pickerSel && pickerSel !== picker.current) {
            if (picker.kind === "category") AppsService.setDefault(picker.key, pickerSel)
            else AppsService.setType(picker.key, pickerSel)
        }
        picker = null
    }

    function categoryGlyph(key) {
        return { browser: "", files: "", editor: "", image: "",
                 video: "", music: "", pdf: "", mail: "",
                 archive: "" }[key] || ""
    }
    // "Zen Browser, Zed, Audacity and 2 more" (distinct current defaults).
    function defaultsSummary() {
        const names = []
        for (const d of AppsService.defaults) {
            const n = AppsService.app(d.current).name
            if (d.current && names.indexOf(n) < 0) names.push(n)
        }
        if (!names.length) return AppsService.loading ? "Loading…" : "Which app opens links and files of each type"
        return names.length <= 3 ? names.join(", ")
             : names.slice(0, 3).join(", ") + " and " + (names.length - 3) + " more"
    }

    Component.onCompleted: AppsService.refresh()

    UiPage {
        id: page
        anchors.fill: parent
        theme: pane.theme

        // ── Chooser ───────────────────────────────────────────────────────
        UiGroup {
            visible: pane.view === ""
            theme: pane.theme
            title: "Manage apps"

            UiRow {
                theme: pane.theme
                icon: ""
                title: "Default apps"
                subtitle: pane.defaultsSummary()
                clickable: true
                onClicked: pane.view = "defaults"
                UiChevron { theme: pane.theme }
            }
            UiRow {
                theme: pane.theme
                icon: ""
                title: "Installed apps"
                readonly property int count: AppsService.apps.filter(a => a.shown).length
                subtitle: count ? count + " apps  ·  Search and remove"
                                : AppsService.loading ? "Loading…" : "Search and remove"
                clickable: true
                onClicked: pane.view = "installed"
                UiChevron { theme: pane.theme }
            }
        }

        // ── Default apps: one tile per category ───────────────────────────
        UiGroup {
            visible: pane.view === "defaults"
            theme: pane.theme
            title: "Default apps"
            description: "Click an app to choose which one opens each kind of link and file"

            Item {
                width: parent.width
                height: catGrid.implicitHeight + 36
                Grid {
                    id: catGrid
                    x: 18; y: 18
                    width: parent.width - 36
                    columns: width >= 620 ? 2 : 1
                    columnSpacing: 18
                    rowSpacing: 16
                    Repeater {
                        model: AppsService.defaults
                        delegate: Column {
                            id: cat
                            required property var modelData
                            width: (catGrid.width - catGrid.columnSpacing * (catGrid.columns - 1)) / catGrid.columns
                            spacing: 7
                            Row {
                                spacing: 8
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pane.categoryGlyph(cat.modelData.key)
                                    color: pane.theme.primary
                                    font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: cat.modelData.label
                                    color: pane.theme.txt2
                                    font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs - 2
                                }
                            }
                            AppTile {
                                width: parent.width
                                appId: cat.modelData.current
                                onClicked: pane.openPicker({
                                    kind: "category", key: cat.modelData.key,
                                    title: "Choose an app", subtitle: cat.modelData.label,
                                    current: cat.modelData.current, candidates: cat.modelData.candidates })
                            }
                        }
                    }
                }
            }
        }

        // ── Default apps by file type ─────────────────────────────────────
        UiGroup {
            visible: pane.view === "defaults"
            theme: pane.theme
            title: "Choose defaults by file type"
            description: "Override the app for a single file or link type"

            Item {
                width: parent.width
                height: 58
                UiTextField {
                    anchors { left: parent.left; right: parent.right; margins: 12; verticalCenter: parent.verticalCenter }
                    theme: pane.theme
                    icon: ""
                    placeholder: "Search types, e.g. .png, video or Zen"
                    onTextChanged: pane.typeQuery = text
                }
            }
            Repeater {
                model: pane.shownTypes
                delegate: TypeRow {}
            }
            Text {
                visible: pane.shownTypes.length === 0
                width: parent.width
                padding: 18
                text: AppsService.loading ? "Loading…" : "No file types match “" + pane.typeQuery + "”"
                color: pane.theme.txt2
                font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
            }
        }

        // ── Installed apps ────────────────────────────────────────────────
        UiGroup {
            visible: pane.view === "installed"
            theme: pane.theme
            title: "Installed apps"
            description: AppsService.removing !== "" ? "Removing " + AppsService.removing + " — finish in the terminal window"
                       : pane.shownApps.length + " apps. Remove uses yay -Rncs: the package, its config backups, "
                         + "dependencies nothing else needs, and packages that depend on it"
            actions: [
                UiButton { theme: pane.theme; icon: ""; onClicked: AppsService.refresh() }
            ]

            Item {
                width: parent.width
                height: 58
                UiTextField {
                    anchors { left: parent.left; right: parent.right; margins: 12; verticalCenter: parent.verticalCenter }
                    theme: pane.theme
                    icon: ""
                    placeholder: "Search apps or packages"
                    onTextChanged: pane.query = text
                }
            }

            Repeater {
                model: pane.shownApps
                delegate: AppLine {
                    id: line
                    required property var modelData
                    readonly property bool asking: pane.confirming !== "" && pane.confirming === modelData.pkg
                    appIcon: modelData.icon
                    title: modelData.name
                    subtitle: asking ? "Remove " + modelData.pkg + " with yay -Rncs? Every app from this package goes with it"
                            : modelData.pkg === "" ? "Not installed by a package (local shortcut)"
                            : [modelData.pkg, modelData.version, modelData.size].filter(s => s).join("  ·  ")
                    subtitleColor: asking ? pane.theme.warn : pane.theme.txt2

                    UiButton {
                        visible: line.modelData.pkg !== "" && !line.asking
                        enabled: AppsService.removing === ""
                        theme: pane.theme
                        kind: "danger"
                        icon: ""
                        text: AppsService.removing === line.modelData.pkg ? "Removing…" : "Remove"
                        onClicked: pane.confirming = line.modelData.pkg
                    }
                    UiButton {
                        visible: line.asking
                        theme: pane.theme
                        text: "Cancel"
                        onClicked: pane.confirming = ""
                    }
                    UiButton {
                        visible: line.asking
                        theme: pane.theme
                        kind: "danger"
                        icon: ""
                        text: "Remove"
                        onClicked: { AppsService.uninstall(line.modelData.pkg); pane.confirming = "" }
                    }
                }
            }

            Text {
                visible: pane.shownApps.length === 0
                width: parent.width
                padding: 18
                text: AppsService.loading ? "Loading…" : "No apps match “" + pane.query + "”"
                color: pane.theme.txt2
                font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
            }
        }
    }

    // ── "Choose an app" sheet ─────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: pane.picker !== null
        z: 10

        Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.45 }
        // Clicking outside the sheet cancels.
        MouseArea { anchors.fill: parent; onClicked: pane.picker = null }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(480, parent.width - 48)
            height: Math.min(sheetHead.height + pickList.contentHeight + sheetFoot.height + 24, parent.height - 48)
            radius: 16
            color: pane.theme.surface
            border.color: pane.theme.sep
            border.width: 1
            clip: true
            MouseArea { anchors.fill: parent }   // keep clicks inside from closing it

            Column {
                id: sheetHead
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 22 }
                height: implicitHeight + 14
                spacing: 4
                Text {
                    text: pane.picker ? pane.picker.title : ""
                    color: pane.theme.fg
                    font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs + 5
                }
                Text {
                    width: parent.width
                    text: pane.picker ? pane.picker.subtitle : ""
                    color: pane.theme.txt2
                    font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                    elide: Text.ElideRight
                }
            }

            Flickable {
                id: pickList
                anchors { top: sheetHead.bottom; bottom: sheetFoot.top; left: parent.left; right: parent.right
                          leftMargin: 12; rightMargin: 12 }
                contentHeight: pickCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: pickCol
                    width: parent.width
                    spacing: 2

                    SheetLabel {
                        visible: !!pane.picker && pane.picker.candidates.length > 0
                        text: "Suggested apps"
                    }
                    Repeater {
                        model: pane.picker ? pane.picker.candidates : []
                        delegate: PickRow {}
                    }

                    // "More apps": every other installed app, collapsed.
                    Rectangle {
                        visible: pane.otherApps.length > 0
                        width: parent.width
                        height: 40
                        radius: 9
                        color: moreHover.hovered ? Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.05) : "transparent"
                        HoverHandler { id: moreHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pane.pickerMore = !pane.pickerMore
                        }
                        Text {
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: "More apps  " + (pane.pickerMore ? "" : "")
                            color: pane.theme.primary
                            font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs - 2
                        }
                    }
                    Repeater {
                        model: pane.pickerMore ? pane.otherApps.map(a => a.id) : []
                        delegate: PickRow {}
                    }
                }
            }

            Row {
                id: sheetFoot
                anchors { bottom: parent.bottom; right: parent.right; margins: 18 }
                height: 36
                spacing: 8
                UiButton {
                    theme: pane.theme
                    text: "Cancel"
                    onClicked: pane.picker = null
                }
                UiButton {
                    theme: pane.theme
                    kind: "primary"
                    enabled: !!pane.picker && pane.pickerSel !== "" && pane.pickerSel !== pane.picker.current
                    text: "Set default"
                    onClicked: pane.applyPicker()
                }
            }
        }
    }

    // Big app button (Windows' default-app tile): icon + name, or a "+"
    // when nothing is set.
    component AppTile: Rectangle {
        id: tile
        property string appId: ""
        property bool compact: false
        signal clicked()
        readonly property var info: AppsService.app(appId)

        height: compact ? 46 : 58
        radius: 10
        color: tileHover.hovered ? Qt.rgba(pane.theme.primary.r, pane.theme.primary.g, pane.theme.primary.b, 0.10)
                                 : pane.theme.inset
        border.width: 1
        border.color: tileHover.hovered ? Qt.rgba(pane.theme.primary.r, pane.theme.primary.g, pane.theme.primary.b, 0.5)
                                        : pane.theme.sep
        Behavior on color { ColorAnimation { duration: 120 } }

        HoverHandler { id: tileHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }

        Item {
            id: tileIcon
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            width: tile.compact ? 26 : 34; height: width
            IconImage {
                visible: tile.appId !== ""
                anchors.fill: parent
                implicitSize: parent.width
                asynchronous: true
                source: IconService.iconFor(tile.info.icon) || IconService.iconFor("application-x-executable")
            }
            Rectangle {
                visible: tile.appId === ""
                anchors.fill: parent
                radius: 8
                color: Qt.rgba(pane.theme.primary.r, pane.theme.primary.g, pane.theme.primary.b, 0.15)
                Text {
                    anchors.centerIn: parent
                    text: ""
                    color: pane.theme.primary
                    font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 2
                }
            }
        }
        Column {
            anchors { left: tileIcon.right; leftMargin: 12; right: parent.right; rightMargin: 12
                      verticalCenter: parent.verticalCenter }
            spacing: 2
            Text {
                width: parent.width
                text: tile.appId !== "" ? tile.info.name : "Choose a default"
                color: tile.appId !== "" ? pane.theme.fg : pane.theme.primary
                font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs - 1
                elide: Text.ElideRight
            }
            Text {
                visible: !tile.compact
                width: parent.width
                text: tile.appId !== "" ? "Click to change" : "No app set"
                color: pane.theme.txt2
                font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
                elide: Text.ElideRight
            }
        }
    }

    // One file/link type: extensions + description, app tile on the right.
    component TypeRow: Item {
        id: tr
        required property var modelData
        width: parent ? parent.width : 0
        height: 64

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
            height: 1
            color: pane.theme.sep
            opacity: 0.6
        }
        Column {
            anchors { left: parent.left; leftMargin: 18; right: trTile.left; rightMargin: 14
                      verticalCenter: parent.verticalCenter }
            spacing: 3
            Text {
                width: parent.width
                text: tr.modelData.ext
                color: pane.theme.fg
                font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs - 1
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: tr.modelData.desc + "  ·  " + tr.modelData.category
                color: pane.theme.txt2
                font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
                elide: Text.ElideRight
            }
        }
        AppTile {
            id: trTile
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            width: Math.min(280, tr.width * 0.45)
            compact: true
            appId: tr.modelData.current
            onClicked: pane.openPicker({
                kind: "type", key: tr.modelData.mime,
                title: "Choose an app",
                subtitle: tr.modelData.ext + "  ·  " + tr.modelData.desc,
                current: tr.modelData.current, candidates: tr.modelData.candidates })
        }
    }

    // One app in the sheet; click selects, double-click sets it at once.
    component PickRow: Rectangle {
        id: pr
        required property var modelData          // desktop id
        readonly property var info: AppsService.app(modelData)
        readonly property bool selected: pane.pickerSel === modelData
        readonly property bool isCurrent: !!pane.picker && pane.picker.current === modelData
        width: parent ? parent.width : 0
        height: 48
        radius: 9
        color: selected ? Qt.rgba(pane.theme.primary.r, pane.theme.primary.g, pane.theme.primary.b, 0.16)
             : prHover.hovered ? Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.05) : "transparent"
        border.width: selected ? 1 : 0
        border.color: Qt.rgba(pane.theme.primary.r, pane.theme.primary.g, pane.theme.primary.b, 0.6)

        HoverHandler { id: prHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: pane.pickerSel = pr.modelData
            onDoubleClicked: { pane.pickerSel = pr.modelData; pane.applyPicker() }
        }
        IconImage {
            id: prIcon
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            implicitSize: 30
            asynchronous: true
            source: IconService.iconFor(pr.info.icon) || IconService.iconFor("application-x-executable")
        }
        Text {
            anchors { left: prIcon.right; leftMargin: 12; right: prTag.left; rightMargin: 8
                      verticalCenter: parent.verticalCenter }
            text: pr.info.name
            color: pane.theme.fg
            font.family: pane.theme.ff; font.bold: pr.selected; font.pixelSize: pane.theme.fs - 1
            elide: Text.ElideRight
        }
        Text {
            id: prTag
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: pr.isCurrent ? "Current" : ""
            color: pane.theme.txt2
            font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
        }
    }

    component SheetLabel: Text {
        leftPadding: 10
        topPadding: 4
        bottomPadding: 4
        color: pane.theme.txt2
        font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs - 3
    }


    // One app inside a group card: app icon, name + subtitle, trailing
    // controls. Same metrics and divider as UiRow, with a real app icon.
    component AppLine: Item {
        id: al
        property string appIcon: ""
        property string title: ""
        property string subtitle: ""
        property color  subtitleColor: pane.theme.txt2
        property bool   clickable: false
        property int    indent: 16
        default property alias trailing: alTrail.data
        signal clicked()

        width: parent ? parent.width : 0
        implicitHeight: Math.max(56, alText.implicitHeight + 20)

        Rectangle {
            anchors { fill: parent; margins: 4 }
            radius: 9
            color: al.clickable && alHover.hovered
                   ? Qt.rgba(pane.theme.fg.r, pane.theme.fg.g, pane.theme.fg.b, 0.05) : "transparent"
        }
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
            height: 1
            color: pane.theme.sep
            opacity: 0.6
        }
        HoverHandler { id: alHover }
        MouseArea {
            anchors.fill: parent
            enabled: al.clickable
            cursorShape: Qt.PointingHandCursor
            onClicked: al.clicked()
        }

        IconImage {
            id: alIcon
            anchors { left: parent.left; leftMargin: al.indent; verticalCenter: parent.verticalCenter }
            implicitSize: 32
            asynchronous: true
            // Icon names missing from the theme fall back to a generic app icon.
            source: IconService.iconFor(al.appIcon) || IconService.iconFor("application-x-executable")
        }
        Column {
            id: alText
            anchors {
                left: alIcon.right; leftMargin: 14
                right: alTrail.left; rightMargin: 14
                verticalCenter: parent.verticalCenter
            }
            spacing: 3
            Text {
                width: parent.width
                text: al.title
                color: pane.theme.fg
                font.family: pane.theme.ff; font.bold: true; font.pixelSize: pane.theme.fs - 1
                elide: Text.ElideRight
            }
            Text {
                visible: al.subtitle !== ""
                width: parent.width
                text: al.subtitle
                color: al.subtitleColor
                font.family: pane.theme.ff; font.pixelSize: pane.theme.fs - 3
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
        Row {
            id: alTrail
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 8
        }
    }
}
