pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The weather now and four hours from now, for bar/WeatherButton.qml.
//
// From Open-Meteo (api.open-meteo.com): no API key, and an hourly
// forecast, so `later` is the hour nearest four hours from now rather
// than whichever three-hour slot came closest — why it replaced wttr.in
// (user request 2026-09-23). Open-Meteo has no IP lookup, so the place
// comes from WEATHER_LATITUDE and WEATHER_LONGITUDE in this config's
// gitignored .env (user request 2026-09-23: the location stays out of
// the repo). Without both, nothing is fetched and the bar module stays
// hidden. An experiment from new-config.sh needs its own copy.
//
// Only today counts (user request 2026-09-23): the forecast is asked for
// one day, so once four hours out is tomorrow there is no `later` and the
// bar shows just the temperature now.
Singleton {
    id: root

    // `timezone=auto` makes the hourly times this place's local time,
    // which is taken to be this machine's.
    property string latitude: ""
    property string longitude: ""
    readonly property bool located: root.latitude !== "" && root.longitude !== ""

    readonly property int refreshInterval: 15 * 60 * 1000
    // Tried sooner after a failure: at login the network is often not up
    // when the bar first asks.
    readonly property int retryInterval: 60 * 1000

    property bool ready: false

    // { temp, feels, desc, icon }
    property var now: null
    // [{ time: Date, temp, desc, icon, rain }], today's hours still ahead
    property var slots: []
    readonly property var later: {
        const target = Date.now() + 4 * 3600 * 1000
        for (const s of root.slots) {
            if (Math.abs(s.time.getTime() - target) <= 30 * 60 * 1000) return s
        }
        return null
    }

    // WMO weather code -> [glyph kind, description], per Open-Meteo's docs.
    readonly property var _codes: ({
        0: ["clear", "Clear sky"],
        1: ["clear", "Mainly clear"],
        2: ["partly", "Partly cloudy"],
        3: ["cloudy", "Overcast"],
        45: ["fog", "Fog"],
        48: ["fog", "Rime fog"],
        51: ["rain", "Light drizzle"],
        53: ["rain", "Drizzle"],
        55: ["rain", "Dense drizzle"],
        56: ["sleet", "Freezing drizzle"],
        57: ["sleet", "Dense freezing drizzle"],
        61: ["rain", "Light rain"],
        63: ["rain", "Rain"],
        65: ["pouring", "Heavy rain"],
        66: ["sleet", "Freezing rain"],
        67: ["sleet", "Heavy freezing rain"],
        71: ["snow", "Light snow"],
        73: ["snow", "Snow"],
        75: ["snow", "Heavy snow"],
        77: ["snow", "Snow grains"],
        80: ["rain", "Light showers"],
        81: ["rain", "Showers"],
        82: ["pouring", "Violent showers"],
        85: ["snow", "Snow showers"],
        86: ["snow", "Heavy snow showers"],
        95: ["thunder", "Thunderstorm"],
        96: ["thunder", "Thunderstorm with hail"],
        99: ["thunder", "Thunderstorm with heavy hail"]
    })

    function _describe(code) {
        return (root._codes[code] || ["cloudy", "Unknown"])[1]
    }

    // Nerd Font Material Design weather glyphs.
    function iconFor(code, night) {
        switch ((root._codes[code] || ["cloudy"])[0]) {
        case "clear":   return String.fromCodePoint(night ? 0xF0594 : 0xF0599)  // weather-night / weather-sunny
        case "partly":  return String.fromCodePoint(night ? 0xF0F31 : 0xF0595)  // weather-night-partly-cloudy / weather-partly-cloudy
        case "fog":     return String.fromCodePoint(0xF0591)                    // weather-fog
        case "rain":    return String.fromCodePoint(0xF0597)                    // weather-rainy
        case "pouring": return String.fromCodePoint(0xF0596)                    // weather-pouring
        case "snow":    return String.fromCodePoint(0xF0598)                    // weather-snowy
        case "sleet":   return String.fromCodePoint(0xF067F)                    // weather-snowy-rainy
        case "thunder": return String.fromCodePoint(0xF067E)                    // weather-lightning-rainy
        default:        return String.fromCodePoint(0xF0590)                    // weather-cloudy
        }
    }

    // "2026-09-23T16:00", local time. Parsed by hand: an ISO string with
    // no offset is local by the spec, but not every JS engine agrees.
    function _time(iso) {
        const [date, clock] = iso.split("T")
        const [y, mo, d] = date.split("-").map(Number)
        const [h, mi] = clock.split(":").map(Number)
        return new Date(y, mo - 1, d, h, mi)
    }

    function _parse(data) {
        const c = data.current
        root.now = {
            temp: Math.round(c.temperature_2m),
            feels: Math.round(c.apparent_temperature),
            desc: root._describe(c.weather_code),
            icon: root.iconFor(c.weather_code, c.is_day === 0)
        }

        const h = data.hourly
        const clock = Date.now()
        const slots = []
        for (let i = 0; i < h.time.length; i++) {
            const time = root._time(h.time[i])
            if (time.getTime() <= clock) continue
            slots.push({
                time: time,
                temp: Math.round(h.temperature_2m[i]),
                desc: root._describe(h.weather_code[i]),
                icon: root.iconFor(h.weather_code[i], h.is_day[i] === 0),
                rain: h.precipitation_probability[i] || 0
            })
        }
        root.slots = slots
        root.ready = true
    }

    function refresh() {
        if (root.located && !fetchProc.running) fetchProc.running = true
    }

    // KEY=VALUE lines; blanks, comments and other keys are skipped.
    function _readEnv(text) {
        const env = {}
        for (const line of text.split("\n")) {
            const m = /^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line)
            if (m) env[m[1]] = m[2].replace(/^(["'])(.*)\1$/, "$2")
        }
        root.latitude = env.WEATHER_LATITUDE || ""
        root.longitude = env.WEATHER_LONGITUDE || ""
    }

    onLocatedChanged: root.refresh()

    FileView {
        path: Quickshell.shellPath(".env")
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._readEnv(text())
    }

    Timer {
        id: timer
        interval: root.refreshInterval
        running: root.located
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: fetchProc
        command: ["curl", "-sf", "--max-time", "20",
            "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + root.latitude + "&longitude=" + root.longitude
            + "&current=temperature_2m,apparent_temperature,weather_code,is_day"
            + "&hourly=temperature_2m,weather_code,is_day,precipitation_probability"
            + "&timezone=auto&forecast_days=1"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._parse(JSON.parse(text))
                    timer.interval = root.refreshInterval
                } catch (e) {
                    // Keep showing the last good reading; a stale
                    // forecast beats an empty slot in the bar.
                    console.warn("Weather: could not read Open-Meteo's answer:", e)
                    timer.interval = root.retryInterval
                }
                timer.restart()
            }
        }
    }
}
