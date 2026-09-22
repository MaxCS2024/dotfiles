pragma Singleton
import Quickshell
import QtQuick

// The soft-cornered surface scale, kept out of config/Theme.qml on
// purpose: these numbers are deliberately *not* the shell-wide ones.
// Theme.radius is whatever Settings.cornerRadius says (2px today — the
// sharp, editorial bar/popout look), and a slab of stacked panes built
// on 2px corners reads like a spreadsheet. A surface that wants large
// soft corners takes its scale from here rather than re-deciding it in
// a file of its own.
//
// "Slab" is what powermenu/PowerMenuPopout.qml's header already calls
// the surface this dresses — one soft-cornered plate carrying a row of
// cards — so it is the name the file took on 2026-09-21. It was
// DashStyle until that day, written for dashboard/Dashboard.qml's bento
// grid and named after it; the grid was deleted and the name outlived
// the only surface it described. Anything older than that date in the
// log calls it DashStyle.
//
// Two readers: PowerMenuPopout.qml, which takes nearly all of it, and
// network/NetworkPanel.qml, which takes tintStrong alone.
//
// Everything below still derives from Appearance, so a surface dressed
// from here follows the wallpaper palette (or a pinned custom one)
// exactly like the rest of the shell — only the geometry and the alphas
// are local.
Singleton {
    id: root

    // ── Geometry ─────────────────────────────────────────
    readonly property int panelRadius: 26
    readonly property int cardRadius: 18
    // The gap between panes. tileRadius, pad and cardPad stood beside it
    // until the grid that needed three separate paddings was deleted.
    readonly property int gap: 14

    // ── Ground ───────────────────────────────────────────
    // Fully opaque, per user request 2026-09-10 ("remove the opacity").
    // The power menu slab, which is what this file dresses now that the
    // dashboard grid is gone, is solid; only the dimmed backdrop it lays
    // over the screen is still see-through, and that's a scrim, not the
    // panel.
    //
    // This was never really glass anyway: decoration:blur.enabled is
    // false in hypr/modules/decorations.lua, so no layer rule can blur
    // anything today — the blur-bar rule there is inert for the same
    // reason, and a blur-dashboard rule sat beside it until both that
    // rule and the panel it named were deleted. Translucency with
    // nothing softening what's behind it just means a terminal's text
    // showing through the card you're trying to read.
    //
    // Both numbers are kept as tokens rather than deleted so this stays
    // one edit either way: turning global blur on is the change that
    // makes real glass work — drop panelAlpha to ~0.80 and cardAlpha to
    // ~0.55 together, and keep both clear of a layer rule's ignore_alpha
    // (0.2), or the compositor drops blur for the whole surface.
    //
    // Cards still sit an elevation step below the panel so they read as
    // panes *in* it rather than boxes stacked on top of it — with the
    // alphas gone, `bar` vs `surface` vs `surfaceAlt` is what carries
    // that relationship on its own.
    readonly property real panelAlpha: 1.0
    readonly property real cardAlpha: 1.0

    readonly property color panelBg: Qt.rgba(Appearance.bar.r, Appearance.bar.g, Appearance.bar.b, root.panelAlpha)
    readonly property color panelBorder: Qt.rgba(Appearance.fgStrong.r, Appearance.fgStrong.g, Appearance.fgStrong.b, 0.10)

    readonly property color cardBg: Qt.rgba(Appearance.surface.r, Appearance.surface.g, Appearance.surface.b, root.cardAlpha)
    // A hairline of light rather than Appearance.border: a solid border
    // ring reads as a drawn box, which is the look these surfaces are
    // trying to get away from. Still a wash rather than a flat color
    // now that the card under it is opaque — it composites against the
    // card, so it tracks whatever ground the card is carrying.
    readonly property color cardBorder: Qt.rgba(Appearance.fgStrong.r, Appearance.fgStrong.g, Appearance.fgStrong.b, 0.07)

    // The one place color is allowed to flood a whole surface:
    // tintStrong, for an *active* control.
    //
    // cardBgTinted is a card fill with the accent mixed into it at ~14%,
    // spelled out channel by channel rather than via Qt.tint()
    // — that helper blends the alphas too, so tinting a translucent card
    // with a 0.10-alpha accent made the tinted card *more* transparent
    // than the cards around it, not warmer. Kept spelled out at
    // cardAlpha 1.0: it's the mix that makes the card warm, and this way
    // lowering the alpha again can't quietly reintroduce that bug.
    readonly property color cardBgTinted: Qt.rgba(
        Appearance.surface.r * 0.86 + Appearance.accent.r * 0.14,
        Appearance.surface.g * 0.86 + Appearance.accent.g * 0.14,
        Appearance.surface.b * 0.86 + Appearance.accent.b * 0.14,
        Math.min(1, root.cardAlpha + 0.06))

    readonly property color tintStrong: Qt.rgba(Appearance.accent.r, Appearance.accent.g, Appearance.accent.b, 0.22)

    // ── Motion ───────────────────────────────────────────
    // Panes fade and rise in one after another on open. The stagger is
    // small on purpose: it should read as the surface assembling itself,
    // not as a slideshow. See powermenu/PowerMenuPopout.qml, which skips
    // the stagger on the way out so dismissal stays instant.
    readonly property int revealDuration: 260
    readonly property int revealStagger: 35
    readonly property int revealRise: 14
}
