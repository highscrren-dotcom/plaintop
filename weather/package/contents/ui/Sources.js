.pragma library

// The weather sources, behind one shape. A source builds its request from the place, the
// number of days and the key, and turns the answer into the common shape:
//
//   { current: { temp, feels, code, wind, windDir, humidity },
//     daily:   [ { date: "YYYY-MM-DD", min, max, code, pop }, … ] }
//
// Metric throughout — °C, km/h, % — the view converts to the units the user chose; `code`
// is a WMO weather code, so the view's one word table serves every source; a field a source
// does not have is null, and the view leaves it out. Nothing here touches the network or
// the widget: build() returns { url, headers }, parse() takes the parsed body.
//
// No i18n here — a library has no context — so the names and attribution lines shown to
// the user live in the QML that shows them (WeatherView.qml, configLocation.qml).

var ids = ["open-meteo", "met-no", "weatherapi", "visual-crossing"]

// Number or null: a missing, empty or non-numeric field is "not given", never 0.
function num(v) {
    if (v === null || v === undefined || v === "")
        return null
    const x = Number(v)
    return isFinite(x) ? x : null
}

function maxOf(a, b) {
    if (a === null) return b
    if (b === null) return a
    return Math.max(a, b)
}

function pad2(n) {
    return (n < 10 ? "0" : "") + n
}

// "YYYY-MM-DD" of an instant shifted by the place's UTC offset: the UTC getters on the
// shifted time are the place's local date, whatever the machine's zone.
function localDate(ms, utcOffsetMin) {
    const d = new Date(ms + utcOffsetMin * 60000)
    return d.getUTCFullYear() + "-" + pad2(d.getUTCMonth() + 1) + "-" + pad2(d.getUTCDate())
}

function offsetOf(opts) {
    return (opts && isFinite(opts.utcOffsetMin)) ? opts.utcOffsetMin : 0
}

// ── Open-Meteo ────────────────────────────────────────────────────────────────
// Current conditions and the daily summary in one answer, already cut into the place's
// days (timezone=auto) and already WMO-coded. No key; free for non-commercial use.
var openMeteo = {
    id: "open-meteo",
    needsKey: false,
    maxDays: 7,
    refreshMin: 15,
    // Open-Meteo can be self-hosted with the same paths.
    base: "https://api.open-meteo.com/v1/forecast",
    build: function(lat, lon, days, key, opts) {
        return { url: this.base + "?latitude=" + lat + "&longitude=" + lon
                      + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m"
                      + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
                      + "&forecast_days=" + days + "&timezone=auto",
                 headers: {} }
    },
    parse: function(d, days, opts) {
        if (!d || !d.current || !d.daily || !Array.isArray(d.daily.time))
            return null
        const c = d.current, t = d.daily
        const daily = []
        for (let i = 0; i < Math.min(days, t.time.length); i++) {
            daily.push({ date: String(t.time[i]),
                         min: num(t.temperature_2m_min && t.temperature_2m_min[i]),
                         max: num(t.temperature_2m_max && t.temperature_2m_max[i]),
                         code: num(t.weather_code && t.weather_code[i]),
                         pop: num(t.precipitation_probability_max && t.precipitation_probability_max[i]) })
        }
        return { current: { temp: num(c.temperature_2m), feels: num(c.apparent_temperature), code: num(c.weather_code),
                            wind: num(c.wind_speed_10m), windDir: num(c.wind_direction_10m), humidity: num(c.relative_humidity_2m) },
                 daily: daily }
    }
}

// ── MET Norway ────────────────────────────────────────────────────────────────
// Locationforecast 2.0: a time series in UTC — hourly for the first two or three days,
// then every six hours — each entry with the instant and the periods that start there
// (next_1_hours, next_6_hours, next_12_hours), each period with a symbol and, in the
// Nordic countries only, a probability of precipitation. `complete` rather than `compact`:
// where the series thins out to six hours, the compact form has four temperatures a day
// and misses the afternoon's peak, while complete carries each six-hour block's
// air_temperature_min/max. The parser works with both.
//
// Their terms: a User-Agent that names the application (the default one gets a 403), at
// most four decimals in the coordinates, and no request before the answer's Expires — the
// view keeps the last Last-Modified and sends it back as If-Modified-Since; a 304 costs
// no body.
var metNo = {
    id: "met-no",
    needsKey: false,
    maxDays: 7,
    refreshMin: 15,
    base: "https://api.met.no/weatherapi/locationforecast/2.0/complete",
    userAgent: "plainweather/0.1 github.com/highscrren-dotcom/plaintop",
    build: function(lat, lon, days, key, opts) {
        const r4 = x => Math.round(x * 10000) / 10000
        return { url: this.base + "?lat=" + r4(lat) + "&lon=" + r4(lon),
                 headers: { "User-Agent": this.userAgent } }
    },
    // Symbol → WMO code. The suffix (_day, _night, _polartwilight) is the icon's, not the
    // weather's. Sleet is the freezing-rain family (66/67); MET has no hail symbol, so
    // every thunder variant is 95 — including the two with a typo in MET's own list
    // (lightssleetshowersandthunder, lightssnowshowersandthunder), caught by the fallback.
    symbolToWmo: function(sym) {
        if (!sym)
            return null
        const s = String(sym).replace(/_(day|night|polartwilight)$/, "")
        const table = {
            clearsky: 0, fair: 1, partlycloudy: 2, cloudy: 3, fog: 45,
            lightrainshowers: 80, rainshowers: 81, heavyrainshowers: 82,
            lightrain: 61, rain: 63, heavyrain: 65,
            lightsleet: 66, sleet: 66, heavysleet: 67,
            lightsleetshowers: 66, sleetshowers: 66, heavysleetshowers: 67,
            lightsnow: 71, snow: 73, heavysnow: 75,
            lightsnowshowers: 85, snowshowers: 85, heavysnowshowers: 86
        }
        if (s in table)
            return table[s]
        if (s.indexOf("thunder") >= 0)
            return 95
        return null
    },
    parse: function(d, days, opts) {
        const ts = (d && d.properties && Array.isArray(d.properties.timeseries)) ? d.properties.timeseries : null
        if (!ts || ts.length === 0)
            return null
        const off = offsetOf(opts)
        const self = this
        const period = function(e, name) {
            return (e.data && e.data[name]) ? e.data[name] : null
        }
        const symbolOf = function(p) {
            return (p && p.summary) ? self.symbolToWmo(p.summary.symbol_code) : null
        }
        const popOf = function(p) {
            return (p && p.details) ? num(p.details.probability_of_precipitation) : null
        }
        // The series is cut at the hour of the request, so on a body kept for a while
        // (a 304 parses the last 200 again) the first entries are past: the parse starts
        // at the entry covering this hour, and "now" and the days follow the clock.
        let start = ts.findIndex(e => Date.parse(e.time) > Date.now() - 3600000)
        if (start < 0)
            start = 0
        // Now: that entry — its instant, and the symbol of the hour ahead, or of the
        // six hours where the series has no hourly period. Wind comes in m/s.
        const first = ts[start]
        const inst0 = (first.data && first.data.instant && first.data.instant.details) ? first.data.instant.details : {}
        const wind = num(inst0.wind_speed)
        const p0 = period(first, "next_1_hours") || period(first, "next_6_hours") || period(first, "next_12_hours")
        const current = { temp: num(inst0.air_temperature), feels: null, code: symbolOf(p0),
                          wind: wind === null ? null : Math.round(wind * 3.6 * 10) / 10,
                          windDir: num(inst0.wind_from_direction), humidity: num(inst0.relative_humidity) }
        // Days: the entries grouped by the place's local date. An entry's instant goes to
        // its own date; where there is an hourly period, its symbol goes there too; where
        // there is none (the six-hourly tail), the six-hour block's symbol and min/max go
        // to the date of the block's middle, three hours in. A day's code is the most
        // severe of its symbols — the highest WMO code, as Open-Meteo's daily code is —
        // and its pop the highest given.
        const byDate = {}
        const order = []
        const day = function(date) {
            if (!(date in byDate)) {
                byDate[date] = { date: date, min: null, max: null, code: null, pop: null }
                order.push(date)
            }
            return byDate[date]
        }
        const take = function(row, temp, code, pop) {
            if (temp !== null) {
                row.min = row.min === null ? temp : Math.min(row.min, temp)
                row.max = row.max === null ? temp : Math.max(row.max, temp)
            }
            if (code !== null && (row.code === null || code > row.code))
                row.code = code
            if (pop !== null && (row.pop === null || pop > row.pop))
                row.pop = pop
        }
        for (const e of ts.slice(start)) {
            const t = Date.parse(e.time)
            if (!isFinite(t))
                continue
            const inst = (e.data && e.data.instant && e.data.instant.details) ? e.data.instant.details : {}
            const hour = period(e, "next_1_hours")
            const six = period(e, "next_6_hours")
            const here = day(localDate(t, off))
            take(here, num(inst.air_temperature), symbolOf(hour), popOf(hour))
            if (!hour && six) {
                const mid = day(localDate(t + 3 * 3600000, off))
                take(mid, num(six.details && six.details.air_temperature_min), symbolOf(six), popOf(six))
                take(mid, num(six.details && six.details.air_temperature_max), null, null)
            }
        }
        return { current: current, daily: order.slice(0, days).map(x => byDate[x]) }
    }
}

// ── WeatherAPI.com ────────────────────────────────────────────────────────────
// forecast.json: current conditions and one block per day, with the source's own
// condition codes. A key is required; the free plan answers with three forecast days
// whatever is asked, so the request asks for three at most. An invalid key is a 401, a
// disabled one or an exhausted quota a 403 — the view shows "bad key" for both.
var weatherApi = {
    id: "weatherapi",
    needsKey: true,
    maxDays: 3,
    refreshMin: 15,
    base: "https://api.weatherapi.com/v1/forecast.json",
    build: function(lat, lon, days, key, opts) {
        return { url: this.base + "?key=" + encodeURIComponent(key) + "&q=" + lat + "," + lon + "&days=" + days,
                 headers: {} }
    },
    // WeatherAPI condition code → WMO.
    codes: {
        1000: 0, 1003: 2, 1006: 3, 1009: 3, 1030: 45, 1063: 80, 1066: 85, 1069: 66, 1072: 56, 1087: 95,
        1114: 73, 1117: 75, 1135: 45, 1147: 48, 1150: 51, 1153: 53, 1168: 56, 1171: 57,
        1180: 61, 1183: 61, 1186: 63, 1189: 63, 1192: 65, 1195: 65, 1198: 66, 1201: 67, 1204: 66, 1207: 67,
        1210: 71, 1213: 71, 1216: 73, 1219: 73, 1222: 75, 1225: 75, 1237: 77,
        1240: 80, 1243: 81, 1246: 82, 1249: 66, 1252: 67, 1255: 85, 1258: 86, 1261: 77, 1264: 77,
        1273: 95, 1276: 96, 1279: 95, 1282: 99
    },
    toWmo: function(code) {
        const c = num(code)
        return (c !== null && c in this.codes) ? this.codes[c] : null
    },
    parse: function(d, days, opts) {
        if (!d || !d.current || !d.forecast || !Array.isArray(d.forecast.forecastday))
            return null
        const c = d.current
        const current = { temp: num(c.temp_c), feels: num(c.feelslike_c), code: this.toWmo(c.condition && c.condition.code),
                          wind: num(c.wind_kph), windDir: num(c.wind_degree), humidity: num(c.humidity) }
        const daily = d.forecast.forecastday.slice(0, days).map(f => {
            const x = f.day || {}
            return { date: String(f.date), min: num(x.mintemp_c), max: num(x.maxtemp_c),
                     code: this.toWmo(x.condition && x.condition.code),
                     // Rain or snow: the chance of either is the chance of precipitation.
                     pop: maxOf(num(x.daily_chance_of_rain), num(x.daily_chance_of_snow)) }
        })
        return { current: current, daily: daily }
    }
}

// ── Visual Crossing ───────────────────────────────────────────────────────────
// The Timeline API, metric, days and current conditions. A key is required; the free
// plan is a thousand records a day and every day in an answer is one, so the request
// names its dates — without them the answer is fifteen days. An unknown key is a 401.
var visualCrossing = {
    id: "visual-crossing",
    needsKey: true,
    maxDays: 7,
    refreshMin: 30,
    base: "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline/",
    build: function(lat, lon, days, key, opts) {
        const off = offsetOf(opts)
        const now = Date.now()
        const from = localDate(now, off)
        const to = localDate(now + (days - 1) * 86400000, off)
        return { url: this.base + lat + "," + lon + "/" + from + "/" + to
                      + "?unitGroup=metric&include=days,current&key=" + encodeURIComponent(key) + "&contentType=json",
                 headers: {} }
    },
    // Icon → WMO. "wind" has no WMO code: partly cloudy stands in.
    icons: {
        "clear-day": 0, "clear-night": 0, "partly-cloudy-day": 2, "partly-cloudy-night": 2, "cloudy": 3,
        "fog": 45, "wind": 2, "rain": 63, "showers-day": 81, "showers-night": 81,
        "snow": 73, "snow-showers-day": 85, "snow-showers-night": 85,
        "sleet": 66, "rain-snow": 66, "rain-snow-showers-day": 66, "rain-snow-showers-night": 66,
        "thunder-rain": 95, "thunder-showers-day": 95, "thunder-showers-night": 95, "hail": 96
    },
    toWmo: function(icon) {
        const s = String(icon || "")
        return (s in this.icons) ? this.icons[s] : null
    },
    parse: function(d, days, opts) {
        if (!d || !Array.isArray(d.days))
            return null
        const c = d.currentConditions || {}
        const current = { temp: num(c.temp), feels: num(c.feelslike), code: this.toWmo(c.icon),
                          wind: num(c.windspeed), windDir: num(c.winddir), humidity: num(c.humidity) }
        const daily = d.days.slice(0, days).map(x => ({
            date: String(x.datetime), min: num(x.tempmin), max: num(x.tempmax),
            code: this.toWmo(x.icon), pop: num(x.precipprob) }))
        return { current: current, daily: daily }
    }
}

var all = [openMeteo, metNo, weatherApi, visualCrossing]

// The source by id; an unknown id is the default, so a stale config still shows weather.
function get(id) {
    for (const s of all) {
        if (s.id === id)
            return s
    }
    return openMeteo
}

// A parsed answer that the view can draw.
function valid(w) {
    return !!(w && w.current && Array.isArray(w.daily))
}
