// Sepia Summit app drawer: a dock button that opens a translucent, full-height
// panel on the left of the screen. The app list comes from contents/code/sepia-drawer.py.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.sessions as Sessions
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    readonly property color cream: "#f5e8ca"
    readonly property color values: "#e4cca2"
    readonly property color tan: "#c4a074"
    readonly property color dim: "#b89b7c"
    readonly property string helper: Qt.resolvedUrl("../code/sepia-drawer.py").toString().replace("file://", "")
    readonly property string listCommand: "python3 " + quoted(helper) + " list"
    readonly property var tabs: ["Games", "Apps", "System"]
    readonly property int edgeGap: 12
    readonly property int dockSpace: 76

    property var apps: []
    property string currentTab: "Games"
    property string query: ""
    property double closedAt: 0
    readonly property var shown: {
        const q = query.trim().toLowerCase()
        if (!q)
            return apps.filter(a => a.tab === currentTab)
        // Rank like Kickoff: name start > word in name > name contains > keyword/generic name > comment
        const words = q.split(/\s+/)
        const score = a => {
            const name = a.name.toLowerCase()
            const kw = a.keywords || ""
            const all = name + " " + kw + " " + (a.comment || "")
            if (!words.every(w => all.includes(w))) return 0
            if (name.startsWith(q)) return 5
            if ((" " + name).includes(" " + q)) return 4
            if (name.includes(q)) return 3
            if ((" " + kw).includes(" " + q)) return 2
            return 1
        }
        return apps.map(a => ({ app: a, s: score(a) }))
                   .filter(x => x.s > 0)
                   .sort((x, y) => y.s - x.s || x.app.name.localeCompare(y.app.name))
                   .map(x => x.app)
    }

    // Only what this machine can actually do (hibernate is often unavailable)
    readonly property var powerActions: [
        { action: "lock", label: "Lock", icon: "system-lock-screen-symbolic", available: session.canLock },
        { action: "logout", label: "Log out", icon: Qt.resolvedUrl("../icons/log-out.svg").toString(), available: session.canLogout },
        { action: "suspend", label: "Sleep", icon: "system-suspend-symbolic", available: session.canSuspend },
        { action: "hibernate", label: "Hibernate", icon: "system-hibernate-symbolic", available: session.canHibernate },
        { action: "reboot", label: "Restart", icon: "system-reboot-symbolic", available: session.canReboot },
        { action: "shutdown", label: "Shut down", icon: "system-shutdown-symbolic", available: session.canShutdown }
    ].filter(a => a.available)

    // The button is the full representation so Plasma never opens its own popup;
    // the drawer is a separate window.
    preferredRepresentation: fullRepresentation
    activationTogglesExpanded: false

    // Plasma's launcher shortcut (the Meta key)
    Connections {
        target: Plasmoid
        function onActivated() { root.toggle() }
    }

    function quoted(s) { return "'" + s.replace(/'/g, "'\\''") + "'" }

    function toggle() {
        if (drawer.visible) {
            drawer.visible = false
        } else if (Date.now() - closedAt > 250) {   // the click that closed it shouldn't reopen it
            query = ""
            search.text = ""
            currentTab = "Games"
            refresh()
            drawer.visible = true
            slideIn.restart()
            drawer.requestActivate()
            search.forceActiveFocus()
        }
    }

    function refresh() {
        runner.disconnectSource(listCommand)
        runner.connectSource(listCommand)
    }

    function launch(app) {
        runner.connectSource("python3 " + quoted(helper) + " launch " + quoted(app.path))
        drawer.visible = false
    }

    // Close first so Plasma's confirmation screen isn't behind the drawer.
    // Anything that ends the session always asks; lock and sleep are harmless.
    function runPower(action) {
        drawer.visible = false
        const ask = Sessions.SessionManagement.ConfirmationMode.ForcePrompt
        switch (action) {
        case "lock": session.lock(); break
        case "logout": session.requestLogout(ask); break
        case "suspend": session.suspend(); break
        case "hibernate": session.hibernate(); break
        case "reboot": session.requestReboot(ask); break
        case "shutdown": session.requestShutdown(ask); break
        }
    }

    Sessions.SessionManagement { id: session }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: (source, data) => {
            if (source === root.listCommand) {
                try { root.apps = JSON.parse(data.stdout) } catch (e) { console.warn("sepia-drawer:", e) }
            }
            disconnectSource(source)
        }
    }

    Component.onCompleted: refresh()

    fullRepresentation: MouseArea {
        hoverEnabled: true
        Layout.minimumWidth: height
        Layout.preferredWidth: height
        Layout.maximumWidth: height
        Layout.fillHeight: true
        onClicked: root.toggle()

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 10
            color: root.tan
            opacity: drawer.visible ? 0.35 : parent.containsMouse ? 0.2 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.round(parent.height * 0.6)
            height: width
            source: "view-app-grid-symbolic"
            color: root.cream
            isMask: true
        }
    }

    PlasmaCore.Dialog {
        id: drawer
        visible: false
        hideOnWindowDeactivate: true
        backgroundHints: PlasmaCore.Dialog.NoBackground
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
        location: PlasmaCore.Types.Floating
        x: Plasmoid.containment.screenGeometry.x + root.edgeGap
        y: Plasmoid.containment.screenGeometry.y + root.edgeGap
        onVisibleChanged: if (!visible) root.closedAt = Date.now()

        mainItem: Item {
            width: 560
            height: Plasmoid.containment.screenGeometry.height - root.edgeGap - root.dockSpace
            Keys.onEscapePressed: drawer.visible = false

            Rectangle {
                id: sheet
                width: parent.width
                height: parent.height
                radius: 16
                color: Qt.rgba(0x1c / 255, 0x12 / 255, 0x0c / 255, 0.88)
                border.color: Qt.rgba(0xc4 / 255, 0xa0 / 255, 0x74 / 255, 0.28)
                border.width: 1

                NumberAnimation on x {
                    id: slideIn
                    running: false
                    from: -40
                    to: 0
                    duration: 170
                    easing.type: Easing.OutCubic
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        QQC2.TextField {
                            id: search
                            Layout.fillWidth: true
                            Layout.rightMargin: 6
                            placeholderText: "Search apps and games"
                            placeholderTextColor: root.dim
                            color: root.cream
                            font.pixelSize: 15
                            leftPadding: 14
                            topPadding: 9
                            bottomPadding: 9
                            background: Rectangle {
                                radius: 10
                                color: Qt.rgba(0xf5 / 255, 0xe8 / 255, 0xca / 255, 0.09)
                                border.color: search.activeFocus ? root.tan : "transparent"
                            }
                            onTextChanged: root.query = text
                            Keys.onEscapePressed: drawer.visible = false
                            Keys.onReturnPressed: if (root.shown.length) root.launch(root.shown[0])
                            Keys.onEnterPressed: if (root.shown.length) root.launch(root.shown[0])
                        }

                        Repeater {
                            model: root.powerActions
                            MouseArea {
                                id: powerButton
                                required property var modelData
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runPower(modelData.action)

                                QQC2.ToolTip.visible: containsMouse
                                QQC2.ToolTip.delay: 300
                                QQC2.ToolTip.text: modelData.label

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 10
                                    color: root.tan
                                    opacity: parent.containsMouse ? 0.25 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                }
                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: 20
                                    height: 20
                                    source: powerButton.modelData.icon
                                    color: powerButton.containsMouse ? root.cream : root.values
                                    isMask: true
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 22
                        visible: root.query.trim() === ""

                        Repeater {
                            model: root.tabs
                            MouseArea {
                                required property string modelData
                                implicitWidth: label.implicitWidth
                                implicitHeight: label.implicitHeight + 8
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.currentTab = modelData

                                Text {
                                    id: label
                                    text: parent.modelData.toUpperCase()
                                    font.family: "Noto Sans"
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.letterSpacing: 2
                                    color: root.currentTab === parent.modelData ? root.cream : root.dim
                                }
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 2
                                    radius: 1
                                    color: root.tan
                                    visible: root.currentTab === parent.modelData
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: root.shown.length
                            font.family: "Noto Sans Mono"
                            font.pixelSize: 12
                            color: root.dim
                        }
                    }

                    GridView {
                        id: grid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        cellWidth: Math.floor(width / 4)
                        cellHeight: 112
                        model: root.shown
                        boundsBehavior: Flickable.StopAtBounds
                        QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }

                        delegate: MouseArea {
                            required property var modelData
                            width: grid.cellWidth
                            height: grid.cellHeight
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.launch(modelData)

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 3
                                radius: 10
                                color: root.tan
                                opacity: parent.containsMouse ? 0.2 : 0
                            }
                            Kirigami.Icon {
                                id: appIcon
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 10
                                width: 52
                                height: 52
                                source: parent.modelData.icon
                            }
                            Text {
                                anchors.top: appIcon.bottom
                                anchors.topMargin: 6
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 12
                                text: parent.modelData.name
                                color: root.values
                                font.family: "Noto Sans"
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
