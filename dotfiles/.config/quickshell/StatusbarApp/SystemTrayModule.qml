import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.CustomTheme

// System tray (StatusNotifierItem hosts).
RowLayout {
    id: tray
    spacing: 4

    // Edge length of the icon drawn inside each 30px round hover target. Fed
    // from statusbar.json ("systemtray": { "iconSize": ... }).
    property int iconSize: 20

    // Flatten every tray icon to a single flat glyph in the bar's accent color
    // (background color while hovered), so the tray matches the bar's own
    // modules. Several common tray clients — nm-applet, firewall-applet — only
    // publish a dark monochrome symbol that is nearly invisible on the dark
    // bar; this makes them read at a glance. Set "systemtray": { "colorize":
    // false } in statusbar.json to render apps' real (multi-color) icons
    // as-is instead.
    property bool colorize: true

    // Collapse the slot when there are no tray items, so the right Repeater
    // hides this Loader and the RowLayout doesn't reserve spacing around an
    // empty, zero-width module (which otherwise leaves a doubled gap next to
    // its neighbours).
    readonly property bool collapsed: SystemTray.items.values.length === 0

    // True while any tray context menu is open. The bar pins itself expanded
    // while this is set: the tray lives in the right area, which is only
    // visible/enabled when the pill is expanded, so without this the popup's
    // anchor item would vanish (pointer leaves the bar -> hover lost ->
    // collapse) and the menu would be dismissed the instant it opened.
    property int openMenuCount: 0
    readonly property bool menuOpen: openMenuCount > 0

    Repeater {
        model: SystemTray.items

        delegate: Rectangle {
            id: trayItem
            required property var modelData

            implicitWidth: 30
            implicitHeight: 30
            radius: 15
            Layout.alignment: Qt.AlignVCenter

            readonly property bool active: mouseArea.containsMouse

            // Same accent-filled circle the other bar modules show on hover.
            color: active ? Theme.primary : "transparent"
            Behavior on color {
                ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
            }

            Image {
                anchors.centerIn: parent
                source: trayItem.modelData.icon
                width: tray.iconSize
                height: tray.iconSize
                sourceSize.width: tray.iconSize
                sourceSize.height: tray.iconSize
                fillMode: Image.PreserveAspectFit
                layer.enabled: tray.colorize
                layer.effect: MultiEffect {
                    // Flatten the icon to a single flat accent-colored glyph.
                    // brightness raises every non-transparent pixel toward white
                    // first, so dark monochrome symbols (nm-applet,
                    // firewall-applet) end up as bright as the solid ones rather
                    // than a dim tinted shape; colorization then recolors the
                    // whole thing to the bar's accent, following the icon's
                    // alpha edges.
                    brightness: 0.5
                    colorization: 1.0
                    colorizationColor: trayItem.active ? Theme.background : Theme.primary
                    Behavior on colorizationColor {
                        ColorAnimation { duration: 500; easing.type: Easing.OutQuint }
                    }
                }
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton && !trayItem.modelData.onlyMenu) {
                        trayItem.modelData.activate()
                    } else if (trayItem.modelData.hasMenu) {
                        trayMenu.open()
                    }
                }
            }

            QsMenuAnchor {
                id: trayMenu
                menu: trayItem.modelData.menu
                anchor.item: trayItem
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom

                // Keep the bar expanded for as long as the menu is open so the
                // anchor item (and this popup) survive the pointer leaving the
                // bar surface.
                onOpened: tray.openMenuCount++
                onClosed: tray.openMenuCount--
            }
        }
    }
}
