import QtQuick

// The settings window's Displays section (AGENTS.md, Settings window ›
// Displays). Edits go to Displays.staged and wait for Apply. The state
// lives in the Displays singleton; this is only the page.
Item {
    id: page

    readonly property var current: Displays.screen(Displays.selected)
    readonly property bool several: Displays.staged.length > 1

    // When this resolution's best refresh rate is well under another
    // resolution's (a 4K screen on HDMI 1.4 tops out at 30 Hz), say where
    // the higher rate is: "Up to 60 Hz at 2560 × 1440".
    readonly property string rateHint: {
        const c = current
        if (!c || !c.enabled)
            return ""
        const top = r => Math.max(0, ...(c.modes[r] || []).map(parseFloat))
        const here = top(c.res)
        const better = Displays.resolutions(c.modes).find(r => top(r) >= here + 10)
        return better ? "Up to " + Math.round(top(better)) + " Hz at " + better.replace("x", " × ") : ""
    }

    // Fresh on every visit, unless there are edits not applied yet.
    Component.onCompleted: if (!Displays.dirty) Displays.refresh()

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.bottomMargin: 56
        contentHeight: content.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            width: flick.width
            spacing: 16

            // ── The arrangement: every screen as a rectangle, to scale ──
            Item {
                id: canvas
                width: parent.width
                height: 160

                // Screens in the layout where Hyprland has them; the rest
                // (off, or mirroring) in a row to their right, dimmed.
                readonly property var layout: {
                    const list = Displays.staged
                    const rects = {}
                    const p = Displays.placed(list)
                    let minX = 0, minY = 0, maxX = 0, maxY = 0
                    if (p.length > 0) {
                        minX = Math.min(...p.map(m => m.x))
                        minY = Math.min(...p.map(m => m.y))
                        maxX = Math.max(...p.map(m => m.x + Displays.size(m).w))
                        maxY = Math.max(...p.map(m => m.y + Displays.size(m).h))
                    }
                    for (const m of p)
                        rects[m.name] = Object.assign({ x: m.x, y: m.y }, Displays.size(m))
                    const gap = Math.max(maxX - minX, 1000) * 0.08
                    let x = p.length > 0 ? maxX + gap : 0
                    for (const m of list) {
                        if (rects[m.name])
                            continue
                        const s = Displays.size(m)
                        rects[m.name] = { x: x, y: minY, w: s.w, h: s.h }
                        maxY = Math.max(maxY, minY + s.h)
                        x += s.w + gap
                    }
                    const right = Math.max(maxX, x - gap)
                    const bw = Math.max(1, right - minX), bh = Math.max(1, maxY - minY)
                    const k = Math.min((width - 32) / bw, (height - 32) / bh)
                    return {
                        rects: rects,
                        k: k,
                        ox: (width - bw * k) / 2 - minX * k,
                        oy: (height - bh * k) / 2 - minY * k,
                    }
                }

                Repeater {
                    model: Displays.staged

                    Rectangle {
                        id: screenRect
                        required property var modelData
                        readonly property var r: canvas.layout.rects[modelData.name] || { x: 0, y: 0, w: 0, h: 0 }
                        readonly property bool chosen: Displays.selected === modelData.name
                        readonly property bool off: !modelData.enabled || modelData.mirror !== ""
                        readonly property bool movable: !off && Displays.placed().length > 1
                        property real dx: 0
                        property real dy: 0

                        x: canvas.layout.ox + r.x * canvas.layout.k + dx
                        y: canvas.layout.oy + r.y * canvas.layout.k + dy
                        z: screenArea.pressed ? 1 : 0
                        // 2px apart, so touching screens read as two.
                        width: Math.max(8, r.w * canvas.layout.k - 2)
                        height: Math.max(8, r.h * canvas.layout.k - 2)
                        radius: 12
                        opacity: off && !chosen ? 0.5 : 1
                        color: chosen ? "white" : Qt.rgba(1, 1, 1, screenArea.containsMouse ? 0.2 : 0.12)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 16

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: screenRect.modelData.label
                                color: screenRect.chosen ? "black" : "white"
                                font.family: "JetBrainsMono Nerd Font"
                                font.weight: Font.Bold
                                font.pixelSize: 13
                            }

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: !screenRect.modelData.enabled ? "Off"
                                    : screenRect.modelData.mirror ? "Mirrors " + screenRect.modelData.mirror
                                    : screenRect.modelData.res.replace("x", " × ")
                                color: screenRect.chosen ? "black" : "white"
                                opacity: 0.6
                                font.family: "JetBrainsMono Nerd Font"
                                font.weight: Font.Bold
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            id: screenArea
                            property point start
                            anchors.fill: parent
                            hoverEnabled: true
                            onPressed: mouse => {
                                Displays.selected = screenRect.modelData.name
                                start = mapToItem(canvas, mouse.x, mouse.y)
                            }
                            onPositionChanged: mouse => {
                                if (!pressed || !screenRect.movable)
                                    return
                                const p = mapToItem(canvas, mouse.x, mouse.y)
                                screenRect.dx = p.x - start.x
                                screenRect.dy = p.y - start.y
                            }
                            onReleased: {
                                if (screenRect.dx !== 0 || screenRect.dy !== 0) {
                                    const k = canvas.layout.k
                                    Displays.move(screenRect.modelData.name,
                                        screenRect.r.x + screenRect.dx / k,
                                        screenRect.r.y + screenRect.dy / k)
                                }
                                screenRect.dx = 0
                                screenRect.dy = 0
                            }
                        }
                    }
                }
            }

            // ── The selected screen ──
            Column {
                width: parent.width
                visible: page.current !== null

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: page.current ? page.current.label : ""
                    color: "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.Bold
                    font.pixelSize: 16
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: page.current ? page.current.name + (page.current.desc ? " – " + page.current.desc : "") : ""
                    color: "white"
                    opacity: 0.6
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.Bold
                    font.pixelSize: 11
                }
            }

            Column {
                width: parent.width
                visible: page.current !== null
                spacing: 4

                SettingRow {
                    width: parent.width
                    label: "Use this display"
                    detail: page.current && Displays.isLast(page.current.name) ? "The only screen in use" : ""

                    Toggle {
                        on: page.current ? page.current.enabled : false
                        opacity: page.current && Displays.isLast(page.current.name) ? 0.4 : 1
                        onToggled: if (!Displays.isLast(page.current.name))
                            Displays.set(page.current.name, "enabled", !page.current.enabled)
                    }
                }

                SettingRow {
                    width: parent.width
                    visible: !!(page.current && page.current.enabled)
                    label: "Resolution"

                    Choice {
                        width: 200
                        value: page.current ? page.current.res : ""
                        options: page.current ? Displays.resolutions(page.current.modes)
                            .map(r => ({ label: r.replace("x", " × "), value: r })) : []
                        onPicked: v => Displays.set(page.current.name, "res", v)
                    }
                }

                SettingRow {
                    width: parent.width
                    visible: !!(page.current && page.current.enabled)
                    label: "Refresh rate"
                    detail: page.rateHint

                    Choice {
                        width: 200
                        value: page.current ? page.current.rate : ""
                        options: page.current ? (page.current.modes[page.current.res] || [page.current.rate])
                            .map(r => ({ label: parseFloat(r).toFixed(2) + " Hz", value: r })) : []
                        onPicked: v => Displays.set(page.current.name, "rate", v)
                    }
                }

                SettingRow {
                    width: parent.width
                    visible: !!(page.current && page.current.enabled)
                    label: "Scale"

                    Segmented {
                        value: page.current ? page.current.scale : 1
                        options: Displays.scales.map(s => ({ label: Math.round(s * 100) + "%", value: s }))
                        onPicked: v => Displays.set(page.current.name, "scale", v)
                    }
                }

                SettingRow {
                    width: parent.width
                    visible: !!(page.current && page.current.enabled)
                    label: "Rotation"

                    Segmented {
                        value: page.current ? page.current.transform : 0
                        options: [
                            { label: "Normal", value: 0 },
                            { label: "90°", value: 1 },
                            { label: "180°", value: 2 },
                            { label: "270°", value: 3 },
                        ]
                        onPicked: v => Displays.set(page.current.name, "transform", v)
                    }
                }

                SettingRow {
                    width: parent.width
                    visible: !!(page.several && page.current && page.current.enabled)
                    label: "Mirror"
                    detail: "Show another screen's picture"

                    Choice {
                        width: 200
                        value: page.current ? page.current.mirror : ""
                        options: [{ label: "Off", value: "" }].concat(Displays.placed()
                            .filter(m => page.current && m.name !== page.current.name)
                            .map(m => ({ label: m.label, value: m.name })))
                        onPicked: v => {
                            if (v === "" || !Displays.isLast(page.current.name))
                                Displays.set(page.current.name, "mirror", v)
                        }
                    }
                }
            }

            // ── For the whole machine ──
            SettingRow {
                width: parent.width
                visible: Displays.hasLaptop
                label: "Laptop screen off when docked"
                detail: "While an external screen is connected"

                Toggle {
                    on: Displays.stagedDock
                    onToggled: Displays.stagedDock = !Displays.stagedDock
                }
            }
        }
    }

    // ── Apply ──
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: Displays.dirty
            text: "Not applied yet"
            color: "white"
            opacity: 0.6
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.Bold
            font.pixelSize: 11
        }

        Item { width: 8; height: 1 }

        PillButton {
            text: "Reset"
            enabled: Displays.dirty && !Displays.confirming
            onClicked: Displays.reset()
        }

        PillButton {
            text: "Apply"
            primary: true
            enabled: Displays.dirty && !Displays.confirming
            onClicked: Displays.apply()
        }
    }

    // ── Keep or revert ──
    Rectangle {
        anchors.fill: parent
        visible: Displays.confirming
        color: Qt.rgba(0, 0, 0, 0.8)

        // Takes every click meant for the page underneath.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }

        Rectangle {
            anchors.centerIn: parent
            width: 360
            height: confirmColumn.height + 48
            radius: 24
            // White at 12% over black, opaque so the page doesn't show through.
            color: Qt.rgba(0.12, 0.12, 0.12, 1)

            Column {
                id: confirmColumn
                anchors.centerIn: parent
                width: parent.width - 48
                spacing: 8

                Text {
                    text: "Keep these display settings?"
                    color: "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.Bold
                    font.pixelSize: 16
                }

                Text {
                    text: "Reverting in " + Displays.secondsLeft + " s"
                    color: "white"
                    opacity: 0.6
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.Bold
                    font.pixelSize: 13
                }

                Item { width: 1; height: 8 }

                Row {
                    anchors.right: parent.right
                    spacing: 8

                    PillButton {
                        text: "Revert"
                        onClicked: Displays.revert()
                    }

                    PillButton {
                        text: "Keep"
                        primary: true
                        onClicked: Displays.keep()
                    }
                }
            }
        }
    }
}
