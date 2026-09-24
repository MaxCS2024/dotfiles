import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"
import "../services"

// One bar per monitor. A bare PanelWindow only ever creates a window on
// the default screen.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: bar
        required property var modelData

        // Per-monitor position/floating/enabled/height,
        // resolved through Settings.barConfigFor() (falls back to a
        // "default" entry for any monitor without its own override —
        // see services/Settings.qml). This machine only has one
        // monitor, so real per-monitor *divergence* (two monitors with
        // different configs at once) couldn't be exercised live — same
        // caveat ActiveWindow's own monitor gating carries. What is
        // verified: a monitor-name-keyed override actually takes effect.
        readonly property string monitorName: bar.modelData.name
        readonly property var cfg: Settings.barConfigFor(bar.monitorName)
        // Settings.barLayoutFor() comes from services/Settings.qml, and
        // the layout it returns is usually the persisted one from
        // settings.json rather than the default in that file. That
        // persisted layout can name a module this config's
        // bar/Modules.qml doesn't register — "keyboard", "mic" and
        // "camera" are all in this machine's saved layout right now,
        // three modules main dropped on 2026-09-08. (The default in
        // Settings.qml named them too until 2026-09-20; it no longer
        // does, but a settings.json written before then still will,
        // which is why this filter is not something that default's fix
        // made redundant.) An unregistered name reaches BarModuleLoader
        // as an undefined
        // sourceComponent: nothing loads, but the Loader is still a
        // visible zero-width child, so RowLayout keeps spacing either
        // side of it. Filtering here drops the names nothing can build
        // instead of rendering those gaps.
        function knownModules(names) { return names.filter(n => n in Modules.registry) }
        readonly property var layout: {
            const l = Settings.barLayoutFor(bar.monitorName)
            return {
                left: bar.knownModules(l.left),
                center: bar.knownModules(l.center),
                right: bar.knownModules(l.right)
            }
        }
        readonly property bool onBottom: bar.cfg.position === "bottom"
        // The bar's height lives here, and only here. config/Theme.qml
        // carried a rival `barHeight: 27` for the config it used to share
        // with quickshell/old, which made the default look like a
        // deviation from a token rather than the number itself; that
        // config went away 2026-09-20 and the property, which nothing
        // read by then, went with it 2026-09-22. services/Settings.qml
        // stores `height: 0` for "unset" rather than a second copy of the
        // default, so there is nothing left to drift. bar.cfg.height (a
        // per-monitor override, from Settings.qml) still wins if the user
        // sets one. 36, not the old 35: Theme.barItemHeight (24) plus 6
        // each side, on the 4px grid (STYLE.md §5).
        readonly property int barHeight: bar.cfg.height > 0 ? bar.cfg.height : 36

        // bar.cfg.enabled is the persisted per-monitor setting;
        // Panels.barVisible is the SUPER+ALT+SPACE runtime toggle (see
        // services/Panels.qml). Both have to say yes for the bar to
        // show — but "hidden" here means mapped-but-inert, NOT
        // `visible: false`. Driving the PanelWindow's own `visible` off
        // and back on brings the layer surface back with its content
        // gone (an empty strip, background and all), and only a config
        // reload restores it. So the window stays mapped and hiding is
        // done in three parts below: hand back the exclusive zone, drop
        // the input region, hide the content.
        //
        // `shown` is the *requested* state — it flips the instant the
        // key is pressed, which is what the modules that pause
        // themselves off it want (WorkspacePill's urgent pulse,
        // MediaPlayer's marquee). The three inert-ing steps key off
        // `occupying` below instead, so they land around the slide
        // rather than during it.
        readonly property bool shown: bar.cfg.enabled && Panels.barVisible

        // How far the bar has travelled away from its screen edge:
        // 0 fully in, slideDistance fully gone. The window itself never
        // moves — its content is translated inside a layer surface only
        // as tall as the bar, so the strip clips the content against
        // the screen edge exactly as if it were sliding off it.
        // Distance covers the floating gap too, so a floating bar
        // clears its own margin.
        readonly property int slideDistance: bar.barHeight + (bar.cfg.floating ? 8 : 0)
        // What animates is how far through the slide the bar is (0 in,
        // 1 gone), not the pixel offset. Animating the offset itself
        // also animated every change to slideDistance, so a hidden bar
        // whose height or floating setting changed "slid" from the old
        // distance to the new one — and `occupying` below, reading
        // offset < distance, took that for the bar being mid-slide and
        // handed it its strip and input back until it finished. As a
        // fraction, a new distance only rescales the offset.
        property real slideProgress: bar.shown ? 0 : 1
        readonly property real slideOffset: bar.slideProgress * bar.slideDistance
        // Asymmetric on purpose, the same way the OSDs' entrance/exit
        // pair is (osd/OsdContent.qml): the bar decelerates into place
        // on the way in, and leaves without the lingering tail that a
        // decel curve gives an exit.
        Behavior on slideProgress {
            NumberAnimation {
                duration: bar.shown ? Theme.animPanel : Theme.animNormal
                easing.type: bar.shown ? Theme.easingDecel : Theme.easingStandard
            }
        }

        // The strip is still real — reserved, clickable, painted — for
        // the whole of the slide, and only stops being so once the bar
        // has actually left. So the toggle lands *after* the slide out,
        // and *before* the slide in: windows reclaim the space as the
        // bar finishes leaving rather than jumping out from under it,
        // and the space is reserved again before it slides back down
        // into it.
        readonly property bool occupying: bar.shown || bar.slideProgress < 1

        visible: bar.cfg.enabled
        // Auto is the untouched default: Quickshell derives the
        // reserved strip from the anchors and height itself. Ignore
        // reserves nothing, so tiled windows reclaim the space instead
        // of leaving a hole where the bar was.
        //
        // Deliberately NO `exclusiveZone` binding here. Writing any
        // literal to it — including -1, meaning "auto" — silently flips
        // exclusionMode off Auto to Normal, and under Normal the value
        // is taken as a literal pixel count rather than a request to
        // compute one. That footgun cost a previous shell a release:
        // the bar looked right while windows tiled flush underneath it,
        // because every test happened to land on the hidden branch that
        // worked. Driving exclusionMode alone avoids it.
        exclusionMode: bar.occupying ? ExclusionMode.Auto : ExclusionMode.Ignore
        // Same empty-Region idiom the OSDs already use for click-through
        // (osd/VolumeOsd.qml et al.) — without it the hidden bar would
        // still swallow clicks along the top edge of the screen.
        mask: bar.occupying ? null : hiddenMask
        Region { id: hiddenMask }
        screen: bar.modelData
        anchors {
            top: !bar.onBottom
            bottom: bar.onBottom
            left: true
            right: true
        }
        implicitHeight: bar.barHeight
        color: "transparent"

        WlrLayershell.namespace: "quickshell:bar"
        // None the rest of the time (the bar never wants
        // to steal keyboard input from whatever app is focused); only
        // OnDemand while kbActive, the same mechanism/idiom
        // launcher/Launcher.qml and every card and window here already
        // use for their own Escape handling (`box.forceActiveFocus()` +
        // `Keys.onPressed`), not a new one invented for this.
        WlrLayershell.keyboardFocus: kbActive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        WlrLayershell.margins {
            top: (bar.cfg.floating && !bar.onBottom) ? 8 : 0
            bottom: (bar.cfg.floating && bar.onBottom) ? 8 : 0
            left: bar.cfg.floating ? 8 : 0
            right: bar.cfg.floating ? 8 : 0
        }

        readonly property var monitor: Hyprland.monitorFor(bar.modelData)

        // Keyboard navigation. SUPER+SHIFT+B (hypr/modules/binds/apps.lua,
        // via services/Panels.qml's "bar-focus" GlobalShortcut) fires
        // Panels.focusBarRequested on every monitor's Bar at once; each
        // instance only actually engages if it's the one on the
        // currently focused monitor — the same gating 2.1's
        // ActiveWindow already uses, so only one bar ever grabs
        // keyboard focus on a multi-monitor setup, not all of them.
        readonly property bool onFocusedMonitor: bar.monitor === Hyprland.focusedMonitor
        property bool kbActive: false
        property int kbIndex: 0

        // Flat, ordered list of BarModuleLoader instances across all
        // three rows whose loaded item opted into keyboard nav by
        // declaring `keyboardFocused` (BarButton does; bar/Workspaces
        // .qml and SystemTray don't subclass BarButton — house style
        // item 6 — so they're silently skipped, not specially excluded).
        // Reads `.count` (a real property) to drive the loop bound,
        // and `.keyboardNavigable` per item (also a real property on
        // each loader) — both are genuine dependencies of this binding,
        // not method calls that would fall outside QML's tracking.
        readonly property var kbTargets: {
            const result = []
            for (let i = 0; i < leftRepeater.count; i++) {
                const it = leftRepeater.itemAt(i)
                if (it && it.keyboardNavigable) result.push(it)
            }
            for (let i = 0; i < centerRepeater.count; i++) {
                const it = centerRepeater.itemAt(i)
                if (it && it.keyboardNavigable) result.push(it)
            }
            for (let i = 0; i < rightRepeater.count; i++) {
                const it = rightRepeater.itemAt(i)
                if (it && it.keyboardNavigable) result.push(it)
            }
            return result
        }

        function kbMove(delta) {
            if (bar.kbTargets.length === 0) return
            bar.kbIndex = (bar.kbIndex + delta + bar.kbTargets.length) % bar.kbTargets.length
        }
        // Enter fires the focused item's tapped() signal directly —
        // signals are callable like functions in QML — the exact same
        // signal a real click already fires (BarButton.qml), so
        // "activate" behaves identically to clicking, not a second,
        // separately-maintained action path.
        function kbActivate() {
            const t = bar.kbTargets[bar.kbIndex]
            if (t && t.item) t.item.tapped()
        }
        function kbRelease() {
            bar.kbActive = false
            kbFocusGrab.active = false
        }

        // Hiding the bar (SUPER+ALT+SPACE) leaves a mapped but empty
        // window, which would happily go on holding a keyboard focus
        // grab the user can't see or escape from. Drop kb nav on the way
        // out; re-showing starts un-focused, same as after Escape.
        onShownChanged: if (!bar.shown && bar.kbActive) bar.kbRelease()

        Connections {
            target: Panels
            function onFocusBarRequested() {
                if (!bar.onFocusedMonitor) return
                bar.kbIndex = 0
                bar.kbActive = true
                kbFocusGrab.active = true
                kbCatcher.forceActiveFocus()
            }
        }

        // The same mechanism the popup windows already use: releases kb nav the moment focus genuinely moves
        // elsewhere (a real click on another window), not just Escape.
        HyprlandFocusGrab {
            id: kbFocusGrab
            windows: [bar]
            onCleared: bar.kbActive = false
        }

        Item {
            id: kbCatcher
            anchors.fill: parent
            focus: bar.kbActive
            Keys.onPressed: (event) => {
                if (!bar.kbActive) return
                if (event.key === Qt.Key_Left) { bar.kbMove(-1); event.accepted = true }
                else if (event.key === Qt.Key_Right) { bar.kbMove(1); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { bar.kbActivate(); event.accepted = true }
                else if (event.key === Qt.Key_Escape) { bar.kbRelease(); event.accepted = true }
            }
        }

        // Settings.stayAwake (services/Settings.qml) is the shared
        // on/off toggle the bar icon and quicksettings' "Coffee" switch
        // both drive. Quickshell.Wayland.IdleInhibitor needs a window
        // property pointing at a real window for the compositor to judge
        // as "important" (a PanelWindow, per Quickshell's own docs,
        // usually qualifies) — since Variants instantiates one Bar per
        // monitor, that means one IdleInhibitor object per monitor here,
        // all driven from the same shared setting.
        IdleInhibitor {
            enabled: Settings.stayAwake
            window: bar
        }

        Item {
            id: barContent
            anchors.fill: parent
            // Opacity, chosen when BarModuleLoader mirrored its module's
            // `visible` and hiding anything above the Loaders latched
            // them off for good. The Loaders read `hasContent` now (see
            // that file), so `visible` would no longer do that; opacity
            // stays because it works and leaves the module tree alone.
            //
            // Held at 1 for the whole slide (`occupying`, not `shown`)
            // — there's nothing to see once the bar has cleared the
            // edge, and fading it out under the slide would just make
            // the slide look half-hearted.
            opacity: bar.occupying ? 1 : 0

            // transform, not y/anchors: barContent is anchors.fill'd,
            // and a Translate leaves the anchors (and every layout
            // under them) alone instead of fighting them.
            transform: Translate {
                y: bar.onBottom ? bar.slideOffset : -bar.slideOffset
            }

            Rectangle {
                id: barBg
                anchors.fill: parent
                radius: bar.cfg.floating ? Theme.radiusLarge : 0
                // Appearance.bar, not Appearance.barGlass: barGlass folds in
                // Settings.barOpacity, a shared setting (services/ is
                // symlinked to main), so reading it here would let main's
                // opacity slider through into this bar. The opaque token
                // keeps this bar always fully opaque, the way the fixed
                // literal it replaces did, while still following whichever
                // palette theme/Appearance.qml is currently resolving to.
                color: Appearance.bar
            }

            RowLayout {
                id: leftRow
                anchors {
                    left: parent.left
                    // Was 8 — same value rightRow uses, so both ends of
                    // the bar are inset alike. Every BarButton carries
                    // Theme.barItemPadX (12px) of its own pad inside the
                    // hover pill, so the first glyph still lands 16px in,
                    // not hard against the edge.
                    leftMargin: Theme.space1
                    verticalCenter: parent.verticalCenter                }
                // Was 12 — with the settings button's side pad on top,
                // that left a 23px void between a bare glyph and the
                // filled workspace chips, so the icon read as stranded
                // instead of part of the same left cluster. One grid
                // step above the edge inset, which is what the heavier
                // chips want beside them.
                spacing: Theme.space2

                Repeater {
                    id: leftRepeater
                    model: bar.layout.left
                    delegate: BarModuleLoader {
                        id: moduleLoader
                        required property string modelData
                        name: modelData
                        barWindow: bar
                        keyboardFocused: bar.kbActive && bar.kbTargets[bar.kbIndex] === moduleLoader
                    }
                }
            }

            RowLayout {
                id: centerRow
                anchors.verticalCenter: parent.verticalCenter
                // The clock holds the middle of the bar, and whatever
                // shares the row grows out from beside it. Centring the
                // row as a whole moved the clock every time a module
                // with `hasContent` came or went — half the voxtype
                // pill's width each time dictation started (user request
                // 2026-09-24; that pill has since moved off the bar, to
                // osd/VoxtypeOsd.qml). Without a clock in the row, the row
                // centres as a whole, the way it always did.
                //
                // `x`, not anchors.centerIn plus a horizontalCenterOffset:
                // the anchor rounds its half-pixel one way and the offset
                // another, which left the clock 1px off whenever the pill
                // was up. One Math.round over the whole sum lands the
                // clock on the same pixel either way.
                x: {
                    let pivot = null
                    for (let i = 0; i < centerRepeater.count; i++) {
                        const it = centerRepeater.itemAt(i)
                        if (it && it.name === "clock") pivot = it
                    }
                    return pivot
                        ? Math.round(parent.width / 2 - (pivot.x + pivot.width / 2))
                        : Math.round((parent.width - centerRow.width) / 2)
                }
                spacing: Theme.space2

                Repeater {
                    id: centerRepeater
                    model: bar.layout.center
                    delegate: BarModuleLoader {
                        id: moduleLoader
                        required property string modelData
                        name: modelData
                        barWindow: bar
                        keyboardFocused: bar.kbActive && bar.kbTargets[bar.kbIndex] === moduleLoader
                    }
                }
            }

            RowLayout {
                id: rightRow
                anchors {
                    right: parent.right
                    rightMargin: Theme.space1
                    verticalCenter: parent.verticalCenter                }
                spacing: Theme.space1

                Repeater {
                    id: rightRepeater
                    model: bar.layout.right
                    delegate: BarModuleLoader {
                        id: moduleLoader
                        required property string modelData
                        name: modelData
                        barWindow: bar
                        keyboardFocused: bar.kbActive && bar.kbTargets[bar.kbIndex] === moduleLoader
                    }
                }
            }
        }
    }
}
