import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"
import "../common"

// Boolean on/off, built from the same box, chrome and timing as
// CapsLockOsd — see that file's header for why neither of the two
// reuses OsdContent.
//
// The state arrives over IPC instead of from a service, because there
// is nothing in the shell to watch: zen lives in Hyprland's config
// (hypr/modules/binds/zen.lua), which holds the snapshot of gaps and
// borders it puts back, and the live values it toggles say nothing on
// their own — border_size is 0 in zen and also 0 for anyone who simply
// runs without borders. The toggle is the only thing that knows, so it
// is the thing that tells us.
OsdWindow {
    id: osd

    surfaceNamespace: "quickshell:osd-zen"

    property bool active: false

    OsdBox {
        shown: osd.shown
        width: 200

        RowLayout {
            anchors.centerIn: parent
            spacing: 12

            Text {
                // md-fullscreen / md-fullscreen_exit — the chrome going
                // away and coming back. Both checked in the font file;
                // Nerd Fonts v3 dropped a lot of v2 codepoints.
                text: osd.active ? "󰊓" : "󰊔"
                color: osd.active ? Appearance.green : Appearance.icon
                font.pixelSize: 20
                font.family: Theme.font
            }

            Text {
                text: osd.active ? "Zen On" : "Zen Off"
                color: Appearance.fg
                font.pixelSize: Theme.fontNormal
                font.family: Theme.font
            }
        }
    }

    // Two functions rather than one taking the state: `qs ipc call` hands
    // every argument over as a string, so a bool parameter is rejected at
    // the call site ("The following argument was not expected: true") and
    // a string one would mean parsing "true"/"false" back out here.
    IpcHandler {
        target: "osd-zen"
        // The state is set before show() rather than passed to it: a
        // show(on) here would shadow OsdWindow's own show(), and calling
        // through to the shadowed one is not a thing QML offers.
        function on(): void { osd.active = true; osd.show() }
        function off(): void { osd.active = false; osd.show() }
    }
}
