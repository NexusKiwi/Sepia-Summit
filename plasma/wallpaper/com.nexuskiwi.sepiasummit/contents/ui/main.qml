// Sepia Summit (live) — Plasma 6 wallpaper
// Layers, back to front:
//   1. the full wallpaper image
//   2. the sun at its real position (and the moon's disc during a solar eclipse), then weather in the
//      sky (clouds, overcast deck), all masked by *_sky.png so they stay behind the peaks
//   3. audio visualiser bars, their base hidden down in the valley (Baseline)
//   4. a cut-out of the nearer ridges (the *_front.png), so bars rise from behind them
//   3a. seasonal snow on the far peaks: the wallpaper brightened, through *_snow.png with a moving threshold
//   4a. valley mist, then trees on the nearer hills (positions from ../code/scene.js), swaying in the wind
//   5. light: overcast dimming, dawn/dusk glow, night; then moon and stars (sky only), fog, rain/snow,
//      lightning, and the seasonal particles (fireflies, autumn leaves, pollen, snow blowing off peaks)
// Audio levels come from sepia-cava-server on 127.0.0.1 (the lock screen blocks all network
// access, so the bars only move on the desktop). The weather is loaded from the QML copy that
// sepia-weather writes to ~/.cache, which works on the lock screen too. Day and night follow
// the real sun position at the weather location, so sunrise, sunset and DST just work.
// With Span on, Background/Foreground are one image for the whole desktop and each
// monitor shows its own slice of it. The lock screen uses this, because it gives
// every monitor the same settings. The bars then show on the rightmost monitor only.
import QtCore
import QtQuick
import QtQuick.Effects
import QtQuick.Particles
import QtQuick.Window
import org.kde.plasma.plasmoid
import "../code/scene.js" as Scene

WallpaperItem {
    id: root

    readonly property string bgSource: configuration.Background || ""
    readonly property string fgSource: configuration.Foreground || ""
    readonly property bool visualiser: configuration.Visualiser !== false
    readonly property int barCount: Math.max(8, configuration.BarCount || 96)
    readonly property real valleyLine: (configuration.Baseline || 80) / 100
    readonly property real maxHeight: (configuration.MaxHeight || 42) / 100
    readonly property real barOpacity: (configuration.BarOpacity === undefined ? 50 : configuration.BarOpacity) / 100
    readonly property color barColor: configuration.BarColor || "#f5e6c8"
    readonly property bool glow: configuration.Glow !== false
    readonly property string endpoint: "http://127.0.0.1:" + (configuration.Port || 37421) + "/"
    readonly property bool weatherOn: configuration.Weather !== false
    readonly property bool dayNightOn: configuration.DayNight !== false
    readonly property bool seasonsOn: configuration.Seasons !== false
    readonly property string skySource: bgSource.replace(/\.png$/, "_sky.png")
    readonly property string snowSource: bgSource.replace(/\.png$/, "_snow.png")

    // The desktop's extent, from every monitor's position (logical pixels).
    readonly property bool span: configuration.Span === true
    readonly property var desk: {
        const ss = Qt.application.screens
        let l = Infinity, r = -Infinity
        for (let i = 0; i < ss.length; i++) {
            l = Math.min(l, ss[i].virtualX)
            r = Math.max(r, ss[i].virtualX + ss[i].width)
        }
        return ss.length ? { left: l, right: r } : { left: 0, right: width }
    }
    readonly property real sliceX: span ? desk.left - Screen.virtualX : 0
    readonly property real sliceW: span ? desk.right - desk.left : width
    // Sky things (clouds, mist, stars) always lie across the whole desktop, even when each monitor
    // shows its own image, so two monitors don't show the same random sky side by side
    readonly property real skyLeft: desk.left - Screen.virtualX
    readonly property real skyWide: Math.max(width, desk.right - desk.left)
    readonly property bool rightmost: !span || Screen.virtualX + Screen.width >= desk.right
    readonly property bool showBars: visualiser && rightmost

    clip: true

    property var levels: []
    property bool busy: false

    // ---- weather and sun ---------------------------------------------------
    property var wx: null                        // the sepia-weather cache, or null
    property real elevation: 45                  // sun elevation in degrees
    property real sunAz: 0                       // sun azimuth, degrees from north (east = 90)

    // The sky by compass direction: you face the equator (north from the southern hemisphere, south
    // from the northern), with the noon sun in the middle. Sunset is on the left in the south, like
    // the old painted sun, and on the right in the north. 90° either side = 1.6 world units.
    readonly property real skyCenter: wx && wx.latitude < 0 ? 0 : 180
    function skyX(az) { return 1.6 * ((((az - skyCenter) % 360) + 540) % 360 - 180) / 90 }
    function skyY(alt) { return 0.58 - 0.5 * Math.sin(Math.max(-15, alt) * Math.PI / 180) }
    function toItem(wx_, wy_) { return Qt.point(map.x0 + wx_ * map.s, map.y0 + wy_ * map.s) }
    readonly property string sky: weatherOn && wx ? wx.sky : "clear"
    readonly property real cover: weatherOn && wx ? wx.cloud_cover / 100 : 0
    readonly property real intensity: weatherOn && wx ? wx.intensity : 0
    readonly property bool wet: ["drizzle", "rain", "showers", "storm"].indexOf(sky) >= 0
    readonly property bool snowing: sky === "snow"
    readonly property bool foggy: sky === "fog"
    // 0 = bright sky .. 1 = full grey deck (rain and snow skies are always heavy)
    readonly property real overcast: Math.max(Math.min(1, Math.max(0, cover - 0.55) / 0.4),
                                              wet || snowing ? 0.65 + 0.35 * intensity : 0,
                                              foggy ? 0.7 : 0)
    // night 0..1 (full by 11° below the horizon, or in a total solar eclipse), glow peaks with the
    // sun on the horizon
    readonly property real night: dayNightOn ? Math.max(smooth(-1, -11, elevation),
                                                        solar.on ? 0.85 * smooth(0.75, 1, solar.obsc) : 0) : 0
    readonly property real dusk: dayNightOn ? Math.max(0, 1 - Math.abs(elevation - 1) / 7) : 0
    readonly property real windPx: (4 + (weatherOn && wx ? wx.wind_kmh : 8) * 0.6) * height / 1440
    // wind direction is where it blows FROM: westerlies push clouds to the right
    readonly property int windSign: weatherOn && wx && Math.sin(wx.wind_dir * Math.PI / 180) > 0 ? -1 : 1
    property real drift: 0                       // seconds, advances clouds, mist and tree sway
    readonly property real wind: weatherOn && wx ? wx.wind_kmh : 8
    readonly property real temp: wx ? wx.temp : 15

    // ---- seasons ---------------------------------------------------------------
    // yearPhase 0 = midsummer (mid-January south of the equator, mid-July north), 0.5 = midwinter.
    // seasonPos 0 summer, 1 autumn, 2 winter, 3 spring, blending between neighbours.
    property real yearPhase: 0
    readonly property real seasonPos: yearPhase * 4
    readonly property int seasonA: Math.floor(seasonPos) % 4
    readonly property int seasonB: (seasonA + 1) % 4
    readonly property real seasonF: smooth(0.3, 0.7, seasonPos - Math.floor(seasonPos))
    function seasonWeight(k) { const d = Math.abs(seasonPos - k) % 4; return Math.max(0, 1 - Math.min(d, 4 - d)) }
    readonly property real winterness: (1 - Math.cos(2 * Math.PI * yearPhase)) / 2
    // how far down the snow reaches (0 none .. 1 everything): season, then recent and falling snow
    readonly property real snowAmount: !seasonsOn ? 0 : Math.min(0.95, 0.2 + 0.4 * Math.pow(winterness, 1.5)
        + (weatherOn && wx ? Math.min(0.3, (wx.snow_cm || 0) * 0.03) + (snowing ? 0.15 + 0.1 * intensity : 0) : 0))
    property real snowShown: snowAmount
    Behavior on snowShown { NumberAnimation { duration: 30000 } }
    readonly property real treeSnow: smooth(0.62, 0.8, snowShown)
    readonly property bool dry: !wet && !snowing && !foggy
    readonly property real fireflies: !seasonsOn ? 0 : Math.min(1, seasonWeight(0) * 1.5 + seasonWeight(3) * 0.4)
        * smooth(0.5, 0.9, night) * smooth(11, 14, temp) * (dry ? 1 : 0) * (wind < 25 ? 1 : 0)
    readonly property real leaves: !seasonsOn ? 0 : Math.min(1, seasonWeight(1) * 1.6) * smooth(10, 30, wind)
        * (wet || snowing ? 0.4 : 1) * (1 - 0.7 * night)
    readonly property real pollen: !seasonsOn ? 0 : Math.min(1, seasonWeight(3) * 1.5) * (1 - night)
        * (dry && wind < 20 ? 1 : 0)
    readonly property real blowSnow: seasonsOn && weatherOn ? smooth(22, 45, wind) * smooth(0.3, 0.5, snowShown) : 0
    readonly property real mist: !(weatherOn && wx) || foggy ? 0 : Math.max(smooth(82, 98, wx.humidity) * 0.7,
        elevation > -3 && elevation < 10 && temp < 13 ? 0.5 : 0)
    function updateSeason() {
        const names = ["summer", "autumn", "winter", "spring"]
        if (wx && wx.season && names.indexOf(wx.season) >= 0) { yearPhase = names.indexOf(wx.season) / 4; return }
        const d = new Date()
        const doy = (d - new Date(d.getFullYear(), 0, 1)) / 86400000
        // a few weeks after the solstice, when it's actually warmest
        const mid = wx && wx.latitude < 0 ? 15 : 196
        yearPhase = (((doy - mid) / 365.25) % 1 + 1) % 1
    }
    // 12 clouds per screen-width of sky (more when one image spans several screens)
    readonly property int cloudSlots: Math.max(12, Math.round(12 * skyWide / Math.max(1, width)))

    function smooth(a, b, v) { const t = Math.max(0, Math.min(1, (v - a) / (b - a))); return t * t * (3 - 2 * t) }
    function rnd(i, k) { const x = Math.sin(i * 12.9898 + k * 78.233) * 43758.5453; return x - Math.floor(x) }

    // Sun elevation for a time and place (low-precision solar position, ±0.5°)
    function sunElevation(date, lat, lon) {
        const r = Math.PI / 180
        const d = date.getTime() / 86400000 - 10957.5           // days since J2000
        const g = (357.529 + 0.98560028 * d) * r
        const q = 280.459 + 0.98564736 * d
        const L = (q + 1.915 * Math.sin(g) + 0.020 * Math.sin(2 * g)) * r
        const e = (23.439 - 0.00000036 * d) * r
        const ra = Math.atan2(Math.cos(e) * Math.sin(L), Math.cos(L))
        const dec = Math.asin(Math.sin(e) * Math.sin(L))
        const gmst = ((18.697374558 + 24.06570982441908 * d) % 24) * 15 * r
        const ha = gmst + lon * r - ra
        return Math.asin(Math.sin(lat * r) * Math.sin(dec) + Math.cos(lat * r) * Math.cos(dec) * Math.cos(ha)) / r
    }
    function sunAzimuth(date, lat, lon) {
        const r = Math.PI / 180
        const d = date.getTime() / 86400000 - 10957.5
        const g = (357.529 + 0.98560028 * d) * r
        const L = (280.459 + 0.98564736 * d + 1.915 * Math.sin(g) + 0.020 * Math.sin(2 * g)) * r
        const e = (23.439 - 0.00000036 * d) * r
        const ra = Math.atan2(Math.cos(e) * Math.sin(L), Math.cos(L))
        const dec = Math.asin(Math.sin(e) * Math.sin(L))
        const ha = ((18.697374558 + 24.06570982441908 * d) % 24) * 15 * r + lon * r - ra
        return (Math.atan2(-Math.sin(ha) * Math.cos(dec),
                           Math.cos(lat * r) * Math.sin(dec) - Math.sin(lat * r) * Math.cos(dec) * Math.cos(ha)) / r + 360) % 360
    }
    function updateSun() {
        const now = new Date()
        if (wx && wx.sun_elevation !== undefined) {                                   // preview mode
            elevation = wx.sun_elevation
            sunAz = wx.sun_az !== undefined ? wx.sun_az : skyCenter - 44
        } else if (wx) {
            elevation = sunElevation(now, wx.latitude, wx.longitude)
            sunAz = sunAzimuth(now, wx.latitude, wx.longitude)
        } else {
            elevation = 45
        }
        updateSeason()
        if (wx) {
            const m = moonInfo(now, wx.latitude, wx.longitude)
            if (wx.moon_alt !== undefined) { m.alt = wx.moon_alt; m.az = wx.moon_az; m.frac = wx.moon_phase }
            moon = m
        }
        const t = now.getTime() / 1000
        eclipseSoon = !!(wx && wx.eclipses && wx.eclipses.some(e => e.end > t - 60 && e.start < t + 120))
        updateEclipse()
    }

    // ---- eclipses (timeline worked out by sepia-weather for this location) ---------
    property bool eclipseSoon: false
    property var solar: ({ on: false, dx: 0, dy: 0, k: 1, obsc: 0 })   // moon offset in sun radii
    property var lunar: ({ on: false, dx: 0, dy: 0, ur: 0, pr: 0 })     // shadow offset in moon radii
    function sample(rows, t) {
        let i = 0
        while (i < rows.length - 2 && rows[i + 1][0] <= t) i++
        const a = rows[i], b = rows[i + 1] || a
        const f = b[0] > a[0] ? Math.max(0, Math.min(1, (t - a[0]) / (b[0] - a[0]))) : 0
        return a.map((v, j) => v + ((b[j] === undefined ? v : b[j]) - v) * f)
    }
    // fraction of the sun's disc (radius 1) covered by the moon (radius k) at distance d
    function covered(d, k) {
        if (d >= 1 + k) return 0
        if (d <= Math.abs(k - 1)) return k >= 1 ? 1 : k * k
        const a = Math.acos((d * d + 1 - k * k) / (2 * d)), b = Math.acos((d * d + k * k - 1) / (2 * d * k))
        return (a + k * k * b - 0.5 * Math.sqrt((-d + 1 + k) * (d + 1 - k) * (d - 1 + k) * (d + 1 + k))) / Math.PI
    }
    function updateEclipse() {
        const t = Date.now() / 1000
        let s = { on: false, dx: 0, dy: 0, k: 1, obsc: 0 }, l = { on: false, dx: 0, dy: 0, ur: 0, pr: 0 }
        if (wx && wx.eclipses && dayNightOn) {
            for (const e of wx.eclipses) {
                if (t < e.start || t > e.end) continue
                const r = sample(e.samples, t)
                if (e.kind === "solar")
                    s = { on: true, dx: r[1], dy: r[2], k: r[3], obsc: covered(Math.hypot(r[1], r[2]), r[3]) }
                else
                    l = { on: true, dx: r[1], dy: r[2], ur: r[3], pr: r[4] }
            }
        }
        solar = s
        lunar = l
    }
    Timer { interval: 1000; repeat: true; running: root.eclipseSoon; onTriggered: root.updateEclipse() }

    // Moon position and phase (low precision, plenty for a wallpaper)
    property var moon: ({ alt: -90, az: 0, frac: 0.5, waxing: true })
    function moonInfo(date, lat, lon) {
        const r = Math.PI / 180
        const d = date.getTime() / 86400000 - 10957.5
        const L = 218.316 + 13.176396 * d, M = (134.963 + 13.064993 * d) * r, F = (93.272 + 13.229350 * d) * r
        const elon = (L + 6.289 * Math.sin(M)) * r, elat = 5.128 * Math.sin(F) * r
        const e = 23.439 * r
        const ra = Math.atan2(Math.sin(elon) * Math.cos(e) - Math.tan(elat) * Math.sin(e), Math.cos(elon))
        const dec = Math.asin(Math.sin(elat) * Math.cos(e) + Math.cos(elat) * Math.sin(e) * Math.sin(elon))
        const gmst = ((18.697374558 + 24.06570982441908 * d) % 24) * 15 * r
        const ha = Math.atan2(Math.sin(gmst + lon * r - ra), Math.cos(gmst + lon * r - ra))
        const alt = Math.asin(Math.sin(lat * r) * Math.sin(dec) + Math.cos(lat * r) * Math.cos(dec) * Math.cos(ha)) / r
        const g = (357.529 + 0.98560028 * d) * r
        const sunLon = (280.459 + 0.98564736 * d + 1.915 * Math.sin(g)) * r
        const el = elon - sunLon
        const az = (Math.atan2(-Math.sin(ha) * Math.cos(dec),
                               Math.cos(lat * r) * Math.sin(dec) - Math.sin(lat * r) * Math.cos(dec) * Math.cos(ha)) / r + 360) % 360
        return { alt: alt, az: az, frac: (1 - Math.cos(el)) / 2, waxing: Math.sin(el) > 0 }
    }
    // A changing query string makes the engine read the file again instead of reusing its cache
    readonly property string weatherFile: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/sepia-summit/weather.qml"
    function fetchWeather() { weatherLoader.source = weatherFile + "?t=" + Date.now() }
    Loader {
        id: weatherLoader
        active: root.weatherOn || root.dayNightOn
        // loaded fires on every reload; status would stay Ready and never signal a change
        onLoaded: {
            if (item && item.data) {
                // ignore data more than 2 hours old (asleep, no network...)
                root.wx = Date.now() / 1000 - item.data.updated < 7200 ? item.data : null
                root.updateSun()
            }
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                root.wx = null
                root.updateSun()
            }
        }
    }
    Timer { interval: 60000; repeat: true; running: true; triggeredOnStart: true; onTriggered: root.fetchWeather() }
    // ~15 fps is plenty for clouds moving a few pixels a second
    Timer {
        interval: 66; repeat: true
        running: root.weatherOn && root.cover > 0 || root.mist > 0 || root.seasonsOn && root.shownTrees.length > 0
        onTriggered: root.drift += 0.066
    }

    // World units (make_wallpaper.py: 1 = image height, x = 0 at the centre of the full image)
    // to this item's coordinates: x = x0 + wx * s, y = y0 + wy * s
    readonly property var map: {
        const iw = bgImage.sourceSize.width, ih = bgImage.sourceSize.height
        if (!iw || !ih) return { x0: -99999, y0: 0, s: 1 }
        const left = bgSource.indexOf("_LEFT") >= 0, right = bgSource.indexOf("_RIGHT") >= 0
        const world = left || right ? iw * 2 : iw
        const scale = Math.max(sliceW / iw, height / ih)
        return { x0: sliceX + (sliceW - iw * scale) / 2 + (world / 2 - (right ? iw : 0)) * scale,
                 y0: (height - ih * scale) / 2, s: ih * scale }
    }
    // The sun: real position with day/night on, otherwise where the old painted sun was
    readonly property point sunPos: dayNightOn && wx ? toItem(skyX(sunAz), skyY(elevation))
                                                     : toItem(-0.78, 0.40)
    readonly property real sunR: 0.055 * map.s                   // disc radius, like the painted one
    // trees on this screen only
    readonly property var shownTrees: {
        const out = [], m = map
        for (let i = 0; i < Scene.trees.length; i++) {
            const t = Scene.trees[i], x = m.x0 + t[0] * m.s
            if (x > -80 && x < width + 80) out.push(t)
        }
        return out
    }

    // The sky mask, laid out exactly like the wallpaper image, used as an alpha mask
    Item {
        id: skyMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Image {
            x: root.sliceX; width: root.sliceW; height: parent.height
            source: root.skySource
            fillMode: Image.PreserveAspectCrop
            smooth: true
        }
    }

    // Everything below the glass, in one item so the glass can sample it
    Item {
        id: scene
        anchors.fill: parent

        Rectangle { anchors.fill: parent; color: "#2a1c12" }

        Image {
            id: bgImage
            x: root.sliceX; width: root.sliceW; height: parent.height
            source: root.bgSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
        }


        // ---- the sun (behind every mountain and every cloud) ----------------------------
        Item {
            id: sunLayer
            anchors.fill: parent
            visible: !root.dayNightOn || root.elevation > -5
            layer.enabled: visible
            layer.effect: MultiEffect { maskEnabled: true; maskSource: skyMask; maskThresholdMin: 0.5; maskSpreadAtMin: 0.2 }
            opacity: 1 - 0.85 * root.overcast
            Behavior on opacity { NumberAnimation { duration: 20000 } }
            Image {                                         // wide glow in the sky
                source: "../images/sunglow.png"
                width: 3.0 * root.map.s; height: width
                x: root.sunPos.x - width / 2; y: root.sunPos.y - height / 2
                opacity: 0.3 * (1 - root.solar.obsc)
            }
            Image {                                         // disc and halo; the halo is the corona at totality
                source: "../images/sun.png"
                width: 0.9 * root.map.s; height: width
                x: root.sunPos.x - width / 2; y: root.sunPos.y - height / 2
                opacity: 1 - 0.5 * root.solar.obsc
            }
            // The moon during a solar eclipse. You only see it where it covers the bright disc, so it's
            // clipped to the sun: a bite out of the sun, then a black disc ringed by the corona.
            Image {                                         // corona, only near totality
                visible: root.solar.on
                source: "../images/sun.png"
                width: 0.42 * root.map.s; height: width
                x: root.sunPos.x - width / 2; y: root.sunPos.y - height / 2
                opacity: 0.9 * root.smooth(0.93, 1, root.solar.obsc)
            }
            Item {
                visible: root.solar.on
                width: 2 * root.sunR; height: width
                x: root.sunPos.x - width / 2; y: root.sunPos.y - height / 2
                layer.enabled: visible
                layer.effect: MultiEffect { maskEnabled: true; maskSource: sunDisc; maskThresholdMin: 0.5; maskSpreadAtMin: 0.3 }
                Rectangle {
                    id: sunDisc
                    anchors.fill: parent; radius: width / 2
                    visible: false; layer.enabled: true
                }
                Rectangle {                                 // the sun's actual disc, seen through the haze
                    anchors.fill: parent; radius: width / 2
                    color: "#f7ecd2"
                    opacity: 0.85 * (1 - root.smooth(0.97, 1, root.solar.obsc))
                }
                Rectangle {
                    readonly property real t: Math.min(1, root.solar.obsc * 1.15)
                    width: 2 * root.sunR * root.solar.k; height: width; radius: width / 2
                    x: parent.width / 2 + root.solar.dx * root.sunR - width / 2
                    y: parent.height / 2 - root.solar.dy * root.sunR - height / 2
                    // the sky beside the sun at first, darkening to near black at totality
                    color: Qt.rgba(0.86 - 0.74 * t * t, 0.76 - 0.67 * t * t, 0.60 - 0.53 * t * t, 1)
                    antialiasing: true
                }
            }
        }

        // ---- weather in the sky (behind every mountain) --------------------------
        Item {
            id: skyFx
            anchors.fill: parent
            visible: root.weatherOn && (root.cover > 0 || root.overcast > 0)
            layer.enabled: visible
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: skyMask
                // the spread is centred on the threshold, so threshold 0 would let half show through the peaks
                maskThresholdMin: 0.5
                maskSpreadAtMin: 0.2
            }

            // grey cloud deck
            Rectangle {
                anchors.fill: parent
                opacity: root.overcast * 0.6
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#6e5641" }
                    GradientStop { position: 0.6; color: "#9c7f62" }
                }
                Behavior on opacity { NumberAnimation { duration: 20000 } }
            }
            // long thin bands when it's mostly cloudy
            Repeater {
                model: 3
                Image {
                    // laid out across the whole desktop (skyLeft/skyWide), so the monitors share one sky
                    readonly property real span: root.skyWide + width
                    source: "../images/stratus" + (index % 2 + 1) + ".png"
                    width: root.height * 1.78 * (1.1 + 0.3 * root.rnd(index, 7)); height: root.height * 0.2
                    y: root.height * (0.06 + 0.13 * index)
                    x: root.skyLeft + ((root.rnd(index, 8) * span + root.windSign * root.drift * root.windPx * 0.5) % span + span) % span - width
                    opacity: Math.max(0, root.overcast - 0.2) * 0.8
                    Behavior on opacity { NumberAnimation { duration: 20000 } }
                }
            }
            // puffy clouds: how many depends on the cloud cover
            Repeater {
                model: root.cloudSlots
                Image {
                    readonly property real scale0: (0.32 + 0.4 * root.rnd(index, 2)) * root.height / 1440
                    readonly property real span: root.skyWide + width
                    source: "../images/cloud" + (index % 5 + 1) + ".png"
                    width: 1000 * scale0; height: 460 * scale0
                    y: root.height * (0.02 + 0.3 * root.rnd(index, 1))
                    x: root.skyLeft + ((root.rnd(index, 0) * span + root.windSign * root.drift * root.windPx * (0.7 + 0.6 * root.rnd(index, 3))) % span + span) % span - width
                    // dimmer under a grey deck, so they don't outshine an overcast sky
                    opacity: index < Math.round(root.cover * root.cloudSlots) ? 0.85 - 0.4 * root.overcast : 0
                    Behavior on opacity { NumberAnimation { duration: 15000 } }
                }
            }
        }

        // ---- seasonal snow on the far peaks -------------------------------------------
        // The wallpaper itself, brightened, shown where the snow level (alpha of *_snow.png) is above
        // 1 - snowShown, so the painted light and shade carry through onto the snow.
        Item {
            id: snowMask
            x: root.sliceX; width: root.sliceW; height: parent.height
            visible: false
            layer.enabled: true
            Image { anchors.fill: parent; source: root.seasonsOn ? root.snowSource : ""; fillMode: Image.PreserveAspectCrop; smooth: true }
        }
        MultiEffect {
            x: bgImage.x; width: bgImage.width; height: bgImage.height
            source: bgImage
            visible: root.seasonsOn && root.snowShown > 0.02
            brightness: 0.22
            maskEnabled: true
            maskSource: snowMask
            maskThresholdMin: 1 - root.snowShown
            maskSpreadAtMin: 0.35
            opacity: 0.65
        }

        Item {
            id: viz
            anchors.fill: parent
            visible: root.showBars
            opacity: root.barOpacity
            layer.enabled: root.glow && root.showBars
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: root.barColor
                shadowBlur: 1.0
                shadowOpacity: 0.9
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }

            Repeater {
                model: root.barCount
                Rectangle {
                    readonly property real slot: viz.width / root.barCount
                    readonly property real v: index < root.levels.length ? root.levels[index] : 0
                    width: Math.max(1, slot * 0.6)
                    x: index * slot + (slot - width) / 2
                    height: Math.max(0, v) * viz.height * root.maxHeight
                    y: viz.height * root.valleyLine - height
                    radius: width / 2
                    // A rounded gradient bar shorter than its width is a degenerate shape.
                    visible: height >= width
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b, 1.0) }
                        GradientStop { position: 1.0; color: Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b, 0.25) }
                    }
                    Behavior on height { NumberAnimation { duration: 70 } }
                }
            }
        }

        Image {
            x: root.sliceX; width: root.sliceW; height: parent.height
            source: root.fgSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
        }

        // ---- valley mist, drifting with the wind ----------------------------------------
        Item {
            anchors.fill: parent
            opacity: root.mist
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 20000 } }
            Repeater {
                model: 4
                Image {
                    readonly property real span: root.skyWide + width
                    source: "../images/stratus" + (index % 2 + 1) + ".png"
                    width: root.height * 1.6; height: root.height * 0.12
                    y: root.height * (0.62 + 0.07 * index)
                    x: root.skyLeft + ((root.rnd(index, 30) * span + root.windSign * root.drift * root.windPx * 0.35) % span + span) % span - width
                    opacity: 0.32 - 0.04 * index
                }
            }
        }

        // ---- trees on the nearer hills -----------------------------------------------------
        // Sprite sheet ../images/trees.png: row = hill (layer 3, 4, 5), 128 px cells. Columns: 0-1
        // conifers, 2-3 the same with snow, then per deciduous tree: summer, autumn, winter, spring.
        Item {
            anchors.fill: parent
            visible: root.seasonsOn
            Repeater {
                model: root.seasonsOn ? root.shownTrees : []
                Item {
                    id: tree
                    required property var modelData
                    required property int index
                    readonly property bool conifer: modelData[4] === 0
                    readonly property int row: modelData[3] - 3
                    readonly property int colA: conifer ? modelData[5] : 4 + modelData[5] * 4 + root.seasonA
                    readonly property int colB: conifer ? modelData[5] + 2 : 4 + modelData[5] * 4 + root.seasonB
                    readonly property real mix: conifer ? root.treeSnow : root.seasonF
                    readonly property real r: root.rnd(modelData[0] * 1000, 40)
                    width: modelData[2] * root.map.s / 0.94; height: width
                    x: root.map.x0 + modelData[0] * root.map.s - width / 2
                    y: root.map.y0 + modelData[1] * root.map.s - height
                    // lean away from the wind and sway around that, conifers stiffer
                    transform: [
                        Scale { origin.x: tree.width / 2; xScale: tree.modelData[6] ? -1 : 1 },
                        Rotation {
                            origin.x: tree.width / 2; origin.y: tree.height
                            angle: (tree.conifer ? 0.6 : 1) * (root.windSign * Math.min(5, root.wind * 0.08) * (0.7 + 0.3 * tree.r)
                                   + Math.min(2.5, 0.3 + root.wind * 0.035) * Math.sin(root.drift * (1.1 + 0.6 * tree.r) + tree.r * 40))
                        }
                    ]
                    Image {
                        anchors.fill: parent
                        source: "../images/trees.png"
                        sourceClipRect: Qt.rect(tree.colA * 128, tree.row * 128, 128, 128)
                        opacity: 1 - tree.mix
                        visible: opacity > 0.01
                        smooth: true; mipmap: true
                    }
                    Image {
                        anchors.fill: parent
                        source: "../images/trees.png"
                        sourceClipRect: Qt.rect(tree.colB * 128, tree.row * 128, 128, 128)
                        opacity: tree.mix
                        visible: opacity > 0.01
                        smooth: true; mipmap: true
                    }
                }
            }
        }

        // ---- light ------------------------------------------------------------------
        Image {                                             // the sun's light over the whole scene
            source: "../images/sunglow.png"
            width: 2.2 * root.map.s; height: width
            x: root.sunPos.x - width / 2; y: root.sunPos.y - height / 2
            opacity: 0.12 * (1 - root.overcast) * (1 - root.night) * (1 - root.solar.obsc)
                     * (root.dayNightOn ? root.smooth(-4, 2, root.elevation) : 1)
        }
        Rectangle {                                         // grey day
            anchors.fill: parent
            color: "#2a1c12"
            opacity: root.overcast * 0.22 + (root.wet ? 0.08 * root.intensity : 0)
            Behavior on opacity { NumberAnimation { duration: 20000 } }
        }
        Rectangle {                                         // sunrise / sunset glow
            anchors.fill: parent
            opacity: root.dusk * (1 - 0.6 * root.overcast)
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.80, 0.42, 0.24, 0.30) }
                GradientStop { position: 0.6; color: Qt.rgba(0.85, 0.50, 0.30, 0.12) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            Behavior on opacity { NumberAnimation { duration: 5000 } }
        }
        Rectangle {                                         // night
            anchors.fill: parent
            opacity: root.night
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.02, 0.03, 0.07, 0.72) }
                GradientStop { position: 1.0; color: Qt.rgba(0.03, 0.03, 0.06, 0.62) }
            }
            Behavior on opacity { NumberAnimation { duration: 5000 } }
        }

        // stars, only in clear sky
        Item {
            anchors.fill: parent
            visible: opacity > 0
            opacity: root.night * Math.max(0, 1 - root.cover * 1.1) * (root.foggy ? 0 : 1)
            Behavior on opacity { NumberAnimation { duration: 5000 } }
            layer.enabled: visible
            layer.effect: MultiEffect { maskEnabled: true; maskSource: skyMask; maskThresholdMin: 0.5; maskSpreadAtMin: 0.2 }
            // the moon, where it really is (az/alt), with its phase; Earth's shadow during a lunar eclipse
            Item {
                id: moonItem
                readonly property real rad: root.map.s * 0.016
                readonly property real side: root.wx && root.wx.latitude < 0 ? -1 : 1
                visible: root.moon.alt > -2
                width: rad * 2; height: rad * 2
                x: root.map.x0 + root.skyX(root.moon.az) * root.map.s - rad
                y: root.map.y0 + root.skyY(root.moon.alt) * root.map.s - rad
                Image {
                    source: "../images/snow.png"
                    anchors.centerIn: parent
                    width: parent.width * 4; height: width
                    opacity: (0.12 + 0.18 * root.moon.frac) * (root.lunar.on ? 0.4 : 1)
                }
                Canvas {
                    id: moonCanvas
                    anchors.fill: parent
                    // lit limb towards the sun: on the right while waxing in the north, flipped in the south
                    readonly property real litSide: (root.moon.waxing ? 1 : -1) * moonItem.side
                    readonly property real frac: root.moon.frac
                    readonly property string shadow: root.lunar.on ? [root.lunar.dx, root.lunar.dy, root.lunar.ur, root.lunar.pr].map(v => v.toFixed(2)).join() : ""
                    onShadowChanged: requestPaint()
                    onFracChanged: requestPaint()
                    onLitSideChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d"), r = width / 2
                        c.reset()
                        c.fillStyle = Qt.rgba(0.96, 0.91, 0.79, 0.1)            // earthshine
                        c.beginPath(); c.arc(r, r, r, 0, 2 * Math.PI); c.fill()
                        c.fillStyle = Qt.rgba(0.96, 0.91, 0.79, 0.92)
                        c.beginPath()
                        for (let i = 0; i <= 32; i++) {
                            const a = -Math.PI / 2 + Math.PI * i / 32
                            c.lineTo(r + litSide * r * Math.cos(a), r + r * Math.sin(a))
                        }
                        for (let i = 32; i >= 0; i--) {
                            const a = -Math.PI / 2 + Math.PI * i / 32
                            c.lineTo(r + litSide * r * Math.cos(a) * (1 - 2 * frac), r + r * Math.sin(a))
                        }
                        c.fill()
                        if (root.lunar.on) {                    // Earth's shadow: soft penumbra, red umbra
                            const L = root.lunar, sx = r + L.dx * r, sy = r - L.dy * r
                            c.save()
                            c.beginPath(); c.arc(r, r, r, 0, 2 * Math.PI); c.clip()
                            const g = c.createRadialGradient(sx, sy, L.ur * r, sx, sy, L.pr * r)
                            g.addColorStop(0, Qt.rgba(0.16, 0.08, 0.06, 0.5))
                            g.addColorStop(1, Qt.rgba(0.16, 0.08, 0.06, 0))
                            c.fillStyle = g
                            c.fillRect(0, 0, width, height)
                            c.fillStyle = Qt.rgba(0.44, 0.21, 0.13, 0.88)
                            c.beginPath(); c.arc(sx, sy, L.ur * r, 0, 2 * Math.PI); c.fill()
                            c.restore()
                        }
                    }
                }
            }
            // an occasional shooting star
            Rectangle {
                id: meteor
                width: root.map.s * 0.09; height: Math.max(1, root.map.s * 0.0012)
                opacity: 0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: "#fff4dc" }
                }
                ParallelAnimation {
                    id: meteorAnim
                    NumberAnimation { target: meteor; property: "x"; duration: 900; easing.type: Easing.InQuad }
                    NumberAnimation { target: meteor; property: "y"; duration: 900; easing.type: Easing.InQuad }
                    SequentialAnimation {
                        NumberAnimation { target: meteor; property: "opacity"; to: 0.55; duration: 200 }
                        NumberAnimation { target: meteor; property: "opacity"; to: 0; duration: 700 }
                    }
                }
                // Sporadic meteors every minute or two; during a shower (sepia-weather: rate per hour you'd
                // see from here) shown at 60% of that rate, each streaking away from the radiant.
                readonly property real rate: root.wx && root.wx.meteors ? root.wx.meteors.rate : 0
                Timer {
                    running: root.night > 0.8 && root.cover < 0.5
                    repeat: true
                    interval: 30000
                    onTriggered: {
                        const shower = meteor.rate >= 1 && Math.random() < 0.85
                        interval = meteor.rate >= 1 ? Math.max(8000, 3600000 / (meteor.rate * 0.6)) * (0.4 + 1.2 * Math.random())
                                                    : 45000 + Math.random() * 120000
                        let x = 0, y = 0, a = (20 + 20 * Math.random()) * Math.PI / 180
                        for (let k = 0; k < 6; k++) {
                            if (shower) {
                                const m = root.wx.meteors, rp = root.toItem(root.skyX(m.radiant_az), root.skyY(m.radiant_alt))
                                a = Math.random() * 2 * Math.PI
                                const dist = root.map.s * (0.08 + 0.4 * Math.random())
                                x = rp.x + Math.cos(a) * dist; y = rp.y + Math.sin(a) * dist
                            } else {
                                x = root.width * (0.1 + 0.7 * Math.random()); y = root.height * (0.05 + 0.2 * Math.random())
                            }
                            if (x > 0 && x < root.width && y > 0 && y < root.height * 0.5) break
                            if (k === 5) return
                        }
                        meteor.rotation = a * 180 / Math.PI
                        meteor.x = x - meteor.width / 2; meteor.y = y
                        meteorAnim.animations[0].to = meteor.x + Math.cos(a) * root.map.s * 0.2
                        meteorAnim.animations[1].to = y + Math.sin(a) * root.map.s * 0.2
                        meteorAnim.restart()
                    }
                }
            }
            Repeater {
                model: Math.round(260 * root.skyWide / root.width)
                Rectangle {
                    readonly property real s: 1 + 1.6 * Math.pow(root.rnd(index, 12), 3)
                    x: root.skyLeft + root.rnd(index, 10) * root.skyWide
                    y: Math.pow(root.rnd(index, 11), 1.4) * root.height * 0.62
                    width: s; height: s; radius: s / 2
                    color: "#fff4dc"
                    opacity: 0.35 + 0.65 * root.rnd(index, 13)
                    SequentialAnimation on opacity {
                        running: index % 9 === 0 && root.night > 0
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: 1200 + 2000 * root.rnd(index, 14); easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 1200 + 2000 * root.rnd(index, 15); easing.type: Easing.InOutSine }
                    }
                }
            }
        }

        // fog pooling in the valleys
        Rectangle {
            anchors.fill: parent
            opacity: root.foggy ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 20000 } }
            gradient: Gradient {
                GradientStop { position: 0.30; color: "transparent" }
                GradientStop { position: 0.62; color: Qt.rgba(0.83, 0.74, 0.60, 0.55 * (1 - 0.6 * root.night)) }
                GradientStop { position: 1.00; color: Qt.rgba(0.80, 0.70, 0.56, 0.35 * (1 - 0.6 * root.night)) }
            }
        }

        // rain and snow
        ParticleSystem {
            id: weatherParticles
            anchors.fill: parent
            running: root.weatherOn && (root.wet || root.snowing)
            // slant with the wind, up to ~18°
            readonly property real slant: root.windSign * Math.min(18, (root.wx ? root.wx.wind_kmh : 0) * 0.35)

            // Kept deliberately faint: muted colours close to the sky, thin streaks, low counts
            ImageParticle {
                groups: ["rain"]
                source: "../images/rain.png"
                color: "#d6c3a2"
                alpha: (root.sky === "drizzle" ? 0.12 : 0.2) * (1 - 0.5 * root.night)
                alphaVariation: 0.06
                rotation: -weatherParticles.slant              // lean the streak with the wind
            }
            ImageParticle {
                groups: ["snow"]
                source: "../images/snow.png"
                color: "#e9dcc4"
                alpha: 0.4 * (1 - 0.5 * root.night)
                alphaVariation: 0.15
            }
            Emitter {
                group: "rain"
                enabled: root.wet
                x: -root.width * 0.2; y: -80
                width: root.width * 1.4; height: 1
                emitRate: (root.sky === "drizzle" ? 50 : 80 + 260 * root.intensity) * root.width / 2560
                lifeSpan: 1200
                size: root.sky === "drizzle" ? 26 : 38
                sizeVariation: 10
                velocity: AngleDirection {
                    angle: 90 - weatherParticles.slant
                    magnitude: root.sky === "drizzle" ? 1000 : 1500
                    magnitudeVariation: 200
                }
            }
            Emitter {
                group: "snow"
                enabled: root.snowing
                x: -root.width * 0.1; y: -30
                width: root.width * 1.2; height: 1
                emitRate: (20 + 70 * root.intensity) * root.width / 2560
                lifeSpan: 16000
                size: 6
                sizeVariation: 3
                velocity: AngleDirection {
                    angle: 90 - weatherParticles.slant * 2
                    angleVariation: 12
                    magnitude: 80
                    magnitudeVariation: 30
                }
            }
            Wander {
                groups: ["snow"]
                xVariance: 60
                pace: 50
            }
        }

        // seasonal life: fireflies on warm summer nights, autumn leaves in the wind, spring pollen,
        // and snow blowing off the peaks. All faint and slow.
        ParticleSystem {
            id: life
            anchors.fill: parent
            running: root.fireflies > 0.05 || root.leaves > 0.05 || root.pollen > 0.05 || root.blowSnow > 0.05

            ImageParticle {
                groups: ["fly"]
                source: "../images/snow.png"
                color: "#f4dc8e"
                alpha: 0.5
                alphaVariation: 0.2
                entryEffect: ImageParticle.Fade                 // glow on, then off again
            }
            Emitter {
                group: "fly"
                enabled: root.fireflies > 0.05
                y: root.height * 0.7; width: root.width; height: root.height * 0.28
                emitRate: 10 * root.fireflies * root.width / 2560
                lifeSpan: 4000; lifeSpanVariation: 1500
                size: 6; sizeVariation: 2
                velocity: AngleDirection { angleVariation: 360; magnitude: 10; magnitudeVariation: 6 }
            }
            Wander { groups: ["fly"]; xVariance: 40; yVariance: 30; pace: 25 }

            ImageParticle {
                groups: ["leaf"]
                source: "../images/leaf.png"
                alpha: 0.55
                rotationVariation: 180
                rotationVelocity: 40; rotationVelocityVariation: 120
                entryEffect: ImageParticle.Fade
            }
            Emitter {
                group: "leaf"
                enabled: root.leaves > 0.05
                x: root.windSign > 0 ? -root.width * 0.3 : 0
                y: root.height * 0.55; width: root.width * 1.3; height: root.height * 0.35
                emitRate: 2.5 * root.leaves * root.width / 2560
                lifeSpan: 9000; lifeSpanVariation: 2000
                size: 12; sizeVariation: 4
                velocity: AngleDirection { angle: root.windSign > 0 ? 5 : 175; angleVariation: 15; magnitude: 40 + root.wind * 3; magnitudeVariation: 30 }
            }
            Gravity { groups: ["leaf"]; angle: 90; magnitude: 6 }
            Wander { groups: ["leaf"]; xVariance: 30; yVariance: 60; pace: 40 }

            ImageParticle {
                groups: ["pollen"]
                source: "../images/snow.png"
                color: "#fff3d4"
                alpha: 0.3
                entryEffect: ImageParticle.Fade
            }
            Emitter {
                group: "pollen"
                enabled: root.pollen > 0.05
                y: root.height * 0.35; width: root.width; height: root.height * 0.6
                emitRate: 3 * root.pollen * root.width / 2560
                lifeSpan: 10000
                size: 3; sizeVariation: 1
                velocity: AngleDirection { angle: -90; angleVariation: 180; magnitude: 8 }
            }
            Wander { groups: ["pollen"]; xVariance: 25; yVariance: 25; pace: 15 }

            ImageParticle {
                groups: ["spin"]
                source: "../images/snow.png"
                color: "#f1e6d0"
                alpha: 0.1 * (1 - 0.5 * root.night)            // soft spindrift, not sparkles
                entryEffect: ImageParticle.Fade
            }
            Repeater {
                model: Scene.peaks
                Emitter {
                    required property var modelData
                    system: life
                    group: "spin"
                    enabled: root.blowSnow > 0.05 && modelData[2] > 1 - root.snowShown
                    x: root.map.x0 + (modelData[0] - 0.02) * root.map.s; y: root.map.y0 + modelData[1] * root.map.s
                    width: 0.04 * root.map.s; height: 6
                    emitRate: 14 * root.blowSnow
                    lifeSpan: 2600; lifeSpanVariation: 800
                    size: 12; sizeVariation: 6
                    endSize: 22
                    velocity: AngleDirection { angle: root.windSign > 0 ? -8 : 188; angleVariation: 15; magnitude: 60 + root.wind * 2.5; magnitudeVariation: 30 }
                }
            }
        }

        // lightning
        Rectangle {
            id: flash
            anchors.fill: parent
            color: "#fff3dc"
            opacity: 0
            // a soft glow rather than a sharp flash
            SequentialAnimation {
                id: flashAnim
                NumberAnimation { target: flash; property: "opacity"; to: 0.08; duration: 250; easing.type: Easing.InOutSine }
                NumberAnimation { target: flash; property: "opacity"; to: 0.03; duration: 300; easing.type: Easing.InOutSine }
                NumberAnimation { target: flash; property: "opacity"; to: 0.06; duration: 250; easing.type: Easing.InOutSine }
                NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 1500; easing.type: Easing.OutQuad }
            }
            Timer {
                running: root.weatherOn && root.sky === "storm"
                repeat: true
                interval: 9000
                onTriggered: { interval = 15000 + Math.random() * 30000; flashAnim.restart() }
            }
        }
    }

    // ---- frosted glass behind the conky panel ------------------------------------------
    // conky is its own window on the desktop layer, which KWin won't blur, so the wallpaper draws a
    // blurred copy of the scene where the panel sits. conky/scripts/panel.lua writes the panel's size
    // and monitor to glass.qml (a QtObject, loaded like weather.qml). Not on the lock screen (Span).
    property var glassPanels: []
    readonly property string glassFile: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/sepia-summit/glass.qml"
    // conky's monitor number counts from the left (install.sh: HEAD=1 = the second screen), so number
    // the screens by position; Qt's own screen order doesn't follow it
    readonly property int screenIndex: {
        const s = Array.from(Qt.application.screens).sort((a, b) => a.virtualX - b.virtualX)
        for (let i = 0; i < s.length; i++) if (s[i].name === Screen.name) return i
        return 0
    }
    Loader {
        id: glassLoader
        onLoaded: root.glassPanels = item && item.panels ? item.panels : []
    }
    Timer {
        interval: 15000; repeat: true; triggeredOnStart: true
        running: !root.span && root.configuration.Glass !== false
        onTriggered: glassLoader.source = root.glassFile + "?t=" + Date.now()
    }
    Repeater {
        model: root.span || root.configuration.Glass === false ? []
               : root.glassPanels.filter(p => p.head === root.screenIndex)
        delegate: Item {
            id: pane
            required property var modelData
            readonly property int m: 40                       // blur margin, so the edges aren't smeared
            x: (modelData.anchor === "top_right" ? root.width - modelData.gap_x - modelData.w : modelData.gap_x) - m
            y: modelData.gap_y - m
            width: modelData.w + 2 * m; height: modelData.h + 2 * m
            ShaderEffectSource {
                id: paneSrc
                anchors.fill: parent
                sourceItem: scene
                sourceRect: Qt.rect(pane.x, pane.y, pane.width, pane.height)
                visible: false
            }
            Item {
                id: paneMask
                anchors.fill: parent
                visible: false; layer.enabled: true
                Rectangle { anchors.fill: parent; anchors.margins: pane.m; radius: pane.modelData.r }
            }
            MultiEffect {
                anchors.fill: parent
                source: paneSrc
                autoPaddingEnabled: false
                blurEnabled: true; blur: 1; blurMax: 48; blurMultiplier: 0.6
                brightness: 0.05
                maskEnabled: true; maskSource: paneMask; maskThresholdMin: 0.5; maskSpreadAtMin: 0.1
            }
        }
    }

    // ~30 fps poll of the local CAVA server. If it isn't running the bars
    // simply stay down and this looks like the normal wallpaper.
    Timer {
        interval: 33
        repeat: true
        running: root.showBars && root.fgSource !== ""
        onTriggered: {
            if (root.busy) return
            root.busy = true
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE) return
                root.busy = false
                let raw = []
                if (xhr.status === 200 && xhr.responseText.length > 0)
                    raw = xhr.responseText.split(";")
                const n = root.barCount
                const old = root.levels
                const out = new Array(n)
                for (let i = 0; i < n; i++) {
                    let t = 0
                    if (raw.length > 0) {
                        const j = Math.min(raw.length - 1, Math.floor(i * raw.length / n))
                        t = Math.min(1, (parseInt(raw[j]) || 0) / 1000)
                    }
                    const o = i < old.length ? old[i] : 0
                    out[i] = t > o ? t : o * 0.8 + t * 0.2   // fast rise, slow fall
                }
                root.levels = out
            }
            xhr.open("GET", root.endpoint)
            xhr.send()
        }
    }
}
