import QtQuick
import QtQuick.Shapes
import "../config"

// The border Hyprland paints around a focused window, for the surfaces in
// this shell that want to read as part of the same desktop rather than as
// something floating above it.
//
// `col.active_border` is a 45 degree gradient between two matugen
// swatches (hypr/modules/colors.lua), and a Rectangle's `border` takes
// one flat colour — so this is a Shape filled with that gradient and cut
// back to a ring by a second, inset rectangle under OddEvenFill. A real
// hole, not an inner rectangle painted the surface's own colour: whatever
// the target draws inside still composites against the target, not
// against a patch that has to be kept in sync with it.
//
// Anchored to fill its parent like common/FocusRing.qml, so a consumer
// writes `HyprFrame {}` and nothing else — and, like that file, it exists
// so the recipe can't drift per site. Declare it as the target's *first*
// child so everything else paints over it.
//
// Theme.hyprBorderStart/End are the same two swatches Hyprland is given,
// read from the same ~/.cache/matugen/colors.json, so a new wallpaper
// re-themes the window borders and every frame drawn here together.
Shape {
    id: root

    // Defaults to Hyprland's own general.border_size (Theme). A target
    // whose `border.width` is something else passes it, so the ring
    // covers that band exactly.
    property int frameWidth: Theme.hyprBorderWidth
    // Radius of the *target*, not of the ring. Hyprland's own
    // `decoration.rounding` is 0 and square is the default here; a
    // rounded target passes its radius so the ring follows the corner.
    property real targetRadius: 0

    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: 0
        fillRule: ShapePath.OddEvenFill

        // A true 45 degrees rather than corner to corner: on a surface far
        // wider than it is tall (or far taller than it is wide) the actual
        // diagonal runs at a quite different angle from the one Hyprland
        // paints a few pixels away, and the two read as different borders.
        // Ending at ((w+h)/2, (w+h)/2) is where the far corner projects
        // onto a 45 degree axis, so the gradient spans the whole surface
        // without clipping either end.
        fillGradient: LinearGradient {
            x1: 0
            y1: 0
            x2: (root.width + root.height) / 2
            y2: (root.width + root.height) / 2
            GradientStop { position: 0.0; color: Theme.hyprBorderStart }
            GradientStop { position: 1.0; color: Theme.hyprBorderEnd }
        }

        PathRectangle {
            width: root.width
            height: root.height
            radius: root.targetRadius
        }
        PathRectangle {
            x: root.frameWidth
            y: root.frameWidth
            width: Math.max(0, root.width - root.frameWidth * 2)
            height: Math.max(0, root.height - root.frameWidth * 2)
            radius: Math.max(0, root.targetRadius - root.frameWidth)
        }
    }
}
