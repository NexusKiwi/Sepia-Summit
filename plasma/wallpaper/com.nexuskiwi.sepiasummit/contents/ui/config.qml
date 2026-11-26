import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_Background: bg.text
    property alias cfg_Foreground: fg.text
    property alias cfg_Visualiser: visualiser.checked
    property alias cfg_BarCount: barCount.value
    property alias cfg_Baseline: baseline.value
    property alias cfg_MaxHeight: maxHeight.value
    property alias cfg_BarOpacity: barOpacity.value
    property alias cfg_BarColor: barColor.text
    property alias cfg_Glow: glow.checked
    property alias cfg_Port: port.value
    property alias cfg_Weather: weather.checked
    property alias cfg_DayNight: dayNight.checked
    property alias cfg_Seasons: seasons.checked
    property alias cfg_Glass: glass.checked

    QQC2.TextField { id: bg; Kirigami.FormData.label: "Wallpaper image:"; Layout.preferredWidth: Kirigami.Units.gridUnit * 24 }
    QQC2.TextField { id: fg; Kirigami.FormData.label: "Front ridges (cut-out):"; Layout.preferredWidth: Kirigami.Units.gridUnit * 24 }

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Visualiser" }

    QQC2.CheckBox { id: visualiser; Kirigami.FormData.label: "Show on this screen:" }
    QQC2.SpinBox { id: barCount; Kirigami.FormData.label: "Bars per screen:"; from: 16; to: 256 }
    QQC2.SpinBox { id: baseline; Kirigami.FormData.label: "Valley line (% from top):"; from: 30; to: 100 }
    QQC2.SpinBox { id: maxHeight; Kirigami.FormData.label: "Max bar height (% of screen):"; from: 5; to: 90 }
    QQC2.SpinBox { id: barOpacity; Kirigami.FormData.label: "Opacity (%):"; from: 5; to: 100 }
    QQC2.TextField { id: barColor; Kirigami.FormData.label: "Bar colour (hex):"; Layout.preferredWidth: Kirigami.Units.gridUnit * 8 }
    QQC2.CheckBox { id: glow; Kirigami.FormData.label: "Glow:" }
    QQC2.SpinBox { id: port; Kirigami.FormData.label: "Audio server port:"; from: 1024; to: 65535 }

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Sky" }

    QQC2.CheckBox { id: weather; Kirigami.FormData.label: "Live weather:"; text: "Clouds, rain, snow, fog (needs sepia-weather)" }
    QQC2.CheckBox { id: dayNight; Kirigami.FormData.label: "Day and night:"; text: "Follow the sun at the weather location" }
    QQC2.CheckBox { id: seasons; Kirigami.FormData.label: "Seasons:"; text: "Snowline, trees, fireflies, autumn leaves" }
    QQC2.CheckBox { id: glass; Kirigami.FormData.label: "Glass:"; text: "Frosted glass behind the conky panel" }
}
