pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.services

// Settings window: navigation on the left, the selected page on the right.
// Open with `qs -c kirin ipc call settings toggle` (Super+I, the launcher).
Scope {
    id: root

    property bool shown: false
    property int currentPage: 0

    // Add a page here: it appears in the menu automatically.
    readonly property var pages: [
        {
            label: "Appearance",
            icon: "palette",
            source: "pages/AppearancePage.qml"
        },
        {
            label: "Display",
            icon: "monitor",
            source: "pages/DisplayPage.qml"
        },
        {
            label: "Input",
            icon: "keyboard",
            source: "pages/InputPage.qml"
        },
        {
            label: "Shortcuts",
            icon: "keyboard_command_key",
            source: "pages/ShortcutsPage.qml"
        },
        {
            label: "Bar",
            icon: "view_sidebar",
            source: "pages/BarPage.qml"
        },
        {
            label: "Notifications",
            icon: "notifications",
            source: "pages/NotificationsPage.qml"
        },
        {
            label: "Sounds",
            icon: "music_note",
            source: "pages/SoundsPage.qml"
        },
        {
            label: "Media",
            icon: "music_note",
            source: "pages/MediaPage.qml"
        },
        {
            label: "Power",
            icon: "battery_charging_full",
            source: "pages/PowerPage.qml"
        },
        {
            label: "Wallpaper",
            icon: "wallpaper",
            source: "pages/WallpaperPage.qml"
        },
        {
            label: "Launcher",
            icon: "search",
            source: "pages/LauncherPage.qml"
        },
        {
            label: "Update",
            icon: "system_update",
            source: "pages/UpdatePage.qml"
        },
        {
            label: "About",
            icon: "info",
            source: "pages/AboutPage.qml"
        }
    ]

    // Opened from elsewhere in the shell, e.g. the bar's battery card.
    Connections {
        target: Panels

        function onSettingsRequested(page: string): void {
            const index = root.pages.findIndex(p => p.label === page);
            if (index >= 0)
                root.currentPage = index;
            root.shown = true;
        }
    }

    IpcHandler {
        target: "settings"

        function open(): void {
            root.shown = true;
        }

        function close(): void {
            root.shown = false;
        }

        function toggle(): void {
            root.shown = !root.shown;
        }

        function page(index: int): void {
            if (index >= 0 && index < root.pages.length)
                root.currentPage = index;
        }
    }

    LazyLoader {
        active: root.shown

        FloatingWindow {
            id: win

            title: "Kirin Settings"
            color: Theme.m3surface
            implicitWidth: 960
            implicitHeight: 640
            minimumSize.width: 720
            minimumSize.height: 480

            // Closed by the compositor (SUPER+C, etc.).
            onVisibleChanged: {
                if (!visible)
                    root.shown = false;
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.shown = false

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.sp(12)
                    spacing: Theme.sp(12)

                    // Navigation drawer.
                    ColumnLayout {
                        Layout.preferredWidth: 256
                        Layout.maximumWidth: 256
                        Layout.fillWidth: false
                        Layout.fillHeight: true
                        spacing: Theme.sp(4)

                        StyledText {
                            text: "Settings"
                            font.pixelSize: Theme.size.titleLarge
                            Layout.leftMargin: Theme.sp(16)
                            Layout.topMargin: Theme.sp(16)
                            Layout.bottomMargin: Theme.sp(16)
                        }

                        // Items with one active indicator that slides between them.
                        // They scroll when the window is too short for them all
                        // (else they'd stretch the window's layout past its
                        // bottom, the page with it).
                        Flickable {
                            id: navFlick

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 0
                            contentWidth: width
                            contentHeight: navColumn.implicitHeight
                            clip: true
                            interactive: contentHeight > height + 1
                            boundsBehavior: Flickable.StopAtBounds

                            TouchpadScroll {
                                flickable: navFlick
                            }

                            Rectangle {
                                readonly property Item target: navRepeater.count > root.currentPage ? navRepeater.itemAt(root.currentPage) : null

                                visible: target !== null
                                width: navFlick.width
                                y: target?.y ?? 0
                                height: target?.height ?? 0
                                radius: height / 2
                                color: Theme.m3secondaryContainer

                                Behavior on y {
                                    Anim {
                                        type: Anim.DefaultSpatial
                                    }
                                }
                            }

                            Column {
                                id: navColumn

                                width: navFlick.width
                                spacing: Theme.sp(4)

                                Repeater {
                                    id: navRepeater

                                    model: root.pages

                                    NavItem {
                                        required property var modelData
                                        required property int index

                                        width: navColumn.width
                                        background: false
                                        icon: modelData.icon
                                        text: modelData.label
                                        active: root.currentPage === index
                                        onClicked: root.currentPage = index
                                    }
                                }
                            }
                        }
                    }

                    // Page.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.rounding.extraLarge
                        color: Theme.m3surfaceContainerLow
                        clip: true

                        Flickable {
                            id: flick

                            anchors.fill: parent
                            contentHeight: page.implicitHeight + Theme.sp(64)
                            boundsBehavior: Flickable.DragAndOvershootBounds
                            // Content as wide as the view, so the touchpad handler covers it.
                            contentWidth: width

                            TouchpadScroll {
                                flickable: flick
                            }

                            ScrollBar.vertical: ScrollBar {
                                policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                contentItem: Rectangle {
                                    implicitWidth: 4
                                    radius: 2
                                    color: Theme.m3outline
                                }
                            }

                            ColumnLayout {
                                id: page

                                x: Theme.sp(32)
                                y: Theme.sp(32)
                                width: flick.width - Theme.sp(64)
                                spacing: Theme.sp(24)

                                StyledText {
                                    text: root.pages[root.currentPage].label
                                    font.pixelSize: Theme.size.headlineSmall
                                }

                                Loader {
                                    id: loader

                                    Layout.fillWidth: true
                                    source: root.pages[root.currentPage].source
                                    transform: Translate {
                                        id: shift
                                    }

                                    onLoaded: {
                                        flick.contentY = 0;
                                        appear.restart();
                                    }

                                    ParallelAnimation {
                                        id: appear

                                        Anim {
                                            target: loader
                                            property: "opacity"
                                            from: 0
                                            to: 1
                                            type: Anim.DefaultEffects
                                        }
                                        Anim {
                                            target: shift
                                            property: "y"
                                            from: Theme.sp(32)
                                            to: 0
                                            type: Anim.DefaultSpatial
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

