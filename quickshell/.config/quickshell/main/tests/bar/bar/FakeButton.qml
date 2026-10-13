import QtQuick

// The BarButton contract Bar.qml relies on: keyboardFocused in, tapped out.
Item {
    property var barWindow
    property bool keyboardFocused: false
    property int taps: 0
    signal tapped()
    onTapped: taps++
    implicitWidth: 10
    implicitHeight: 10
}
