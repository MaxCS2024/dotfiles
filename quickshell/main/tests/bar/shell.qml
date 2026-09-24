import Quickshell
import Quickshell.Wayland
import QtQuick
import "bar"
import "services"

// Tests for bar/Bar.qml. Run with `tests/run bar`, which copies the
// real Bar.qml and BarModuleLoader.qml in beside the stubs here — this
// file can't run on its own.
//
// Each step is a function run in order; one that returns a number waits
// that many ms before the next, which is how the slide tests let the
// Behavior on slideProgress finish. Results go to the log as
// "TEST PASS|FAIL <name>", then one "TEST DONE <failures>" line —
// qs ignores Qt.quit(), so the runner watches for that line and kills it.
ShellRoot {
    id: root

    Bar { id: bars }

    // One bar per screen; every test below reads the first.
    readonly property var bar: bars.instances.length > 0 ? bars.instances[0] : null
    property int failures: 0
    property int step: 0

    function check(name, ok, detail) {
        if (!ok) root.failures++
        console.log(`TEST ${ok ? "PASS" : "FAIL"} ${name}${ok || detail === undefined ? "" : ` (${detail})`}`)
    }
    function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
    function useLayout(left, center, right) {
        Settings.barLayout = { left: left, center: center, right: right }
    }
    function useConfig(over) {
        Settings.barConfig = Object.assign({ enabled: true, position: "top", floating: false, height: 0 }, over)
    }
    // The FakeButton each keyboard target loaded, in kbTargets order.
    function buttons() { return root.bar.kbTargets.map(t => t.item) }

    readonly property var steps: [
        () => {
            root.check("one bar per screen", bars.instances.length === Quickshell.screens.length,
                       `${bars.instances.length} bars, ${Quickshell.screens.length} screens`)
        },

        // ── hidden at start ────────────────────────────────
        () => {
            const b = root.bar
            root.check("hidden bar stays mapped", b.visible)
            root.check("hidden bar reserves no space", b.exclusionMode === ExclusionMode.Ignore)
            root.check("hidden bar lets clicks through", b.mask !== null)
            root.useConfig({ enabled: false })
            root.check("disabled bar is unmapped", !b.visible)
            root.useConfig({})
        },

        // ── layout ─────────────────────────────────────────
        () => {
            root.useLayout(["button", "keyboard", "widget"], ["mic"], ["button", "camera"])
            root.check("unregistered module names are dropped",
                       root.same(root.bar.layout, { left: ["button", "widget"], center: [], right: ["button"] }),
                       JSON.stringify(root.bar.layout))
        },
        () => {
            root.useLayout(["button", "widget"], [], [])
            Features.off = ["fakefeature"]
            root.check("a module whose feature is off is dropped",
                       root.same(root.bar.layout.left, ["button"]), JSON.stringify(root.bar.layout.left))
            Features.off = []
            root.check("it comes back when the feature is turned on",
                       root.same(root.bar.layout.left, ["button", "widget"]), JSON.stringify(root.bar.layout.left))
        },

        // ── height ─────────────────────────────────────────
        () => {
            root.useConfig({})
            root.check("height 0 means the 36px default", root.bar.barHeight === 36, root.bar.barHeight)
            root.check("window takes the bar height", root.bar.implicitHeight === 36, root.bar.implicitHeight)
            root.useConfig({ height: 42 })
            root.check("per-monitor height overrides the default", root.bar.barHeight === 42, root.bar.barHeight)
        },

        // ── position and floating ──────────────────────────
        () => {
            root.useConfig({ position: "bottom", floating: true })
            const b = root.bar
            root.check("bottom bar anchors to the bottom edge", b.anchors.bottom && !b.anchors.top)
            root.check("floating bottom bar is inset on every side but the top",
                       b.WlrLayershell.margins.bottom === 8 && b.WlrLayershell.margins.top === 0
                       && b.WlrLayershell.margins.left === 8 && b.WlrLayershell.margins.right === 8)
            root.check("floating bar slides its margin clear too", b.slideDistance === 36 + 8, b.slideDistance)
            root.useConfig({})
            root.check("docked top bar has no margins",
                       b.anchors.top && !b.anchors.bottom && b.WlrLayershell.margins.top === 0
                       && b.WlrLayershell.margins.left === 0)
            root.check("docked bar slides exactly its height", b.slideDistance === 36, b.slideDistance)
        },

        // ── showing: space is reserved before the slide in ──
        () => {
            Panels.barVisible = true
            const b = root.bar
            root.check("showing reserves space at once", b.occupying && b.exclusionMode === ExclusionMode.Auto)
            root.check("showing takes input at once", b.mask === null)
            root.check("showing starts the slide from off-screen", b.slideOffset > 0, b.slideOffset)
            return 300
        },
        () => {
            root.check("shown bar has slid fully in", root.bar.slideOffset === 0, root.bar.slideOffset)
        },

        // ── hiding: space is kept until the slide out ends ──
        () => {
            Panels.barVisible = false
            const b = root.bar
            root.check("hiding keeps the space during the slide", b.occupying && b.exclusionMode === ExclusionMode.Auto)
            root.check("hiding keeps input during the slide", b.mask === null)
            return 300
        },
        () => {
            const b = root.bar
            root.check("hidden bar has slid its whole distance", b.slideOffset === b.slideDistance, b.slideOffset)
            root.check("space is handed back once the slide ends", !b.occupying && b.exclusionMode === ExclusionMode.Ignore)
            root.check("input is dropped once the slide ends", b.mask !== null)
        },

        // ── settings changes while hidden ──────────────────
        // A new slideDistance used to be animated towards like a hide,
        // and occupying read that animation as the bar mid-slide — so a
        // hidden bar took its strip and its input back for the length
        // of the slide whenever its height or floating setting changed.
        () => {
            root.useConfig({ floating: true, height: 42 })
            const b = root.bar
            root.check("resizing a hidden bar doesn't reserve space", !b.occupying && b.exclusionMode === ExclusionMode.Ignore)
            root.check("resizing a hidden bar doesn't take input", b.mask !== null)
            root.check("resized hidden bar is already fully off-screen", b.slideOffset === b.slideDistance,
                       `${b.slideOffset} of ${b.slideDistance}`)
            // Mid-way through what would have been the slide.
            return 20
        },
        () => {
            const b = root.bar
            root.check("resized hidden bar stays inert mid-slide", !b.occupying && b.mask !== null)
            root.useConfig({})
            root.check("shrinking a hidden bar doesn't reserve space either", !b.occupying && b.mask !== null)
            Panels.barVisible = true
            return 300
        },

        // ── keyboard targets ───────────────────────────────
        () => {
            root.useLayout(["widget", "button"], ["button"], ["widget", "button"])
            const b = root.bar
            root.check("only modules declaring keyboardFocused are targets", b.kbTargets.length === 3, b.kbTargets.length)
            root.check("targets run left, center, right",
                       b.kbTargets.every(t => t.name === "button")
                       && b.kbTargets[0].parent.x < b.kbTargets[1].parent.x
                       && b.kbTargets[1].parent.x < b.kbTargets[2].parent.x)
        },
        () => {
            const b = root.bar
            Panels.focusBarRequested()
            root.check("SUPER+SHIFT+B on the focused monitor engages kb nav", b.onFocusedMonitor ? b.kbActive : true,
                       "is this screen the focused monitor?")
            root.check("kb nav starts on the first target", b.kbIndex === 0, b.kbIndex)
            root.check("only the current target shows focus",
                       root.same(root.buttons().map(i => i.keyboardFocused), [true, false, false]))
        },
        () => {
            const b = root.bar
            b.kbActive = true
            b.kbMove(1)
            root.check("right moves to the next target", b.kbIndex === 1, b.kbIndex)
            root.check("focus follows the index",
                       root.same(root.buttons().map(i => i.keyboardFocused), [false, true, false]))
            b.kbMove(1)
            b.kbMove(1)
            root.check("right from the last target wraps to the first", b.kbIndex === 0, b.kbIndex)
            b.kbMove(-1)
            root.check("left from the first target wraps to the last", b.kbIndex === 2, b.kbIndex)
        },
        () => {
            const b = root.bar
            const before = root.buttons().map(i => i.taps)
            b.kbActivate()
            const after = root.buttons().map(i => i.taps)
            root.check("enter taps only the focused target",
                       after[2] === before[2] + 1 && after[0] === before[0] && after[1] === before[1],
                       `${before} -> ${after}`)
        },
        () => {
            const b = root.bar
            b.kbRelease()
            root.check("escape ends kb nav", !b.kbActive)
            root.check("no target shows focus after escape", root.buttons().every(i => !i.keyboardFocused))
        },
        () => {
            const b = root.bar
            b.kbActive = true
            Panels.barVisible = false
            root.check("hiding the bar ends kb nav", !b.kbActive)
            return 300
        },
        () => {
            root.useLayout(["widget"], [], [])
            const b = root.bar
            b.kbIndex = 0
            b.kbMove(1)
            root.check("moving with no targets is a no-op", b.kbIndex === 0, b.kbIndex)
            b.kbActivate()
            root.check("activating with no targets doesn't throw", true)
        },

        // ── self-hiding modules ────────────────────────────
        // The loader used to mirror its module's `visible`, which Qt
        // reports with the parent's folded in, so a module that hid itself
        // hid its loader, and from then on read false because its loader
        // was hidden. The media pill vanished with the last player and
        // didn't come back for the next one until a reload, or never
        // appeared at all if the shell started with nothing playing.
        () => {
            Modules.selfHidingHasContent = false
            root.useLayout(["selfhiding", "button"], [], [])
            const slot = root.findLoader("selfhiding")
            root.check("self-hiding module is loaded", slot !== null)
            root.check("module with nothing to show takes no slot", slot !== null && !slot.visible)
        },
        () => {
            const slot = root.findLoader("selfhiding")
            Modules.selfHidingHasContent = true
            root.check("module that starts empty appears once it has content", slot.visible && slot.item.visible)
            Modules.selfHidingHasContent = false
            root.check("module gives its slot back when its content goes", !slot.visible)
            Modules.selfHidingHasContent = true
            root.check("module comes back for content after being hidden", slot.visible && slot.item.visible)
        }
    ]

    // The loader for a module by registry name, found by walking the bar.
    function findLoader(name) {
        const walk = item => {
            if (item.name === name && "keyboardNavigable" in item) return item
            for (const child of item.children) {
                const found = walk(child)
                if (found) return found
            }
            return null
        }
        return walk(root.bar.contentItem)
    }

    Timer {
        id: runner
        interval: 0
        onTriggered: {
            if (root.step >= root.steps.length) {
                console.log(`TEST DONE ${root.failures}`)
                return
            }
            let wait
            try {
                wait = root.steps[root.step]()
            } catch (e) {
                root.check(`step ${root.step} threw`, false, e)
            }
            root.step++
            runner.interval = typeof wait === "number" ? wait : 0
            runner.start()
        }
    }

    // Give Variants a moment to build the bars before the first step.
    Component.onCompleted: { runner.interval = 200; runner.start() }
}
