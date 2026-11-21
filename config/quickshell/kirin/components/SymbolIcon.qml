import QtQuick
import QtQuick.Effects
import Quickshell
import qs.services

// An app's icon as a one-colour symbol, no background, for icons sitting on
// the bar itself. From Papirus's symbolic set (Symbols): the app's own, else
// one for its kind (terminal, browser, …, from the desktop entry's
// categories), else a generic app symbol. Without the set, the icon theme's
// symbolic icons the same way.
Item {
    id: root

    // The desktop entry (DesktopEntries.heuristicLookup), or null.
    property var entry: null
    // The window's app id / class, tried as well.
    property string appId
    property color color: Theme.m3onSurface

    // Categories (freedesktop menu spec) to a symbol, first match wins.
    readonly property var kinds: [
        ["TerminalEmulator", "utilities-terminal-symbolic"],
        ["WebBrowser", "web-browser-symbolic"],
        ["InstantMessaging", "chat-message-new-symbolic"],
        ["Chat", "chat-message-new-symbolic"],
        ["Email", "mail-unread-symbolic"],
        ["TextEditor", "text-editor-symbolic"],
        ["IDE", "applications-engineering-symbolic"],
        ["Development", "applications-engineering-symbolic"],
        ["FileManager", "system-file-manager-symbolic"],
        ["Audio", "multimedia-player-symbolic"],
        ["Video", "applications-multimedia-symbolic"],
        ["AudioVideo", "applications-multimedia-symbolic"],
        ["Game", "applications-games-symbolic"],
        ["Graphics", "applications-graphics-symbolic"],
        ["Office", "applications-office-symbolic"],
        ["Settings", "preferences-system-symbolic"],
        ["Network", "applications-internet-symbolic"],
        ["System", "applications-system-symbolic"]
    ]

    // Apps whose desktop icon name differs from Papirus's name for their
    // symbol. Count as the app's own.
    readonly property var aliases: ({
            "blueman": "bluetooth-symbolic",
            "blueman-manager": "bluetooth-symbolic",
            "org.pulseaudio.pavucontrol": "multimedia-volume-control-symbolic",
            "pavucontrol": "multimedia-volume-control-symbolic"
        })

    // A symbol of the app itself (not one for its kind or the generic one).
    readonly property bool specific: found.specific
    readonly property string source: found.source
    readonly property var found: {
        const names = [];
        const own = Config.bar.appSymbols?.[appId];
        if (own)
            names.push(own);
        const icon = entry?.icon ?? "";
        if (icon && !icon.startsWith("/"))
            names.push(`${icon}-symbolic`);
        for (const key of [icon, appId, appId.toLowerCase()])
            if (aliases[key])
                names.push(aliases[key]);
        if (appId)
            names.push(`${appId}-symbolic`, `${appId.toLowerCase()}-symbolic`);
        const ownCount = names.length;
        const categories = entry?.categories ?? [];
        for (const [category, name] of kinds)
            if (categories.includes(category))
                names.push(name);
        names.push("application-default-symbolic", "application-x-executable-symbolic");
        for (let i = 0; i < names.length; i++) {
            const path = Symbols.available ? Symbols.find(names[i]) : Quickshell.iconPath(names[i], true);
            if (path)
                return {
                    source: path.startsWith("/") ? `file://${path}` : path,
                    specific: i < ownCount
                };
        }
        return {
            source: "",
            specific: false
        };
    }

    Image {
        id: symbol

        visible: false
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(width * 2, height * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }

    Rectangle {
        id: ink

        visible: false
        anchors.fill: parent
        color: root.color
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: ink
        maskEnabled: true
        maskSource: symbol
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }
}
