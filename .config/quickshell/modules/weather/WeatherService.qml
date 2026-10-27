pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Weather: wttr.in JSON every 15 min → weather. The location preference
// persists to state/weather-location.txt (empty = IP auto-detect).
Singleton {
    id: root

    property var weather: ({
        ready: false,
        city: "", region: "",
        temp: "", feelsLike: "",
        humidity: "", windKph: "",
        description: "",
        icon: "",
        sunrise: "", sunset: "",
        forecast: []
    })
    property string weatherLocation: ""

    function refresh() {
        weatherProc.running = false
        weatherProc.running = true
    }
    function refreshWeather() { refresh() }
    function setWeatherLocation(loc) {
        weatherLocation = (loc || "").trim()
        locationFile.save(weatherLocation)
        refresh()
    }

    StateFile {
        id: locationFile
        name: "weather-location.txt"
        onLoaded: lines => {
            for (const line of lines) root.weatherLocation = line.trim()
            root.refresh()
        }
    }

    // Fetch: wttr.in returns multi-line JSON — buffer, then parse on exit.
    Process {
        id: weatherProc
        property string buffer: ""
        // Empty location = IP auto-detect, else /<city>.
        command: ["sh", "-c",
            "curl -sSf --max-time 8 \"https://wttr.in/$LOC?format=j1\" || true"]
        environment: ({ LOC: encodeURIComponent(root.weatherLocation) })
        onRunningChanged: if (running) buffer = ""
        stdout: SplitParser {
            onRead: line => weatherProc.buffer += line + "\n"
        }
        onExited: (code, status) => {
            const buf = weatherProc.buffer
            if (!buf || buf.length < 50) { root._retryIfEmpty(); return }
            try {
                const j = JSON.parse(buf)
                const cur   = j.current_condition?.[0]
                const area  = j.nearest_area?.[0]
                const astro = j.weather?.[0]?.astronomy?.[0]
                if (!cur) { root._retryIfEmpty(); return }
                const wcode = parseInt(cur.weatherCode)
                root.weather = {
                    ready: true,
                    // nearest_area is wttr.in's closest *listed* place (often a
                    // neighbouring town), so prefer the name the user typed.
                    city:        root.weatherLocation || (area?.areaName?.[0]?.value ?? ""),
                    region:      area?.region?.[0]?.value   ?? "",
                    temp:        cur.temp_C + "°C",
                    feelsLike:   cur.FeelsLikeC + "°C",
                    humidity:    cur.humidity,
                    windKph:     cur.windspeedKmph,
                    description: cur.weatherDesc?.[0]?.value ?? "",
                    icon:        wttrIcon(wcode),
                    sunrise:     astro?.sunrise ?? "",
                    sunset:      astro?.sunset  ?? "",
                    forecast:    (j.weather || []).map(d => ({
                        date:     d.date,
                        icon:     wttrIcon(parseInt(d.hourly?.[4]?.weatherCode ?? wcode)),
                        maxTempC: d.maxtempC,
                        minTempC: d.mintempC,
                        desc:     d.hourly?.[4]?.weatherDesc?.[0]?.value ?? ""
                    }))
                }
                weatherRetry.stop()
            } catch(e) {
                console.log("weather parse failed:", e)
                root._retryIfEmpty()
            }
        }
    }
    // Nothing fetched yet (e.g. offline at login): retry in a minute rather
    // than showing "Loading…" until the next 15-minute refresh.
    function _retryIfEmpty() { if (!root.weather.ready) weatherRetry.restart() }
    Timer { id: weatherRetry; interval: 60 * 1000; onTriggered: root.refresh() }
    // wttr.in WWO weather codes → Nerd Font weather glyphs (nf-weather-*)
    function wttrIcon(code) {
        if (code === 113) return "\ue30d"                                   // clear / sunny
        if ([116].includes(code)) return "\ue302"                           // partly cloudy
        if ([119, 122].includes(code)) return "\ue312"                      // cloudy / overcast
        if ([143, 248, 260].includes(code)) return "\ue313"                 // fog / mist
        if ([200, 386, 389, 392, 395].includes(code)) return "\ue31d"       // thunder
        if ([179, 182, 185, 227, 230, 320, 323, 326, 329, 332, 335,
             338, 350, 362, 365, 368, 371, 374, 377].includes(code)) return "\ue31a" // snow / sleet
        if ([176, 263, 266, 281, 284, 293, 296, 299, 302, 305, 308,
             311, 314, 353, 356, 359].includes(code)) return "\ue318"          // rain
        return "\ue312"
    }

    // The first fetch runs once the saved location has loaded (locationFile);
    // firing on start too sent a wasted location-less request every launch.
    Timer {
        id: weatherTimer
        interval: 15 * 60 * 1000; repeat: true; running: true
        onTriggered: root.refresh()
    }
}
