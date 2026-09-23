import QtQuick

import org.kde.plasma.plasma5support as P5Support

// The weather as text: one line for now, one per forecast day, drawn the way the monitor
// draws its lines — monospace, no frames. The data is Open-Meteo's forecast API, read with
// XMLHttpRequest straight from the widget: an https request to a public host works inside
// plasmashell (verified 2026-09-23; only file:// is blocked, docs/GOTCHAS.md), so there is
// no relay. Open-Meteo is free for non-commercial use and asks for attribution — hence the
// last line, on by default.
Item {
    id: view

    // ── Inputs ────────────────────────────────────────────────────────────────
    // The user's location, as text: empty means not set, and then the widget falls back
    // to the guess it made from the time zone. The guess is kept apart, so the user's
    // choice stays empty and the header can say where the place came from. The numbers
    // use a point whatever the locale: the settings page writes them, nobody types them.
    property string latitude: ""
    property string longitude: ""
    property string placeName: ""
    property string guessedLat: ""
    property string guessedLon: ""
    property string guessedName: ""
    // 0: by the locale (US → °F mph, otherwise °C km/h); 1 °C km/h; 2 °C m/s; 3 °F mph.
    property int units: 0
    property int days: 3
    property bool attribution: true
    property int columns: 52
    // The last good response and when it came, from the config: drawn at start, before
    // the first request of this run completes.
    property string cachedJson: ""
    property string cachedTime: ""

    property string fontFamily: "JetBrainsMono Nerd Font Mono"
    property int fontSize: 10
    property color colorFg: "#C8CCD4"
    property color colorAccent: "#E05561"
    property color colorDim: "#6B7280"

    // Where the data comes from. Open-Meteo can be self-hosted with the same paths.
    property string forecastUrl: "https://api.open-meteo.com/v1/forecast"
    property string geocodingUrl: "https://geocoding-api.open-meteo.com/v1/search"

    // ── Outputs ───────────────────────────────────────────────────────────────
    // The host writes these into the config: the view knows nothing of Plasmoid.
    signal fetched(string json, string iso)
    signal guessed(string lat, string lon, string name)

    // ── Location ──────────────────────────────────────────────────────────────
    function num(s) {
        const v = parseFloat(String(s).trim())
        return isFinite(v) ? v : NaN
    }

    // {lat, lon, name}: from the config at start, or looked up from the time zone once.
    property var guess: null
    readonly property bool hasOwn: isFinite(num(latitude)) && isFinite(num(longitude))
    readonly property bool located: hasOwn || guess !== null
    readonly property real lat: hasOwn ? num(latitude) : (guess ? guess.lat : NaN)
    readonly property real lon: hasOwn ? num(longitude) : (guess ? guess.lon : NaN)
    readonly property string place: hasOwn
        ? (placeName.length > 0 ? placeName : latitude.trim() + ", " + longitude.trim())
        : (guess ? guess.name : "")

    readonly property int unitMode: units > 0 ? units
        : (Qt.locale().measurementSystem === Locale.ImperialUSSystem ? 3 : 1)

    // ── State ─────────────────────────────────────────────────────────────────
    property var weather: null          // the last good response, parsed
    property string fetchedAt: ""       // when it came, ISO
    property bool offline: false        // the last request failed
    property int failures: 0
    property var xhr: null              // the request in flight, if any
    property string tzCity: ""          // "Yekaterinburg" for Asia/Yekaterinburg
    property bool guessFailed: false    // the lookup answered, and found nothing
    property bool ready: false          // Component.onCompleted has run

    // Ticks once a minute so the header's "N min ago" moves without any data arriving.
    property real now: Date.now()
    readonly property int ageMinutes: fetchedAt.length > 0
        ? Math.max(0, Math.floor((now - Date.parse(fetchedAt)) / 60000)) : -1

    Timer {
        id: clock
        interval: 60000
        repeat: true
        running: true
        onTriggered: view.now = Date.now()
    }

    // One request every 15 minutes; after a failure 1, 2, 4, 8 and then 15 minutes.
    Timer {
        id: refresh
        onTriggered: view.fetch()
    }

    // ⚠️ Qt's XMLHttpRequest ignores its timeout property (verified 2026-09-23): the
    // request is aborted by hand, and the handler then sees readyState DONE with status 0,
    // the same as any failed request.
    Timer {
        id: watchdog
        interval: 10000
        onTriggered: { if (view.xhr) view.xhr.abort() }
    }

    // The time zone's city, from Plasma's time engine — connected only while a guess is
    // needed, that is on a first run with no location set. Its "Timezone City" is the part
    // after the region ("Yekaterinburg"); zones like Etc/GMT+5 give nothing usable, and the
    // lookup then finds nothing, which is the "set a location" line.
    P5Support.DataSource {
        engine: "time"
        interval: 0
        connectedSources: (view.located || view.guessFailed) ? [] : ["Local"]
        onNewData: function(source, data) {
            const city = String(data["Timezone City"] || "").split("/").pop().replace(/_/g, " ").trim()
            if (city.length > 0 && view.tzCity !== city) {
                view.tzCity = city
                if (view.ready)
                    view.fetch()
            }
        }
    }

    Component.onCompleted: {
        const g = { lat: num(guessedLat), lon: num(guessedLon), name: guessedName }
        if (isFinite(g.lat) && isFinite(g.lon))
            guess = g
        if (cachedJson.length > 0) {
            try {
                const d = JSON.parse(cachedJson)
                if (d && d.current && d.daily && d.daily.time) {
                    weather = d
                    fetchedAt = cachedTime
                }
            } catch (e) {
                // A cache that does not parse is no cache.
            }
        }
        ready = true
        fetch()
    }

    // Settings changed under a running widget: ask again with the new values. Deferred, so
    // a dialog that writes several keys at once ends in one request, not one per key.
    function refetch() {
        if (ready)
            Qt.callLater(fetch)
    }
    // Another place: what is shown is that other place's weather, so it goes, and until
    // the answer comes the widget says "no data yet" rather than showing the wrong rows.
    function moved() {
        if (!ready)
            return
        weather = null
        fetchedAt = ""
        // The cache in the config is that other place's too: the host writes it empty.
        fetched("", "")
        refetch()
    }
    onLatChanged: moved()
    onLonChanged: moved()
    onUnitModeChanged: refetch()
    onDaysChanged: {
        if (weather === null || days > weather.daily.time.length)
            refetch()
    }

    // ── Requests ──────────────────────────────────────────────────────────────
    // One request in flight at a time; a new one supersedes it — the old handler finds it
    // is no longer view.xhr and does nothing — so a burst of changes ends with the final
    // values. The handler gets the parsed body, or null, with the status and the raw text.
    function begin(url, handler) {
        if (xhr !== null) {
            const old = xhr
            xhr = null
            old.abort()
        }
        const req = new XMLHttpRequest()
        xhr = req
        req.onreadystatechange = function() {
            // ⚠️ Reading status before DONE throws.
            if (req.readyState !== XMLHttpRequest.DONE || view.xhr !== req)
                return
            view.xhr = null
            watchdog.stop()
            let data = null
            if (req.status === 200) {
                try {
                    data = JSON.parse(req.responseText)
                } catch (e) {
                    data = null
                }
            }
            handler(data, req.status, req.responseText)
        }
        req.open("GET", url)
        req.send()
        watchdog.restart()
    }

    function schedule() {
        const backoff = [1, 2, 4, 8, 15]
        refresh.interval = (failures === 0 ? 15 : backoff[Math.min(failures, backoff.length) - 1]) * 60000
        refresh.restart()
    }

    function forecastQuery() {
        let q = forecastUrl + "?latitude=" + lat + "&longitude=" + lon
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            + "&forecast_days=" + Math.max(1, Math.min(7, days)) + "&timezone=auto"
        if (unitMode === 3)
            q += "&temperature_unit=fahrenheit&wind_speed_unit=mph"
        else if (unitMode === 2)
            q += "&wind_speed_unit=ms"
        return q
    }

    function fetch() {
        if (!located) {
            if (tzCity.length > 0 && !guessFailed)
                locate()
            return
        }
        begin(forecastQuery(), function(data, status, text) {
            if (data && data.current && data.daily && data.daily.time) {
                view.weather = data
                view.fetchedAt = new Date().toISOString()
                view.now = Date.now()
                view.offline = false
                view.failures = 0
                view.fetched(text, view.fetchedAt)
            } else {
                view.offline = true
                view.failures++
                // 400 means the request itself is wrong — our bug, not the network's.
                if (status === 400)
                    console.warn("plainweather: the forecast request was rejected:", text)
            }
            view.schedule()
        })
    }

    // The two-letter language for the geocoder, so the place is named as the user would.
    function language() {
        const l = Qt.locale().name.split("_")[0].toLowerCase()
        return /^[a-z]{2}$/.test(l) ? l : "en"
    }

    // The largest place of that name: a time zone is named after the big city.
    function best(results) {
        if (!Array.isArray(results) || results.length === 0)
            return null
        return results.slice().sort((a, b) => (b.population || 0) - (a.population || 0))[0]
    }

    function locate() {
        begin(geocodingUrl + "?name=" + encodeURIComponent(tzCity) + "&count=5&language=" + language(),
              function(data, status, text) {
            if (data !== null) {
                const hit = view.best(data.results)
                if (hit) {
                    view.failures = 0
                    view.guess = { lat: hit.latitude, lon: hit.longitude, name: hit.name }
                    view.guessed(String(hit.latitude), String(hit.longitude), hit.name)
                    // Now located: the coordinates changed, and that asks for the forecast.
                } else {
                    view.guessFailed = true
                }
            } else {
                view.failures++
                view.schedule()
            }
        })
    }

    // ── Formatting ────────────────────────────────────────────────────────────
    // Written here, not through a Formatter: the ready-made ones insert invisible
    // U+2009/U+200B characters and the monospace columns drift (docs/GOTCHAS.md). The
    // unit labels are ours too — the response carries its own ("mp/h"), never shown.

    function deg(x) {
        return Math.round(x) + "°"
    }

    // The wind unit, mapped from what the response says it used, so a cached response in
    // the old units is labelled right until the new one arrives.
    function windUnit(d) {
        const u = (d && d.current_units) ? String(d.current_units.wind_speed_10m) : ""
        if (u === "m/s" || (u === "" && unitMode === 2))
            return i18nc("wind speed unit", "m/s")
        if (u === "mp/h" || u === "mph" || (u === "" && unitMode === 3))
            return i18nc("wind speed unit", "mph")
        return i18nc("wind speed unit", "km/h")
    }

    function compass(deg) {
        const names = [i18nc("compass point", "N"), i18nc("compass point", "NE"),
                       i18nc("compass point", "E"), i18nc("compass point", "SE"),
                       i18nc("compass point", "S"), i18nc("compass point", "SW"),
                       i18nc("compass point", "W"), i18nc("compass point", "NW")]
        const d = parseFloat(deg)
        return isFinite(d) ? names[Math.round(d / 45) % 8] : ""
    }

    // WMO weather code → a word.
    function condition(code) {
        if (code === null || code === undefined)
            return "—"
        switch (Number(code)) {
        case 0: return i18nc("weather condition", "clear")
        case 1: return i18nc("weather condition", "mostly clear")
        case 2: return i18nc("weather condition", "partly cloudy")
        case 3: return i18nc("weather condition", "overcast")
        case 45: return i18nc("weather condition", "fog")
        case 48: return i18nc("weather condition", "rime fog")
        case 51: return i18nc("weather condition", "light drizzle")
        case 53: return i18nc("weather condition", "drizzle")
        case 55: return i18nc("weather condition", "heavy drizzle")
        case 56: return i18nc("weather condition", "freezing drizzle")
        case 57: return i18nc("weather condition", "heavy freezing drizzle")
        case 61: return i18nc("weather condition", "light rain")
        case 63: return i18nc("weather condition", "rain")
        case 65: return i18nc("weather condition", "heavy rain")
        case 66: return i18nc("weather condition", "freezing rain")
        case 67: return i18nc("weather condition", "heavy freezing rain")
        case 71: return i18nc("weather condition", "light snow")
        case 73: return i18nc("weather condition", "snow")
        case 75: return i18nc("weather condition", "heavy snow")
        case 77: return i18nc("weather condition", "snow grains")
        case 80: return i18nc("weather condition", "light showers")
        case 81: return i18nc("weather condition", "showers")
        case 82: return i18nc("weather condition", "heavy showers")
        case 85: return i18nc("weather condition", "snow showers")
        case 86: return i18nc("weather condition", "heavy snow showers")
        case 95: return i18nc("weather condition", "thunderstorm")
        case 96: return i18nc("weather condition", "thunderstorm with hail")
        case 99: return i18nc("weather condition", "thunderstorm with heavy hail")
        default: return "—"
        }
    }

    // Minutes up to two hours, hours after that.
    function ageText(minutes) {
        if (minutes < 120)
            return i18ncp("how old the shown weather is", "%1 min ago", "%1 min ago", minutes)
        return i18ncp("how old the shown weather is", "%1 h ago", "%1 h ago", Math.floor(minutes / 60))
    }

    // ⚠️ "YYYY-MM-DD" from parts: new Date("2026-09-24") would be UTC midnight, which is
    // the day before west of Greenwich. The weekday's name is the locale's — through
    // toLocaleDateString, since Qt.formatDate takes the C locale (docs/GOTCHAS.md).
    function weekday(iso) {
        const p = String(iso).split("-")
        return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
            .toLocaleDateString(Qt.locale(), "ddd").toLowerCase()
    }

    // Cuts a line of parts to the column width, ending it with an ellipsis. Code points,
    // not UTF-16 units, so a degree sign or a non-Latin name is not cut in half.
    function fit(parts) {
        let left = columns
        const out = []
        for (const p of parts) {
            if (left <= 0)
                break
            const chars = Array.from(p.text)
            if (chars.length <= left) {
                out.push(p)
                left -= chars.length
            } else {
                out.push({ text: chars.slice(0, Math.max(0, left - 1)).join("") + "…", role: p.role })
                left = 0
            }
        }
        return out
    }

    // ── Lines ─────────────────────────────────────────────────────────────────
    // Each line is a list of parts with a role — "fg", "dim", "accent" — as in the
    // monitor and the player.
    readonly property var lines: {
        const out = []
        if (!located) {
            out.push(fit([{ text: i18nc("no location, no guess", "set a location in the widget settings"), role: "dim" }]))
            return out
        }
        let tail = "  " + place
        if (!hasOwn)
            tail += " · " + i18nc("header: the place was guessed from the time zone", "time zone")
        if (weather !== null && ageMinutes >= 60)
            tail += " · " + ageText(ageMinutes)
        if (offline)
            tail += " · " + i18nc("header: the last request failed", "offline")
        out.push(fit([{ text: i18nc("the widget's header line", "WEATHER"), role: "fg" },
                      { text: tail, role: "dim" }]))
        if (weather === null) {
            out.push(fit([{ text: i18nc("nothing fetched yet", "no data yet"), role: "dim" }]))
            return out
        }

        const c = weather.current
        out.push(fit([{ text: deg(c.temperature_2m), role: "accent" },
                      { text: " " + condition(c.weather_code), role: "fg" },
                      { text: "  " + i18nc("apparent temperature", "feels %1", deg(c.apparent_temperature))
                              + "  " + i18nc("wind: speed, its unit, compass direction", "wind %1 %2 %3",
                                             Math.round(c.wind_speed_10m), windUnit(weather), compass(c.wind_direction_10m))
                              + "  " + Math.round(c.relative_humidity_2m) + "%", role: "dim" }]))

        // One row per day, today first; the columns line up across the rows.
        const d = weather.daily
        const rows = []
        for (let i = 0; i < Math.min(days, d.time.length); i++) {
            const prob = d.precipitation_probability_max[i]
            rows.push({ day: weekday(d.time[i]),
                        lo: String(Math.round(d.temperature_2m_min[i])),
                        hi: String(Math.round(d.temperature_2m_max[i])),
                        cond: condition(d.weather_code[i]),
                        prob: (prob === null || prob === undefined) ? "" : Math.round(prob) + "%" })
        }
        const dayW = Math.max(...rows.map(r => Array.from(r.day).length), 0)
        const loW = Math.max(...rows.map(r => r.lo.length), 0)
        const hiW = Math.max(...rows.map(r => r.hi.length), 0)
        for (const r of rows) {
            const parts = [{ text: r.day.padEnd(dayW) + "  ", role: "dim" },
                           { text: r.lo.padStart(loW) + "° / " + r.hi.padStart(hiW) + "°  ", role: "fg" },
                           { text: r.cond, role: "fg" }]
            if (r.prob.length > 0)
                parts.push({ text: "  " + r.prob, role: "dim" })
            out.push(fit(parts))
        }

        if (attribution)
            out.push(fit([{ text: i18nc("Open-Meteo's terms ask for this line", "Weather data by Open-Meteo.com"), role: "dim" }]))
        return out
    }

    function paint(role) {
        switch (role) {
        case "accent": return view.colorAccent
        case "dim": return view.colorDim
        default: return view.colorFg
        }
    }

    // A widget line: monospace text, colour and size set in place.
    component Line: Text {
        color: view.colorFg
        font.family: view.fontFamily
        font.pointSize: view.fontSize
        renderType: Text.NativeRendering
    }

    Column {
        spacing: 0

        // The model is a count, not the array: with a count the delegates stay when the
        // lines are rebuilt, and a Text whose string did not change does nothing
        // (docs/GOTCHAS.md, the Repeater note).
        Repeater {
            model: view.lines.length

            Row {
                id: lineRow
                required property int index
                readonly property var parts: view.lines[index] || []
                spacing: 0

                Repeater {
                    model: lineRow.parts.length

                    Line {
                        required property int index
                        readonly property var part: lineRow.parts[index] || ({ text: "", role: "fg" })
                        text: part.text
                        color: view.paint(part.role)
                    }
                }
            }
        }
    }
}
