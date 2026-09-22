import QtQuick
import "../common/qrcode.js" as QrCode

// Draws a QR code for `payload` on a white plate.
//
// Canvas rather than a grid of Rectangles: a version 4 code is 33x33, so
// the Repeater version of this would be 1089 live items for something
// that never changes after it is drawn once.
//
// Black on white, fixed, not themed — this is the one surface in the
// shell that exists to be read by a camera rather than by a person, and
// phone decoders want maximum contrast and the conventional polarity
// (many refuse an inverted code outright). The plate it sits on is part
// of the code: the four-module quiet zone is required by the spec, not
// padding, and a code bled to its own edge scans badly or not at all.
Item {
    id: root

    property string payload: ""
    // Quiet zone, in modules. Four is the spec minimum.
    property int quiet: 4

    readonly property var code: root.payload === "" ? null : QrCode.encode(root.payload)
    // Null when the payload is longer than a version 10 code can carry —
    // the caller shows a message instead of an empty white square.
    readonly property bool valid: root.code !== null

    onPayloadChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onWidthChanged: canvas.requestPaint()
        onHeightChanged: canvas.requestPaint()

        onPaint: {
            const ctx = canvas.getContext("2d")
            ctx.reset()
            ctx.fillStyle = "#ffffff"
            ctx.fillRect(0, 0, canvas.width, canvas.height)

            const code = root.code
            if (!code) return

            const total = code.size + root.quiet * 2
            // Integer module size, and the whole code centred on what is
            // left over. A fractional scale puts module edges on
            // half-pixels, and the antialiasing that follows softens the
            // very transitions the decoder is looking for.
            const scale = Math.max(1, Math.floor(Math.min(canvas.width, canvas.height) / total))
            const originX = Math.floor((canvas.width - scale * total) / 2)
            const originY = Math.floor((canvas.height - scale * total) / 2)

            ctx.fillStyle = "#000000"
            for (let y = 0; y < code.size; y++) {
                for (let x = 0; x < code.size; x++) {
                    if (!code.modules[y * code.size + x]) continue
                    ctx.fillRect(originX + (x + root.quiet) * scale,
                                 originY + (y + root.quiet) * scale,
                                 scale, scale)
                }
            }
        }
    }
}
