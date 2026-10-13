import QtQuick

// The workspace flash: "Workspace N". Switching again while it shows
// slides the old name out and the new one in beside it, 16px apart, the
// dynamic-island's way: to a higher number they move left (the new name
// comes in from the right), to a lower one right.
Item {
    id: face

    property var activity: null
    property string mode: "transient"

    readonly property int number: activity?.number ?? 0
    readonly property int direction: activity?.direction ?? 1

    implicitWidth: widest.advanceWidth
    implicitHeight: labelA.implicitHeight

    TextMetrics {
        id: widest
        text: "Workspace " + face.number
        font.family: Config.font
        font.weight: Font.Bold
        font.pixelSize: Config.fontSize
    }

    // Two labels take turns; `current` is the one showing.
    property Text current: labelA
    property int shownNumber: 0

    onNumberChanged: {
        if (number < 1)
            return
        if (shownNumber < 1 || !visible) {
            current.text = "Workspace " + number
            current.shift = 0
            shownNumber = number
            return
        }
        const out = current
        const inn = current === labelA ? labelB : labelA
        slideOut.stop()
        slideIn.stop()
        inn.text = "Workspace " + number
        const distance = out.implicitWidth / 2 + 16 + inn.implicitWidth / 2
        const dir = direction > 0 ? -1 : 1
        current = inn
        shownNumber = number
        slideOut.target = out
        slideOut.from = out.shift
        slideOut.to = dir * distance
        slideOut.start()
        slideIn.target = inn
        slideIn.from = -dir * distance
        slideIn.to = 0
        slideIn.start()
    }

    Component.onCompleted: {
        if (number > 0) {
            labelA.text = "Workspace " + number
            shownNumber = number
        }
    }

    NumberAnimation {
        id: slideOut
        property: "shift"
        duration: 160
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: slideIn
        property: "shift"
        duration: 160
        easing.type: Easing.OutCubic
    }

    component Label: Text {
        property real shift: 0
        property bool showing: false
        property real boxWidth: 0
        // The one going out fades as it goes.
        opacity: showing ? 1 : Math.max(0, 1 - Math.abs(shift) / (implicitWidth / 2 + 16))
        x: (boxWidth - implicitWidth) / 2 + shift
        anchors.verticalCenter: parent.verticalCenter
        color: Config.foreground
        font.family: Config.font
        font.weight: Font.Bold
        font.pixelSize: Config.fontSize
    }

    Label { id: labelA; showing: face.current === labelA; boxWidth: face.width }
    Label { id: labelB; showing: face.current === labelB; boxWidth: face.width; shift: 10000 }
}
