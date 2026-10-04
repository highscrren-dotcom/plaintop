// Stand for the weather sources: does Sources.js turn each API's answer into the one shape
// the view draws, and build the request each source wants?
//
// What it checks. Sources.js (weather/package/contents/ui/) is plain JavaScript with no
// network and no widget in it: build() returns a URL and headers, parse() takes a parsed
// body. Four answers shaped like the real ones — Open-Meteo, MET Norway, WeatherAPI.com,
// Visual Crossing — are parsed and read back: temperatures, codes mapped to WMO, the
// chance of precipitation, the days cut to what was asked, a field a source lacks left
// null; MET's series grouped by the place's date and started at the current hour; the
// User-Agent MET demands, the key encoded in the URL, Visual Crossing's dates named.
//
// How to run: ./install.sh --check-weather, or by hand from the repo root
//   QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/weather.qml
// /usr/bin/qmltestrunner is the Qt 5 runner and cannot read a Qt 6 qmldir. Nothing of
// Plasma is imported here: QtQuick and QtTest are enough.
//
// ⚠️ Written 2026-10-05 in a container without Qt; the same fixtures and assertions were run
// against Sources.js under Node there, so the logic is checked — the Qt run is the PC's.

import QtQuick
import QtTest
import "../weather/package/contents/ui/Sources.js" as Sources

TestCase {
    name: "WeatherSources"

    // ── Fixtures ──────────────────────────────────────────────────────────────
    readonly property var openMeteo: ({
        current: { temperature_2m: 12.3, relative_humidity_2m: 71, apparent_temperature: 10.1,
                   weather_code: 3, wind_speed_10m: 14.4, wind_direction_10m: 230 },
        daily: { time: ["2026-10-05", "2026-10-06", "2026-10-07"],
                 weather_code: [3, 61, 0],
                 temperature_2m_max: [14.2, 11.0, 15.5],
                 temperature_2m_min: [6.1, 5.5, 4.0],
                 precipitation_probability_max: [10, 80, null] }
    })

    readonly property var weatherApi: ({
        current: { temp_c: 20, feelslike_c: 19, condition: { code: 1003 }, wind_kph: 10, wind_degree: 90, humidity: 50 },
        forecast: { forecastday: [
            { date: "2026-10-05", day: { mintemp_c: 9, maxtemp_c: 21, condition: { code: 1183 }, daily_chance_of_rain: 70, daily_chance_of_snow: 0 } },
            { date: "2026-10-06", day: { mintemp_c: 8, maxtemp_c: 18, condition: { code: 1210 }, daily_chance_of_rain: 10, daily_chance_of_snow: 40 } },
            { date: "2026-10-07", day: { mintemp_c: 7, maxtemp_c: 17, condition: { code: 9999 } } }
        ] }
    })

    readonly property var visualCrossing: ({
        currentConditions: { temp: 5, feelslike: 2, icon: "rain", windspeed: 20, winddir: 180, humidity: 90 },
        days: [
            { datetime: "2026-10-05", tempmin: 1, tempmax: 8, icon: "snow", precipprob: 60 },
            { datetime: "2026-10-06", tempmin: 2, tempmax: 9, icon: "wind", precipprob: 0 },
            { datetime: "2026-10-07", tempmin: 3, tempmax: 10, icon: "something-new" }
        ]
    })

    // MET's series is cut at the hour of the request, so its times are made from now:
    // one entry two hours back (to be skipped), the current hour, two more hourly ones,
    // and a six-hourly block a day ahead with only next_6_hours.
    function metSeries() {
        const base = Math.floor(Date.now() / 3600000) * 3600000
        const at = h => new Date(base + h * 3600000).toISOString()
        const hourly = (h, temp, sym, pop) => ({
            time: at(h),
            data: { instant: { details: { air_temperature: temp, wind_speed: 5, wind_from_direction: 270, relative_humidity: 80 } },
                    next_1_hours: { summary: { symbol_code: sym }, details: { probability_of_precipitation: pop } } }
        })
        return { base: base, body: { properties: { timeseries: [
            hourly(-2, 99, "clearsky_day", 0),
            hourly(0, 11, "lightrainshowers_day", 20),
            hourly(1, 12, "rain", 60),
            hourly(2, 9, "fair_night", null),
            { time: at(24), data: { instant: { details: { air_temperature: 4 } },
                                    next_6_hours: { summary: { symbol_code: "snow" },
                                                    details: { air_temperature_min: 2, air_temperature_max: 9, probability_of_precipitation: 75 } } } }
        ] } } }
    }

    // ── Open-Meteo ────────────────────────────────────────────────────────────
    function test_01_open_meteo_parses_and_cuts_the_days() {
        const s = Sources.get("open-meteo")
        const w = s.parse(openMeteo, 2, {})
        verify(Sources.valid(w), "a drawable shape")
        compare(w.current.temp, 12.3); compare(w.current.feels, 10.1); compare(w.current.code, 3)
        compare(w.current.wind, 14.4); compare(w.current.windDir, 230); compare(w.current.humidity, 71)
        compare(w.daily.length, 2, "cut to the days asked")
        compare(w.daily[1].date, "2026-10-06"); compare(w.daily[1].code, 61); compare(w.daily[1].pop, 80)
        const all = s.parse(openMeteo, 7, {})
        compare(all.daily.length, 3, "no more days than the answer has")
        compare(all.daily[2].pop, null, "a missing probability is null, not 0")
        compare(s.parse({}, 3, {}), null, "an answer without current or daily is refused")
        compare(s.parse(null, 3, {}), null)
    }

    function test_02_open_meteo_builds_its_request() {
        const r = Sources.get("open-meteo").build(55.75, 37.62, 5, "", {})
        verify(r.url.indexOf("latitude=55.75&longitude=37.62") > 0, r.url)
        verify(r.url.indexOf("forecast_days=5") > 0 && r.url.indexOf("timezone=auto") > 0, r.url)
        compare(Object.keys(r.headers).length, 0, "no headers")
        compare(Sources.get("open-meteo").needsKey, false)
    }

    // ── MET Norway ────────────────────────────────────────────────────────────
    function test_03_met_symbols_to_wmo() {
        const m = Sources.get("met-no")
        compare(m.symbolToWmo("lightrainshowers_day"), 80, "the suffix is the icon's, not the weather's")
        compare(m.symbolToWmo("heavysnow_polartwilight"), 75)
        compare(m.symbolToWmo("lightssleetshowersandthunder"), 95, "MET's own typo lands on thunder")
        compare(m.symbolToWmo("rainandthunder"), 95)
        compare(m.symbolToWmo("sleet"), 66)
        compare(m.symbolToWmo("nosuchsymbol"), null)
        compare(m.symbolToWmo(null), null)
    }

    function test_04_met_parses_the_series_from_the_current_hour() {
        const fx = metSeries()
        const w = Sources.get("met-no").parse(fx.body, 7, { utcOffsetMin: 0 })
        verify(Sources.valid(w))
        compare(w.current.temp, 11, "the entry of the current hour, not the past one")
        compare(w.current.code, 80, "the hour ahead's symbol")
        compare(w.current.wind, 18, "m/s to km/h: 5 → 18")
        compare(w.current.feels, null, "MET has no feels-like")
        compare(w.current.humidity, 80)
        const today = Sources.localDate(fx.base, 0)
        const first = w.daily[0]
        compare(first.date, today, "the days start at the place's date of now")
        verify(first.max >= 11 && first.min <= 11, "min/max cover the hourly temperatures: " + JSON.stringify(first))
        verify(first.code >= 63 || w.daily.length > 1, "the most severe symbol of the day: " + JSON.stringify(first))
        // The six-hour block a day ahead: its min/max and symbol go to the block's middle.
        const mid = Sources.localDate(fx.base + 27 * 3600000, 0)
        let found = null
        for (let i = 0; i < w.daily.length; i++) if (w.daily[i].date === mid) found = w.daily[i]
        verify(found !== null, "the six-hourly block has a day: " + JSON.stringify(w.daily))
        compare(found.min, 2); compare(found.max, 9); compare(found.code, 73); compare(found.pop, 75)
        verify(w.daily.length <= 7)
        compare(Sources.get("met-no").parse({ properties: { timeseries: [] } }, 3, {}), null, "an empty series is refused")
    }

    function test_05_met_builds_with_a_user_agent_and_four_decimals() {
        const r = Sources.get("met-no").build(55.751244, 37.618423, 3, "", {})
        verify(r.url.indexOf("lat=55.7512&lon=37.6184") > 0, r.url)
        verify(/^plainweather\//.test(r.headers["User-Agent"]), "MET answers 403 to the default agent")
    }

    // ── WeatherAPI.com ────────────────────────────────────────────────────────
    function test_06_weatherapi_maps_codes_and_takes_rain_or_snow() {
        const s = Sources.get("weatherapi")
        const w = s.parse(weatherApi, 2, {})
        compare(w.current.temp, 20); compare(w.current.code, 2, "1003 partly cloudy → 2")
        compare(w.current.wind, 10); compare(w.current.humidity, 50)
        compare(w.daily.length, 2)
        compare(w.daily[0].code, 61, "1183 light rain → 61"); compare(w.daily[0].pop, 70)
        compare(w.daily[1].code, 71, "1210 patchy snow → 71"); compare(w.daily[1].pop, 40, "the higher of rain and snow")
        const all = s.parse(weatherApi, 3, {})
        compare(all.daily[2].code, null, "an unknown code is null"); compare(all.daily[2].pop, null)
        compare(s.maxDays, 3, "the free plan answers three days")
        compare(s.needsKey, true)
        const r = s.build(1.5, 2.5, 3, "k e&y", {})
        verify(r.url.indexOf("key=k%20e%26y") > 0, "the key is URL-encoded: " + r.url)
        verify(r.url.indexOf("q=1.5,2.5&days=3") > 0, r.url)
    }

    // ── Visual Crossing ───────────────────────────────────────────────────────
    function test_07_visual_crossing_maps_icons_and_names_its_dates() {
        const s = Sources.get("visual-crossing")
        const w = s.parse(visualCrossing, 3, {})
        compare(w.current.temp, 5); compare(w.current.code, 63, "rain → 63"); compare(w.current.windDir, 180)
        compare(w.daily[0].code, 73, "snow → 73"); compare(w.daily[0].pop, 60)
        compare(w.daily[1].code, 2, "wind has no WMO code: partly cloudy stands in")
        compare(w.daily[2].code, null, "an unknown icon is null"); compare(w.daily[2].pop, null)
        compare(s.parse(visualCrossing, 1, {}).daily.length, 1)
        compare(s.parse({ currentConditions: {} }, 3, {}), null, "no days, no answer")
        const r = s.build(10, 20, 3, "KEY", { utcOffsetMin: 0 })
        const from = Sources.localDate(Date.now(), 0)
        const to = Sources.localDate(Date.now() + 2 * 86400000, 0)
        verify(r.url.indexOf("/10,20/" + from + "/" + to + "?") > 0, "the dates are named, or the answer is fifteen days: " + r.url)
        verify(r.url.indexOf("include=days,current") > 0 && r.url.indexOf("key=KEY") > 0, r.url)
        compare(s.refreshMin, 30, "the free plan counts records: refresh less often")
    }

    // ── The module itself ─────────────────────────────────────────────────────
    function test_08_helpers_and_the_default_source() {
        compare(Sources.get("no-such-source").id, "open-meteo", "an unknown id falls back to the default")
        compare(Sources.ids.length, 4)
        compare(Sources.valid(null), false)
        compare(Sources.valid({ current: {}, daily: [] }), true)
        compare(Sources.valid({ current: {} }), false)
        compare(Sources.localDate(0, 0), "1970-01-01")
        compare(Sources.localDate(Date.UTC(2026, 9, 5, 23, 30), 180), "2026-10-06", "the place's date, three hours east")
        compare(Sources.localDate(Date.UTC(2026, 9, 5, 1, 30), -300), "2026-10-04", "five hours west")
        compare(Sources.num(""), null); compare(Sources.num("12.5"), 12.5); compare(Sources.num("x"), null); compare(Sources.num(0), 0)
        compare(Sources.maxOf(null, 3), 3); compare(Sources.maxOf(4, null), 4); compare(Sources.maxOf(4, 7), 7); compare(Sources.maxOf(null, null), null)
    }
}
