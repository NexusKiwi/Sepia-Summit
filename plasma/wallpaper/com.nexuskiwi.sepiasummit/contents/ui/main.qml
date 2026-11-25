// Sepia Summit (live) — Plasma 6 wallpaper
// Layers, back to front:
//   1. the full wallpaper image
//   2. weather in the sky (clouds, overcast haze), masked by *_sky.png so it stays behind the peaks
//   3. audio visualiser bars, their base hidden down in the valley (Baseline)
//   4. a cut-out of the nearer ridges (the *_front.png), so bars rise from behind them
//   5. light: overcast dimming, dawn/dusk glow, night; then stars (sky only), fog, rain/snow, lightning
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
    readonly property string skySource: bgSource.replace(/\.png$/, "_sky.png")

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
    readonly property bool rightmost: !span || Screen.virtualX + Screen.width >= desk.right
    readonly property bool showBars: visualiser && rightmost

    clip: true

    property var levels: []
    property bool busy: false

    // ---- weather and sun ---------------------------------------------------
    property var wx: null                        // the sepia-weather cache, or null
    property real elevation: 45                  // sun elevation in degrees
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
    // night 0..1 (full by 11° below the horizon), glow peaks with the sun on the horizon
    readonly property real night: dayNightOn ? smooth(-1, -11, elevation) : 0
    readonly property real dusk: dayNightOn ? Math.max(0, 1 - Math.abs(elevation - 1) / 7) : 0
    readonly property real windPx: (4 + (weatherOn && wx ? wx.wind_kmh : 8) * 0.6) * height / 1440
    // wind direction is where it blows FROM: westerlies push clouds to the right
    readonly property int windSign: weatherOn && wx && Math.sin(wx.wind_dir * Math.PI / 180) > 0 ? -1 : 1
    property real drift: 0                       // seconds, advances the clouds
    // 12 clouds per screen-width of sky (more when one image spans several screens)
    readonly property int cloudSlots: Math.max(12, Math.round(12 * sliceW / Math.max(1, width)))

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
    function updateSun() {
        if (wx && wx.sun_elevation !== undefined) elevation = wx.sun_elevation       // preview mode
        else if (wx) elevation = sunElevation(new Date(), wx.latitude, wx.longitude)
        else elevation = 45
    }
    // A changing query string makes the engine read the file again instead of reusing its cache
    readonly property string weatherFile: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/sepia-summit/weather.qml"
    function fetchWeather() { weatherLoader.source = weatherFile + "?t=" + Date.now() }
    Loader {
        id: weatherLoader
        active: root.weatherOn || root.dayNightOn
        onStatusChanged: {
            if (status === Loader.Ready && item && item.data) {
                // ignore data more than 2 hours old (asleep, no network...)
                root.wx = Date.now() / 1000 - item.data.updated < 7200 ? item.data : null
                root.updateSun()
            } else if (status === Loader.Error) {
                root.wx = null
                root.updateSun()
            }
        }
    }
    Timer { interval: 60000; repeat: true; running: true; triggeredOnStart: true; onTriggered: root.fetchWeather() }
    // ~15 fps is plenty for clouds moving a few pixels a second
    Timer { interval: 66; repeat: true; running: root.weatherOn && root.cover > 0; onTriggered: root.drift += 0.066 }

    // Where the painted sun is, in this item's coordinates (sun_x/sun_y from make_wallpaper.py)
    readonly property point sunPos: {
        const iw = bgImage.sourceSize.width, ih = bgImage.sourceSize.height
        if (!iw || !ih) return Qt.point(-9999, -9999)
        const left = bgSource.indexOf("_LEFT") >= 0, right = bgSource.indexOf("_RIGHT") >= 0
        const world = left || right ? iw * 2 : iw
        const sx = world / 2 - 0.78 * ih - (right ? iw : 0), sy = 0.40 * ih
        const scale = Math.max(sliceW / iw, height / ih)
        return Qt.point(sliceX + (sliceW - iw * scale) / 2 + sx * scale, (height - ih * scale) / 2 + sy * scale)
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

    Rectangle { anchors.fill: parent; color: "#2a1c12" }

    Image {
        id: bgImage
        x: root.sliceX; width: root.sliceW; height: parent.height
        source: root.bgSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
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
            maskSpreadAtMin: 0.3
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
        // hide the painted sun behind the clouds
        Image {
            source: "../images/veil.png"
            width: parent.height * 0.75; height: width
            x: root.sunPos.x - width / 2; y: root.sunPos.y - height / 2
            opacity: Math.min(1, root.overcast * 1.3)
            Behavior on opacity { NumberAnimation { duration: 20000 } }
        }
        // long thin bands when it's mostly cloudy
        Repeater {
            model: 3
            Image {
                // laid out across the whole desktop (sliceX/sliceW), so Span mode shows one sky
                readonly property real span: root.sliceW + width
                source: "../images/stratus" + (index % 2 + 1) + ".png"
                width: root.height * 1.78 * (1.1 + 0.3 * root.rnd(index, 7)); height: root.height * 0.2
                y: root.height * (0.06 + 0.13 * index)
                x: root.sliceX + ((root.rnd(index, 8) * span + root.windSign * root.drift * root.windPx * 0.5) % span + span) % span - width
                opacity: Math.max(0, root.overcast - 0.2) * 0.8
                Behavior on opacity { NumberAnimation { duration: 20000 } }
            }
        }
        // puffy clouds: how many depends on the cloud cover
        Repeater {
            model: root.cloudSlots
            Image {
                readonly property real scale0: (0.32 + 0.4 * root.rnd(index, 2)) * root.height / 1440
                readonly property real span: root.sliceW + width
                source: "../images/cloud" + (index % 5 + 1) + ".png"
                width: 1000 * scale0; height: 460 * scale0
                y: root.height * (0.02 + 0.3 * root.rnd(index, 1))
                x: root.sliceX + ((root.rnd(index, 0) * span + root.windSign * root.drift * root.windPx * (0.7 + 0.6 * root.rnd(index, 3))) % span + span) % span - width
                // dimmer under a grey deck, so they don't outshine an overcast sky
                opacity: index < Math.round(root.cover * root.cloudSlots) ? 0.85 - 0.4 * root.overcast : 0
                Behavior on opacity { NumberAnimation { duration: 15000 } }
            }
        }
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

    // ---- light ------------------------------------------------------------------
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
        layer.effect: MultiEffect { maskEnabled: true; maskSource: skyMask; maskSpreadAtMin: 0.3 }
        Repeater {
            model: Math.round(260 * root.sliceW / root.width)
            Rectangle {
                readonly property real s: 1 + 1.6 * Math.pow(root.rnd(index, 12), 3)
                x: root.sliceX + root.rnd(index, 10) * root.sliceW
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
