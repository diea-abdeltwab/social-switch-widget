// Widget.qml — Social Switch bar icon (manifest entry point)
//
// Structure mirrors the official Omarchy plugin-development guide
// (omarchyplugins.com/develop.html), which clones the built-in clock
// as its worked example. That guide names this file "BarWidget.qml";
// it's named Widget.qml here because naming it identically to the
// imported `BarWidget` type it instantiates caused a "File name case
// mismatch" load failure in testing — a different filename with the
// same root element sidesteps that.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
    id: root
    moduleName: "diea.social-switch"

    readonly property bool opened: panelLoader.item
        ? panelLoader.item.opened === true
        : false
    readonly property bool popoutSwitchClosing: panelLoader.item
        ? panelLoader.item.popoutSwitchClosing === true
        : false

    readonly property string scriptPath: "/usr/local/bin/social-switch"

    // NOTE: named blockState, not "state" — QML Items already have a
    // built-in `state` property for the QML States system, and an
    // earlier version of this file shadowed it by naming this
    // property "state", which competed with Quickshell's own use of
    // `state` on the same Item.
    property string blockState: "on"      // "on" | "off"
    property int blockedCount: 0
    property int total: 0
    property var platforms: []            // [{key,label,status}]

    function open() { if (panelLoader.item) panelLoader.item.open() }
    function close() { if (panelLoader.item) panelLoader.item.close() }
    function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
    function closeForPopoutSwitch() {
        if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
    }

    function injectPanel() {
        if (!panelLoader.item) return
        panelLoader.item.bar = root.bar
        panelLoader.item.anchorItem = button
        panelLoader.item.hostWidget = root
    }

    // Pushed to the panel too (if loaded), so both the icon and the
    // popup content stay in sync from one fetch instead of each
    // polling /etc/hosts independently.
    function applyStatus(data) {
        root.blockState = data.state
        root.blockedCount = data.blocked_count
        root.total = data.total
        root.platforms = data.platforms
        if (panelLoader.item && panelLoader.item.applyStatus)
            panelLoader.item.applyStatus(data)
    }

    function refresh() { statusProc.running = true }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onBarChanged: injectPanel()

    // Unprivileged status read — safe to poll on a timer since it's
    // just `social-switch status --json` (no root, no /etc/hosts writes).
    Process {
        id: statusProc
        command: [root.scriptPath, "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyStatus(JSON.parse(text))
                } catch (e) {
                    console.warn("social-switch: bad status JSON:", e, text)
                }
            }
        }
    }

    Timer {
        interval: 20000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
            // Hand the panel whatever we already know, so it isn't
            // blank on first open while its own refresh is in flight.
            Qt.callLater(function() {
                if (panelLoader.item && panelLoader.item.applyStatus) {
                    panelLoader.item.applyStatus({
                        state: root.blockState,
                        blocked_count: root.blockedCount,
                        total: root.total,
                        platforms: root.platforms
                    })
                }
            })
        }
    }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.blockState === "off" ? "OFF" : "ON"
        tooltipText: root.blockState === "off"
            ? (root.blockedCount + " / " + root.total + " platforms blocked")
            : "Social media allowed"
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton) root.toggle()
        }
    }
}
