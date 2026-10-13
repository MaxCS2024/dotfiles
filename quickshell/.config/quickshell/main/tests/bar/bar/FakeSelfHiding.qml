import QtQuick

// The self-hiding module contract (MediaPlayer, ActiveWindow,
// BrightnessButton): no content, no slot.
Item {
    readonly property bool hasContent: Modules.selfHidingHasContent
    implicitWidth: 10
    implicitHeight: 10
}
