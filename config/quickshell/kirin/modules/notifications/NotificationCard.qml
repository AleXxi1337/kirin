pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets
import qs.components
import qs.services

// One notification, after Android's: collapsed it's a single line of title
// and age over a single line of text, with an expand chip at the right;
// hovering unfolds it (app name, the whole text, the actions). Used by the
// popups and the notification centre. Clicking runs the default action;
// the close button dismisses it.
Rectangle {
    id: root

    required property var notification
    // Set by the popups to animate the card away first; the centre leaves
    // them null and acts at once.
    property var dismissHandler: null
    property var activateHandler: null
    property var invokeHandler: null
    // Popup: the close button only when unfolded. Centre: the same.
    property bool popup: false
    readonly property bool hovered: hover.hovered
    readonly property bool critical: notification?.urgency === NotificationUrgency.Critical
    readonly property var buttons: Notifs.buttons(notification)
    // The sending app's desktop entry and icon name, for its symbol.
    readonly property var entry: {
        DesktopEntries.applications.values;
        const id = notification?.desktopEntry ?? "";
        const icon = /^image:\/\/icon\/([^?]+)/.exec(notification?.image ?? "")?.[1] ?? notification?.appIcon ?? "";
        return (id ? DesktopEntries.byId(id) : null) ?? (icon && !icon.startsWith("/") ? DesktopEntries.byId(icon) : null) ?? DesktopEntries.heuristicLookup(notification?.appName ?? "");
    }
    readonly property string appIcon: {
        const icon = notification?.appIcon ?? "";
        if (icon && !icon.startsWith("/") && !icon.startsWith("file:"))
            return icon;
        // An icon name sent as the app icon can end up as the image.
        const m = /^image:\/\/icon\/([^?]+)/.exec(notification?.image ?? "");
        return m ? m[1] : notification?.desktopEntry ?? "";
    }
    readonly property bool knownApp: entry !== null || appIcon !== ""
    // A real picture (a contact's photo, a cover); not the app icon, which
    // Quickshell also puts here when the app sent no image.
    readonly property string image: {
        const img = notification?.image ?? "";
        return img.startsWith("image://icon/") ? "" : img;
    }
    readonly property string summary: notification?.summary ?? ""
    readonly property string body: notification?.body ?? ""

    // Anything more to show than the collapsed lines.
    readonly property bool expandable: buttons.length > 0 || fullBody.lineCount > 1 || fullBody.truncated || summaryLine.truncated
    readonly property bool expanded: expandable && hovered
    // 0 collapsed … 1 expanded; everything that unfolds follows it, so the
    // card's height moves in one piece.
    property real shown: expanded ? 1 : 0

    Behavior on shown {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    readonly property real padding: Theme.sp(14)

    implicitHeight: content.implicitHeight + padding * 2
    radius: Theme.rounding.large
    color: Theme.m3surfaceContainerHigh

    HoverHandler {
        id: hover
    }

    // Whole card: the default action.
    StateLayer {
        onClicked: root.activateHandler ? root.activateHandler() : Notifs.activate(root.notification)
    }

    Item {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.padding
        implicitHeight: Math.max(leading.height, column.implicitHeight)

        // The image (a contact's photo, an album cover) or the app's icon.
        Rectangle {
            id: leading

            width: 40
            height: 40
            radius: Theme.iconRadius(width)
            // No plate under the app's own icon.
            color: root.image === "" && appSymbol.visible && appSymbol.useOwn ? "transparent" : root.critical ? Theme.m3error : Theme.m3primaryContainer
            clip: true

            ClippingRectangle {
                visible: root.image !== ""
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"

                Image {
                    anchors.fill: parent
                    source: root.image
                    sourceSize: Qt.size(80, 80)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            // The app's own icon, as in the launcher.
            AppIcon {
                id: appSymbol

                visible: root.image === "" && root.knownApp
                anchors.fill: parent
                entry: root.entry
                appId: root.appIcon
                critical: root.critical
                themed: false
            }

            MaterialIcon {
                visible: root.image === "" && !root.knownApp
                anchors.centerIn: parent
                text: root.critical ? "priority_high" : "notifications"
                fill: true
                size: 22
                color: root.critical ? Theme.m3onError : Theme.m3onPrimaryContainer
            }

            // Small app icon over the corner of an image.
            AppIcon {
                visible: root.image !== "" && root.knownApp
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 18
                height: 18
                entry: root.entry
                appId: root.appIcon
                themed: false
            }
        }

        // Expand chip (Android's): turns over when unfolded. Close sits left
        // of it once unfolded.
        Rectangle {
            id: chip

            visible: root.expandable
            anchors.right: parent.right
            anchors.top: parent.top
            width: 28
            height: 24
            radius: 12
            color: Theme.m3surfaceContainerHighest

            MaterialIcon {
                anchors.centerIn: parent
                text: "expand_more"
                size: 18
                rotation: root.shown * 180
                color: Theme.m3onSurfaceVariant
            }
        }

        Rectangle {
            id: close

            anchors.right: chip.visible ? chip.left : parent.right
            anchors.rightMargin: chip.visible ? Theme.sp(4) : 0
            anchors.top: parent.top
            width: 24
            height: 24
            radius: 12
            color: "transparent"
            // Collapsed only for the centre (no chip there needs the room);
            // unfolded always.
            opacity: root.expandable ? root.shown : (root.hovered || !root.popup ? 1 : 0)
            visible: opacity > 0

            Behavior on opacity {
                enabled: !root.expandable

                Anim {
                    type: Anim.FastEffects
                }
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: "close"
                size: 18
                color: Theme.m3onSurfaceVariant
            }

            StateLayer {
                onClicked: root.dismissHandler ? root.dismissHandler() : Notifs.dismiss(root.notification)
            }
        }

        Column {
            id: column

            anchors.left: leading.right
            anchors.leftMargin: Theme.sp(12)
            anchors.right: parent.right
            // Room for the chip, kept also when it's hidden: a width that
            // changed with it would rewrap the text, which decides whether
            // there is anything to unfold. The close button goes in the
            // header line that unfolds, beside the chip.
            anchors.rightMargin: 28 + Theme.sp(8)

            // Unfolded: the app's name over the title.
            Item {
                width: parent.width
                height: Math.round(appLine.implicitHeight * root.shown)
                clip: true

                StyledText {
                    id: appLine

                    // Clear of the close button, which sits at this height.
                    width: parent.width - Theme.sp(20)
                    text: root.notification?.appName || "Notification"
                    elide: Text.ElideRight
                    font.pixelSize: Theme.size.labelMedium
                    color: Theme.m3onSurfaceVariant
                    opacity: root.shown
                }
            }

            // Title · age, on one line.
            Row {
                width: parent.width
                spacing: Theme.sp(6)

                StyledText {
                    id: summaryLine

                    width: Math.min(implicitWidth, parent.width - ageLabel.width - parent.spacing)
                    text: root.summary || (root.notification?.appName ?? "")
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.size.bodyLarge
                    font.weight: Font.Medium
                    color: Theme.m3onSurface
                }

                StyledText {
                    id: ageLabel

                    anchors.baseline: summaryLine.baseline
                    text: `· ${Notifs.age(root.notification)}`
                    font.pixelSize: Theme.size.labelMedium
                    color: Theme.m3onSurfaceVariant
                }
            }

            // The text: one elided line collapsed, all of it (up to 6 lines)
            // unfolded; the height moves between the two.
            Item {
                visible: root.body !== ""
                width: parent.width
                height: oneLine.implicitHeight + (fullBody.implicitHeight - oneLine.implicitHeight) * root.shown
                clip: true

                StyledText {
                    id: oneLine

                    width: parent.width
                    text: root.body.replace(/<[^>]*>/g, "").replace(/\s+/g, " ")
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.size.bodyMedium
                    color: Theme.m3onSurfaceVariant
                    opacity: 1 - root.shown
                }

                StyledText {
                    id: fullBody

                    width: parent.width
                    text: root.body
                    wrapMode: Text.Wrap
                    maximumLineCount: 6
                    elide: Text.ElideRight
                    // Apps may use <b>, <i>, <a href>.
                    textFormat: Text.StyledText
                    linkColor: Theme.m3primary
                    font.pixelSize: Theme.size.bodyMedium
                    color: Theme.m3onSurfaceVariant
                    opacity: root.shown
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }

            // Actions: plain bold labels in the accent colour, no container;
            // hovering dims them a little. Unfolded only.
            Item {
                visible: root.buttons.length > 0
                width: parent.width
                height: Math.round(actions.implicitHeight * root.shown)
                clip: true

                Flow {
                    id: actions

                    width: parent.width
                    topPadding: Theme.sp(10)
                    spacing: Theme.sp(20)
                    opacity: root.shown

                    Repeater {
                        model: root.buttons

                        StyledText {
                            id: button

                            required property var modelData

                            width: Math.min(implicitWidth, actions.width)
                            height: Math.max(implicitHeight, 28)
                            text: modelData.text
                            elide: Text.ElideRight
                            font.pixelSize: Theme.size.labelLarge
                            font.weight: Font.Bold
                            color: Theme.m3primary
                            opacity: buttonMouse.pressed ? 0.6 : buttonMouse.containsMouse ? 0.8 : 1

                            Behavior on opacity {
                                Anim {
                                    type: Anim.FastEffects
                                }
                            }

                            MouseArea {
                                id: buttonMouse

                                anchors.fill: parent
                                anchors.margins: -Theme.sp(6)
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.invokeHandler ? root.invokeHandler(button.modelData) : Notifs.invoke(root.notification, button.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
