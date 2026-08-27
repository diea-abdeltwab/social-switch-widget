// Panel.qml — Social Switch popup (toggle + per-platform grid)
//
// Built on Quattro's own Panel base, the same way the official clock
// example is: `KeyboardPanel` handles anchoring to the bar button and
// Escape-to-close via `PanelKeyCatcher`; we only supply the content.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "diea.social-switch"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null

    readonly property string scriptPath: "/usr/local/bin/social-switch"

    property string blockState: "on"
    property int blockedCount: 0
    property int total: 0
    property var platforms: []

    // Tri-state read of the aggregate, so the global switch can show a
    // genuine "mixed" position instead of jumping to a full ON/OFF
    // extreme the moment a single tile changes. Blocking just one
    // platform out of twelve is not the same situation as blocking all
    // twelve, and the switch showing them identically is what made a
    // single-tile tap look like it had toggled the global switch.
    readonly property bool allBlocked: root.total > 0 && root.blockedCount === root.total
    readonly property bool noneBlocked: root.blockedCount === 0

    function open() { root.controller.show() }
    function close() { root.controller.hide() }

    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.hostWidget || root, direction)
        return false
    }

    // Pushed from Widget.qml's own poll — see that file's applyStatus().
    // Kept as the single source of truth instead of this panel running a
    // second, redundant status Process.
    function applyStatus(data) {
        root.blockState = data.state
        root.blockedCount = data.blocked_count
        root.total = data.total
        root.platforms = data.platforms
    }

    // Ask the bar icon (which owns the actual status Process) to refresh;
    // it will push the result back to us via applyStatus().
    function refresh() {
        if (root.hostWidget && typeof root.hostWidget.refresh === "function")
            root.hostWidget.refresh()
    }

    onOpenedChanged: if (root.opened) root.refresh()

    // Privileged actions. One shared Process, re-pointed per call — the
    // script itself validates the subcommand/platform, this just invokes it.
    //
    // `busy` guards against re-entrancy: tapping a second tile (or the
    // toggle) while a pkexec call is still awaiting a password used to
    // silently overwrite privProc.command without restarting it (Process
    // ignores `running = true` while already running), so the second tap
    // just vanished and the UI looked frozen. Now extra taps are ignored
    // outright until the in-flight one finishes, and the UI dims to make
    // that state visible instead of silently eating clicks.
    property bool busy: false

    Process {
        id: privProc
        onRunningChanged: if (!running) {
            root.busy = false
            root.refresh()
        }
    }

    function runPrivileged(cmd) {
        if (root.busy) return
        root.busy = true
        privProc.command = cmd
        privProc.running = true
    }

    function setGlobalState(wantOn) {
        runPrivileged(["pkexec", root.scriptPath, wantOn ? "on" : "off"])
    }

    // Direct per-platform toggle: block/unblock that one platform,
    // independent of everything else. No separate "exclude" concept —
    // a platform is simply blocked or allowed, and tapping it flips
    // that directly. The global on/off buttons are bulk actions (set
    // every platform to allowed / blocked at once), not a "mode" that
    // this interacts with — see bin/social-switch's BLOCKED_FILE.
    function togglePlatform(key, currentlyBlocked) {
        var sub = currentlyBlocked ? "unblock" : "block"
        runPrivileged(["pkexec", root.scriptPath, sub, key])
    }

    // Failsafe: if pkexec's dialog is dismissed in a way that never fires
    // onRunningChanged (a real edge case, but one that would otherwise
    // wedge the panel shut until the shell restarts), release the busy
    // lock after a minute so a stuck action degrades to "try again"
    // instead of "reload your session".
    Timer {
        interval: 60000
        running: root.busy
        onTriggered: root.busy = false
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(260))
        contentHeight: panel.fittedContentHeight(content.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.switchPanel(direction) }

            Column {
                id: content
                width: parent.width
                spacing: Style.space(10)

                // -- header ---------------------------------------------
                Column {
                    width: parent.width
                    spacing: 2

                    Text {
                        text: "Social Switch"
                        color: root.barForeground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.bold: true
                        font.pixelSize: 13
                    }
                    Text {
                        text: root.allBlocked
                            ? "All blocked"
                            : root.noneBlocked
                              ? "All allowed"
                              : (root.blockedCount + " / " + root.total + " platforms blocked")
                        color: root.barForeground
                        opacity: 0.7
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: 11
                    }
                }

                // -- global toggle ----------------------------------------
                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        // "ON"/"OFF" here means the SAME thing they mean
                        // on the bar icon: ON = social media allowed
                        // (nothing blocked), OFF = blocked. An earlier
                        // version said "Blocking is ON" for the fully-
                        // blocked case — the opposite word for the exact
                        // same state the icon calls "OFF" at the same
                        // moment. Two different labels for one state,
                        // using inverted vocabulary, is what kept looking
                        // like a bug even after the switch's thumb
                        // position itself was already correct.
                        text: root.busy
                            ? "Working…"
                            : root.allBlocked
                              ? "Social media is OFF"
                              : root.noneBlocked
                                ? "Social media is ON"
                                : "Mixed (" + root.blockedCount + " / " + root.total + " blocked)"
                        color: root.barForeground
                        opacity: root.busy ? 0.5 : 1.0
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        id: toggleTrack
                        width: 40; height: 20; radius: 10
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: root.busy ? 0.4 : 1.0
                        color: root.allBlocked
                            ? "#e06c75"
                            : root.noneBlocked
                              ? "#58c46a"
                              : "#d9a441"

                        Rectangle {
                            width: 16; height: 16; radius: 8
                            color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                            // Three real positions, not just two — left
                            // (nothing blocked), middle (some blocked),
                            // right (everything blocked). A tile tap that
                            // blocks one platform out of many now visibly
                            // lands in the middle instead of snapping the
                            // thumb all the way to the "everything
                            // blocked" end.
                            x: root.allBlocked
                                ? parent.width - width - 2
                                : root.noneBlocked
                                  ? 2
                                  : (parent.width - width) / 2
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !root.busy
                            // From "all blocked", tapping releases
                            // everything. From "all allowed" OR "mixed",
                            // tapping blocks everything — mixed counts as
                            // "not fully protected yet" rather than
                            // "already partly done, so allow the rest".
                            onClicked: root.setGlobalState(root.allBlocked ? true : false)
                        }
                    }
                }

                // -- per-platform grid --------------------------------------
                Grid {
                    width: parent.width
                    columns: 4
                    spacing: 6

                    Repeater {
                        model: root.platforms
                        delegate: Rectangle {
                            required property var modelData
                            width: 56; height: 34
                            radius: 6
                            opacity: root.busy ? 0.4 : 1.0
                            color: modelData.status === "blocked"
                                ? Qt.rgba(0.88, 0.42, 0.46, 0.25)
                                : Qt.rgba(0.36, 0.72, 0.45, 0.25)
                            border.width: 1
                            border.color: modelData.status === "blocked"
                                ? "#e06c75"
                                : "#58c46a"

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label.length > 8
                                    ? modelData.label.substring(0, 7) + "…"
                                    : modelData.label
                                color: root.barForeground
                                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                                font.pixelSize: 9
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !root.busy
                                onClicked: root.togglePlatform(
                                    modelData.key, modelData.status === "blocked")
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Tap a platform to block or allow it directly. Green = allowed, red = blocked. The switch above blocks or allows everything at once."
                    color: root.barForeground
                    opacity: 0.55
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: 9
                }
            }
        }
    }
}
