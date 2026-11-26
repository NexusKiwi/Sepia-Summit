// Sepia Tray Button: one tray app's icon as its own dock button, so it can sit anywhere in the
// dock (the system tray always puts its arrow last). Clicks go to the app's StatusNotifierItem.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    readonly property color tan: "#c4a074"
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property string helper: Qt.resolvedUrl("../code/sepia-trayitem.py").toString().replace("file://", "")
    readonly property string itemId: Plasmoid.configuration.itemId
    readonly property string statusCommand: "python3 " + quoted(helper) + " status " + quoted(itemId)
    property bool running: true

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    toolTipMainText: Plasmoid.configuration.label
    toolTipSubText: running ? "" : "Not running"

    function quoted(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function run(args) { exec.connectSource("python3 " + quoted(helper) + " " + args + " ; echo") }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            if (source === root.statusCommand) root.running = data.stdout.trim() === "1"
            disconnectSource(source)
        }
    }
    Timer {
        interval: 10000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: exec.connectSource(root.statusCommand)
    }

    fullRepresentation: MouseArea {
        id: button
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        Layout.preferredWidth: root.vertical ? -1 : height
        Layout.preferredHeight: root.vertical ? width : -1
        Layout.fillWidth: root.vertical
        Layout.fillHeight: !root.vertical
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                const p = button.mapToGlobal(mouse.x, mouse.y)
                root.run("menu " + root.quoted(root.itemId) + " " + Math.round(p.x) + " " + Math.round(p.y))
            } else {
                root.run("activate " + root.quoted(root.itemId))
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 10
            color: "#f5e8ca"
            opacity: parent.containsMouse ? 0.10 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.round(Math.min(parent.width, parent.height) * 0.62)   // the drawing has less padding than Breeze tray icons
            height: width
            source: Plasmoid.configuration.icon
            opacity: root.running ? 1 : 0.45
        }
    }
}
