pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// Battery events (AGENTS.md, Battery events): the charger going in or
// out, charging done, and the battery running low or critical. Events
// only: nothing while nothing changes, and never a standing percentage.
Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool present: device?.ready && device.isPresent && device.isLaptopBattery

    // The real readings, unless a test is simulating others.
    property bool simulating: false
    readonly property var reading: present && !simulating
        ? { onBattery: UPower.onBattery, percent: device.percentage * 100, state: device.state }
        : null
    onReadingChanged: if (reading) update(reading)

    // The last reading, to compare the next one with. The first only
    // sets it; so does anything in the first 2 seconds, while UPower's
    // readings arrive.
    property var last: null
    property bool armed: false
    Timer {
        running: true
        interval: 2000
        onTriggered: {
            root.armed = true
            // Already critical at start: say so once.
            const r = root.last
            if (r && r.onBattery && r.percent < Config.batteryCriticalPercent)
                root.showCritical(r.percent)
        }
    }

    function update(r) {
        const before = last
        last = r
        if (!before || !armed || !Config.battery)
            return
        if (r.onBattery !== before.onBattery) {
            showCharger(!r.onBattery, r.percent)
            return
        }
        // Done: Charging to full, or to the charge limit (PendingCharge).
        if (!r.onBattery && before.state === UPowerDeviceState.Charging
                && (r.state === UPowerDeviceState.FullyCharged || r.state === UPowerDeviceState.PendingCharge)) {
            showCharged(r.state === UPowerDeviceState.FullyCharged, r.percent)
            return
        }
        if (r.onBattery) {
            const crossed = t => before.percent >= t && r.percent < t
            if (crossed(Config.batteryCriticalPercent))
                showCritical(r.percent)
            else if (crossed(Config.batteryLowPercent))
                showLow(r.percent)
        }
    }

    // ── Submitting ──
    // One key: the newest battery event replaces the one before.
    function submit(spec) {
        ActivityQueue.submit(Object.assign({
            key: "battery",
            transient: true,
            priority: 40,
            timeout: Config.batteryTimeout,
            face: "",
            progress: -1,
        }, spec))
    }

    function pct(p) {
        return Math.round(p) + "%"
    }

    function showCharger(plugged, p) {
        submit(plugged
            ? { icon: "\u{f0084}", label: `Charger connected – ${pct(p)}` }
            : { icon: "\u{f06a6}", label: `On battery – ${pct(p)}` })
    }

    function showCharged(full, p) {
        submit({ icon: "\u{f0079}", label: full ? "Fully charged" : `Charged to ${pct(p)}` })
    }

    function showLow(p) {
        submit({ icon: "\u{f007a}", label: `Low battery – ${pct(p)}` })
    }

    // Above everything but notifications, and longer: the laptop is
    // about to die.
    function showCritical(p) {
        submit({
            icon: "\u{f0083}",
            label: `Battery critical – ${pct(p)}`,
            priority: 55,
            timeout: Config.batteryCriticalTimeout,
        })
    }

    // ── Battery tests ──
    // Feeds made-up readings through the same comparison (AGENTS.md,
    // Testing). `state`: "charging", "discharging", "full" or "pending".
    // `real` goes back to UPower's readings without an event.
    IpcHandler {
        target: "battery"

        function simulate(onBattery: bool, percent: real, state: string): void {
            root.simulating = true
            const states = {
                charging: UPowerDeviceState.Charging,
                discharging: UPowerDeviceState.Discharging,
                full: UPowerDeviceState.FullyCharged,
                pending: UPowerDeviceState.PendingCharge,
            }
            root.update({ onBattery, percent, state: states[state] ?? UPowerDeviceState.Unknown })
        }
        function real(): void {
            // Cleared first: the real reading then only sets the baseline.
            root.last = null
            root.simulating = false
        }
    }
}
