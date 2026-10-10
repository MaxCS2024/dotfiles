import QtQuick

// Several icon buttons fused into one rounded pill, as the main bar puts
// volume, network and battery on one island. The pill is white at 12%;
// a hovered segment lifts to about 20%, and an `active` one is solid
// white with a black icon. The end segments follow the pill's rounding.
//
// `model` is a list of { icon: () => string, active: () => bool,
// tap: () => void }; the functions are called inside bindings, so the
// segments follow whatever they read.
Rectangle {
    id: group

    property var model: []

    height: 40
    radius: height / 2
    color: Qt.rgba(1, 1, 1, 0.12)

    Row {
        anchors.fill: parent

        Repeater {
            id: repeater
            model: group.model

            delegate: Item {
                id: segment
                required property var modelData
                required property int index

                readonly property bool first: index === 0
                readonly property bool last: index === repeater.count - 1
                readonly property bool active: modelData.active()

                width: group.width / repeater.count
                height: group.height
                // Clips the fill's inner side square; its outer side keeps
                // the pill's rounding on the end segments.
                clip: true

                Rectangle {
                    x: segment.first ? 0 : -radius
                    width: parent.width + (segment.first ? 0 : radius) + (segment.last ? 0 : radius)
                    height: parent.height
                    radius: group.radius
                    color: segment.active ? "white"
                        : Qt.rgba(1, 1, 1, area.containsMouse ? 0.09 : 0)

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: segment.modelData.icon()
                    color: segment.active ? "black" : "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 18
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: segment.modelData.tap()
                }
            }
        }
    }
}
