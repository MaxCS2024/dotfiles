import Quickshell
import Quickshell.Wayland
import QtQuick

// The layouts bar on one screen. It slides up from the bottom when a
// dragged window's cursor touches the bottom edge, stays while the cursor is
// within reach of it, and goes when the drag ends or moves away. The zone
// under the cursor turns white; letting go there places the window.
// The pointer belongs to the drag the whole time, so the bar never takes
// input: hover comes from the cursor position snap.lua sends.
PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    // The island's look: white on black, the zones white at two strengths.
    readonly property color plateColor: "black"
    readonly property color zoneColor: Qt.rgba(1, 1, 1, 0.24)
    readonly property color zoneHoverColor: "white"
    // The plate's radius is the zones' plus the padding, so the corners
    // run parallel.
    readonly property int zoneRadius: 4
    readonly property int plateRadius: zoneRadius + pad

    readonly property int pad: 12
    readonly property int tileW: 96
    readonly property int tileH: 56
    readonly property int tileGap: 12
    readonly property int zoneGap: 4
    // How far the plate slides up as it opens.
    readonly property int drop: 8
    // The cursor counts as at the bottom edge this close to it.
    readonly property int edge: 4
    // How far above the bar the cursor can go before it closes.
    readonly property int reach: 32

    // Each layout's zones, as [x, y, width, height] fractions of the screen,
    // in Windows 11's order.
    readonly property var layouts: [
        [[0, 0, 1/2, 1], [1/2, 0, 1/2, 1]],
        [[0, 0, 2/3, 1], [2/3, 0, 1/3, 1]],
        [[0, 0, 1/3, 1], [1/3, 0, 1/3, 1], [2/3, 0, 1/3, 1]],
        [[0, 0, 1/2, 1], [1/2, 0, 1/2, 1/2], [1/2, 1/2, 1/2, 1/2]],
        [[0, 0, 1/2, 1/2], [1/2, 0, 1/2, 1/2], [0, 1/2, 1/2, 1/2], [1/2, 1/2, 1/2, 1/2]],
        [[0, 0, 1/4, 1], [1/4, 0, 1/2, 1], [3/4, 0, 1/4, 1]]
    ]

    property bool open: false
    property int hoverTile: -1
    property int hoverZone: -1

    // At rest the plate sits margins.bottom + drop (16px) above the edge.
    anchors.bottom: true
    margins.bottom: 8
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:snap"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}
    color: "transparent"

    implicitWidth: plate.width
    implicitHeight: plate.height + drop

    property real shown: open ? 1 : 0
    Behavior on shown {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
    visible: shown > 0

    function track() {
        const lx = WindowDrag.x - modelData.x
        const ly = WindowDrag.y - modelData.y
        if (lx < 0 || lx >= modelData.width || ly < 0 || ly >= modelData.height) {
            close()
            return
        }
        // The window's top edge, in screen coordinates; the plate rests there.
        const top = modelData.height - margins.bottom - implicitHeight
        if (ly >= modelData.height - 1 - edge)
            open = true
        else if (ly < top - reach)
            open = false
        if (open)
            hit(lx - (modelData.width - implicitWidth) / 2, ly - top)
        else
            hoverTile = hoverZone = -1
    }

    // Which zone is under a point in the plate's coordinates. The gaps
    // between tiles belong to the nearer tile, so nothing in the bar is dead.
    function hit(px, py) {
        hoverTile = hoverZone = -1
        const slack = tileGap / 2
        if (py < pad - slack || py > pad + tileH + slack)
            return
        const step = tileW + tileGap
        const t = Math.floor((px - pad + slack) / step)
        if (t < 0 || t >= layouts.length)
            return
        const fx = Math.min(Math.max((px - pad - t * step) / tileW, 0), 0.999)
        const fy = Math.min(Math.max((py - pad) / tileH, 0), 0.999)
        const zones = layouts[t]
        for (let z = 0; z < zones.length; z++) {
            const r = zones[z]
            if (fx >= r[0] && fx < r[0] + r[2] && fy >= r[1] && fy < r[1] + r[3]) {
                hoverTile = t
                hoverZone = z
                return
            }
        }
    }

    function close() {
        open = false
        hoverTile = hoverZone = -1
    }

    Connections {
        target: WindowDrag

        function onMoved() {
            root.track()
        }

        function onDropped(address) {
            if (root.open && root.hoverTile >= 0)
                WindowDrag.place(address, root.modelData.name, root.layouts[root.hoverTile][root.hoverZone])
            root.close()
        }
    }

    Rectangle {
        id: plate

        y: root.drop * (1 - root.shown)
        opacity: root.shown
        width: root.pad * 2 + root.layouts.length * root.tileW + (root.layouts.length - 1) * root.tileGap
        height: root.pad * 2 + root.tileH
        radius: root.plateRadius
        color: root.plateColor

        Row {
            x: root.pad
            y: root.pad
            spacing: root.tileGap

            Repeater {
                model: root.layouts

                Item {
                    id: tile

                    required property var modelData
                    required property int index

                    width: root.tileW
                    height: root.tileH

                    Repeater {
                        model: tile.modelData

                        // Fractions of the tile plus one gap, so every gap
                        // between zones comes out the same.
                        Rectangle {
                            required property var modelData
                            required property int index

                            readonly property real unitW: root.tileW + root.zoneGap
                            readonly property real unitH: root.tileH + root.zoneGap

                            x: Math.round(modelData[0] * unitW)
                            y: Math.round(modelData[1] * unitH)
                            width: Math.round((modelData[0] + modelData[2]) * unitW) - root.zoneGap - x
                            height: Math.round((modelData[1] + modelData[3]) * unitH) - root.zoneGap - y
                            radius: root.zoneRadius
                            color: root.hoverTile === tile.index && root.hoverZone === index
                                ? root.zoneHoverColor : root.zoneColor

                            Behavior on color {
                                ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }
            }
        }
    }
}
