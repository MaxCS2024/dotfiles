pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../services"

// ── matugen integration ─────────────────────────────────────
//
// Set matugenEnabled to false to disable this entirely and always use
// the hardcoded fallback palette below, regardless of whether matugen
// is installed or has ever been run.
//
// When enabled, this reads ~/.cache/matugen/colors.json (special.
// background/foreground plus a handful of accent colors, written by
// the `[templates.quickshell]` template in matugen/config.toml — see
// its comments for the color-role mapping) and derives every color
// token below from it. If that file doesn't exist yet, is malformed,
// or is missing an expected key, matugenActive stays false and every
// property below falls back to its original literal value.
//
// The file is watched live: running `matugen image <image>` re-themes
// the whole shell without restarting Quickshell. Hyprland reads the
// same file via hypr/modules/colors.lua for its border colors, but
// only at config load, so this file also triggers a reload on it —
// see onLoaded.
Singleton {
    id: root

    property bool matugenEnabled: true
    property bool _loadedOk: false
    property bool _firstLoad: true
    readonly property bool matugenActive: root.matugenEnabled && root._loadedOk

    property color _bg: "#000000"
    property color _fg: "#eeeeee"
    property color _c0: "#000000"
    property color _c1: "#f87171"   // red
    property color _c2: "#4ade80"   // green
    property color _c3: "#fb923c"   // yellow/orange
    property color _c4: "#60a5fa"   // blue

    Process {
        id: resolvePathProc
        running: root.matugenEnabled
        command: ["sh", "-c", "printf '%s' \"$HOME/.cache/matugen/colors.json\""]
        stdout: StdioCollector {
            onStreamFinished: colorsFile.path = text
        }
    }

    FileView {
        id: colorsFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                const s = parsed.special
                const c = parsed.colors
                const required = [s && s.background, s && s.foreground,
                    c && c.color0, c && c.color1, c && c.color2, c && c.color3, c && c.color4]

                if (required.every(v => typeof v === "string" && v.length > 0)) {
                    root._bg = s.background
                    root._fg = s.foreground
                    root._c0 = c.color0
                    root._c1 = c.color1
                    root._c2 = c.color2
                    root._c3 = c.color3
                    root._c4 = c.color4
                    root._loadedOk = true
                } else {
                    root._loadedOk = false
                }
            } catch (e) {
                // Malformed JSON — fall back rather than half-apply.
                root._loadedOk = false
            }

            // Hyprland derives its border colors from this same file
            // (hypr/modules/colors.lua) but only reads it at config load,
            // so it needs a nudge. Skipped on the first load, which
            // happens on every shell start and would reload for nothing.
            //
            // Fires regardless of whether parsing succeeded above: the
            // Lua side does its own read and has its own fallback, so a
            // file we couldn't use is still a file Hyprland should
            // re-evaluate.
            if (root._firstLoad)
                root._firstLoad = false
            else
                Quickshell.execDetached(["hyprctl", "reload"])
        }
    }

    // ── Luminance-aware elevation ────────────────────────
    // Every surface/text tone below used to be hardcoded to
    // Qt.lighter(_bg,..) / Qt.darker(_fg,..), silently assuming a dark
    // matugen palette. Given a light wallpaper, _bg is near-white and
    // Qt.lighter() on it saturates to pure white almost immediately —
    // every elevation step collapses to the same color and hover states
    // vanish. elevate()/recede() pick the correct direction from _bg's
    // own measured relative luminance (WCAG's formula) instead of
    // assuming one.
    readonly property real _bgLuminance: 0.2126 * _bg.r + 0.7152 * _bg.g + 0.0722 * _bg.b
    readonly property bool isDark: _bgLuminance < 0.5

    // Surfaces move away from _bg to create visual separation —
    // lighter on a dark theme, darker on a light one.
    function elevate(c, n) { return isDark ? Qt.lighter(c, n) : Qt.darker(c, n) }
    // Text recedes toward _bg to reduce emphasis — the opposite
    // direction from elevate(), for the opposite reason.
    function recede(c, n) { return isDark ? Qt.darker(c, n) : Qt.lighter(c, n) }

    function _luminance(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    function _contrastRatio(c1, c2) {
        const l1 = root._luminance(c1) + 0.05
        const l2 = root._luminance(c2) + 0.05
        return l1 > l2 ? l1 / l2 : l2 / l1
    }
    // fgMuted was flagged early as the token most likely to go
    // unreadable — it's already the second-most-receded text
    // token, so a palette with unusually low overall contrast has the
    // least room left before it disappears into `surface`.
    //
    // Backs the recede factor *off* until a floor contrast ratio against
    // `surface` is met. It nudged the factor up until 2026-09-18, which
    // is the wrong way round: receding moves a tone toward the
    // background, so every step of that loop spent contrast instead of
    // buying it. A palette that missed the floor at 1.55 then marched to
    // the n < 4.0 bound and landed on top of the surface it was being
    // measured against — seen at rgb(44,47,58) on a card of
    // rgb(36,40,59), a ratio of 1.05, which is a label you cannot read.
    // It is also why network/NetworkPanel.qml sets its own label tone
    // rather than taking this one.
    //
    // Walking down terminates on its own: n = 1.0 is _fg itself, which
    // is the most contrast this palette has against its own surface. So
    // the result is as receded as the floor allows and never more
    // prominent than _fg — the guarantee the old direction was reaching
    // for and, going the other way, could not keep.
    function _fgMutedColor() {
        let n = 1.55
        let c = root.recede(_fg, n)
        while (root._contrastRatio(c, root.surface) < 3.0 && n > 1.0) {
            n = Math.max(1.0, n - 0.05)
            c = root.recede(_fg, n)
        }
        return c
    }

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

    // ── Surfaces ─────────────────────────────────────────
    readonly property color bar: matugenActive ? _bg : "#000000"
    readonly property color surface: matugenActive ? elevate(_bg, 1.15) : "#161616"
    readonly property color surfaceAlt: matugenActive ? elevate(_bg, 1.25) : "#1c1c1c"
    readonly property color hover: matugenActive ? elevate(_bg, 1.35) : "#202020"
    readonly property color hoverStrong: matugenActive ? elevate(_bg, 1.45) : "#242424"
    readonly property color selected: matugenActive ? elevate(_bg, 1.55) : "#2a2a2a"
    readonly property color trackBg: matugenActive ? elevate(_bg, 1.3) : "#2a2a2a"
    readonly property color scrollTrack: matugenActive ? elevate(_bg, 1.1) : "#1e1e1e"
    readonly property color scrollThumb: matugenActive ? elevate(_bg, 1.8) : "#444444"

    // ── Translucency ─────────────────────────────────────
    // Only the root Rectangle of each window paints with barGlass or
    // panelGlass. Every surface above stays fully opaque on purpose:
    // they're elevation colors drawn on top of the translucent root, and
    // making them translucent too turns a panel into mush and makes
    // hover states vanish over a busy wallpaper.
    //
    // Keep ignore_alpha in the blur-quickshell layer rule
    // (hypr/modules/windowrules.lua) just below the lower of these two,
    // or the panel bodies won't blur.
    property real alphaBar: Settings.barOpacity
    property real alphaPanel: 0.7
    readonly property color barGlass: Qt.rgba(bar.r, bar.g, bar.b, alphaBar)
    readonly property color panelGlass: Qt.rgba(surface.r, surface.g, surface.b, alphaPanel)

    // ── Lines ────────────────────────────────────────────
    readonly property color border: matugenActive ? elevate(_bg, 1.7) : "#333333"
    readonly property color separator: matugenActive ? elevate(_bg, 1.5) : "#2f2f2f"

    // The two swatches hypr/modules/colors.lua feeds to Hyprland's
    // `col.active_border` as a 45 degree gradient — same colors.json, so a
    // toast framed with these matches the window borders around it, and a
    // new wallpaper re-themes both at once. The literals mirror that
    // file's own no-matugen fallback rather than inventing a second one.
    //
    // Hyprland puts these at "ee" alpha; these stay opaque on purpose. A
    // translucent edge composites against whatever is behind the window
    // (see the border note in notifications/NotificationCard.qml), which
    // is exactly the muddiness that note describes.
    readonly property color hyprBorderStart: matugenActive ? _c4 : "#33ccff"
    readonly property color hyprBorderEnd: matugenActive ? _c2 : "#00ff99"
    // hypr/modules/decorations.lua's general.border_size, so a surface
    // wearing common/HyprFrame.qml is the same weight as the window edges
    // around it — and so that number lives here with the two colours
    // rather than as a literal at each site, the way focusRingWidth does
    // for common/FocusRing.qml.
    readonly property int hyprBorderWidth: 2

    // ── Text ─────────────────────────────────────────────
    readonly property color fgStrong: matugenActive ? _fg : "#ffffff"
    readonly property color fg: matugenActive ? recede(_fg, 1.03) : "#eeeeee"
    readonly property color fgSoft: matugenActive ? recede(_fg, 1.15) : "#cccccc"
    readonly property color fgMuted: matugenActive ? _fgMutedColor() : "#999999"
    readonly property color fgFaint: matugenActive ? recede(_fg, 1.7) : "#888888"
    readonly property color fgDim: matugenActive ? recede(_fg, 2.1) : "#666666"
    readonly property color placeholder: matugenActive ? recede(_fg, 1.9) : "#777777"
    readonly property color icon: matugenActive ? recede(_fg, 1.02) : "#e2e8f0"
    readonly property color disabled: matugenActive ? recede(_fg, 2.5) : "#555555"

    // ── Accents ──────────────────────────────────────────
    readonly property color green: matugenActive ? _c2 : "#4ade80"
    readonly property color orange: matugenActive ? _c3 : "#fb923c"
    readonly property color red: matugenActive ? _c1 : "#f87171"

    // ── Workspaces ───────────────────────────────────────
    readonly property color wsOccupied: matugenActive ? elevate(_bg, 1.25) : "#1e2030"
    readonly property color wsEmpty: matugenActive ? _bg : "#111111"

    // ── Package source badges ────────────────────────────
    readonly property color badgePacman: matugenActive ? Qt.darker(_c4, 1.8) : "#1e3a5f"
    readonly property color badgeAur: matugenActive ? Qt.darker(_c3, 1.8) : "#5f3a1e"
    readonly property color badgeFlatpak: matugenActive ? Qt.darker(_c2, 1.8) : "#1e5f3a"
    readonly property color installedBg: matugenActive ? Qt.darker(_c2, 2.2) : "#1e3a1e"
    readonly property color dangerBg: matugenActive ? Qt.darker(_c1, 2.2) : "#3a1f1f"
    readonly property color dangerBorder: matugenActive ? Qt.darker(_c1, 1.3) : "#4a2a2a"

    // ── "Classical" plate system ──────────────────────────
    // Originally a *fixed*, hand-picked palette
    // — "deriving it from the wallpaper would be actively wrong" — kept
    // deliberately separate from matugen. Reversed per user request
    // 2026-09-04: every ground/text token below now derives from the
    // live matugen palette instead, same `matugenActive` fallback
    // pattern as the rest of this file, so the power menu/lock preview/
    // settings window follow the wallpaper exactly like the bar already
    // does. `accent` stays a manually-picked value on purpose (see
    // below) — that one's a curated color-swatch picker
    // (settingswindow/AppearancePane.qml), not a themed surface.
    //
    // "Paper" and "ink" must each stay recognizably light/dark
    // regardless of how light or dark the wallpaper itself is (a plate
    // popout over a bright wallpaper still needs a light card, not a
    // near-white-on-white one) — so these mix a small fraction of the
    // matugen background's hue into a fixed light/dark base rather than
    // just relabeling `_bg`.
    function _paperTint(bg) { return Qt.rgba(Math.min(1, bg.r * 0.12 + 0.88), Math.min(1, bg.g * 0.12 + 0.88), Math.min(1, bg.b * 0.12 + 0.88), 1) }
    function _inkTint(bg) { return Qt.rgba(bg.r * 0.14, bg.g * 0.14, bg.b * 0.14, 1) }
    function _foxedTint(bg) { return Qt.rgba(Math.min(1, bg.r * 0.16 + 0.82), Math.min(1, bg.g * 0.13 + 0.76), Math.min(1, bg.b * 0.08 + 0.64), 1) }

    readonly property color groundPaper: matugenActive ? _paperTint(_bg) : "#f7f6f5"
    readonly property color inkGround: matugenActive ? _inkTint(_bg) : "#191715"
    readonly property color groundFoxed: matugenActive ? _foxedTint(_bg) : "#e7dcc4"

    readonly property color plateBg: groundPaper
    readonly property color plateBgInk: Qt.rgba(inkGround.r, inkGround.g, inkGround.b, 0.96)
    readonly property color plateBorderInk: matugenActive ? elevate(inkGround, 1.6) : "#332f2b"
    // A translucent hairline reads correctly against any hue of dark ink
    // ground, so this doesn't need its own wallpaper-derived variant.
    readonly property color dividerInk: Qt.rgba(1, 1, 1, 0.08)

    // Text against the always-dark ink ground — blended from matugen's
    // own foreground color toward light rather than reused verbatim,
    // since `_fg` is tuned for contrast against `_bg`, not against a
    // ground that's deliberately darker still.
    readonly property color fgInkStrong: matugenActive ? Qt.rgba(Math.min(1, _fg.r * 0.3 + 0.88), Math.min(1, _fg.g * 0.3 + 0.88), Math.min(1, _fg.b * 0.3 + 0.85), 1) : "#f2ece1"
    readonly property color fgInk: matugenActive ? Qt.rgba(Math.min(1, _fg.r * 0.25 + 0.68), Math.min(1, _fg.g * 0.25 + 0.66), Math.min(1, _fg.b * 0.25 + 0.62), 1) : "#c9c0b3"
    readonly property color fgHeaderInk: matugenActive ? Qt.rgba(Math.min(1, _fg.r * 0.2 + 0.55), Math.min(1, _fg.g * 0.2 + 0.5), Math.min(1, _fg.b * 0.2 + 0.42), 1) : "#a3937c"
    // Header text on the paper ground (`common/Plate.qml`'s non-ink
    // case) — muted, darkened from `_fg` the same way `fgHeaderInk` is
    // lightened from it, mirrored for the opposite (light) ground.
    readonly property color fgHeader: matugenActive ? Qt.darker(_fg, 2.4) : "#8a7f6e"
    readonly property color fgIntro: fgSoft
    readonly property color fgLabel: fg

    // ── Lock preview (lockscreen/LockScreen.qml) ──────────
    readonly property color lockRule: dividerInk
    readonly property color lockPasswordBorder: matugenActive ? Qt.rgba(1, 1, 1, 0.16) : "#3d372f"
    readonly property color lockStatus: fgInk
    readonly property color lockUsername: fgHeaderInk
    readonly property color lockFooter: Qt.rgba(fgInk.r, fgInk.g, fgInk.b, 0.55)

    // ── Brand accent ───────────────────────────────────────
    // Deliberately NOT matugen-derived — settingswindow/AppearancePane.qml
    // offers this as an explicit 4-swatch picker (`Settings.accent`),
    // same idea as an OS-level "accent color" setting that coexists with
    // (rather than being replaced by) wallpaper-driven theming elsewhere.
    readonly property color accent: Settings.accent
    readonly property color accentText: accent
    // Danger/shutdown state (power menu's "Shut down" row) — reuses the
    // existing matugen-derived `red` rather than inventing a parallel
    // fixed token, so it tracks the wallpaper like every other status
    // color in this file already does.
    readonly property color accentAlarm: matugenActive ? red : "#9c4b3f"

    readonly property color settingsSidebarBg: matugenActive ? elevate(_bg, 1.1) : "#141414"
    readonly property color press: hoverStrong
    readonly property color groundCardTint: Qt.rgba(accent.r, accent.g, accent.b, 0.09)
    readonly property color sidebarSelectedTint: Qt.rgba(accent.r, accent.g, accent.b, 0.10)

    // ── Plate layout (common/Plate.qml) ───────────────────
    readonly property int platePaddingH: 18
    readonly property int platePaddingV: 16
    readonly property int plateHeaderGap: 10
    readonly property int space2: 10

    // ── Focus ring (common/FocusRing.qml) ─────────────────
    readonly property color focusRing: accent
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
    // out more than the always-on-screen bar strip does. Not derived
    // from matugen — a fixed dark shadow reads correctly under any
    // generated palette, light or dark.
    readonly property color shadowColor: "#99000000"          // ~60% black
    readonly property real shadowBlurPopup: 0.7
    readonly property real shadowVerticalOffsetPopup: 4
    readonly property real shadowBlurBar: 0.4
    readonly property real shadowVerticalOffsetBar: 2

    // "Docked" popouts (anchored under the bar module that opened them)
    // want a subtler shadow than "floating" ones (centred overlays like
    // the power menu) — same color, less blur/throw. See common/Plate.qml.
    readonly property color shadowColorDocked: shadowColor
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
