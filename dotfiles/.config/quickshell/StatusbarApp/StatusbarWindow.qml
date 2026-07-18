import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.CustomTheme

// One bar instance is created per configured monitor (see targetScreens
// below), each as its own PanelWindow. Everything that must be a single
// source of truth across all of them — the settings file, its FileViews, and
// the IPC handler — lives on this outer Scope instead of on the PanelWindow.
Scope {
    id: statusbarScope

    // --- USER SETTINGS ---
    // One of two files is the "master" that feeds the settings object below:
    //
    //   1. ~/.config/ml4w-statusbar/statusbar.json — the user override. When this
    //      file EXISTS it is the master: every value is read from it and the
    //      Sidebar switches write their changes (enabled / alwaysExpanded) back
    //      into it. The shipped file is ignored while it exists.
    //   2. ~/.config/ml4w/settings/statusbar.json — the shipped fallback, used
    //      only when the override file is absent. It carries the dynamic state
    //      the SidebarApp writes (bar.enabled and bar.alwaysExpanded).
    //
    // The active master file is merged over the built-in defaults, so a partial
    // or entirely missing file still leaves every value defined.
    readonly property var defaultSettings: ({
        "bar":    { "height": 40, "reservedHeight": 72, "enabled": true, "alwaysExpanded": false, "monitors": [] },
        "pill":   { "collapsedWidth": 0, "expandedWidth": 680, "radius": 12, "animationDuration": 350 },
        "modules":{ "left": ["terminal", "workspaces"],
                    "center": ["launcher", "clock", "swaync"],
                    "right": ["updates", "battery", "powerprofile", "volume", "systemtray", "logo", "power"] },
        "border": { "width": 2, "colorTop": "", "colorBottom": "" },
        "opacity":{ "collapsed": 0.6, "expanded": 0.8 },
        "clock":  { "format": "HH:mm", "dateFormat": "ddd, dd MMM" },
        "workspaces": { "count": 5 }
    })

    property var settings: defaultSettings

    // True while the user override file is present. Decides which file is the
    // master for both reads (applySettings) and writes (setEnabled /
    // setAlwaysExpanded).
    property bool overrideExists: false

    // User override / master file. When it loads it becomes the source of truth;
    // when it is absent (loadFailed) the shipped file takes over. printErrors is
    // off so a missing override does not log an error on every startup/reload.
    FileView {
        id: overrideFile
        path: Quickshell.env("HOME") + "/.config/ml4w-statusbar/statusbar.json"
        blockLoading: true
        printErrors: false
        onLoaded: { statusbarScope.overrideExists = true; statusbarScope.applySettings() }
        onLoadFailed: { statusbarScope.overrideExists = false; statusbarScope.applySettings() }
    }

    // Shipped fallback holding the dynamic state (enabled / alwaysExpanded), used
    // only when the override file is absent. Changes are not picked up
    // automatically; trigger a re-read explicitly with
    //   qs ipc call statusbar reload
    FileView {
        id: settingsFile
        path: Quickshell.env("HOME") + "/.config/ml4w/settings/statusbar.json"
        blockLoading: true
        onLoaded: statusbarScope.applySettings()
    }

    // The active master file: the override when it exists, otherwise the shipped
    // file. The Sidebar switches write here and applySettings reads from here.
    function masterFile() {
        return statusbarScope.overrideExists ? overrideFile : settingsFile
    }

    // Force a re-read of both settings files and re-apply them. reload()
    // refreshes each FileView from disk (re-firing onLoaded/onLoadFailed, which
    // re-runs applySettings with an up-to-date overrideExists).
    function reloadSettings(): void {
        overrideFile.reload()
        settingsFile.reload()
        applySettings()
    }

    // Parse a settings JSON document that may contain a /* ... */ comment block
    // and — being hand-edited — trailing commas before a closing } or ], which
    // strict JSON.parse rejects. Returns the parsed object, or undefined when the
    // text is empty or cannot be parsed even after that cleanup. Never throws.
    function parseSettings(src) {
        if (!src)
            return undefined
        let raw = src.replace(/\/\*[\s\S]*?\*\//g, "")
        if (raw.trim() === "")
            return undefined
        try {
            return JSON.parse(raw)
        } catch (e) {
            try {
                // Tolerate trailing commas: ",}" / ",]" (optional whitespace).
                return JSON.parse(raw.replace(/,(\s*[}\]])/g, "$1"))
            } catch (e2) {
                console.warn("statusbar settings: could not parse a file,"
                    + " ignoring it:", e2)
                return undefined
            }
        }
    }

    // Merge one JSON document (given as text) over an already-built settings
    // object, key by key. Empty or unparseable text is ignored so a
    // missing/partial file never clears previously merged values.
    function mergeSettings(merged, src): void {
        let parsed = parseSettings(src)
        if (parsed === undefined)
            return
        for (let group in parsed)
            for (let key in parsed[group])
                if (merged[group] !== undefined)
                    merged[group][key] = parsed[group][key]
    }

    // Rebuild the settings object: the built-in defaults with the master file
    // merged on top. An explicit masterText can be passed (e.g. right after a
    // switch writes the master file) so the merge does not depend on the FileView
    // buffer having refreshed yet.
    function applySettings(masterText): void {
        let merged = JSON.parse(JSON.stringify(statusbarScope.defaultSettings))
        let text = (masterText !== undefined) ? masterText : statusbarScope.masterFile().text()
        mergeSettings(merged, text)
        statusbarScope.settings = merged
    }

    // Persist a bar.<key> boolean into the master file and return the updated
    // text. A regex replace is used when the key is already present (so the
    // file's formatting/comments are kept); when the key is missing (e.g. an
    // override file that did not list it) it falls back to a JSON rewrite of the
    // parsed document. If the file cannot be parsed at all the write is skipped
    // rather than replaced with an empty object, so a malformed hand-edited
    // override is never wiped — its current text is returned unchanged.
    function persistBarFlag(key, on): string {
        let file = statusbarScope.masterFile()
        let src = file.text()
        let re = new RegExp('("' + key + '"\\s*:\\s*)(true|false)')
        let updated
        if (re.test(src)) {
            updated = src.replace(re, "$1" + (on ? "true" : "false"))
        } else {
            let obj = statusbarScope.parseSettings(src)
            if (obj === undefined && src && src.trim() !== "") {
                // Unparseable and non-empty: don't destroy the user's file.
                console.warn("statusbar settings: master file is not valid"
                    + " JSON; leaving it untouched instead of overwriting.")
                return src
            }
            if (typeof obj !== "object" || obj === null)
                obj = {}
            if (obj.bar === undefined)
                obj.bar = {}
            obj.bar[key] = on
            updated = JSON.stringify(obj, null, 4) + "\n"
        }
        file.setText(updated)
        return updated
    }

    // Whether the bar is shown. The "enabled" flag in statusbar.json is the
    // single source of truth; it is toggled from the SidebarApp switch and via
    // "qs ipc call statusbar toggle", persisted back to the file, and survives
    // restarts. Kept as a binding so a settings reload updates it for free.
    property bool barEnabled: settings.bar.enabled

    // Persist the enabled state into the master file (override when present,
    // otherwise the shipped file) and apply it. applySettings re-parses the
    // updated text, which updates settings.bar.enabled and therefore the
    // barEnabled binding above.
    function setEnabled(on: bool): void {
        applySettings(persistBarFlag("enabled", on))
    }

    // When set in statusbar.json the pill never collapses: it stays in its
    // expanded (full-width) state independent of hover or the IPC toggle. This
    // is purely visual — unlike barExpanded it does not grab the keyboard — so
    // the left/right module areas remain permanently visible.
    property bool alwaysExpanded: settings.bar.alwaysExpanded

    // Persist the alwaysExpanded state into the master file and apply it.
    // Mirrors setEnabled.
    function setAlwaysExpanded(on: bool): void {
        applySettings(persistBarFlag("alwaysExpanded", on))
    }

    // --- SHARED UPDATE-CHECK STATE ---
    // Polled once here (rather than once per monitor's UpdatesModule) so N
    // bar instances don't each spawn ml4w-check-system-updates and don't
    // fight over the `qs ipc call updates ...` IpcHandler target — Quickshell
    // only honors the first registration for a given target and warns about
    // the rest. Every monitor's copy of the module just displays this count.
    property int updatesCount: 0

    function refreshUpdates(): void {
        updatesProc.running = false
        updatesProc.running = true
    }

    // Parse the script's JSON output ({"text": "69", ...}); an empty line
    // means zero updates and the script prints nothing.
    Process {
        id: updatesProc
        command: ["bash", "-c",
            Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-check-system-updates"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let raw = this.text.trim()
                    statusbarScope.updatesCount = raw ? parseInt(JSON.parse(raw).text) || 0 : 0
                } catch (e) {
                    statusbarScope.updatesCount = 0
                }
            }
        }
    }

    // Re-check on the same 1800s interval as the Waybar module.
    Timer {
        interval: 1800 * 1000
        running: true
        repeat: true
        onTriggered: statusbarScope.refreshUpdates()
    }

    // Let external scripts drive the module via `qs ipc call updates ...`
    // (ml4w-install-system-updates calls "refresh" after running updates).
    // `reset` clears the count immediately so the module hides itself
    // without waiting for the next poll.
    IpcHandler {
        target: "updates"
        function reset(): void { statusbarScope.updatesCount = 0 }
        function refresh(): void { statusbarScope.refreshUpdates() }
    }

    // --- MONITOR PLACEMENT ---
    // Which monitors get a bar instance, driven by bar.monitors in the settings
    // file:
    //   []                 (default)  -> first monitor only, i.e. the original
    //                                     single-bar behavior from before this
    //                                     setting existed.
    //   ["all"] or ["*"]              -> one bar per connected monitor.
    //   ["DP-1", "DP-2"]              -> an explicit list of monitor names, as
    //                                     reported by `hyprctl monitors`.
    // Falls back to the first monitor when named monitors match nothing
    // currently connected, so a stale/typo'd name never leaves zero bars.
    readonly property var targetScreens: {
        let screens = Quickshell.screens
        let names = statusbarScope.settings.bar.monitors || []
        if (names.length === 0)
            return screens.length > 0 ? [screens[0]] : []
        if (names.indexOf("all") !== -1 || names.indexOf("*") !== -1)
            return screens
        let filtered = screens.filter(s => names.indexOf(s.name) !== -1)
        return filtered.length > 0 ? filtered : (screens.length > 0 ? [screens[0]] : [])
    }

    // --- CROSS-MONITOR IPC ROUTING ---
    // "focus"/"expand"/"collapse" act on a single bar (the one on the currently
    // focused monitor) rather than all of them at once. Each token is bumped
    // here and every bar instance below reacts only when its own monitor is the
    // focused one — the same pattern the overview module uses for its
    // per-monitor focus grab.
    property int focusRequestToken: 0
    property int expandToggleToken: 0
    property int collapseToken: 0

    IpcHandler {
        target: "statusbar"
        function toggle(): void { statusbarScope.setEnabled(!statusbarScope.settings.bar.enabled) }
        // Named enable/disable rather than show/hide: "show" is a reserved
        // subcommand of "qs ipc" and would never reach the function.
        function enable(): void { statusbarScope.setEnabled(true) }
        function disable(): void { statusbarScope.setEnabled(false) }
        // Persist and apply the alwaysExpanded (permanently expanded) mode,
        // toggled from the SidebarApp switch.
        function alwaysExpand(): void { statusbarScope.setAlwaysExpanded(true) }
        function autoCollapse(): void { statusbarScope.setAlwaysExpanded(false) }
        // Re-read statusbar.json from disk (used by the SidebarApp switch).
        function refresh(): void { statusbarScope.reloadSettings() }
        // Expand the bar on the focused monitor (if needed) and grab the
        // keyboard for navigation. Bound to SUPER + SPACE. Idempotent: when
        // that bar is already expanded it only re-grabs keyboard focus instead
        // of toggling back to collapsed, so the keybinding always lands in
        // keyboard-navigation mode.
        function focus(): void { statusbarScope.focusRequestToken++ }
        // Toggle between collapsed and expanded mode on the focused monitor.
        function expand(): void { statusbarScope.expandToggleToken++ }
        function collapse(): void { statusbarScope.collapseToken++ }
        // Re-read statusbar.json and apply the changes.
        function reload(): void { statusbarScope.reloadSettings() }
    }

    Variants {
        id: barVariants
        model: statusbarScope.targetScreens

        PanelWindow {
            id: root

            required property var modelData
            screen: modelData

            // Used to route the shared focus/expand/collapse IPC tokens above to
            // only the bar on the currently focused monitor.
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
            property bool monitorIsFocused: Hyprland.focusedMonitor?.id === monitor?.id

            // --- WAYLAND CONFIGURATION ---
            WlrLayershell.layer: WlrLayer.Top
            // Keyboard focus is owned by the HyprlandFocusGrab below (the same primitive
            // the Calendar/Power popups use), not by the layer-shell focus mode. A
            // WlrKeyboardFocus.Exclusive grab held the keyboard until Escape and left
            // running apps dead; OnDemand never grabbed from the keybinding at all. The
            // focus grab gives the bar the keyboard while expanded *and* fires onCleared
            // when the pointer/keyboard goes to another window, which is what hands focus
            // back to the app (and collapses the bar). Leave the layer-shell mode at its
            // default (None) so the two mechanisms don't fight.

            // Grabs the keyboard for this bar while it is expanded so SUPER + SPACE can
            // drive Left/Right/Return navigation, and releases it the moment the user
            // interacts with another window (clicking/entering an app) — which returns
            // the keyboard to that app and collapses the bar.
            HyprlandFocusGrab {
                windows: [root]
                active: root.barExpanded
                onCleared: root.barExpanded = false
            }

            // Settings are read from the shared Scope above; every bar instance
            // sees the same values.
            property var settings: statusbarScope.settings

            property int barHeight: settings.bar.height
            // Constant vertical space reserved for the bar (windows tile below this).
            property int reservedHeight: settings.bar.reservedHeight
            property bool barEnabled: settings.bar.enabled

            // Hide completely and reserve no space when disabled.
            visible: barEnabled
            // Reserve 20px less than the band so the gap below the pill is smaller
            // than above (windows tile 20px higher).
            exclusiveZone: barEnabled ? reservedHeight - 20 : 0

            // Keep the pill expanded regardless of hover. Set via the shared
            // focusRequestToken/expandToggleToken IPC routing below, which only
            // reaches the bar on the currently focused monitor.
            property bool barExpanded: false

            property bool alwaysExpanded: settings.bar.alwaysExpanded

            // True while a system-tray context menu is open on this monitor's bar.
            // Kept per-instance (rather than on the shared scope) since each bar
            // has its own SystemTrayModule and the pill should only pin itself
            // expanded on the monitor where the menu is actually showing.
            property bool trayMenuOpen: false

            // Route the shared IPC tokens to this window only when its monitor
            // currently has focus.
            Connections {
                target: statusbarScope
                function onFocusRequestTokenChanged(): void {
                    if (!root.monitorIsFocused)
                        return
                    root.barExpanded = true
                    keyHandler.forceActiveFocus()
                }
                function onExpandToggleTokenChanged(): void {
                    if (root.monitorIsFocused)
                        root.barExpanded = !root.barExpanded
                }
                function onCollapseTokenChanged(): void {
                    if (root.monitorIsFocused)
                        root.barExpanded = false
                }
            }

            // --- MODULE PLACEMENT ---
            // Each module name in the settings file maps to the component placed into
            // the left/center/right groups. Unknown names load nothing.
            Component { id: cTerminal;   TerminalModule {} }
            Component {
                id: cWorkspaces
                WorkspacesModule {
                    minWorkspaces: root.settings.workspaces.count
                }
            }
            Component { id: cLauncher;   LauncherModule {} }
            Component {
                id: cClock
                ClockModule {
                    expanded: pill.expanded
                    timeFormat: root.settings.clock.format
                    dateFormat: root.settings.clock.dateFormat
                }
            }
            Component { id: cSwaync;     SwayncModule {} }
            Component {
                id: cSystemTray
                SystemTrayModule {
                    // Rebuild keyboard navigation when the tray empties or repopulates
                    // (it collapses out of the layout when it has no items).
                    onCollapsedChanged: Qt.callLater(root.rebuildNavItems)
                    // Surface the open-menu state up to the window so the pill stays
                    // expanded for as long as a tray menu is showing.
                    Binding {
                        target: root
                        property: "trayMenuOpen"
                        value: menuOpen
                    }
                }
            }
            Component { id: cLogo;       Ml4wLogoModule {} }
            Component { id: cPower;      PowerModule {} }
            Component { id: cVolume;     VolumeModule {} }
            Component {
                id: cUpdates
                UpdatesModule {
                    count: statusbarScope.updatesCount
                    // Rebuild the keyboard navigation list when the module hides or
                    // reappears (its collapsed state tracks the available update count).
                    onCollapsedChanged: Qt.callLater(root.rebuildNavItems)
                }
            }
            Component {
                id: cBattery
                BatteryModule {
                    // Rebuild the keyboard navigation list when the module hides or
                    // reappears (it only shows while running on battery power).
                    onCollapsedChanged: Qt.callLater(root.rebuildNavItems)
                }
            }
            Component { id: cPowerProfile; PowerProfileModule {} }

            readonly property var moduleComponents: ({
                "terminal":   cTerminal,
                "workspaces": cWorkspaces,
                "launcher":   cLauncher,
                "clock":      cClock,
                "swaync":     cSwaync,
                "systemtray": cSystemTray,
                "logo":       cLogo,
                "power":      cPower,
                "updates":      cUpdates,
                "volume":       cVolume,
                "battery":      cBattery,
                "powerprofile": cPowerProfile
            })

            // --- KEYBOARD NAVIGATION ---
            // Ordered left-to-right list of the navigable items, rebuilt from the
            // placed modules whenever the layout or the (dynamic) workspace buttons
            // change. The workspace buttons are spliced in at the workspaces module's
            // position; collection modules without a single action (the system tray)
            // are skipped.
            property var navItems: []
            // Index of the keyboard-selected item, or -1 when none is selected.
            property int focusIndex: -1

            // The placed workspaces module, tracked so navItems can be rebuilt when its
            // button list changes (workspaces appear/disappear asynchronously).
            property var workspacesRef: null
            Connections {
                target: root.workspacesRef
                ignoreUnknownSignals: true
                function onNavButtonsChanged(): void { root.rebuildNavItems() }
            }

            function rebuildNavItems(): void {
                let items = []
                let ws = null
                let groups = [leftRepeater, centerRepeater, rightRepeater]
                for (let g = 0; g < groups.length; g++) {
                    let rep = groups[g]
                    for (let i = 0; i < rep.count; i++) {
                        let loader = rep.itemAt(i)
                        let m = loader ? loader.item : null
                        if (!m)
                            continue
                        if (m.collapsed === true)                // hidden (e.g. updates)
                            continue
                        if (m.navButtons !== undefined) {        // workspaces
                            ws = m
                            items = items.concat(m.navButtons)
                        } else if (typeof m.activate === "function") {
                            items.push(m)
                        }
                    }
                }
                root.workspacesRef = ws
                root.navItems = items
            }

            Component.onCompleted: Qt.callLater(rebuildNavItems)
            onSettingsChanged: Qt.callLater(rebuildNavItems)

            // Highlight exactly the item at focusIndex and clear all others. Called
            // both when the selection moves and when navItems changes underneath it.
            function applyFocus(): void {
                let items = root.navItems
                for (let i = 0; i < items.length; i++)
                    items[i].focused = (i === root.focusIndex)
            }

            onFocusIndexChanged: applyFocus()
            onNavItemsChanged: {
                // Keep the selection in range when the workspace count changes.
                if (root.focusIndex >= root.navItems.length)
                    root.focusIndex = root.navItems.length - 1
                applyFocus()
            }

            onBarExpandedChanged: {
                if (barExpanded) {
                    focusIndex = 0
                    keyHandler.forceActiveFocus()
                } else {
                    focusIndex = -1
                }
            }

            function moveFocus(dir: int): void {
                if (!barExpanded)
                    return
                let n = root.navItems.length
                root.focusIndex = (root.focusIndex + dir + n) % n
            }

            // Forward an Up/Down press to the keyboard-selected module if it exposes a
            // step() function (e.g. the volume module), so the arrows adjust it in place
            // without leaving keyboard-navigation mode.
            function stepFocused(dir: int): void {
                if (root.focusIndex < 0 || root.focusIndex >= root.navItems.length)
                    return
                let m = root.navItems[root.focusIndex]
                if (typeof m.step === "function")
                    m.step(dir)
            }

            function activateFocused(): void {
                if (root.focusIndex >= 0 && root.focusIndex < root.navItems.length)
                    root.navItems[root.focusIndex].activate()
                // Collapse so the keyboard is handed back to the (possibly newly
                // launched) application instead of staying captured by the bar.
                root.barExpanded = false
            }

            color: "transparent"

            // Full-width strip anchored to the top of this monitor
            anchors {
                top: true
                left: true
                right: true
            }

            margins {
                top: 0
            }

            implicitHeight: barHeight + 40

            // ==========================================
            // CENTERED PILL
            // ==========================================
            Item {
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                // Center the pill within the reserved band. The window is taller than
                // the band (to fit the shadow / expanded pill), so offset accordingly.
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: (root.reservedHeight / 2) - (root.implicitHeight / 2)

                // Collapsed = sized to content, Expanded = fixed width.
                property bool expanded: hoverHandler.hovered || root.barExpanded
                    || root.alwaysExpanded || root.trayMenuOpen
                // 0 in the settings file means "hug the center content".
                property real collapsedWidth: root.settings.pill.collapsedWidth > 0
                    ? root.settings.pill.collapsedWidth
                    : centerArea.implicitWidth + 32

                // Minimum width the content needs so the centered center area never
                // overlaps the left/right areas. The center stays centered, so each
                // side must clear half of it: the bar has to be at least as wide as the
                // center plus twice the wider of the two side areas (whichever side
                // would collide first), plus the 16px edge margins and some breathing
                // room. Computed live so adding workspaces (or any module growing)
                // pushes the bar wider instead of clipping.
                property real contentWidth: centerArea.implicitWidth
                    + 2 * Math.max(leftArea.implicitWidth, rightArea.implicitWidth)
                    + 64
                // expandedWidth from the settings file is treated as a minimum: the
                // pill grows past it when the content needs more room.
                property real expandedWidth: Math.max(
                    root.settings.pill.expandedWidth, contentWidth)

                width: expanded ? expandedWidth : collapsedWidth
                height: expanded ? root.barHeight + 10 : root.barHeight

                Behavior on width {
                    NumberAnimation {
                        duration: root.settings.pill.animationDuration
                        easing.type: Easing.OutQuint
                    }
                }

                Behavior on height {
                    NumberAnimation {
                        duration: root.settings.pill.animationDuration
                        easing.type: Easing.OutQuint
                    }
                }

                HoverHandler {
                    id: hoverHandler
                }

                // Captures arrow keys (navigate), Return (execute) and Escape
                // (collapse) while the bar is in expanded mode.
                FocusScope {
                    id: keyHandler
                    anchors.fill: parent
                    focus: root.barExpanded
                    Keys.onLeftPressed: root.moveFocus(-1)
                    Keys.onRightPressed: root.moveFocus(1)
                    Keys.onUpPressed: root.stepFocused(1)
                    Keys.onDownPressed: root.stepFocused(-1)
                    Keys.onReturnPressed: root.activateFocused()
                    Keys.onEnterPressed: root.activateFocused()
                    Keys.onEscapePressed: root.barExpanded = false
                }

                RectangularShadow {
                    anchors.fill: pillBg
                    radius: pillBg.radius
                    blur: 15
                    color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.4)
                }

                // Gradient BORDER layer (outer)
                Rectangle {
                    id: pillBg
                    anchors.fill: parent
                    radius: root.settings.pill.radius
                    opacity: pill.expanded
                        ? root.settings.opacity.expanded
                        : root.settings.opacity.collapsed
                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.settings.pill.animationDuration
                            easing.type: Easing.OutQuint
                        }
                    }

                    // Border colors come from the settings file; empty strings fall
                    // back to the dynamic wallpaper theme.
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop {
                            position: 0.0
                            color: root.settings.border.colorTop !== ""
                                ? root.settings.border.colorTop
                                : Theme.primary
                        }
                        GradientStop {
                            position: 1.0
                            color: root.settings.border.colorBottom !== ""
                                ? root.settings.border.colorBottom
                                : Theme.on_primary
                        }
                    }

                    // Actual background fill (inner), inset by the border thickness
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: root.settings.border.width
                        radius: parent.radius - anchors.margins
                        color: Theme.background
                    }
                }

                // ==========================================
                // LEFT AREA (only visible when expanded)
                // ==========================================
                RowLayout {
                    id: leftArea
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    opacity: pill.expanded ? 1 : 0
                    visible: opacity > 0
                    enabled: pill.expanded

                    Behavior on opacity {
                        NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
                    }

                    Repeater {
                        id: leftRepeater
                        model: root.settings.modules.left
                        Loader {
                            Layout.alignment: Qt.AlignVCenter
                            sourceComponent: root.moduleComponents[modelData] || null
                            onLoaded: Qt.callLater(root.rebuildNavItems)
                        }
                    }
                }

                // ==========================================
                // CENTER AREA (always visible)
                // ==========================================
                RowLayout {
                    id: centerArea
                    anchors.centerIn: parent
                    spacing: 14

                    Repeater {
                        id: centerRepeater
                        model: root.settings.modules.center
                        Loader {
                            Layout.alignment: Qt.AlignVCenter
                            sourceComponent: root.moduleComponents[modelData] || null
                            onLoaded: Qt.callLater(root.rebuildNavItems)
                        }
                    }
                }

                // ==========================================
                // RIGHT AREA (only visible when expanded)
                // ==========================================
                RowLayout {
                    id: rightArea
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    opacity: pill.expanded ? 1 : 0
                    visible: opacity > 0
                    enabled: pill.expanded

                    Behavior on opacity {
                        NumberAnimation { duration: 250; easing.type: Easing.OutQuint }
                    }

                    Repeater {
                        id: rightRepeater
                        model: root.settings.modules.right
                        Loader {
                            Layout.alignment: Qt.AlignVCenter
                            sourceComponent: root.moduleComponents[modelData] || null
                            // Collapse the layout slot when the module marks itself
                            // collapsed (e.g. the updates module with no pending
                            // updates). Reading the plain `collapsed` flag — rather than
                            // the module's effective `visible` — avoids a binding latch
                            // that would pin this Loader hidden once the right area
                            // collapses in the pill's collapsed state.
                            visible: (item && item.collapsed !== undefined) ? !item.collapsed : true
                            onLoaded: Qt.callLater(root.rebuildNavItems)
                        }
                    }
                }
            }
        }
    }
}
