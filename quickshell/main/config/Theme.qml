pragma Singleton
import Quickshell
import QtQuick
import "../services"

// Sizes, fonts, motion, radii and a few shell-wide names: everything
// about how the shell is drawn except its colours. Colours live only in
// theme/Appearance.qml (see STYLE.md §2).
Singleton {
    id: root

    // ── Typography ───────────────────────────────────────
    readonly property string font: "JetBrainsMono Nerd Font"
    // "Classical" display face — headers, labels, monogram
    // letters. Reuses the same Nerd Font rather than a separate
    // Cormorant/Lora pairing (removed per user request 2026-09-04 — this
    // machine only has JetBrains Mono installed); EB Garamond/Iosevka
    // stay unavailable in settingswindow/AppearancePane.qml's picker.
    readonly property string fontHeading: font
    readonly property string fontMono: font
    // Was 9, raised per user request 2026-09-10: most of its call sites
    // pair it with Font.SmallCaps, which draws the lowercase letters as
    // capitals at roughly 0.75em — so a 9px label was really a ~7px one,
    // and the dashboard's tile captions ("Wallpaper", "Coffee") stopped
    // resolving into words. That puts it level with fontCaption/fontSmall
    // rather than a step below them; the step is only worth having back
    // if something is drawn at this size *without* small caps.
    readonly property int fontMicro: 11
    readonly property int fontXSmall: 10
    readonly property int fontTiny: 10
    readonly property int fontCaption: 11
    readonly property int fontSmall: 11
    readonly property int fontNormal: 12
    readonly property real fontProse: 12.5
    readonly property int fontMedium: 13
    readonly property int fontBig: 14
    readonly property int fontLarge: 15
    readonly property int fontHuge: 32
    readonly property int fontLockTime: 64
    readonly property int iconSize: 16

    // ── Translucency ─────────────────────────────────────
    // How see-through the bar's and panels' root Rectangles are
    // (Appearance.barGlass). Every surface drawn on top stays fully
    // opaque on purpose: making those translucent too turns a panel into
    // mush and makes hover states vanish over a busy wallpaper.
    //
    // Keep ignore_alpha in the blur-quickshell layer rule
    // (hypr/modules/windowrules.lua) just below the lower of these two,
    // or the panel bodies won't blur.
    property real alphaBar: Settings.barOpacity
    property real alphaPanel: 0.7

    // hypr/modules/decorations.lua's general.border_size, so a surface
    // wearing common/HyprFrame.qml is the same weight as the window edges
    // around it.
    readonly property int hyprBorderWidth: 2

    // ── Spacing scale ────────────────────────────────────
    // Every gap, margin and padding sits on a 4px grid: spaceN is N × 4.
    // Reach for these instead of a literal. 1–2px hairlines (borders,
    // focus rings) are the only exception.
    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16
    readonly property int space5: 20
    readonly property int space6: 24
    readonly property int space8: 32
    readonly property int space10: 40

    // Inner padding of the card inside a bar dropdown (the Battery,
    // Calendar, Media, Themes, Volume and Weather panels).
    readonly property int cardPadding: space4

    // ── Bar items ────────────────────────────────────────
    // Every item on the bar is a barItemHeight-tall pill (HoverPill,
    // workspace chips), padded barItemPadX each side of its content.
    // The bar itself is barHeight in bar/Bar.qml.
    readonly property int barItemHeight: space6
    readonly property int barItemPadX: space3

    // ── Plate layout (common/Plate.qml) ───────────────────
    readonly property int platePaddingH: space4
    readonly property int platePaddingV: space4
    readonly property int plateHeaderGap: space2

    // ── Focus ring (common/FocusRing.qml) ─────────────────
    readonly property int focusRingWidth: 2
    readonly property int focusRingOffset: 2

    // ── Geometry & motion ────────────────────────────────
    readonly property int radius: Settings.cornerRadius
    readonly property int radiusLarge: 4
    readonly property int radiusMedium: 6

    readonly property int animFast: 120
    readonly property int animNormal: 200
    readonly property int animPanel: 220
    readonly property int easingQuint: Easing.OutQuint

    // Legend values shown (read-only) by settingswindow/AnimationsPane.qml
    // — see that file's comment on why these are display tokens, not
    // live-editable durations.
    readonly property int popoutOpenDuration: animPanel
    readonly property int popoutCloseDuration: 160
    readonly property int workspaceSlideDuration: 140
    readonly property int osdHoldDuration: 1800
    readonly property int lockShakeDistance: 8
    readonly property int lockShakeDuration: 300

    // font.letterSpacing wants an absolute pixel value; the design specs
    // tracking as an em fraction of the type size (e.g. "0.16em") — this
    // converts one to the other so call sites can just write the em value.
    function tracking(pixelSize, em) { return pixelSize * em }

    // Durations were already tokenised; easing wasn't — most animations
    // spelled out `Easing.OutCubic` inline and some specified nothing
    // (QML's default, Linear, applied by accident rather than choice).
    // Two tokens, not one, because the two existing patterns in this
    // codebase are for genuinely different things: easingDecel for
    // something moving/growing *into* place (a panel sliding in, a pill
    // expanding) — decelerating into a stop reads as the thing
    // "arriving". easingStandard for everything else that animates but
    // isn't "arriving" anywhere — color/opacity fades, generic size
    // tweens — a symmetric ease-in-out rather than Linear's constant,
    // slightly mechanical rate.
    readonly property int easingDecel: Easing.OutCubic
    readonly property int easingStandard: Easing.InOutQuad

    // ── Shadow ───────────────────────────────────────────
    // Used via layer.enabled + layer.effect: MultiEffect on each
    // panel's backing Rectangle. "Popup" is slightly heavier/more
    // visible than "bar", since transient panels benefit from standing
    // out more than the always-on-screen bar strip does. The colour is
    // Appearance.shadow.
    readonly property real shadowBlurPopup: 0.7
    readonly property real shadowVerticalOffsetPopup: 4
    readonly property real shadowBlurBar: 0.4
    readonly property real shadowVerticalOffsetBar: 2

    // "Docked" popouts (anchored under the bar module that opened them)
    // want a subtler shadow than "floating" ones (centred overlays like
    // the power menu) — same colour, less blur/throw. See common/Plate.qml.
    readonly property real shadowBlurDocked: shadowBlurBar
    readonly property real shadowVerticalOffsetDocked: shadowVerticalOffsetBar

    // ── External commands ────────────────────────────────
    readonly property string terminal: "foot"
    readonly property string appLauncherPrefix: "uwsm-app"
    readonly property string logoutCmd: "uwsm stop"

    // How to tell `terminal` what app-id to take. Wayland's app_id is what
    // Hyprland matches as `class`, so this is the handle a window rule can
    // grab — see floatAppId below. The flag is terminal-specific (foot and
    // wezterm take --app-id, kitty and alacritty --class), which is why it
    // lives beside the terminal it belongs to rather than in the caller.
    readonly property string terminalAppIdArg: "--app-id="

    // The app-id a transient, task-shaped window asks for when it wants to
    // be floated and centred instead of tiled into the layout: a package
    // upgrade, a dependency check, anything you open to watch and then
    // close. hypr/modules/windowrules.lua matches this exact string in its
    // "float-task-window" rule, so the two have to agree — that rule is
    // the whole mechanism, and this is the only name it knows.
    //
    // Nothing about it is terminal-specific: any window that can be told
    // its own app-id can opt in the same way.
    readonly property string floatAppId: "quickshell-float"
}