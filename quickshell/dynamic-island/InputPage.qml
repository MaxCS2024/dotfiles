import QtQuick

// The settings window's Input section (AGENTS.md, Settings window ›
// Input). Every control applies at once through InputSettings.
Item {
    id: page

    readonly property var layouts: InputSettings.value("layouts") || []
    property bool adding: false
    property string filter: ""

    // Layouts not added yet that match the search: the one whose code
    // it is first, then names starting with it, then shorter names first,
    // so "eng" puts English (US) and (UK) before English (Cameroon).
    readonly property var matches: {
        const f = filter.trim().toLowerCase()
        const found = InputSettings.allLayouts.filter(l => layouts.indexOf(l.code) === -1
            && (f === "" || l.name.toLowerCase().indexOf(f) !== -1 || l.code.toLowerCase() === f))
        if (f === "")
            return found
        const rank = l => (l.code.toLowerCase() === f ? 0 : l.name.toLowerCase().startsWith(f) ? 1 : 2)
        return found.sort((a, b) => rank(a) - rank(b) || a.name.length - b.name.length || a.name.localeCompare(b.name))
    }

    Component.onCompleted: InputSettings.refresh()

    function moveFirst(code) {
        InputSettings.set("layouts", [code].concat(layouts.filter(l => l !== code)))
    }

    function remove(code) {
        if (layouts.length > 1)
            InputSettings.set("layouts", layouts.filter(l => l !== code))
    }

    function add(code) {
        InputSettings.set("layouts", layouts.concat([code]))
        adding = false
        filter = ""
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: content.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            width: flick.width
            spacing: 4

            // ── Keyboard ──
            Heading { text: "Keyboard" }

            // The layouts, the first one used at login. Each other one can
            // be made the first, and any but the last removed.
            Repeater {
                model: page.layouts

                Rectangle {
                    id: layoutRow
                    required property string modelData
                    required property int index
                    width: content.width
                    height: 40
                    radius: 20
                    color: Qt.rgba(1, 1, 1, rowArea.containsMouse ? 0.12 : 0)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    Text {
                        id: layoutIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        horizontalAlignment: Text.AlignHCenter
                        text: "\u{f030c}"
                        color: "white"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 18
                    }

                    Text {
                        anchors.left: layoutIcon.right
                        anchors.leftMargin: 8
                        anchors.right: buttons.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: InputSettings.layoutName(layoutRow.modelData)
                        color: "white"
                        font.family: "JetBrainsMono Nerd Font"
                        font.weight: Font.Bold
                        font.pixelSize: 13
                    }

                    Row {
                        id: buttons
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: layoutRow.index === 0 && page.layouts.length > 1
                            rightPadding: 12
                            text: "At login"
                            color: "white"
                            opacity: 0.6
                            font.family: "JetBrainsMono Nerd Font"
                            font.weight: Font.Bold
                            font.pixelSize: 11
                        }

                        IconButton {
                            visible: layoutRow.index > 0
                            icon: "\u{f005d}"
                            onClicked: page.moveFirst(layoutRow.modelData)
                        }

                        IconButton {
                            visible: page.layouts.length > 1
                            icon: "\u{f0156}"
                            onClicked: page.remove(layoutRow.modelData)
                        }
                    }
                }
            }

            // Adding a layout: a button, then a search field over the list.
            Item {
                width: content.width
                height: 40

                PillButton {
                    visible: !page.adding
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add layout"
                    onClicked: {
                        page.adding = true
                        search.forceActiveFocus()
                    }
                }

                Rectangle {
                    visible: page.adding
                    anchors.fill: parent
                    radius: 20
                    color: Qt.rgba(1, 1, 1, 0.12)

                    TextInput {
                        id: search
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.right: closeSearch.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true
                        selectByMouse: true
                        color: "white"
                        selectionColor: Qt.rgba(1, 1, 1, 0.3)
                        font.family: "JetBrainsMono Nerd Font"
                        font.weight: Font.Bold
                        font.pixelSize: 13
                        text: page.filter
                        onTextEdited: page.filter = text
                        onAccepted: if (page.matches.length > 0) page.add(page.matches[0].code)
                        Keys.onEscapePressed: {
                            page.adding = false
                            page.filter = ""
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: search.text === ""
                            text: "Search layouts"
                            color: "white"
                            opacity: 0.4
                            font: search.font
                        }
                    }

                    IconButton {
                        id: closeSearch
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "\u{f0156}"
                        onClicked: {
                            page.adding = false
                            page.filter = ""
                        }
                    }
                }
            }

            ListView {
                id: matchList
                visible: page.adding
                width: content.width
                height: Math.min(count, 5) * 44 - 4
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: page.matches

                delegate: ListRow {
                    required property var modelData
                    width: matchList.width
                    label: modelData.name
                    detail: modelData.code
                    onClicked: page.add(modelData.code)
                }
            }

            SettingRow {
                width: content.width
                visible: page.layouts.length > 1
                label: "Switch layouts with"

                Choice {
                    width: 200
                    value: InputSettings.value("switchKey")
                    options: InputSettings.switchKeys
                    onPicked: v => InputSettings.set("switchKey", v)
                }
            }

            SettingRow {
                width: content.width
                label: "Repeat delay"
                detail: "Before a held key repeats"

                Row {
                    spacing: 8

                    ResetButton { key: "repeatDelay" }

                    ValueSlider {
                        from: 150
                        to: 1000
                        step: 10
                        value: InputSettings.value("repeatDelay") || 600
                        format: v => Math.round(v / 10) * 10 + " ms"
                        onMoved: v => InputSettings.set("repeatDelay", v)
                    }
                }
            }

            SettingRow {
                width: content.width
                label: "Repeat rate"
                detail: "Characters per second"

                Row {
                    spacing: 8

                    ResetButton { key: "repeatRate" }

                    ValueSlider {
                        from: 10
                        to: 60
                        step: 1
                        value: InputSettings.value("repeatRate") || 25
                        format: v => Math.round(v) + " /s"
                        onMoved: v => InputSettings.set("repeatRate", v)
                    }
                }
            }

            // ── Touchpad ──
            Item { width: 1; height: 12; visible: InputSettings.touchpads.length > 0 }
            Heading { text: "Touchpad"; visible: InputSettings.touchpads.length > 0 }

            Column {
                width: content.width
                visible: InputSettings.touchpads.length > 0
                spacing: 4

                SettingRow {
                    width: parent.width
                    label: "Tap to click"
                    Toggle {
                        on: !!InputSettings.value("tapToClick")
                        onToggled: InputSettings.set("tapToClick", !on)
                    }
                }

                SettingRow {
                    width: parent.width
                    label: "Natural scrolling"
                    detail: "Content follows your fingers"
                    Toggle {
                        on: !!InputSettings.value("naturalScroll")
                        onToggled: InputSettings.set("naturalScroll", !on)
                    }
                }

                SettingRow {
                    width: parent.width
                    label: "Disable while typing"
                    Toggle {
                        on: !!InputSettings.value("disableWhileTyping")
                        onToggled: InputSettings.set("disableWhileTyping", !on)
                    }
                }

                SettingRow {
                    width: parent.width
                    label: "Speed"
                    ValueSlider {
                        from: -1
                        to: 1
                        step: 0.05
                        value: InputSettings.value("touchpadSpeed") || 0
                        format: page.speedText
                        onMoved: v => InputSettings.set("touchpadSpeed", v)
                    }
                }
            }

            // ── Mouse ──
            Item { width: 1; height: 12 }
            Heading { text: "Mouse" }

            SettingRow {
                width: content.width
                label: "Speed"
                detail: "Mice and the TrackPoint"
                ValueSlider {
                    from: -1
                    to: 1
                    step: 0.05
                    value: InputSettings.value("mouseSpeed") || 0
                    format: page.speedText
                    onMoved: v => InputSettings.set("mouseSpeed", v)
                }
            }

            SettingRow {
                width: content.width
                label: "Acceleration"
                detail: "Faster movements go further"
                Toggle {
                    on: InputSettings.value("mouseAccel") !== false
                    onToggled: InputSettings.set("mouseAccel", !on)
                }
            }
        }
    }

    // -1…1 as -100…+100, 0 as "Default".
    function speedText(v) {
        const n = Math.round(v * 20) * 5
        return n === 0 ? "Default" : (n > 0 ? "+" : "") + n
    }

    component Heading: Text {
        height: 32
        verticalAlignment: Text.AlignVCenter
        color: "white"
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 16
    }

    // Back to the default for one setting: a restore arrow, there only
    // while the setting is changed from it (its place kept, so the
    // slider doesn't jump).
    component ResetButton: IconButton {
        property string key
        icon: "\u{f099b}"
        opacity: InputSettings.isSet(key) ? 1 : 0
        enabled: InputSettings.isSet(key)
        onClicked: InputSettings.unset(key)
    }

    // A round 32px glyph button: no fill, white at 12% while hovered.
    component IconButton: Rectangle {
        id: ib
        property string icon: ""
        signal clicked()
        width: 32
        height: 32
        radius: 16
        color: Qt.rgba(1, 1, 1, ibArea.containsMouse ? 0.12 : 0)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: ib.icon
            color: "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
        }

        MouseArea {
            id: ibArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: ib.clicked()
        }
    }
}
