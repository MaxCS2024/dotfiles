import QtQuick

// The island's Slider over a range, with its value written beside it in
// bold 13px (`format` turns the value into text). 240px wide: 180 of
// slider, the rest for the text. `moved` gives the value in the range,
// rounded to `step`.
Item {
    id: vs

    property real from: 0
    property real to: 1
    property real step: 0.01
    property real value: 0
    property var format: v => String(v)
    signal moved(real value)

    width: 240
    height: 32

    Slider {
        id: slider
        width: 180
        anchors.verticalCenter: parent.verticalCenter
        value: (vs.value - vs.from) / (vs.to - vs.from)
        onMoved: v => vs.moved(Math.round((vs.from + v * (vs.to - vs.from)) / vs.step) * vs.step)
    }

    Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: vs.format(vs.from + slider.shownValue * (vs.to - vs.from))
        color: "white"
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13
    }
}
