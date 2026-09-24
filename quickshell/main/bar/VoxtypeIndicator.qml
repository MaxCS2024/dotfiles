import QtQuick
import "../theme"
import "../services"

// Dictation in progress: shown left of the clock while voxtype is
// recording or transcribing (services/Voxtype.qml), and gone the rest of
// the time. SUPER+V starts and stops it (hypr/modules/binds/apps.lua).
//
// The glyph's colour is the only state signal (STYLE.md §8): red while
// the microphone is live, which is the one thing here worth catching the
// eye, and plain fg while the recording is turned into text. voxtype's
// own GTK OSD is switched off (osd.enabled = false in
// ~/.config/voxtype/config.toml) so this is the only indicator.
BarButton {
    id: root

    dropdownEnabled: false

    readonly property bool hasContent: Voxtype.busy

    // U+F036C is nf-md-microphone, U+F147D nf-md-waveform.
    icon: Voxtype.recording ? "\u{F036C}" : "\u{F147D}"
    iconColor: Voxtype.recording ? Appearance.red : Appearance.fg
    label: Voxtype.recording ? "Recording" : "Transcribing"
    labelColor: Appearance.fg

    // Left click is SUPER+V: stops the recording and types it out.
    // Right click throws it away instead.
    onTapped: Voxtype.toggle()
    onRightTapped: Voxtype.cancel()
}
