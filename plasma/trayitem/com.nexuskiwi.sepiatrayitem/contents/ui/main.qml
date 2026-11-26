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
    readonly property string statusCommand: "python3 " + quoted(helper) + " source " + quoted(itemId)
    property bool running: true
    property string source: ""     // the item's tray source, e.g. ":1.944/StatusNotifierItem"
    property var pendingClick: null
    readonly property string triggerCommand: "python3 " + quoted(helper) + " trigger " + quoted(itemId) + " "
                                             + quoted(Plasmoid.configuration.leftClick)

    // Clicks go through the system tray widget in the same panel when there is one: it hands the app
    // a Wayland activation token (without one the app may not raise its window) and draws the app's
    // D-Bus menu (Qt apps such as OpenRGB ignore a bare ContextMenu call). Otherwise call D-Bus directly.
    function trayApplet() {
        const applets = Plasmoid.containment ? Plasmoid.containment.applets : []
        for (let i = 0; i < applets.length; i++) {
            if (applets[i].pluginName === "org.kde.plasma.systemtray") return applets[i]
        }
        return null
    }
    function click(item, menu, x, y) {
        // Left click: the configured menu entry if the app has one, else a normal tray click
        if (!menu && Plasmoid.configuration.leftClick && !pendingClick) {
            pendingClick = { item: item, x: x, y: y }
            exec.connectSource(triggerCommand)
            return
        }
        pendingClick = null
        const tray = source ? trayApplet() : null
        if (tray && typeof tray.openContextMenu === "function") {
            const pos = typeof tray.popupPosition === "function" ? tray.popupPosition(item, x, y)
                                                                 : item.mapToGlobal(x, y)
            if (menu) tray.openContextMenu(source, pos, item)
            else tray.activate(source, pos, item)
            return
        }
        if (menu) {
            const p = item.mapToGlobal(x, y)
            run("menu " + quoted(itemId) + " " + Math.round(p.x) + " " + Math.round(p.y))
        } else {
            run("activate " + quoted(itemId))
        }
    }

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
            if (source === root.statusCommand) {
                root.source = data.stdout.trim()
                root.running = root.source !== ""
            }
            if (source === root.triggerCommand && root.pendingClick) {
                const c = root.pendingClick
                if (data.stdout.trim() === "1") root.pendingClick = null
                else root.click(c.item, false, c.x, c.y)     // no such entry: a normal tray click
            }
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
        onClicked: mouse => root.click(button, mouse.button === Qt.RightButton, mouse.x, mouse.y)

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
