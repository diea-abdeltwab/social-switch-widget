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
    property string blockState: "on"      // "on" | "off"  ("off" = anything blocked)
    property int blockedCount: 0          // effectively blocked right now
    property int wantedCount: 0           // blocked as the user asked (can be > blockedCount)
    property int total: 0
    property var platforms: []            // [{key,label,status,wanted}]
    property bool needsSync: false        // wanted-but-missing entries -> `sync`
    property var lastData: null           // raw JSON, handed to the panel as-is

    // True when something the user asked to block is not actually blocked in
    // /etc/hosts (another tool rewrote the file) - fixed by `social-switch sync`.
    function computeNeedsSync(data) {
        var i
        if (data.platforms) {
            for (i = 0; i < data.platforms.length; i++) {
                var p = data.platforms[i]
                if (p.wanted === true && p.status !== "blocked") return true
            }
        }
        if (data.custom) {
            for (i = 0; i < data.custom.length; i++) {
                if (data.custom[i].status !== "blocked") return true
            }
        }
        return false
    }

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
        root.lastData = data
        root.blockState = data.state
        root.blockedCount = data.blocked_count
        // wanted_count exists from social-switch 2.2; older CLIs only had blocked_count.
        root.wantedCount = (data.wanted_count !== undefined) ? data.wanted_count : data.blocked_count
        root.total = data.total
        root.platforms = data.platforms
        root.needsSync = root.computeNeedsSync(data)
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
                if (root.lastData && panelLoader.item && panelLoader.item.applyStatus)
                    panelLoader.item.applyStatus(root.lastData)
            })
        }
    }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: (root.blockState === "off" ? "OFF" : "ON") + (root.needsSync ? "!" : "")
        tooltipText: root.needsSync
            ? "Some blocks are missing from /etc/hosts - open the panel and re-apply"
            : root.blockState === "off"
              ? (root.wantedCount + " / " + root.total + " platforms blocked")
              : "Social media allowed"
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton) root.toggle()
        }
    }
}
