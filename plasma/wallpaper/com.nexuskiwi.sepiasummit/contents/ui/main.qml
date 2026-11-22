// Sepia Summit (live) — Plasma 6 wallpaper
// Layers, back to front:
//   1. the full wallpaper image
//   2. audio visualiser bars, their base hidden down in the valley (Baseline)
//   3. a cut-out of the nearer ridges (the *_front.png), so bars rise from behind them
// Audio levels come from sepia-cava-server (a tiny local service around CAVA).
import QtQuick
import QtQuick.Effects
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    readonly property string bgSource: configuration.Background || ""
    readonly property string fgSource: configuration.Foreground || ""
    readonly property int barCount: Math.max(8, configuration.BarCount || 96)
    readonly property real baseline: (configuration.Baseline || 80) / 100
    readonly property real maxHeight: (configuration.MaxHeight || 42) / 100
    readonly property real barOpacity: (configuration.BarOpacity === undefined ? 50 : configuration.BarOpacity) / 100
    readonly property color barColor: configuration.BarColor || "#f5e6c8"
    readonly property bool glow: configuration.Glow !== false
    readonly property string endpoint: "http://127.0.0.1:" + (configuration.Port || 37421) + "/"

    property var levels: []
    property bool busy: false

    Rectangle { anchors.fill: parent; color: "#2a1c12" }

    Image {
        anchors.fill: parent
        source: root.bgSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }

    Item {
        id: viz
        anchors.fill: parent
        opacity: root.barOpacity
        layer.enabled: root.glow
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
                y: viz.height * root.baseline - height
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b, 1.0) }
                    GradientStop { position: 1.0; color: Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b, 0.25) }
                }
                Behavior on height { NumberAnimation { duration: 70 } }
            }
        }
    }

    Image {
        anchors.fill: parent
        source: root.fgSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }

    // ~30 fps poll of the local CAVA server. If it isn't running the bars
    // simply stay down and this looks like the normal wallpaper.
    Timer {
        interval: 33
        repeat: true
        running: root.fgSource !== ""
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
