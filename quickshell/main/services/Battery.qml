pragma Singleton
import Quickshell
import Quickshell.Services.UPower
import QtQuick
import "../config"

Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool available: device !== null && device !== undefined

    readonly property real percentage: device ? device.percentage * 100 : 0
    readonly property bool charging: device ? device.state === UPowerDeviceState.Charging : false
    readonly property bool full: device ? device.state === UPowerDeviceState.FullyCharged : false
    readonly property bool discharging: device ? device.state === UPowerDeviceState.Discharging : false

    readonly property real timeToEmpty: (device && device.timeToEmpty !== undefined) ? device.timeToEmpty : 0
    readonly property real timeToFull: (device && device.timeToFull !== undefined) ? device.timeToFull : 0
    readonly property real changeRate: (device && device.changeRate !== undefined) ? device.changeRate : 0
    readonly property real health: (device && device.healthPercentage !== undefined) ? device.healthPercentage : -1

    readonly property string statusText: full ? "Full"
                                        : charging ? "Charging"
                                        : discharging ? "Discharging"
                                        : "Unknown"

    readonly property color fillColor: (charging || full) ? Theme.green
                                     : percentage <= 10 ? Theme.red
                                     : percentage <= 25 ? Theme.orange
                                     : Theme.icon

    readonly property string icon: {
        if (charging || full) return "󰂄"
        if (percentage >= 90) return "󰂂"
        if (percentage >= 80) return "󰂁"
        if (percentage >= 70) return "󰂀"
        if (percentage >= 60) return "󰁿"
        if (percentage >= 50) return "󰁾"
        if (percentage >= 40) return "󰁽"
        if (percentage >= 30) return "󰁼"
        if (percentage >= 20) return "󰁻"
        if (percentage >= 10) return "󰁺"
        return "󰂎"
    }

    readonly property string remainingLabel: charging ? "Time to Full" : "Time Remaining"
    readonly property string remainingText: charging ? fmtTime(timeToFull) : fmtTime(timeToEmpty)
    readonly property string rateText: changeRate ? changeRate.toFixed(1) + " W" : "—"
    // `health > 0`, not `>= 0`: UPower reports 0 both for "no wear data"
    // and for a device it has no health for at all, and this machine's
    // display device is the second kind — it aggregates two packs and
    // carries none of their health, so every surface reading this used to
    // claim a 0% battery while BAT0 and BAT1 reported 80% and 88%
    // themselves (found 2026-09-21 building the battery rail). A dash is
    // the honest answer to a number that isn't there; per-pack health is
    // in `deviceHealth` below, which is where the real figures live.
    readonly property string healthText: health > 0 ? Math.round(health) + "%" : "—"

    function fmtTime(seconds) {
        if (!seconds || seconds <= 0) return "—"
        const h = Math.floor(seconds / 3600)
        const m = Math.floor((seconds % 3600) / 60)
        return h + "h " + m + "m"
    }

    // ── The packs behind that one number ─────────────────
    // UPower.displayDevice, which everything above reads, is an
    // aggregate. On this ThinkPad it averages two packs — BAT0 internal,
    // BAT1 in the bay — into the single percentage the bar draws, and
    // that average can be a long way from either: 48% while BAT0 sat at
    // 16% and BAT1 at 80%. battery/BatteryPanel.qml breaks it back apart,
    // and the list belongs here, beside everything else this singleton
    // knows about the battery.
    //
    // `powerSupply` is the split between a pack that runs the machine and
    // a device that merely has a battery in it. It is the flag and not
    // the type that separates them: UPower gives a wireless mouse its own
    // device type (Mouse, 5) rather than calling it a Battery, so a
    // peripheral filter written against the type would miss exactly the
    // devices it is for. LinePower is excluded by name as well — the AC
    // brick and this machine's two USB-C ports are all powerSupply
    // devices with no charge of their own, and a 0% row for a wall socket
    // is not a battery reading.
    //
    // Naming UPower.devices *here* rather than only in the panel is
    // deliberate: the model enumerates over D-Bus on first access and
    // stays empty for about a second afterwards (measured — a probe that
    // read it once at 5s saw nothing, one that read it every 1.5s had it
    // by the second tick). This singleton is built at startup, because
    // the bar's battery module names it, so the enumeration is long done
    // by the time a rail is opened. A panel that asked first would open
    // on an empty list and grow rows a beat later, which on a card that
    // sizes to its content means the card itself jumping.
    readonly property var packs: {
        const out = []
        for (const d of UPower.devices.values)
            if (d.type === UPowerDeviceType.Battery && d.powerSupply) out.push(d)
        return out
    }

    // Everything else UPower knows a charge for: a mouse, a keyboard, a
    // headset. Empty on this machine, which is why the panel hides the
    // section rather than drawing an empty one — and why the filter is
    // kept to the one rule that is certainly right rather than a list of
    // types guessed at from the enum.
    readonly property var peripherals: {
        const out = []
        for (const d of UPower.devices.values)
            if (!d.powerSupply && d.type !== UPowerDeviceType.LinePower && d.percentage > 0)
                out.push(d)
        return out
    }

    // What to call one of the above. A pack answers to its kernel name —
    // BAT0/BAT1 is what the machine's own label, its BIOS and every other
    // tool call them, where `model` is a part number (01AV421). A
    // peripheral is the other way round: `model` is the name on the box
    // and nativePath is a HID path nobody reads.
    function deviceLabel(d) {
        if (!d) return "Battery"
        return (d.powerSupply ? (d.nativePath || d.model) : (d.model || d.nativePath)) || "Battery"
    }

    // UPowerDeviceState.toString gives "Charging", "Discharging",
    // "Fully Charged", "Pending Charge" — already the words this shell
    // would have written by hand, so they are taken rather than mapped.
    // The one substitution is "Pending Charge", which is what a
    // ThinkPad's second pack reads while the first one charges: true, and
    // opaque. "Waiting" says the same thing to someone looking at why one
    // of two bars is not moving.
    function deviceState(d) {
        if (!d) return "—"
        const text = UPowerDeviceState.toString(d.state)
        return text === "Pending Charge" ? "Waiting" : text
    }

    // The colour rule the aggregate wears above, applied to any one
    // device — a charging pack is green wherever it is drawn, and a pack
    // low enough to matter is red whether or not the average is.
    function deviceColor(d) {
        if (!d) return Theme.icon
        if (d.state === UPowerDeviceState.Charging || d.state === UPowerDeviceState.FullyCharged)
            return Theme.green
        const pct = d.percentage * 100
        if (pct <= 10) return Theme.red
        if (pct <= 25) return Theme.orange
        return Theme.icon
    }

    // Energy against the capacity this pack has left after wear, in the
    // watt-hours UPower reports — "3.1 / 19.2 Wh". Blank when a device
    // doesn't report energy at all, which every peripheral does.
    function deviceEnergy(d) {
        if (!d || !d.energyCapacity) return ""
        return d.energy.toFixed(1) + " / " + d.energyCapacity.toFixed(1) + " Wh"
    }

    function deviceHealth(d) {
        return (d && d.healthPercentage > 0) ? Math.round(d.healthPercentage) + "% health" : ""
    }

    // The same glyph ladder `icon` above walks, for one device rather
    // than for the aggregate — so a pack at 80% and a pack at 16% wear
    // different marks in the list even while the bar shows the average of
    // them. A peripheral gets a battery glyph too rather than a mouse or
    // a headset: UPower's device type would support drawing those, but
    // nothing on this machine has ever produced one to look at, and a
    // battery glyph is at least certainly true of anything in that list.
    function deviceIcon(d) {
        if (!d) return "󰂎"
        if (d.state === UPowerDeviceState.Charging || d.state === UPowerDeviceState.FullyCharged)
            return "󰂄"
        const pct = d.percentage * 100
        if (pct >= 90) return "󰂂"
        if (pct >= 80) return "󰂁"
        if (pct >= 70) return "󰂀"
        if (pct >= 60) return "󰁿"
        if (pct >= 50) return "󰁾"
        if (pct >= 40) return "󰁽"
        if (pct >= 30) return "󰁼"
        if (pct >= 20) return "󰁻"
        if (pct >= 10) return "󰁺"
        return "󰂎"
    }

    // ── Low battery warning ──────────────────────────────
    // Three warnings on the way down, not one (user request 2026-09-18):
    // 20% is "think about a charger", 5% is "now". Descending, and the
    // code below leans on that order.
    readonly property var lowThresholds: [20, 10, 5]
    readonly property int lowThreshold: root.lowThresholds[0]

    // Only while actually draining: sitting on AC at 15%, or charging
    // back up through the line, is not something to interrupt anyone
    // about.
    readonly property bool low: root.discharging
                             && root.percentage < root.lowThreshold

    // The lowest threshold the charge has fallen under, or 0 above all of
    // them: 14% gives 20, 8% gives 10, 3% gives 5. One number that says
    // both which warning is due and how bad things are, and it only ever
    // decreases over a discharge.
    readonly property int _crossed: {
        let hit = 0
        for (const t of root.lowThresholds)
            if (root.percentage < t) hit = t
        return hit
    }

    // Latched on the crossings rather than on the level — percentage
    // updates continuously, so a battery resting at 19.8% would otherwise
    // warn on every UPower tick. Re-arms only once the battery leaves the
    // low state entirely (charged back over the line, or plugged in), so
    // one discharge is one warning per threshold and no more.
    //
    // The latch is the threshold last warned at rather than a bool, so
    // each of the three fires once. 101 is "nothing warned yet this
    // discharge" — above any real charge, so the first crossing compares
    // true without a special case for it.
    //
    // In PersistentProperties and not a plain property on this singleton,
    // because a plain one is wiped by every config reload and the latch
    // then re-fires. Not hypothetical: editing this shell with the
    // battery under 20% re-warned on every save (2026-09-18, found while
    // the user watched it happen). It reads far worse than it sounds,
    // because _maybeWarn() waits for input — so each of those reloads
    // banked a warning that fired the instant someone touched the
    // machine, which looks exactly like a notification that refuses to
    // stay dismissed.
    //
    // Reloadable survives a hot reload, which is the case that was
    // broken. A full `qs kill && qs` still starts fresh, and one warning
    // after a deliberate restart is correct rather than a bug.
    PersistentProperties {
        id: warnState
        reloadableId: "batteryLowWarned"
        property int warnedAt: 101
    }

    onLowChanged: {
        if (!root.low) warnState.warnedAt = 101
        root._maybeWarn()
    }

    // The 20 -> 10 and 10 -> 5 crossings happen while `low` is already
    // true, so onLowChanged never fires for them and they need their own
    // trigger. This is the only handler here that runs off the charge
    // itself, and _crossed changes three times a discharge rather than on
    // every UPower tick, which is the whole reason it exists.
    on_CrossedChanged: root._maybeWarn()

    // Idle is part of the trigger here instead of being left to
    // Notifications.post()'s own idle gate: that gate drops the popup but
    // still writes the history row, so crossing 20% in front of an idle
    // screen would spend the one warning on a toast nobody was there to
    // read. Waiting for input instead means the warning lands — quoting
    // whatever the charge has fallen to by then — the moment someone is
    // actually back at the machine.
    Connections {
        target: Idle
        function onIsIdleChanged() { root._maybeWarn() }
    }

    // Critical urgency so the card sits there until it is dismissed
    // (durationFor() gives critical no expiry) rather than timing out
    // while the user is reading something else. It does NOT bypass DND —
    // that is reserved for relay and bare-CLI senders, see
    // Notifications._bypassesDnd() — so DND silences this to history like
    // anything else.
    // Away while the charge falls 20 -> 4 and you get one card on your
    // return, for 5%, not three stacked ones: _crossed is already 5 by
    // then and the two it passed are below the latch. The most urgent one
    // is the one worth showing, and it is the only one still true.
    function _maybeWarn() {
        if (!root.low || Idle.isIdle) return
        if (root._crossed === 0 || root._crossed >= warnState.warnedAt) return
        warnState.warnedAt = root._crossed
        Notifications.post("Battery low",
                           Math.round(root.percentage) + "% remaining"
                               + (root.timeToEmpty > 0
                                  ? " — " + root.fmtTime(root.timeToEmpty) + " left"
                                  : ""),
                           "critical", "Battery", root.icon)
    }
}
